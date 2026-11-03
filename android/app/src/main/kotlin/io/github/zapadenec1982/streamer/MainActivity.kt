package io.github.zapadenec1982.streamer

import android.content.Intent
import android.provider.OpenableColumns
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * While the app is on the screen and a panel is chosen, the phone's volume buttons move the
 * panel's volume, not the phone's: each press goes to Dart as +1 or -1 (a held button repeats),
 * and Dart turns it into audio.volume. In the background the buttons are the phone's again.
 */
class MainActivity : FlutterActivity() {
    private var intercept = false
    private var presses: EventChannel.EventSink? = null

    // a document picked or being saved: one at a time
    private var pending: MethodChannel.Result? = null
    private var saving: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "streamer/volume_keys").setMethodCallHandler { call, result ->
            if (call.method == "intercept") {
                intercept = call.arguments == true
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        // Countries by their ISO codes, in the app's language: the catalogue's country list. The
        // web asks Intl.DisplayNames; here the phone's own locale data says it.
        MethodChannel(messenger, "streamer/regions").setMethodCallHandler { call, result ->
            if (call.method == "names") {
                val codes = call.argument<List<String>>("codes").orEmpty()
                val language = java.util.Locale(call.argument<String>("language") ?: "en")
                result.success(
                    codes.associateWith { code ->
                        java.util.Locale("", code).getDisplayCountry(language).ifEmpty { code }
                    },
                )
            } else {
                result.notImplemented()
            }
        }
        // A file the person picks, and one saved where they choose: the system's own document
        // picker (the Storage Access Framework), no storage permission — a firmware image, a
        // backup, a playlist, EQ filters: what the web takes from <input type=file> and downloads.
        MethodChannel(messenger, "streamer/files").setMethodCallHandler { call, result ->
            if (pending != null) {
                result.error("busy", null, null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "open" -> {
                    val types = call.argument<List<String>>("types").orEmpty()
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        if (types.isNotEmpty()) putExtra(Intent.EXTRA_MIME_TYPES, types.toTypedArray())
                    }
                    pending = result
                    startActivityForResult(intent, OPEN_DOCUMENT)
                }
                "save" -> {
                    val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("type") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "file")
                    }
                    saving = call.argument<ByteArray>("bytes")
                    pending = result
                    startActivityForResult(intent, SAVE_DOCUMENT)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "streamer/volume_keys/presses").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    presses = events
                }

                override fun onCancel(arguments: Any?) {
                    presses = null
                }
            },
        )
    }

    @Deprecated("the picker's answer; FlutterActivity is no ComponentActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != OPEN_DOCUMENT && requestCode != SAVE_DOCUMENT) return
        val result = pending ?: return
        pending = null
        val bytes = saving
        saving = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        try {
            if (requestCode == OPEN_DOCUMENT) {
                val read = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                    ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
                    ?: uri.lastPathSegment.orEmpty()
                result.success(mapOf("name" to name, "bytes" to (read ?: ByteArray(0))))
            } else {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes ?: ByteArray(0)) }
                result.success(true)
            }
        } catch (e: Exception) {
            result.error("io", e.message, null)
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val step = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> 1
            KeyEvent.KEYCODE_VOLUME_DOWN -> -1
            else -> 0
        }
        val sink = presses
        if (step != 0 && intercept && sink != null) {
            if (event.action == KeyEvent.ACTION_DOWN) sink.success(step)
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    private companion object {
        const val OPEN_DOCUMENT = 7101
        const val SAVE_DOCUMENT = 7102
    }
}
