package com.example.script_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID

/**
 * A5 头像图片选择：通过系统选择器取图，不引入第三方插件。
 *
 * 为什么用 MethodChannel 而不是新增 picker 插件：
 *   1. `rules.md` 与开发规格要求不得私自新增依赖，本能力用平台原生 API 即可完成；
 *   2. 选择结果只需「文件路径」，最小实现就是系统选择器 + 复制到应用缓存目录。
 *
 * 实现要点（注意：本注释内不得出现斜杠星号组合，否则会提前结束注释）：
 *   1. 用 ACTION_GET_CONTENT 配合图片 MIME 类型选择器（无需运行时权限），
 *      它返回带临时授权的 content URI，因此必须复制到应用私有目录后才能稳定读取；
 *   2. 复制到 cacheDir/avatar_pick/，不把外部 URI 权限带进上传流程；
 *   3. 只把路径交回 Dart，不记录文件内容或选择结果到日志。
 */
class MainActivity : FlutterActivity() {

    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickImage(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickImage(result: MethodChannel.Result) {
        if (pendingResult != null) {
            // 已有选择器在前台，避免并发回调错位
            result.error("busy", "image picker already active", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/jpeg", "image/png", "image/gif", "image/bmp", "image/x-ms-bmp"))
        }
        try {
            startActivityForResult(Intent.createChooser(intent, "选择图片"), REQUEST_PICK)
        } catch (e: Exception) {
            pendingResult = null
            result.error("unavailable", "no activity available for image picking", null)
        }
    }

    @Deprecated("最小实现沿用 startActivityForResult；模板未引入 AndroidX Activity Result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val pending = pendingResult
        if (pending == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            pendingResult = null
            // 用户取消：回 null，Dart 侧按「未选择」处理，不当作错误
            pending.success(null)
            return
        }
        val uri: Uri? = data?.data
        if (uri == null) {
            pendingResult = null
            pending.success(null)
            return
        }
        // URI 可能来自慢速或云端文件提供方，复制与格式识别均在后台完成。
        Thread {
            try {
                val copied = copyToCache(uri)
                runOnUiThread {
                    pendingResult = null
                    pending.success(copied)
                }
            } catch (e: ImagePickException) {
                runOnUiThread {
                    pendingResult = null
                    pending.error(e.code, e.message, null)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    pendingResult = null
                    pending.error("copy_failed", "无法读取所选图片，请重试", null)
                }
            }
        }.start()
    }

    /** 限量复制，并根据实际文件头保留格式；任何失败都删除部分缓存。 */
    private fun copyToCache(uri: Uri): String {
        val dir = File(cacheDir, "avatar_pick")
        if (!dir.exists() && !dir.mkdirs()) {
            throw ImagePickException("copy_failed", "无法读取所选图片，请重试")
        }
        val input: InputStream = contentResolver.openInputStream(uri)
            ?: throw ImagePickException("copy_failed", "无法读取所选图片，请重试")
        return input.buffered().use { source ->
            source.mark(12)
            val header = ByteArray(12)
            var count = 0
            while (count < header.size) {
                val read = source.read(header, count, header.size - count)
                if (read < 0) break
                count += read
            }
            source.reset()
            if (count == 0) throw ImagePickException("empty", "图片不能为空")
            val format = when {
                count >= 3 && header[0] == 0xff.toByte() && header[1] == 0xd8.toByte() && header[2] == 0xff.toByte() -> "jpg"
                count >= 8 && header.take(8).toByteArray().contentEquals(byteArrayOf(0x89.toByte(), 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)) -> "png"
                count >= 6 && String(header, 0, 6, Charsets.US_ASCII) in arrayOf("GIF87a", "GIF89a") -> "gif"
                count >= 2 && header[0] == 0x42.toByte() && header[1] == 0x4d.toByte() -> "bmp"
                else -> throw ImagePickException("format", "请选择 JPG、PNG、GIF 或 BMP 图片")
            }
            val target = File(dir, UUID.randomUUID().toString() + "." + format)
            try {
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(8192)
                    var total = 0L
                    while (true) {
                        val read = source.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_IMAGE_BYTES) throw ImagePickException("too_large", "图片不能超过 5 MB")
                        output.write(buffer, 0, read)
                    }
                }
                target.absolutePath
            } catch (e: Exception) {
                target.delete()
                throw e
            }
        }
    }

    private class ImagePickException(val code: String, message: String) : Exception(message)

    companion object {
        private const val CHANNEL = "smartscript/native_image"
        private const val REQUEST_PICK = 4101
        private const val MAX_IMAGE_BYTES = 5 * 1024 * 1024L
    }
}
