package com.example.script_app

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.util.UUID

/**
 * A5 原生能力网关（不引入第三方插件，只用平台 API）。
 *
 * 1. 头像图片选择（pickImage）：用 ACTION_GET_CONTENT 取图，复制到应用私有缓存后回传路径。
 * 2. 本地通知（showNotification / ensureNotificationPermission）：App 运行时轮询到新消息后，
 *    通过系统通知横幅提示（Android 8+ 通知渠道；Android 13+ 需先申请 POST_NOTIFICATIONS 运行时权限）。
 *    注意：这是 App 进程存活时的本地通知，不是离线推送；App 被系统杀掉后收不到。
 */
class MainActivity : FlutterActivity() {

    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ensureNotificationChannel()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImage" -> pickImage(result)
                    else -> result.notImplemented()
                }
            }
        MethodChannel(messenger, CHANNEL_NOTIFY)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showNotification" -> showNotification(call, result)
                    "ensureNotificationPermission" -> ensureNotificationPermission(result)
                    else -> result.notImplemented()
                }
            }
    }

    /** 创建通知渠道（Android 8+，幂等）。 */
    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "消息通知",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "平台消息与审核结果提醒"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    /**
     * 弹出系统通知。入参：id(Int)、title(String)、body(String)。
     * 点击通知回到本 App（单实例，singleTop）。
     */
    private fun showNotification(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        try {
            val id = call.argument<Int>("id") ?: (System.currentTimeMillis() % Int.MAX_VALUE).toInt()
            val title = call.argument<String>("title") ?: "新消息"
            val body = call.argument<String>("body") ?: ""
            val manager = getSystemService(NotificationManager::class.java)
            if (manager == null) {
                result.success(false)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
            ) {
                // 无通知权限：不弹窗，由 Dart 侧决定是否引导申请
                result.success(false)
                return
            }
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val pendingIntent = PendingIntent.getActivity(
                this, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            val notification = builder
                .setSmallIcon(applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .build()
            manager.notify(id, notification)
            result.success(true)
        } catch (e: Exception) {
            result.error("notify_failed", "通知发送失败", null)
        }
    }

    /**
     * 申请通知运行时权限（Android 13+ POST_NOTIFICATIONS），其余版本直接视为已授予。
     * 权限对话框结果在 onRequestPermissionsResult 中回传。
     */
    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.success(false)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATION_PERMISSION)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }
        val pending = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending?.success(granted)
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
        private const val CHANNEL_NOTIFY = "smartscript/native_notify"
        private const val REQUEST_NOTIFICATION_PERMISSION = 4102
        private const val NOTIFICATION_CHANNEL_ID = "smartscript_messages"
    }
}
