package com.bgm.irena

import android.content.ContentValues
import android.content.Context
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 仅将应用缓存中的已校验图片复制到相册，不申请整个存储空间的权限。
 */
class ImageSaveBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "saveImage") {
            result.notImplemented()
            return
        }
        var inserted: android.net.Uri? = null
        try {
            val file = File(requireNotNull(call.argument<String>("path"))).canonicalFile
            require(file.path.startsWith(context.cacheDir.canonicalPath + File.separator))
            require(file.isFile && file.length() in 1L..(20L * 1024 * 1024))
            val mime = requireNotNull(call.argument<String>("mime"))
            val extension = mapOf("image/png" to "png", "image/jpeg" to "jpg",
                "image/gif" to "gif", "image/webp" to "webp", "image/bmp" to "bmp",
                "image/avif" to "avif")[mime] ?: error("Unsupported image")
            val name = "bangumi-${System.currentTimeMillis()}.$extension"
            val values = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, name)
                put(MediaStore.Images.Media.MIME_TYPE, mime)
                put(MediaStore.Images.Media.RELATIVE_PATH, "${Environment.DIRECTORY_PICTURES}/Bangumi")
                put(MediaStore.Images.Media.IS_PENDING, 1)
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                ?: error("Cannot create image")
            inserted = uri
            resolver.openOutputStream(uri)?.use { output ->
                file.inputStream().use { input -> input.copyTo(output) }
            } ?: error("Cannot open image")
            values.clear()
            values.put(MediaStore.Images.Media.IS_PENDING, 0)
            check(resolver.update(uri, values, null, null) == 1)
            result.success(true)
        } catch (_: Exception) {
            inserted?.let { runCatching { context.contentResolver.delete(it, null, null) } }
            result.error("save_image_failed", "Unable to save image", null)
        }
    }
}
