package com.example.script_app

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * 把应用私有目录下的 APK 以 content:// 交给系统安装器。
 *
 * 为什么不用 androidx.core 的 FileProvider：在 Android 16（16KB 页）的 release 构建里，
 * FileProvider.attachInfo 会 SIGSEGV 导致应用启动即崩溃（debug 不会，属该库与 ART 的兼容问题）。
 * 这里只实现安装器真正需要的最小能力：openFile + getType + 文件名字段，
 * 并经文件名白名单限定到固定目录，不解析任何 XML。
 */
class ApkContentProvider : ContentProvider() {

    override fun onCreate(): Boolean = true

    /** 允许共享的目录：外部专属目录（下载目录）与缓存（兜底）。 */
    private fun roots(): List<File> = listOfNotNull(
        context?.getExternalFilesDir(null),
        context?.cacheDir,
    )

    private fun resolve(uri: Uri): File {
        val segments = uri.pathSegments
        if (segments.isEmpty() || segments.size > 2) throw FileNotFoundException("非法路径")
        for (segment in segments) {
            // 逐段校验，杜绝 ../ 或分隔符越级
            if (segment.isEmpty() || segment.contains('/') || segment.contains('\\') || segment.contains("..")) {
                throw FileNotFoundException("非法文件名")
            }
        }
        val sub = segments.dropLast(1).joinToString("/")
        if (sub.isNotEmpty() && sub != UPDATES_DIR) throw FileNotFoundException("非法目录")
        for (root in roots()) {
            val base = (if (sub.isEmpty()) root else File(root, sub)).canonicalFile
            val canonical = File(base, segments.last()).canonicalFile
            if (canonical.parentFile == base && canonical.isFile) {
                return canonical
            }
        }
        throw FileNotFoundException("文件不存在")
    }

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("只读")
        return ParcelFileDescriptor.open(resolve(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "application/vnd.android.package-archive"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? {
        val file = try {
            resolve(uri)
        } catch (e: FileNotFoundException) {
            return null
        }
        val columns = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).apply {
            addRow(arrayOf(file.name, file.length()))
        }
    }

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    companion object {
        /** 应用内更新的下载子目录（与 ApkInstaller.downloadDirectory 保持一致）。 */
        const val UPDATES_DIR = "updates"

        /** 为 [file] 生成 content:// 地址；只接受专属目录根级或 updates/ 下的文件。 */
        fun uriFor(context: Context, file: File): Uri {
            val canonical = file.canonicalFile
            val roots = listOfNotNull(context.getExternalFilesDir(null), context.cacheDir)
            for (root in roots) {
                val rootCanonical = root.canonicalFile
                val updates = File(rootCanonical, UPDATES_DIR).canonicalFile
                val inUpdates = canonical.parentFile == updates
                if (canonical.parentFile == rootCanonical || inUpdates) {
                    val builder = Uri.Builder()
                        .scheme("content")
                        .authority("${context.packageName}.fileprovider")
                    if (inUpdates) builder.appendPath(UPDATES_DIR)
                    return builder.appendPath(canonical.name).build()
                }
            }
            throw IllegalArgumentException("只共享应用专属目录根级或 updates/ 下的文件")
        }
    }
}
