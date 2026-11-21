package com.reelcount.app.overlay

import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowInsets
import android.view.WindowManager
import android.view.WindowMetrics
import com.reelcount.app.storage.BubblePosition
import com.reelcount.app.storage.BubblePositionKind
import com.reelcount.app.storage.BubblePreferences
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

internal data class ManagedOverlay(
    val kind: BubblePositionKind,
    val view: View,
    val params: WindowManager.LayoutParams,
)

internal class BubblePositionManager(
    context: Context,
    private val preferences: BubblePreferences,
    private val onPermissionLost: () -> Unit,
) {
    private val appContext = context.applicationContext
    private val windowManager = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val density = appContext.resources.displayMetrics.density
    private val touchSlop = ViewConfiguration.get(appContext).scaledTouchSlop
    private val margin = dp(12)
    private val snapDistance = dp(56)

    fun dp(value: Int): Int = (value * density).roundToInt()

    fun dpFloat(value: Int): Float = value * density

    fun expandedWidth(): Int {
        val available = bounds().width() - margin * 2
        return min(dp(280), max(1, available))
    }

    fun createParams(kind: BubblePositionKind, view: View): WindowManager.LayoutParams {
        val width = when (kind) {
            BubblePositionKind.COLLAPSED -> dp(BUBBLE_SIZE_DP)
            BubblePositionKind.EXPANDED -> expandedWidth()
        }
        val height = when (kind) {
            BubblePositionKind.COLLAPSED -> dp(BUBBLE_SIZE_DP)
            BubblePositionKind.EXPANDED -> WindowManager.LayoutParams.WRAP_CONTENT
        }
        val params = baseParams(width, height)
        restorePosition(kind, ManagedOverlay(kind, view, params))
        return params
    }

    fun restorePosition(kind: BubblePositionKind, overlay: ManagedOverlay) {
        val bounds = bounds()
        val size = measure(overlay)
        val stored = preferences.getPosition(kind)
        if (stored == null) {
            val statusBar = statusBarHeight()
            overlay.params.x = bounds.right - size.width - margin
            overlay.params.y = bounds.top + statusBar + margin
        } else {
            overlay.params.x = if (stored.width > 0) {
                (stored.x.toFloat() * bounds.width().toFloat() / stored.width.toFloat()).roundToInt()
            } else {
                stored.x
            }
            overlay.params.y = if (stored.height > 0) {
                (stored.y.toFloat() * bounds.height().toFloat() / stored.height.toFloat()).roundToInt()
            } else {
                stored.y
            }
        }
        clamp(overlay)
    }

    fun repositionAll(overlays: List<ManagedOverlay>) {
        overlays.forEach { overlay ->
            restorePosition(overlay.kind, overlay)
            if (overlay.view.isAttachedToWindow) {
                update(overlay)
            }
        }
    }

    fun alignExpandedToCollapsed(collapsed: ManagedOverlay, expanded: ManagedOverlay) {
        val collapsedSize = measure(collapsed)
        val expandedSize = measure(expanded)
        val bounds = bounds()
        val collapsedCenter = collapsed.params.x + collapsedSize.width / 2f
        expanded.params.x = if (collapsedCenter < bounds.centerX()) {
            collapsed.params.x
        } else {
            collapsed.params.x + collapsedSize.width - expandedSize.width
        }
        expanded.params.y = collapsed.params.y - expandedSize.height - margin
        if (expanded.params.y < bounds.top + margin) {
            expanded.params.y = collapsed.params.y + collapsedSize.height + margin
        }
        clamp(expanded)
    }

    fun savePosition(overlay: ManagedOverlay) {
        val size = measure(overlay)
        preferences.savePosition(
            overlay.kind,
            BubblePosition(overlay.params.x, overlay.params.y, size.width, size.height),
        )
    }

    fun add(overlay: ManagedOverlay): Boolean {
        if (!canDrawOverlays()) {
            onPermissionLost()
            return false
        }
        if (overlay.view.isAttachedToWindow) {
            return true
        }
        return try {
            windowManager.addView(overlay.view, overlay.params)
            true
        } catch (_: WindowManager.BadTokenException) {
            false
        } catch (_: IllegalStateException) {
            overlay.view.isAttachedToWindow
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            onPermissionLost()
            false
        }
    }

    fun update(overlay: ManagedOverlay): Boolean {
        if (!overlay.view.isAttachedToWindow) {
            return false
        }
        if (!canDrawOverlays()) {
            onPermissionLost()
            return false
        }
        return try {
            windowManager.updateViewLayout(overlay.view, overlay.params)
            true
        } catch (_: WindowManager.BadTokenException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            onPermissionLost()
            false
        }
    }

    fun remove(overlay: ManagedOverlay) {
        if (!overlay.view.isAttachedToWindow) {
            return
        }
        try {
            windowManager.removeViewImmediate(overlay.view)
        } catch (_: WindowManager.BadTokenException) {
        } catch (_: IllegalArgumentException) {
        } catch (_: SecurityException) {
            onPermissionLost()
        }
    }

    fun attachDrag(
        overlay: ManagedOverlay,
        touchTarget: View = overlay.view,
        sizeSource: View = overlay.view,
    ) {
        val measuredOverlay = ManagedOverlay(overlay.kind, sizeSource, overlay.params)
        var pointerId = -1
        var startX = 0f
        var startY = 0f
        var startParamX = 0
        var startParamY = 0
        var moved = false

        touchTarget.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    pointerId = event.getPointerId(0)
                    startX = event.rawX
                    startY = event.rawY
                    startParamX = overlay.params.x
                    startParamY = overlay.params.y
                    moved = false
                    true
                }

                MotionEvent.ACTION_POINTER_DOWN -> true

                MotionEvent.ACTION_MOVE -> {
                    if (event.getPointerId(event.actionIndex) != pointerId) {
                        return@setOnTouchListener true
                    }
                    val deltaX = event.rawX - startX
                    val deltaY = event.rawY - startY
                    if (!moved && (abs(deltaX) > touchSlop || abs(deltaY) > touchSlop)) {
                        moved = true
                    }
                    if (moved) {
                        overlay.params.x = startParamX + deltaX.roundToInt()
                        overlay.params.y = startParamY + deltaY.roundToInt()
                        clamp(measuredOverlay)
                        update(overlay)
                    }
                    true
                }

                MotionEvent.ACTION_UP -> {
                    if (event.getPointerId(event.actionIndex) != pointerId) {
                        return@setOnTouchListener true
                    }
                    if (moved) {
                        snapToEdge(measuredOverlay)
                        clamp(measuredOverlay)
                        update(overlay)
                        savePosition(overlay)
                    } else {
                        touchTarget.performClick()
                    }
                    pointerId = -1
                    moved = false
                    true
                }

                MotionEvent.ACTION_CANCEL -> {
                    if (moved) {
                        snapToEdge(measuredOverlay)
                        clamp(measuredOverlay)
                        update(overlay)
                        savePosition(overlay)
                    }
                    pointerId = -1
                    moved = false
                    true
                }

                else -> false
            }
        }
    }

    private fun canDrawOverlays(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Settings.canDrawOverlays(appContext)

    private fun baseParams(width: Int, height: Int): WindowManager.LayoutParams {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            throw IllegalStateException("Overlay requires Android O or newer")
        }
        return WindowManager.LayoutParams(
            width,
            height,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.LEFT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }

    private fun clamp(overlay: ManagedOverlay) {
        val bounds = bounds()
        val size = measure(overlay)
        val minX = bounds.left + margin
        val minY = bounds.top + margin
        val maxX = max(minX, bounds.right - margin - size.width)
        val maxY = max(minY, bounds.bottom - margin - size.height)
        overlay.params.x = overlay.params.x.coerceIn(minX, maxX)
        overlay.params.y = overlay.params.y.coerceIn(minY, maxY)
    }

    private fun snapToEdge(overlay: ManagedOverlay) {
        val bounds = bounds()
        val size = measure(overlay)
        val left = bounds.left + margin
        val right = max(left, bounds.right - margin - size.width)
        if (overlay.params.x - left <= snapDistance) {
            overlay.params.x = left
        } else if (right - overlay.params.x <= snapDistance) {
            overlay.params.x = right
        }
    }

    private fun measure(overlay: ManagedOverlay): ViewSize {
        val widthSpec = if (overlay.params.width > 0) {
            View.MeasureSpec.makeMeasureSpec(overlay.params.width, View.MeasureSpec.EXACTLY)
        } else {
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        }
        val heightSpec = if (overlay.params.height > 0) {
            View.MeasureSpec.makeMeasureSpec(overlay.params.height, View.MeasureSpec.EXACTLY)
        } else {
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
        }
        overlay.view.measure(widthSpec, heightSpec)
        return ViewSize(max(1, overlay.view.measuredWidth), max(1, overlay.view.measuredHeight))
    }

    private fun bounds(): Rect {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics: WindowMetrics = windowManager.currentWindowMetrics
            if (!metrics.bounds.isEmpty) {
                return Rect(metrics.bounds)
            }
        }
        @Suppress("DEPRECATION")
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)
        return Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
    }

    private fun statusBarHeight(): Int {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val insets = windowManager.currentWindowMetrics.windowInsets
                .getInsetsIgnoringVisibility(WindowInsets.Type.systemBars())
            return insets.top
        }
        return dp(24)
    }

    private data class ViewSize(val width: Int, val height: Int)

    private companion object {
        const val BUBBLE_SIZE_DP = 58
    }
}
