package cn.com.omnimind.bot.webchat

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import cn.com.omnimind.bot.manager.AssistsCoreManager
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.UUID
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal data class NormalizedAgentRunPayload(
    val userMessage: String,
    val attachments: List<Map<String, Any?>>
)

internal object AgentRunRequestNormalizer {
    fun normalize(request: Map<String, Any?>): NormalizedAgentRunPayload {
        val explicitUserMessage = request["userMessage"]?.toString().orEmpty()
        val explicitAttachments = normalizeListOfMaps(request["attachments"])
        if (explicitUserMessage.isNotBlank() || explicitAttachments.isNotEmpty()) {
            return NormalizedAgentRunPayload(
                userMessage = explicitUserMessage,
                attachments = explicitAttachments
            )
        }

        val directContent = normalizeContentBlocks(request["content"])
        if (directContent != null) {
            return directContent
        }

        val messages = request["messages"] as? List<*> ?: emptyList<Any?>()
        for (index in messages.indices.reversed()) {
            val message = normalizeMap(messages[index]) ?: continue
            val role = message["role"]?.toString()?.trim()?.lowercase().orEmpty()
            if (role != "user") continue
            val content = message["content"]
            if (content is String) {
                return NormalizedAgentRunPayload(
                    userMessage = content,
                    attachments = emptyList()
                )
            }
            normalizeContentBlocks(content)?.let { return it }
        }

        return NormalizedAgentRunPayload(
            userMessage = "",
            attachments = emptyList()
        )
    }

    private fun normalizeContentBlocks(raw: Any?): NormalizedAgentRunPayload? {
        val blocks = raw as? List<*> ?: return null
        val texts = mutableListOf<String>()
        val attachments = mutableListOf<Map<String, Any?>>()
        blocks.forEachIndexed { index, item ->
            val block = normalizeMap(item) ?: return@forEachIndexed
            val type = inferBlockType(block)
            when (type) {
                "text", "input_text" -> {
                    val text = block["text"]?.toString().orEmpty()
                    if (text.isNotBlank()) {
                        texts += text
                    }
                }

                "image_url", "input_image", "image" -> {
                    val imageUrl = extractImageUrl(block)
                    if (imageUrl.isBlank()) {
                        return@forEachIndexed
                    }
                    val attachment = linkedMapOf<String, Any?>(
                        "isImage" to true
                    )
                    val fileName = block["fileName"]?.toString()?.trim().orEmpty()
                    if (fileName.isNotBlank()) {
                        attachment["fileName"] = fileName
                        attachment["name"] = fileName
                    } else {
                        attachment["fileName"] = "image_$index"
                        attachment["name"] = "image_$index"
                    }
                    val mimeType = extractMimeType(imageUrl, block["mimeType"]?.toString())
                    if (mimeType.isNotBlank()) {
                        attachment["mimeType"] = mimeType
                    }
                    if (imageUrl.startsWith("data:", ignoreCase = true)) {
                        attachment["dataUrl"] = imageUrl
                    } else {
                        attachment["url"] = imageUrl
                    }
                    attachments += attachment
                }

                "file", "attachment", "input_file" -> {
                    val attachment = extractAttachment(block, index)
                    if (attachment != null) {
                        attachments += attachment
                    }
                }
            }
        }
        return NormalizedAgentRunPayload(
            userMessage = texts.joinToString("\n").trim(),
            attachments = attachments
        )
    }

    private fun inferBlockType(block: Map<String, Any?>): String {
        val explicit = block["type"]?.toString()?.trim()?.lowercase().orEmpty()
        if (explicit.isNotEmpty()) {
            return explicit
        }
        if (block.containsKey("image_url") || block.containsKey("imageUrl")) {
            return "image_url"
        }
        if (block.containsKey("text")) {
            return "text"
        }
        if (block.containsKey("file") ||
            block.containsKey("attachment") ||
            block.containsKey("input_file")
        ) {
            return "attachment"
        }
        val mimeType = block["mimeType"]?.toString()?.trim().orEmpty()
        if (mimeType.startsWith("image/", ignoreCase = true) &&
            (block.containsKey("url") || block.containsKey("dataUrl"))
        ) {
            return "image_url"
        }
        return if (block.containsKey("url") ||
            block.containsKey("path") ||
            block.containsKey("filePath") ||
            block.containsKey("promptPath") ||
            block.containsKey("workspacePath") ||
            block.containsKey("fileName") ||
            block.containsKey("name")
        ) {
            "attachment"
        } else {
            ""
        }
    }

    private fun extractImageUrl(block: Map<String, Any?>): String {
        val imageUrlField = block["image_url"]
        val nested = when (imageUrlField) {
            is Map<*, *> -> imageUrlField["url"]?.toString()
            else -> imageUrlField?.toString()
        }
        return sequenceOf(
            nested,
            block["url"]?.toString(),
            block["imageUrl"]?.toString()
        ).map { it?.trim().orEmpty() }
            .firstOrNull { it.isNotBlank() }
            .orEmpty()
    }

    private fun extractMimeType(imageUrl: String, explicit: String?): String {
        val normalizedExplicit = explicit?.trim().orEmpty()
        if (normalizedExplicit.isNotBlank()) {
            return normalizedExplicit
        }
        if (imageUrl.startsWith("data:", ignoreCase = true)) {
            return imageUrl
                .substringAfter("data:", "")
                .substringBefore(';')
                .trim()
        }
        return ""
    }

    private fun extractAttachment(
        block: Map<String, Any?>,
        index: Int
    ): Map<String, Any?>? {
        val nested = sequenceOf(
            block["attachment"],
            block["file"],
            block["input_file"]
        ).mapNotNull(::normalizeMap).firstOrNull()

        fun readField(key: String): Any? = nested?.get(key) ?: block[key]

        val attachment = linkedMapOf<String, Any?>()
        val name = readField("name")?.toString()?.trim().orEmpty()
        val fileName = readField("fileName")?.toString()?.trim().orEmpty()
        val resolvedName = fileName.ifEmpty { name }
        if (resolvedName.isNotEmpty()) {
            attachment["name"] = resolvedName
            attachment["fileName"] = resolvedName
        } else {
            attachment["fileName"] = "attachment_$index"
            attachment["name"] = "attachment_$index"
        }

        val mimeType = readField("mimeType")?.toString()?.trim().orEmpty()
        if (mimeType.isNotEmpty()) {
            attachment["mimeType"] = mimeType
        }

        copyIfNotBlank(attachment, "id", readField("id")?.toString())
        copyIfNotBlank(attachment, "path", firstNonBlank(readField("path"), readField("filePath")))
        copyIfNotBlank(attachment, "promptPath", readField("promptPath")?.toString())
        copyIfNotBlank(attachment, "workspacePath", readField("workspacePath")?.toString())
        copyIfNotBlank(attachment, "url", readField("url")?.toString())
        copyIfNotBlank(attachment, "dataUrl", readField("dataUrl")?.toString())

        when (val raw = readField("size") ?: readField("sizeBytes")) {
            is Number -> attachment["size"] = raw.toLong()
            is String -> raw.trim().toLongOrNull()?.let { attachment["size"] = it }
        }

        val explicitImage = when (val raw = readField("isImage")) {
            is Boolean -> raw
            is String -> raw.equals("true", ignoreCase = true)
            else -> false
        }
        val looksLikeImage = explicitImage ||
            mimeType.startsWith("image/", ignoreCase = true) ||
            attachment["dataUrl"]?.toString()?.startsWith("data:image/", ignoreCase = true) == true ||
            firstNonBlank(attachment["path"], attachment["url"])
                ?.let(::looksLikeImagePath) == true
        attachment["isImage"] = looksLikeImage

        when (val raw = readField("sendToModel")) {
            is Boolean -> if (!raw) attachment["sendToModel"] = false
            is String -> if (raw.equals("false", ignoreCase = true)) {
                attachment["sendToModel"] = false
            }
        }

        return if (
            attachment["path"] != null ||
            attachment["url"] != null ||
            attachment["dataUrl"] != null ||
            attachment["promptPath"] != null ||
            attachment["workspacePath"] != null
        ) {
            attachment
        } else {
            null
        }
    }

    private fun firstNonBlank(vararg values: Any?): String? {
        return values.firstNotNullOfOrNull { value ->
            value?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        }
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

    private fun looksLikeImagePath(value: String): Boolean {
        val normalized = value.trim().lowercase().split('?').firstOrNull().orEmpty()
        return normalized.endsWith(".png") ||
            normalized.endsWith(".jpg") ||
            normalized.endsWith(".jpeg") ||
            normalized.endsWith(".webp") ||
            normalized.endsWith(".gif") ||
            normalized.endsWith(".bmp") ||
            normalized.endsWith(".heic") ||
            normalized.endsWith(".heif")
    }

    internal fun normalizeMap(value: Any?): Map<String, Any?>? {
        return (value as? Map<*, *>)?.entries?.associate { entry ->
            entry.key.toString() to normalizeValue(entry.value)
        }
    }

    internal fun normalizeListOfMaps(value: Any?): List<Map<String, Any?>> {
        return (value as? List<*>)?.mapNotNull { entry ->
            normalizeMap(entry)
        } ?: emptyList()
    }

    private fun normalizeValue(value: Any?): Any? {
        return when (value) {
            is Map<*, *> -> normalizeMap(value)
            is List<*> -> value.map { normalizeValue(it) }
            else -> value
        }
    }
}

class AgentRunService(
    private val context: Context
) {
    suspend fun startConversationRun(
        conversationId: Long,
        request: Map<String, Any?>
    ): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        if (manager.hasActiveAgentRuns()) {
            throw IllegalStateException("设备当前已有运行中的 Agent 任务，请稍后重试")
        }
        val taskId = request["taskId"]?.toString()?.trim()?.ifEmpty { null }
            ?: UUID.randomUUID().toString()
        val normalizedPayload = AgentRunRequestNormalizer.normalize(request)
        val arguments = linkedMapOf<String, Any?>(
            "taskId" to taskId,
            "conversationId" to conversationId,
            "conversationMode" to normalizeConversationMode(
                request["conversationMode"]?.toString()
            ),
            "userMessage" to normalizedPayload.userMessage,
            "attachments" to normalizedPayload.attachments,
            "terminalEnvironment" to AgentRunRequestNormalizer.normalizeMap(request["terminalEnvironment"]),
            "modelOverride" to AgentRunRequestNormalizer.normalizeMap(request["modelOverride"])
        )
        invokeManager("createAgentTask", arguments) {
            manager.createAgentTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "accepted"
        )
    }

    suspend fun cancelTask(taskId: String?): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        invokeManager(
            method = "cancelRunningTask",
            arguments = taskId?.let { mapOf("taskId" to it) }
        ) {
            manager.cancelRunningTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "cancelled"
        )
    }

    suspend fun clarifyTask(taskId: String?, reply: String): Map<String, Any?> {
        val manager = AssistsCoreManager.sharedInstanceOrCreate(context)
        invokeManager(
            method = "provideUserInputToVLMTask",
            arguments = mapOf("taskId" to taskId, "userInput" to reply)
        ) {
            manager.provideUserInputToVLMTask(it, this)
        }
        return mapOf(
            "taskId" to taskId,
            "status" to "submitted"
        )
    }

    private suspend fun invokeManager(
        method: String,
        arguments: Map<String, Any?>?,
        block: MethodChannel.Result.(MethodCall) -> Unit
    ): Any? {
        return suspendCancellableCoroutine { continuation ->
            val call = MethodCall(method, arguments)
            val result = object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!continuation.isCompleted) {
                        continuation.resume(result)
                    }
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?
                ) {
                    if (!continuation.isCompleted) {
                        continuation.resumeWithException(
                            IllegalStateException(
                                "$errorCode: ${errorMessage ?: "native bridge error"}"
                            )
                        )
                    }
                }

                override fun notImplemented() {
                    if (!continuation.isCompleted) {
                        continuation.resumeWithException(
                            NotImplementedError("Method not implemented: $method")
                        )
                    }
                }
            }
            result.block(call)
        }
    }

    private fun normalizeConversationMode(rawMode: String?): String {
        val normalized = rawMode?.trim()?.lowercase().orEmpty()
        return if (normalized.isEmpty()) "normal" else normalized
    }
}
