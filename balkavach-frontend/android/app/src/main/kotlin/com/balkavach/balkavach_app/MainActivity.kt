package com.balkavach.balkavach_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Talk to Panda: device speech capabilities and app-settings deep link.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "balkavach/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "onDeviceAvailable" -> result.success(
                        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                            runCatching { SpeechRecognizer.isOnDeviceRecognitionAvailable(this) }
                                .getOrDefault(false)
                    )
                    "isRecognitionAvailable" -> result.success(
                        runCatching { SpeechRecognizer.isRecognitionAvailable(this) }
                            .getOrDefault(false)
                    )
                    "openAppSettings" -> {
                        val opened = runCatching {
                            val intent = Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                            true
                        }.getOrDefault(false)
                        result.success(opened)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
