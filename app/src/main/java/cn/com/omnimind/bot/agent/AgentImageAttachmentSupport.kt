package cn.com.omnimind.bot.agent

import android.util.Base64
import cn.com.omnimind.baselib.util.ImageCompressor
import cn.com.omnimind.baselib.util.OmniLog
import cn.com.omnimind.assists.controller.http.HttpController
import cn.com.omnimind.omniintelligence.models.AgentRequest.Payload
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import kotlin.math.ceil
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.Locale
import java.util.concurrent.TimeUnit

internal object AgentImageAttachmentSupport {
    private const val TAG = "AgentImageAttachmentSupport"
    private const val MODEL_SCALE = 0.75f
    private const val MODEL_QUALITY = 92
    private const val PREVIEW_SCALE = 0.35f
    private const val PREVIEW_QUALITY = 80
    private const val NO_BYPASS_THRESHOLD = 0L

    internal data class PreparedAttachments(
        val runtimeAttachments: List<Map<String, Any?>>,
        val modelAttachments: List<Map<String, Any?>>,
        val historyAttachments: List<Map<String, Any?>>
    )

    internal data class ResolvedImageData(
        val dataUrl: String,
        val mimeType: String,
        val originalWidth: Int,
        val originalHeight: Int,
        val compressedWidth: Int,
        val compressedHeight: Int
    )

    internal data class FileReadImageResult(
        val payload: Map<String, Any?>,
        val imageDataUrl: String
    )

    internal interface Backend {
        fun readFileAsDataUrl(file: File, mimeTypeHint: String?): String?

        fun compressDataUrl(
            dataUrl: String,
            scale: Float,
            quality: Int
        ): ResolvedImageData?
    }

    private object RealBackend : Backend {
        override fun readFileAsDataUrl(file: File, mimeTypeHint: String?): String? {
            if (!file.exists() || !file.isFile) {
                return null
            }
            return runCatching {
                val mimeType = normalizeImageMimeType(mimeTypeHint, file.name)
                val encoded = Base64.encodeToString(file.readBytes(), Base64.NO_WRAP)
                "data:$mimeType;base64,$encoded"
            }.onFailure { error ->
                OmniLog.w(TAG, "read image file failed: ${file.absolutePath}: ${error.message}")
            }.getOrNull()
        }

        override fun compressDataUrl(
            dataUrl: String,
            scale: Float,
            quality: Int
        ): ResolvedImageData? {
            return runCatching {
                val result = ImageCompressor.compressBase64Image(
                    base64String = dataUrl,
                    scale = scale,
                    quality = quality,
                    bypassThreshold = NO_BYPASS_THRESHOLD
                )
                ResolvedImageData(
                    dataUrl = result.base64,
                    mimeType = extractMimeType(result.base64),
                    originalWidth = result.originalWidth,
                    originalHeight = result.originalHeight,
                    compressedWidth = result.compressedWidth,
                    compressedHeight = result.compressedHeight
                )
            }.onFailure { error ->
                OmniLog.w(TAG, "compress image dataUrl failed: ${error.message}")
            }.getOrNull()
        }
    }

    @Volatile
    internal var backend: Backend = RealBackend

    internal fun resetBackendForTests() {
        backend = RealBackend
    }

    /**
     * 外部注入的 workspaceManager，用于在处理附件时保存到 .omnibot/attachments/。
     * 由 AgentRuntime 在初始化时注入。
     */
    internal var workspaceManagerProvider: (() -> AgentWorkspaceManager)? = null

    fun prepareAttachments(rawAttachments: List<Map<String, Any?>>): PreparedAttachments {
        if (rawAttachments.isEmpty()) {
            return PreparedAttachments(
                runtimeAttachments = emptyList(),
                modelAttachments = emptyList(),
                historyAttachments = emptyList()
            )
        }
        val runtimeAttachments = mutableListOf<Map<String, Any?>>()
        val modelAttachments = mutableListOf<Map<String, Any?>>()
        val historyAttachments = mutableListOf<Map<String, Any?>>()
        rawAttachments.forEach { raw ->
            // 先保存附件到 attachments/ 目录（修复 Bug 1）
            saveAttachmentToWorkspace(raw)
            val prepared = prepareSingleAttachment(raw) ?: return@forEach
            val shouldSendToModel = shouldSendAttachmentToModel(raw)
            val isImage = prepared.second["isImage"] == true
            if (shouldSendToModel && isImage) {
                modelAttachments += prepared.first
            }
            runtimeAttachments += if (shouldSendToModel && isImage) {
                prepared.first
            } else {
                prepared.second
            }
            historyAttachments += prepared.second
        }
        return PreparedAttachments(
            runtimeAttachments = runtimeAttachments,
            modelAttachments = modelAttachments,
            historyAttachments = historyAttachments
        )
    }

    internal fun isImageAttachment(attachment: Map<String, Any?>): Boolean {
        val localPath = localPathFromAttachment(attachment)
        val remoteUrl = remoteUrlFromAttachment(attachment)
        val dataUrl = dataUrlFromAttachment(attachment)
        val mimeType = mimeTypeFromAttachment(attachment)
        return detectImageAttachment(
            attachment = attachment,
            mimeType = mimeType,
            localPath = localPath,
            remoteUrl = remoteUrl,
            dataUrl = dataUrl
        )
    }

    fun resolveImageAttachmentUrl(attachment: Map<String, Any?>): String {
        localPathFromAttachment(attachment)?.let { path ->
            val file = File(path)
            val dataUrl = backend.readFileAsDataUrl(file, mimeTypeFromAttachment(attachment))
            if (!dataUrl.isNullOrBlank()) {
                val compressed = backend.compressDataUrl(
                    dataUrl = dataUrl,
                    scale = MODEL_SCALE,
                    quality = MODEL_QUALITY
                )
                if (compressed != null) {
                    return compressed.dataUrl
                }
                return dataUrl
            }
        }

        val dataUrl = dataUrlFromAttachment(attachment)
        if (dataUrl.isNotBlank()) {
            return dataUrl
        }

        val remoteUrl = remoteUrlFromAttachment(attachment)
        if (remoteUrl.isNotBlank()) {
            return remoteUrl
        }
        return ""
    }

    fun buildFileReadImageResult(
        file: File,
        shellPath: String,
        mimeTypeHint: String,
        uri: String,
        sizeBytes: Long
    ): FileReadImageResult? {
        val dataUrl = backend.readFileAsDataUrl(file, mimeTypeHint) ?: return null
        val compressed = backend.compressDataUrl(
            dataUrl = dataUrl,
            scale = MODEL_SCALE,
            quality = MODEL_QUALITY
        ) ?: return null
        val payload = linkedMapOf<String, Any?>(
            "path" to shellPath,
            "androidPath" to file.absolutePath,
            "uri" to uri,
            "size" to sizeBytes,
            "mimeType" to normalizeImageMimeType(mimeTypeHint, file.name),
            "kind" to "image",
            "width" to compressed.originalWidth,
            "height" to compressed.originalHeight,
            "previewWidth" to compressed.compressedWidth,
            "previewHeight" to compressed.compressedHeight
        )
        return FileReadImageResult(
            payload = payload,
            imageDataUrl = compressed.dataUrl
        )
    }

    /**
     * 将附件从临时路径保存到 .omnibot/attachments/ 目录。
     * 修复 Bug：附件停留在 cache/file_picker/，未持久化到 workspace。
     */
    private fun saveAttachmentToWorkspace(attachment: Map<String, Any?>) {
        val path = attachment["path"]?.toString()?.trim().orEmpty()
        if (path.isBlank() || path.startsWith("http")) return
        // 如果已经在 attachments/ 下则跳过
        if (path.contains("/attachments/")) return

        val provider = workspaceManagerProvider ?: return
        val manager = provider()
        val saved = manager.saveIncomingAttachment(path) ?: return
        // 更新 path 为新位置，后续代码使用新路径
        if (attachment is MutableMap) {
            attachment["path"] = saved.absolutePath
        }
        OmniLog.i(TAG, "saveAttachmentToWorkspace: saved to ${saved.absolutePath}")
    }

    private fun prepareSingleAttachment(
        raw: Map<String, Any?>
    ): Pair<Map<String, Any?>, Map<String, Any?>>? {
        val localPath = localPathFromAttachment(raw)
        val remoteUrl = remoteUrlFromAttachment(raw)
        val dataUrl = dataUrlFromAttachment(raw)
        val mimeType = mimeTypeFromAttachment(raw)
        val isImage = detectImageAttachment(
            attachment = raw,
            mimeType = mimeType,
            localPath = localPath,
            remoteUrl = remoteUrl,
            dataUrl = dataUrl
        )

        val base = linkedMapOf<String, Any?>()
        copyIfNotBlank(base, "id", raw["id"]?.toString())
        val normalizedName = attachmentName(raw, localPath)
        copyIfNotBlank(base, "name", normalizedName)
        copyIfNotBlank(base, "fileName", raw["fileName"]?.toString() ?: normalizedName)
        normalizedSize(raw["size"] ?: raw["sizeBytes"])?.let { base["size"] = it }
        if (mimeType.isNotBlank()) {
            base["mimeType"] = mimeType
        }
        base["isImage"] = isImage
        if (!localPath.isNullOrBlank()) {
            base["path"] = localPath
        }
        if (!remoteUrl.isNullOrBlank()) {
            base["url"] = remoteUrl
        }
        copyIfNotBlank(base, "promptPath", raw["promptPath"]?.toString())
        copyIfNotBlank(base, "workspacePath", raw["workspacePath"]?.toString())
        if (!shouldSendAttachmentToModel(raw)) {
            base["sendToModel"] = false
        }

        if (!isImage) {
            return base to base
        }

        val sourceDataUrl = when {
            !localPath.isNullOrBlank() -> {
                backend.readFileAsDataUrl(File(localPath), mimeType.takeIf { it.isNotBlank() })
                    ?: dataUrl.takeIf { it.isNotBlank() }
            }
            dataUrl.isNotBlank() -> dataUrl
            else -> null
        }

        if (!sourceDataUrl.isNullOrBlank()) {
            val modelImage = backend.compressDataUrl(
                dataUrl = sourceDataUrl,
                scale = MODEL_SCALE,
                quality = MODEL_QUALITY
            )
            val historyImage = backend.compressDataUrl(
                dataUrl = sourceDataUrl,
                scale = PREVIEW_SCALE,
                quality = PREVIEW_QUALITY
            )
            if (modelImage != null || historyImage != null) {
                val modelAttachment = LinkedHashMap(base)
                val historyAttachment = LinkedHashMap(base)
                val resolvedMimeType = modelImage?.mimeType
                    ?: historyImage?.mimeType
                    ?: mimeType
                if (resolvedMimeType.isNotBlank()) {
                    modelAttachment["mimeType"] = resolvedMimeType
                    historyAttachment["mimeType"] = resolvedMimeType
                }
                modelImage?.let {
                    modelAttachment["dataUrl"] = it.dataUrl
                    modelAttachment["width"] = it.originalWidth
                    modelAttachment["height"] = it.originalHeight
                }
                historyImage?.let {
                    historyAttachment["dataUrl"] = it.dataUrl
                    historyAttachment["width"] = it.originalWidth
                    historyAttachment["height"] = it.originalHeight
                }
                return modelAttachment to historyAttachment
            }
            val fallbackModelAttachment = LinkedHashMap(base)
            fallbackModelAttachment["dataUrl"] = sourceDataUrl
            return fallbackModelAttachment to LinkedHashMap(base)
        }

        return base to base
    }

    private fun shouldSendAttachmentToModel(attachment: Map<String, Any?>): Boolean {
        return when (val raw = attachment["sendToModel"]) {
            is Boolean -> raw
            is String -> !raw.equals("false", ignoreCase = true)
            else -> true
        }
    }

    private fun localPathFromAttachment(attachment: Map<String, Any?>): String? {
        val raw = attachment["path"]?.toString()?.trim().orEmpty()
        return raw.takeIf { it.isNotEmpty() && !it.startsWith("http://") && !it.startsWith("https://") }
    }

    private fun remoteUrlFromAttachment(attachment: Map<String, Any?>): String {
        val raw = extractUrlCandidate(attachment)
        return if (
            raw.startsWith("http://", ignoreCase = true) ||
            raw.startsWith("https://", ignoreCase = true)
        ) {
            raw
        } else {
            ""
        }
    }

    private fun dataUrlFromAttachment(attachment: Map<String, Any?>): String {
        val explicitDataUrl = attachment["dataUrl"]?.toString()?.trim().orEmpty()
        if (explicitDataUrl.startsWith("data:", ignoreCase = true)) {
            return explicitDataUrl
        }
        val urlCandidate = extractUrlCandidate(attachment)
        return if (urlCandidate.startsWith("data:", ignoreCase = true)) {
            urlCandidate
        } else {
            ""
        }
    }

    private fun extractUrlCandidate(attachment: Map<String, Any?>): String {
        val direct = sequenceOf(
            attachment["url"],
            attachment["imageUrl"],
            attachment["image_url"]
        ).mapNotNull { value ->
            when (value) {
                is Map<*, *> -> value["url"]?.toString()?.trim()
                else -> value?.toString()?.trim()
            }
        }.firstOrNull { it.isNotBlank() }
        return direct.orEmpty()
    }

    private fun mimeTypeFromAttachment(attachment: Map<String, Any?>): String {
        val explicit = attachment["mimeType"]?.toString()?.trim().orEmpty()
        if (explicit.isNotBlank()) {
            return explicit
        }
        val dataUrl = dataUrlFromAttachment(attachment)
        if (dataUrl.startsWith("data:", ignoreCase = true)) {
            return extractMimeType(dataUrl)
        }
        val path = localPathFromAttachment(attachment)
        val url = remoteUrlFromAttachment(attachment)
        return inferMimeTypeFromPath(path ?: url)
    }

    private fun attachmentName(
        attachment: Map<String, Any?>,
        localPath: String?
    ): String {
        val name = attachment["name"]?.toString()?.trim().orEmpty()
        if (name.isNotBlank()) {
            return name
        }
        val fileName = attachment["fileName"]?.toString()?.trim().orEmpty()
        if (fileName.isNotBlank()) {
            return fileName
        }
        val path = localPath.orEmpty()
        if (path.isBlank()) {
            return ""
        }
        return path.replace('\\', '/').substringAfterLast('/')
    }

    private fun normalizedSize(rawSize: Any?): Long? {
        return when (rawSize) {
            is Number -> rawSize.toLong()
            is String -> rawSize.trim().toLongOrNull()
            else -> null
        }?.takeIf { it >= 0L }
    }

    private fun detectImageAttachment(
        attachment: Map<String, Any?>,
        mimeType: String,
        localPath: String?,
        remoteUrl: String,
        dataUrl: String
    ): Boolean {
        val explicit = when (val rawFlag = attachment["isImage"]) {
            is Boolean -> rawFlag
            is String -> rawFlag.equals("true", ignoreCase = true)
            else -> false
        }
        if (explicit) {
            return true
        }
        if (mimeType.startsWith("image/", ignoreCase = true)) {
            return true
        }
        if (dataUrl.startsWith("data:image/", ignoreCase = true)) {
            return true
        }
        return looksLikeImagePath(localPath) || looksLikeImagePath(remoteUrl)
    }

    private fun looksLikeImagePath(value: String?): Boolean {
        val normalized = value?.trim().orEmpty().lowercase(Locale.US).split('?').firstOrNull().orEmpty()
        return normalized.endsWith(".png") ||
            normalized.endsWith(".jpg") ||
            normalized.endsWith(".jpeg") ||
            normalized.endsWith(".webp") ||
            normalized.endsWith(".gif") ||
            normalized.endsWith(".bmp") ||
            normalized.endsWith(".heic") ||
            normalized.endsWith(".heif")
    }

    private fun copyIfNotBlank(
        target: MutableMap<String, Any?>,
        key: String,
        value: String?
    ) {
        val normalized = value?.trim().orEmpty()
        if (normalized.isNotEmpty()) {
            target[key] = normalized
        }
    }

    private fun normalizeImageMimeType(mimeTypeHint: String?, pathHint: String): String {
        val normalizedHint = mimeTypeHint?.trim().orEmpty()
        if (normalizedHint.startsWith("image/", ignoreCase = true)) {
            return normalizedHint
        }
        val inferred = inferMimeTypeFromPath(pathHint)
        if (inferred.isNotBlank()) {
            return inferred
        }
        return "image/jpeg"
    }

    private fun inferMimeTypeFromPath(pathHint: String): String {
        val lower = pathHint.lowercase(Locale.US)
        return when {
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".webp") -> "image/webp"
            lower.endsWith(".gif") -> "image/gif"
            lower.endsWith(".bmp") -> "image/bmp"
            lower.endsWith(".heic") -> "image/heic"
            lower.endsWith(".heif") -> "image/heif"
            else -> ""
        }
    }

    private fun extractMimeType(dataUrl: String): String {
        val header = dataUrl.substringBefore(',', "")
        if (!header.startsWith("data:", ignoreCase = true)) {
            return "image/jpeg"
        }
        val mimeType = header.removePrefix("data:").substringBefore(';').trim()
        return if (mimeType.isBlank()) "image/jpeg" else mimeType
    }

    // ===== VLM 图像描述 — 共享方法（两端复用） =====

    private val vlmDescriptionCache = mutableMapOf<String, String>()
    private var lastVlmCallMs = 0L

    /** 缩放 base64 data URL 到 maxDimension 以内，保持宽高比。采样解码避免大图 OOM。JPEG quality=85。 */
    internal fun downscaleImageIfNeeded(dataUrl: String, maxDimension: Int): String {
        try {
            val commaIndex = dataUrl.indexOf(',')
            if (commaIndex < 0) return dataUrl
            val base64Data = dataUrl.substring(commaIndex + 1)
            val imageBytes = Base64.decode(base64Data, Base64.DEFAULT)

            // ★ 先采样获取尺寸，避免全尺寸解码 OOM
            val opts = android.graphics.BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, opts)
            val origW = opts.outWidth
            val origH = opts.outHeight
            if (origW <= 0 || origH <= 0) return dataUrl

            val maxSide = maxOf(origW, origH)
            if (maxSide <= maxDimension) {
                // 已经够小，直接解码（小图不会 OOM）
                val bitmap = android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                if (bitmap == null) return dataUrl
                val output = java.io.ByteArrayOutputStream()
                bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, output)
                bitmap.recycle()
                val encoded = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
                return "data:image/jpeg;base64,$encoded"
            }

            // ★ 计算 inSampleSize：目标是让采样后短边 ~maxDimension
            val sampleSize = ceil(maxSide.toDouble() / maxDimension).toInt().coerceAtLeast(2)
            val sampleOpts = android.graphics.BitmapFactory.Options().apply {
                inSampleSize = sampleSize
            }
            val sampled = android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, sampleOpts)
            if (sampled == null) return dataUrl

            // ★ 从采样结果再精确缩放到 maxDimension
            val sampledMaxSide = maxOf(sampled.width, sampled.height)
            if (sampledMaxSide <= maxDimension) {
                val output = java.io.ByteArrayOutputStream()
                sampled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, output)
                sampled.recycle()
                val encoded = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
                return "data:image/jpeg;base64,$encoded"
            }

            val scale = maxDimension.toFloat() / sampledMaxSide
            val newW = (sampled.width * scale).toInt()
            val newH = (sampled.height * scale).toInt()
            val scaled = android.graphics.Bitmap.createScaledBitmap(sampled, newW, newH, true)
            sampled.recycle()

            val output = java.io.ByteArrayOutputStream()
            scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, output)
            scaled.recycle()

            val encoded = Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)
            return "data:image/jpeg;base64,$encoded"
        } catch (e: Exception) {
            OmniLog.w(TAG, "图片缩放失败，使用原图: ${e.message}")
            return dataUrl
        }
    }

    /**
     * 调用 scene.vlm.operation.primary 描述图片内容返回文本。
     * 缩放 max(w,h)<=1024, JPEG quality=85, 采样解码防大图 OOM, 缓存 32 张, 限流 500ms, 重试 3 次
     */
    internal suspend fun describeImageViaVlm(imageDataUrl: String): String {
        // ★ 远程 URL 需要先下载转 base64
        val dataUrlForVlm = if (imageDataUrl.startsWith("http://") || imageDataUrl.startsWith("https://")) {
            try {
                downloadImageAsDataUrl(imageDataUrl)
            } catch (e: Exception) {
                OmniLog.w(TAG, "远程图片下载失败: ${e.message}")
                throw e
            }
        } else {
            imageDataUrl
        }

        val cacheKey = dataUrlForVlm.hashCode().toString()
        synchronized(vlmDescriptionCache) {
            vlmDescriptionCache[cacheKey]?.let { return it }
        }

        val sinceLast = System.currentTimeMillis() - lastVlmCallMs
        if (sinceLast < 500) delay(500 - sinceLast)

        // ★ 所有图片统一缩放到 max 1024 再送 VLM，避免超大 payload 导致 VLM 超时/失败
        // 注：Assists 路径在 prepareSingleAttachment 中已压缩过 data URL，此处 downscale 会跳过已符合尺寸的图片
        val scaledDataUrl = downscaleImageIfNeeded(dataUrlForVlm, maxDimension = 1024)

        var lastError: Throwable? = null
        repeat(3) { attempt ->
            if (attempt > 0) delay(when(attempt) { 1 -> 2_000L else -> 4_000L })
            try {
                lastVlmCallMs = System.currentTimeMillis()
                val result = withTimeout(30_000) {
                    HttpController.postVLMDescriptionRequest(
                        sceneId = "scene.vlm.operation.primary",
                        payload = Payload.VLMChatPayload(
                            model = "scene.vlm.operation.primary",
                            images = listOf(scaledDataUrl),
                            text = "请详细描述这张图片的所有视觉内容、界面布局、控件和可见文字"
                        )
                    )
                }
                val vlmResult = result.message.ifBlank { "（VLM 返回空描述）" }
                synchronized(vlmDescriptionCache) {
                    if (vlmDescriptionCache.size >= 32) {
                        vlmDescriptionCache.remove(vlmDescriptionCache.keys.first())
                    }
                    vlmDescriptionCache[cacheKey] = vlmResult
                }
                return vlmResult
            } catch (e: kotlinx.coroutines.TimeoutCancellationException) {
                lastError = e
                OmniLog.w(TAG, "VLM 描述第 ${attempt + 1} 次超时")
            } catch (e: Exception) {
                lastError = e
                OmniLog.w(TAG, "VLM 描述第 ${attempt + 1} 次失败: ${e.message}")
            }
        }
        throw lastError ?: IllegalStateException("VLM 描述全部失败")
    }

    /** 下载远程图片并转为 base64 data URL */
    private suspend fun downloadImageAsDataUrl(url: String): String {
        return withTimeout(30_000) {
            val client = okhttp3.OkHttpClient.Builder()
                .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                .readTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
                .build()
            val request = okhttp3.Request.Builder().url(url).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw Exception("HTTP ${response.code}")
                }
                val body = response.body ?: throw Exception("empty body")
                val bytes = body.bytes()
                // 从 URL 或 Content-Type 推断 MIME
                val mimeType = run {
                    val ct = response.header("Content-Type")?.lowercase(Locale.ROOT)
                    when {
                        ct?.contains("png") == true -> "image/png"
                        ct?.contains("gif") == true -> "image/gif"
                        ct?.contains("webp") == true -> "image/webp"
                        ct?.contains("heic") == true || ct?.contains("heif") == true -> "image/heic"
                        else -> {
                            val lower = url.lowercase(Locale.ROOT)
                            when {
                                lower.contains(".png") -> "image/png"
                                lower.contains(".gif") -> "image/gif"
                                lower.contains(".webp") -> "image/webp"
                                else -> "image/jpeg"
                            }
                        }
                    }
                }
                val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                "data:$mimeType;base64,$base64"
            }
        }
    }
}
