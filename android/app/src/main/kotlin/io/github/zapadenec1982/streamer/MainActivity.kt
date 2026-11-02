package io.github.zapadenec1982.streamer

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
}
