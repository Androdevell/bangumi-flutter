package com.bgm.irena

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val highRefreshRateController by lazy { HighRefreshRateController(this) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        highRefreshRateController.apply()
    }

    override fun onResume() {
        super.onResume()
        highRefreshRateController.apply()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) highRefreshRateController.apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BangumiNetworkBridge.CHANNEL_NAME,
        ).setMethodCallHandler(BangumiNetworkBridge(this))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AndroidSecureVault.CHANNEL_NAME,
        ).setMethodCallHandler(AndroidSecureVault(this))
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DISPLAY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestHighestRefreshRate" -> {
                    highRefreshRateController.apply()
                    result.success(highRefreshRateController.displayInfo())
                }

                "getDisplayInfo" -> result.success(highRefreshRateController.displayInfo())
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_ICON_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "setAppIcon") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val style = call.argument<String>("style")
            val selected = if (style == "anime") ANIME_ICON else CLASSIC_ICON
            val unselected = if (style == "anime") CLASSIC_ICON else ANIME_ICON
            packageManager.setComponentEnabledSetting(
                ComponentName(this, "$packageName.$selected"),
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                PackageManager.DONT_KILL_APP,
            )
            packageManager.setComponentEnabledSetting(
                ComponentName(this, "$packageName.$unselected"),
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                PackageManager.DONT_KILL_APP,
            )
            result.success(true)
        }
    }

    companion object {
        private const val DISPLAY_CHANNEL = "bangumi_flutter/display"
        private const val APP_ICON_CHANNEL = "com.bgm.irena/app-icon"
        private const val CLASSIC_ICON = "ClassicIcon"
        private const val ANIME_ICON = "AnimeIcon"
    }
}
