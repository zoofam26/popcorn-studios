package com.popcornstudio.popcorn_studio

import android.content.pm.ApplicationInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Exposes platform details to the Dart side:
 *  - `getNativeLibraryDir`: where bundled `lib*.so` executables (the aria2
 *    engine binary) are extracted and marked executable by the package
 *    installer. This is the only location Android 10+ reliably allows
 *    `exec()` from.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "com.popcornstudio.popcorn_studio/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                    else -> result.notImplemented()
                }
            }
    }
}
