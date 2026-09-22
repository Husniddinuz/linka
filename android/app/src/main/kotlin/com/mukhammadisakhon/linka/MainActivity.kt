package com.mukhammadisakhon.linka

import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Course Reels: FLAG_SECURE blanks the window in screenshots, screen
        // recordings, casting and the recents thumbnail while a course video
        // is on screen (lib/services/screen_security_service.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "linka/screen_security")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") == true
                        runOnUiThread {
                            if (secure) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                            }
                            result.success(null)
                        }
                    }
                    // Android has no capture signal; FLAG_SECURE already blanks it.
                    "isCaptured" -> result.success(false)
                    else -> result.notImplemented()
                }
            }
    }
}
