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
        pendingResult = null
        if (pending == null) {
            return
        }
        if (resultCode != Activity.RESULT_OK) {
            // 用户取消：回 null，Dart 侧按「未选择」处理，不当作错误
            pending.success(null)
            return
        }
        val uri: Uri? = data?.data
        if (uri == null) {
            pending.success(null)
            return
        }
        try {
            val copied = copyToCache(uri)
            if (copied == null) {
                pending.error("copy_failed", "selected image could not be read", null)
            } else {
                pending.success(copied)
            }
        } catch (e: Exception) {
            pending.error("copy_failed", "selected image could not be read", null)
        }
    }

    /** 复制到应用缓存目录并返回绝对路径；无法读取时返回 null。 */
    private fun copyToCache(uri: Uri): String? {
        val dir = File(cacheDir, "avatar_pick")
        if (!dir.exists() && !dir.mkdirs()) {
            return null
        }
        // 每次选择新建文件，避免旧文件残留造成脏读
        val target = File(dir, UUID.randomUUID().toString() + ".img")
        val input: InputStream = contentResolver.openInputStream(uri) ?: return null
        input.use { source ->
            FileOutputStream(target).use { output ->
                source.copyTo(output)
            }
        }
        return if (target.length() > 0L) target.absolutePath else null
    }

    companion object {
        private const val CHANNEL = "smartscript/native_image"
        private const val REQUEST_PICK = 4101
    }
}
