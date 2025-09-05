package com.example.ord_project

import android.view.WindowManager
import android.os.Build
import android.content.ContentValues
import android.provider.MediaStore
import android.net.Uri
import java.io.OutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "screen_secure"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    runOnUiThread { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                    result.success(null)
                }
                "disable" -> {
                    runOnUiThread { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE) }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "downloads_saver"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "save" -> {
                    val args = call.arguments as? Map<*, *>
                    val name = args?.get("name") as? String
                    val bytes = args?.get("bytes") as? ByteArray
                    if (name == null || bytes == null) {
                        result.error("bad_args", "Missing name/bytes", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val savedAt = saveToDownloads(name, bytes)
                        result.success(savedAt)
                    } catch (e: Exception) {
                        result.error("save_failed", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(name: String, bytes: ByteArray): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, mimeFromName(name))
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val itemUri: Uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Failed to create download entry")
            resolver.openOutputStream(itemUri)?.use { os: OutputStream ->
                os.write(bytes)
            } ?: throw IllegalStateException("Failed to open stream")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(itemUri, values, null, null)
            itemUri.toString()
        } else {
            // For older devices, fall back to app-specific external files dir (visible via file managers)
            val dir = getExternalFilesDir(null) ?: applicationContext.filesDir
            val file = java.io.File(dir, name)
            file.outputStream().use { it.write(bytes) }
            file.absolutePath
        }
    }

    private fun mimeFromName(name: String): String {
        val lower = name.lowercase()
        return when {
            lower.endsWith(".pdf") -> "application/pdf"
            lower.endsWith(".png") -> "image/png"
            lower.endsWith(".jpg") || lower.endsWith(".jpeg") -> "image/jpeg"
            lower.endsWith(".gif") -> "image/gif"
            else -> "application/octet-stream"
        }
    }
}
