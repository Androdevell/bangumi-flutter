package com.bgm.irena

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
    }

    companion object {
        private const val DISPLAY_CHANNEL = "bangumi_flutter/display"
    }
}
