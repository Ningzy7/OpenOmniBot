package cn.com.omnimind.baselib.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import java.io.ByteArrayOutputStream

/**
 * 压缩图片质量档位枚举
 *
 * 用于统一管理图片压缩参数，确保各调用点使用一致的压缩配置。
 * 后续可扩展为基于目标像素量的智能缩放。
 *
 * @param scale 缩放比例 (0-1)
 * @param quality JPEG 压缩质量 (1-100)
 * @param bypassThreshold 像素阈值，低于此值不缩放 (0 = 无条件压缩)
 */
enum class ImageQuality(
    val scale: Float,
    val quality: Int,
    val bypassThreshold: Long
) {
    /**
     * 原图 - 不压缩
     */
    ORIGINAL(1.0f, 100, Long.MAX_VALUE),

    /**
     * 高质量 - 适合精细操作（如复杂 UI 点击）
     */
    HIGH(0.75f, 100, ImageCompressor.RESIZE_BYPASS_PIXEL_THRESHOLD),

    /**
     * 中等质量 - 默认 VLM 操作（点击/滑动/输入）
     */
    MEDIUM(0.5f, 85, ImageCompressor.RESIZE_BYPASS_PIXEL_THRESHOLD),

    /**
     * 低质量 - 快速传输或多图场景
     */
    LOW(0.35f, 90, ImageCompressor.RESIZE_BYPASS_PIXEL_THRESHOLD),

    /**
     * 摘要质量 - 任务摘要截图，极低流量
     */
    SUMMARY(0.5f, 90, 0L);

    companion object {
        /**
         * 默认 压缩质量
         */
        val DEFAULT = MEDIUM
    }
}

/**
 * 图片压缩工具类 - 用于 VLM 截图压缩
 *
 * 提供 Base64 图片的解码、缩放、压缩功能，主要用于减小传输给大模型的图片体积。
 * 包含智能跳过机制（像素过少不压缩）和详细的尺寸元数据返回。
 */
object ImageCompressor {

    private const val TAG = "ImageCompressor"
    private const val JPEG_DATA_URI_PREFIX = "data:image/jpeg;base64,"

    /**
     * 默认像素阈值: 小于 1.2MP 时不缩放，避免小屏截图或裁剪图过于模糊
     */
    const val RESIZE_BYPASS_PIXEL_THRESHOLD = 1_200_000L

    /**
     * 仅缩放 Bitmap 的结果数据类
     * @param bitmap 缩放后的 Bitmap（调用者负责回收）
     * @param appliedScale 实际应用的缩放比例 (若跳过缩放则为 1.0f)
     * @param originalWidth 原始图片宽度
     * @param originalHeight 原始图片高度
     * @param scaledWidth 缩放后图片宽度
     * @param scaledHeight 缩放后图片高度
     */
    data class ScaleResult(
        val bitmap: Bitmap,
        val appliedScale: Float,
        val originalWidth: Int,
        val originalHeight: Int,
        val scaledWidth: Int,
        val scaledHeight: Int
    ) {
        /**
         * 将基于缩放图片的坐标还原到原始分辨率
         */
        fun scaleCoordinatesToOriginal(coords: Pair<Float, Float>): Pair<Float, Float> {
            return ImageCompressor.scaleCoordinatesToOriginal(coords, appliedScale)
        }
    }

    /**
     * 压缩结果数据类（用于生成 Base64）
     * @param base64 压缩/处理后的 Base64 字符串
     * @param appliedScale 实际应用的缩放比例 (若跳过压缩则为 1.0f)
     * @param originalWidth 原始图片宽度
     * @param originalHeight 原始图片高度
     * @param compressedWidth 压缩后图片宽度
     * @param compressedHeight 压缩后图片高度
     */
    data class CompressResult(
        val base64: String,
        val appliedScale: Float,
        val originalWidth: Int,
        val originalHeight: Int,
        val compressedWidth: Int,
        val compressedHeight: Int
    ) {
        /**
         * 将基于压缩图片的坐标缩放到原始分辨率
         */
        fun scaleCoordinatesToOriginal(coords: Pair<Float, Float>): Pair<Float, Float> {
            return ImageCompressor.scaleCoordinatesToOriginal(coords, appliedScale)
        }
    }

    /**
     * 将基于压缩图片的坐标缩放到原始分辨率（静态方法）
     * 
     * VLM 返回的坐标是基于压缩后图片的，需要放大到原始分辨率才能正确点击
     * 
     * @param coords 基于压缩图片的坐标
     * @param appliedScale 应用的缩放比例
     * @return 放大到原始分辨率的坐标
     */
    @JvmStatic
    fun scaleCoordinatesToOriginal(coords: Pair<Float, Float>, appliedScale: Float): Pair<Float, Float> {
        // 如果没有压缩（appliedScale >= 1.0），直接返回原坐标
        if (appliedScale >= 1.0f) {
            return coords
        }
        return Pair(coords.first / appliedScale, coords.second / appliedScale)
    }

    // ==================== 仅缩放 Bitmap（不生成 Base64）====================

    /**
     * 仅缩放 Bitmap，不生成 Base64
     *
     * 注意：此函数不会回收传入的 Bitmap，调用者需自行管理原始 Bitmap 生命周期
     * 返回的缩放后 Bitmap 也由调用者负责回收
     *
     * @param bitmap 原始 Bitmap（由调用者自行回收）
     * @param scale 目标缩放比例 (0-1之间，默认0.5)
     * @param bypassThreshold 像素阈值，低于此值不缩放 (默认 1.2MP)。设为 0 表示无条件缩放
     * @return 缩放结果，包含缩放后的 Bitmap 和元信息
     */
    @JvmStatic
    @JvmOverloads
    fun scaleBitmap(
        bitmap: Bitmap,
        scale: Float = 0.5f,
        bypassThreshold: Long = RESIZE_BYPASS_PIXEL_THRESHOLD
    ): ScaleResult {
        val originalWidth = bitmap.width
        val originalHeight = bitmap.height
        val pixelCount = originalWidth.toLong() * originalHeight.toLong()

        // scale >= 1 或像素数低于阈值时，不缩放，返回原 bitmap
        if (scale >= 1f || pixelCount < bypassThreshold) {
            return ScaleResult(
                bitmap = bitmap,
                appliedScale = 1f,
                originalWidth = originalWidth,
                originalHeight = originalHeight,
                scaledWidth = originalWidth,
                scaledHeight = originalHeight
            )
        }

        val newWidth = (originalWidth * scale).toInt().coerceAtLeast(1)
        val newHeight = (originalHeight * scale).toInt().coerceAtLeast(1)

        val resized = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)

        OmniLog.d(TAG, "Bitmap scaled: ${originalWidth}x${originalHeight} -> ${newWidth}x${newHeight}, scale=$scale")

        return ScaleResult(
            bitmap = resized,
            appliedScale = scale,
            originalWidth = originalWidth,
            originalHeight = originalHeight,
            scaledWidth = newWidth,
            scaledHeight = newHeight
        )
    }

    /**
     * 使用预设质量档位缩放 Bitmap
     */
    @JvmStatic
    fun scaleBitmap(bitmap: Bitmap, quality: ImageQuality): ScaleResult {
        return scaleBitmap(bitmap, quality.scale, quality.bypassThreshold)
    }

    // ==================== 压缩 Bitmap 并生成 Base64 ====================

    /**
     * 压缩 Bitmap 图片并生成 Base64（不保留 Bitmap）
     *
     * 注意：此函数不会回收传入的 Bitmap，调用者需自行管理 Bitmap 生命周期
     *
     * @param bitmap 原始 Bitmap（由调用者自行回收）
     * @param scale 目标缩放比例 (0-1之间，默认0.5)
     * @param quality JPEG 压缩质量 (1-100，默认100)
     * @param bypassThreshold 像素阈值，低于此值不缩放 (默认 1.2MP)。设为 0 表示无条件压缩
     * @return 压缩结果，包含压缩后的 Base64 和元信息
     */
    @JvmStatic
    @JvmOverloads
    fun compressBitmapImage(
        bitmap: Bitmap,
        scale: Float = 0.5f,
        quality: Int = 100,
        bypassThreshold: Long = RESIZE_BYPASS_PIXEL_THRESHOLD
    ): CompressResult {
        val originalWidth = bitmap.width
        val originalHeight = bitmap.height
        val pixelCount = originalWidth.toLong() * originalHeight.toLong()

        // scale >= 1 或像素数低于阈值时，不缩放
        if (scale >= 1f || pixelCount < bypassThreshold) {
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
            val base64 = Base64.encodeToString(outputStream.toByteArray(), Base64.DEFAULT)
            return CompressResult(
                base64 = JPEG_DATA_URI_PREFIX + base64,
                appliedScale = 1f,
                originalWidth = originalWidth,
                originalHeight = originalHeight,
                compressedWidth = originalWidth,
                compressedHeight = originalHeight
            )
        }

        val newWidth = (originalWidth * scale).toInt().coerceAtLeast(1)
        val newHeight = (originalHeight * scale).toInt().coerceAtLeast(1)

        val resized = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
        val outputStream = ByteArrayOutputStream()
        resized.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
        val resizedBase64 = Base64.encodeToString(outputStream.toByteArray(), Base64.DEFAULT)

        OmniLog.d(TAG, "Bitmap compressed: ${originalWidth}x${originalHeight} -> ${newWidth}x${newHeight}, scale=$scale")

        // 回收内部创建的 resized bitmap（如果与原 bitmap 不同）
        if (resized != bitmap && !resized.isRecycled) {
            resized.recycle()
        }

        return CompressResult(
            base64 = JPEG_DATA_URI_PREFIX + resizedBase64,
            appliedScale = scale,
            originalWidth = originalWidth,
            originalHeight = originalHeight,
            compressedWidth = newWidth,
            compressedHeight = newHeight
        )
    }

    /**
     * 使用预设质量档位压缩 Bitmap 并生成 Base64
     */
    @JvmStatic
    fun compressBitmapImage(bitmap: Bitmap, quality: ImageQuality): CompressResult {
        return compressBitmapImage(bitmap, quality.scale, quality.quality, quality.bypassThreshold)
    }

    // ==================== 压缩 Base64 图片 ====================

    /**
     * 压缩 Base64 编码的图片
     *
     * @param base64String 原始 Base64 图片字符串 (可带 data:image/xxx;base64, 前缀)
     * @param scale 目标缩放比例 (0-1之间，默认0.5)
     * @param quality JPEG 压缩质量 (1-100，默认100)
     * @param bypassThreshold 像素阈值，低于此值不缩放 (默认 1.2MP)。设为 0 表示无条件压缩（无门槛）
     * @return 压缩结果，包含压缩后的 Base64 和元信息
     */
    @JvmStatic
    @JvmOverloads
    fun compressBase64Image(
        base64String: String,
        scale: Float = 0.5f,
        quality: Int = 100,
        bypassThreshold: Long = RESIZE_BYPASS_PIXEL_THRESHOLD
    ): CompressResult {
        // scale >= 1 时无需缩放，直接返回原图
        if (scale >= 1f) {
            return parseAndReturnOriginal(base64String)
        }

        return try {
            // 去除 data:image/xxx;base64, 前缀
            val cleanBase64 = base64String.substringAfter(",")
            val imageBytes = Base64.decode(cleanBase64, Base64.DEFAULT)
            val bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
                ?: return parseAndReturnOriginal(base64String)

            val originalWidth = bitmap.width
            val originalHeight = bitmap.height
            val pixelCount = originalWidth.toLong() * originalHeight.toLong()

            // 像素数低于阈值时跳过缩放
            if (pixelCount < bypassThreshold) {
                OmniLog.d(TAG, "Skip resize: ${originalWidth}x${originalHeight} (${pixelCount} px) < $bypassThreshold px")
                if (!bitmap.isRecycled) bitmap.recycle()
                return CompressResult(
                    base64 = base64String,
                    appliedScale = 1f,
                    originalWidth = originalWidth,
                    originalHeight = originalHeight,
                    compressedWidth = originalWidth,
                    compressedHeight = originalHeight
                )
            }

            val newWidth = (originalWidth * scale).toInt().coerceAtLeast(1)
            val newHeight = (originalHeight * scale).toInt().coerceAtLeast(1)

            val resized = Bitmap.createScaledBitmap(bitmap, newWidth, newHeight, true)
            val outputStream = ByteArrayOutputStream()
            resized.compress(Bitmap.CompressFormat.JPEG, quality, outputStream)
            val resizedBytes = outputStream.toByteArray()
            val resizedBase64 = Base64.encodeToString(resizedBytes, Base64.DEFAULT)

            OmniLog.d(TAG, "Compressed: ${originalWidth}x${originalHeight} -> ${newWidth}x${newHeight}, scale=$scale, quality=$quality, bypassThreshold=$bypassThreshold")

            // 回收 Bitmap
            if (bitmap != resized && !bitmap.isRecycled) {
                bitmap.recycle()
            }
            if (!resized.isRecycled) {
                resized.recycle()
            }

            // 保留原始前缀
            val finalBase64 = if (base64String.contains(",")) {
                base64String.substringBefore(",") + "," + resizedBase64
            } else {
                resizedBase64
            }

            CompressResult(
                base64 = finalBase64,
                appliedScale = scale,
                originalWidth = originalWidth,
                originalHeight = originalHeight,
                compressedWidth = newWidth,
                compressedHeight = newHeight
            )
        } catch (e: Exception) {
            OmniLog.e(TAG, "Failed to compress image: ${e.message}", e)
            parseAndReturnOriginal(base64String)
        }
    }

    /**
     * 使用预设质量档位压缩 Base64 图片
     */
    @JvmStatic
    fun compressBase64Image(base64String: String, quality: ImageQuality): CompressResult {
        return compressBase64Image(base64String, quality.scale, quality.quality, quality.bypassThreshold)
    }


    /**
     * 解析原始图片尺寸并返回未压缩的结果
     */
    private fun parseAndReturnOriginal(base64String: String): CompressResult {
        var width = 0
        var height = 0
        try {
            val cleanBase64 = base64String.substringAfter(",")
            val imageBytes = Base64.decode(cleanBase64, Base64.DEFAULT)
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            width = options.outWidth
            height = options.outHeight
        } catch (e: Exception) {
            OmniLog.e(TAG, "Failed to parse image dimensions: ${e.message}", e)
        }
        return CompressResult(
            base64 = base64String,
            appliedScale = 1f,
            originalWidth = width,
            originalHeight = height,
            compressedWidth = width,
            compressedHeight = height
        )
    }
}
