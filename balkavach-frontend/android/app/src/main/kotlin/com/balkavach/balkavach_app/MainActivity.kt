package com.balkavach.balkavach_app

import android.os.Build
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Talk to Panda: whether this phone has an on-device (offline) speech
        // recogniser. Same check speech_to_text uses to pick its on-device
        // recogniser; when this is false that plugin would silently use the
        // cloud recogniser instead, so the app must know before listening.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balkavach/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "onDeviceAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(this) }
                                .getOrDefault(false)
                    )
                    else -> result.notImplemented()
                }
            }
    }
}
