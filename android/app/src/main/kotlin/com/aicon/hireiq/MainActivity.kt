package com.aicon.hireiq

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.aicon.hireiq/version"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getAppVersion") {
                try {
                    val packageInfo = packageManager.getPackageInfo(packageName, 0)
                    val versionName = packageInfo.versionName
                    val versionCode = packageInfo.versionCode
                    result.success("$versionName ($versionCode)")
                } catch (e: PackageManager.NameNotFoundException) {
                    result.error("VERSION_ERROR", "Could not get version info", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }
}
