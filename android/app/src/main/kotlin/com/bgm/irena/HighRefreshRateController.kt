package com.bgm.irena

import android.app.Activity
import android.os.Build
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import java.util.WeakHashMap

/**
 * 为窗口和 Flutter 渲染 Surface 请求设备支持的最高刷新率。
 *
 * Android 将刷新率请求视为偏好，厂商的省电模式或应用级刷新率设置仍可覆盖该请求。
 */
class HighRefreshRateController(
    private val activity: Activity,
) {
    private val surfaceCallbacks = WeakHashMap<SurfaceView, SurfaceHolder.Callback>()
    private var requestedRefreshRate = 0f

    fun apply() {
        val display = activity.display ?: return
        val currentMode = display.mode
        val targetMode = display.supportedModes
            .asSequence()
            .filter {
                it.physicalWidth == currentMode.physicalWidth &&
                        it.physicalHeight == currentMode.physicalHeight
            }
            .maxByOrNull { it.refreshRate }
            ?: currentMode

        requestedRefreshRate = targetMode.refreshRate
        activity.window.attributes = activity.window.attributes.apply {
            preferredDisplayModeId = targetMode.modeId
            preferredRefreshRate = targetMode.refreshRate
        }

        activity.window.decorView.post {
            applyToSurfaces(activity.window.decorView, targetMode.refreshRate)
        }
        activity.window.decorView.postDelayed(
            { applyToSurfaces(activity.window.decorView, targetMode.refreshRate) },
            SURFACE_RETRY_DELAY_MILLIS,
        )
    }

    fun displayInfo(): Map<String, Any> {
        val display = activity.display
        val currentMode = display?.mode
        val rates = display?.supportedModes
            ?.filter {
                currentMode == null ||
                        (it.physicalWidth == currentMode.physicalWidth &&
                                it.physicalHeight == currentMode.physicalHeight)
            }
            ?.map { it.refreshRate }
            ?.distinct()
            ?.sorted()
            ?: emptyList()

        return mapOf(
            "currentRefreshRate" to (display?.refreshRate ?: 0f),
            "requestedRefreshRate" to requestedRefreshRate,
            "supportedRefreshRates" to rates,
        )
    }

    private fun applyToSurfaces(view: View, refreshRate: Float) {
        if (view is SurfaceView) {
            applyToSurface(view.holder.surface, refreshRate)
            if (!surfaceCallbacks.containsKey(view)) {
                val callback = object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        applyToSurface(holder.surface, refreshRate)
                    }

                    override fun surfaceChanged(
                        holder: SurfaceHolder,
                        format: Int,
                        width: Int,
                        height: Int,
                    ) {
                        applyToSurface(holder.surface, refreshRate)
                    }

                    override fun surfaceDestroyed(holder: SurfaceHolder) = Unit
                }
                surfaceCallbacks[view] = callback
                view.holder.addCallback(callback)
            }
        }

        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                applyToSurfaces(view.getChildAt(index), refreshRate)
            }
        }
    }

    private fun applyToSurface(surface: Surface, refreshRate: Float) {
        if (!surface.isValid) return
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                surface.setFrameRate(
                    refreshRate,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                    Surface.CHANGE_FRAME_RATE_ALWAYS,
                )
            } else {
                surface.setFrameRate(
                    refreshRate,
                    Surface.FRAME_RATE_COMPATIBILITY_DEFAULT,
                )
            }
        }
    }

    companion object {
        private const val SURFACE_RETRY_DELAY_MILLIS = 500L
    }
}
