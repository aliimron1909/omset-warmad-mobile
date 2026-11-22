package com.rffamily.warmad

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "warmad/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidId" -> {
                    val id = Settings.Secure.getString(
                        contentResolver,
                        Settings.Secure.ANDROID_ID
                    ) ?: ""
                    result.success(id)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "warmad/storage"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDocumentsPath" -> result.success(applicationContext.filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }
    }
}
