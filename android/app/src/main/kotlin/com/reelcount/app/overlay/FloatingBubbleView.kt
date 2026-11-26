package com.reelcount.app.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewOutlineProvider
import androidx.core.content.ContextCompat
import com.reelcount.app.R
import com.reelcount.app.storage.BubblePreferences
import kotlin.math.min

internal class FloatingBubbleView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val size = dp(BUBBLE_SIZE_DP)
    private val backgroundDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(Color.rgb(0x1B, 0x20, 0x1C))
        setStroke(dp(2), Color.rgb(0xB6, 0xF3, 0x6B))
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0xF5, 0xF7, 0xF3)
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = ACCENT
    }
    private val brainDrawable = ContextCompat.getDrawable(context, R.drawable.ic_brain)?.mutate()
    private val brainWidth = dp(BRAIN_SIZE_DP)
    private val brainHeight = (brainWidth * (VIEWPORT_HEIGHT / VIEWPORT_WIDTH)).toInt()
    private val preferences = BubblePreferences(context)
    private var count = 0
    private var dailyTarget = preferences.dailyTarget
    private var brainColor = ACCENT

    init {
        background = backgroundDrawable
        elevation = dpFloat(10)
        translationZ = dpFloat(2)
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (view.width > 0 && view.height > 0) {
                    outline.setOval(0, 0, view.width, view.height)
                } else {
                    outline.setEmpty()
                }
            }
        }
        clipToOutline = true
        isClickable = true
        updateBrainColor()
        updateContentDescription()
    }

    fun setCount(value: Int) {
        count = maxOf(0, value)
        dailyTarget = preferences.dailyTarget
        updateBrainColor()
        updateContentDescription()
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(size, size)
    }

    override fun onSizeChanged(width: Int, height: Int, oldWidth: Int, oldHeight: Int) {
        backgroundDrawable.cornerRadius = min(width, height) / 2f
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val brainLeft = (width - brainWidth) / 2
        val brainTop = dp(BRAIN_TOP_DP)
        brainDrawable?.setBounds(brainLeft, brainTop, brainLeft + brainWidth, brainTop + brainHeight)
        brainDrawable?.draw(canvas)

        val label = count.toString()
        val baseSize = when (label.length) {
            in 0..2 -> 16
            3 -> 14
            4 -> 12
            5 -> 11
            else -> 10
        }
        var textSize = dpFloat(baseSize)
        val availableWidth = width - dpFloat(18)
        textPaint.textSize = textSize
        while (textPaint.measureText(label) > availableWidth && textSize > dpFloat(9)) {
            textSize -= dpFloat(1)
            textPaint.textSize = textSize
        }
        val fontMetrics = textPaint.fontMetrics
        val baseline = dpFloat(COUNT_CENTER_DP) - (fontMetrics.ascent + fontMetrics.descent) / 2f
        canvas.drawText(label, width / 2f, baseline, textPaint)
        canvas.drawCircle(width - dpFloat(13), dpFloat(13), dpFloat(3), accentPaint)
    }

    private fun updateBrainColor() {
        brainColor = when {
            dailyTarget <= 0 -> ACCENT
            count <= dailyTarget / 2 -> ACCENT
            count <= dailyTarget -> WARNING
            else -> DANGER
        }
        brainDrawable?.colorFilter = PorterDuffColorFilter(brainColor, PorterDuff.Mode.SRC_IN)
        accentPaint.color = brainColor
    }

    private fun updateContentDescription() {
        contentDescription = "Scrollo daily total $count"
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    private fun dpFloat(value: Int): Float = value * density

    private companion object {
        const val BUBBLE_SIZE_DP = 60
        const val BRAIN_SIZE_DP = 30
        const val BRAIN_TOP_DP = 7
        const val COUNT_CENTER_DP = 46
        const val VIEWPORT_WIDTH = 516.4220444f
        const val VIEWPORT_HEIGHT = 459.4220444f
        val ACCENT = Color.rgb(0xB6, 0xF3, 0x6B)
        val WARNING = Color.rgb(0xFF, 0xB4, 0x54)
        val DANGER = Color.rgb(0xFF, 0x65, 0x65)
    }
}
