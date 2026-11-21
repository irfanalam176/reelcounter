package com.reelcount.app.overlay

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.drawable.GradientDrawable
import android.view.View
import android.view.ViewOutlineProvider
import kotlin.math.min

internal class FloatingBubbleView(context: Context) : View(context) {
    private val density = resources.displayMetrics.density
    private val size = dp(BUBBLE_SIZE_DP)
    private val backgroundDrawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        setColor(Color.rgb(10, 15, 26))
        setStroke(dp(2), Color.rgb(34, 197, 94))
    }
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        textAlign = Paint.Align.CENTER
        isFakeBoldText = true
    }
    private val accentPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(34, 197, 94)
    }
    private var count = 0

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
        updateContentDescription()
    }

    fun setCount(value: Int) {
        count = maxOf(0, value)
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
        val label = count.toString()
        val baseSize = when (label.length) {
            in 0..2 -> 20
            3 -> 18
            4 -> 16
            5 -> 14
            else -> 12
        }
        var textSize = dpFloat(baseSize)
        val availableWidth = width - dpFloat(18)
        textPaint.textSize = textSize
        while (textPaint.measureText(label) > availableWidth && textSize > dpFloat(9)) {
            textSize -= dpFloat(1)
            textPaint.textSize = textSize
        }
        val fontMetrics = textPaint.fontMetrics
        val baseline = height / 2f - (fontMetrics.ascent + fontMetrics.descent) / 2f
        canvas.drawText(label, width / 2f, baseline, textPaint)
        canvas.drawCircle(width - dpFloat(13), dpFloat(13), dpFloat(3), accentPaint)
    }

    private fun updateContentDescription() {
        contentDescription = "ReelCount daily total $count"
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    private fun dpFloat(value: Int): Float = value * density

    private companion object {
        const val BUBBLE_SIZE_DP = 58
    }
}
