package com.reelcount.app.overlay

import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.reelcount.app.storage.BubbleCounts
import com.reelcount.app.storage.BubblePlatform

internal class ExpandedBubbleView(
    context: Context,
    private val callbacks: Callbacks,
) : LinearLayout(context) {
    interface Callbacks {
        fun onCollapse()
        fun onHide()
    }

    private val density = resources.displayMetrics.density
    private val totalText: TextView
    private val statusText: TextView
    private val rows = mutableMapOf<BubblePlatform, TextView>()
    val dragHandle: View

    init {
        orientation = VERTICAL
        background = panelBackground()
        elevation = dpFloat(12)
        translationZ = dpFloat(2)
        outlineProvider = object : android.view.ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                if (view.width > 0 && view.height > 0) {
                    outline.setRoundRect(0, 0, view.width, view.height, dpFloat(20))
                } else {
                    outline.setEmpty()
                }
            }
        }
        clipToOutline = true
        setPadding(dp(16), dp(12), dp(16), dp(14))

        dragHandle = createDragHandle()
        addView(dragHandle)
        createTotalRow().let { (row, value) ->
            totalText = value
            addView(row)
        }
        addView(
            TextView(context).apply {
                text = "TODAY'S REELS WATCHED"
                setTextColor(MUTED)
                textSize = 10f
                letterSpacing = 0.08f
                layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
            },
        )
        statusText = TextView(context).apply {
            text = "Checking detection status…"
            setTextColor(MUTED)
            textSize = 11f
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(6)
            }
        }
        addView(statusText)

        BubblePlatform.entries.forEach { platform ->
            createPlatformRow(platform).let { (row, count) ->
                rows[platform] = count
                addView(row)
            }
        }

        val actionRow = LinearLayout(context).apply {
            orientation = HORIZONTAL
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(10)
            }
        }
        actionRow.addView(createButton("Collapse", Action.COLLAPSE), weightedParams())
        actionRow.addView(createButton("Hide", Action.HIDE), weightedParams())
        addView(actionRow)
    }

    fun setCounts(counts: BubbleCounts) {
        totalText.text = counts.total.toString()
        BubblePlatform.entries.forEach { platform ->
            rows[platform]?.text = counts.countFor(platform).toString()
        }
    }

    fun setTrackingState(state: String, message: String) {
        statusText.text = message
        statusText.setTextColor(if (state == "active") GREEN else MUTED)
    }

    private fun createDragHandle(): View = LinearLayout(context).apply {
        orientation = HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        isClickable = true
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            bottomMargin = dp(8)
        }
        addView(
            View(context).apply {
                background = GradientDrawable().apply {
                    cornerRadius = dpFloat(2)
                    setColor(GREEN)
                }
                layoutParams = LayoutParams(dp(34), dp(4)).apply {
                    marginEnd = dp(10)
                }
            },
        )
        addView(
            TextView(context).apply {
                text = "ReelCount"
                setTextColor(Color.WHITE)
                textSize = 14f
                isAllCaps = false
                layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
            },
        )
    }

    private fun createTotalRow(): Pair<LinearLayout, TextView> {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT)
        }
        val label = TextView(context).apply {
            text = "TOTAL"
            setTextColor(GREEN)
            textSize = 11f
            layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
        }
        val value = TextView(context).apply {
            text = "0"
            setTextColor(Color.WHITE)
            textSize = 30f
            gravity = Gravity.END or Gravity.CENTER_VERTICAL
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        }
        row.addView(label)
        row.addView(value)
        return row to value
    }

    private fun createPlatformRow(platform: BubblePlatform): Pair<LinearLayout, TextView> {
        val row = LinearLayout(context).apply {
            orientation = HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(10), dp(7), dp(10), dp(7))
            background = rowBackground()
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
                topMargin = dp(4)
            }
        }
        row.addView(
            TextView(context).apply {
                text = platform.label
                setTextColor(Color.rgb(226, 232, 240))
                textSize = 12f
                layoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f)
            },
        )
        val count = TextView(context).apply {
            text = "0"
            setTextColor(Color.WHITE)
            textSize = 13f
            gravity = Gravity.END
            layoutParams = LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT)
        }
        row.addView(count)
        return row to count
    }

    private fun createButton(text: String, action: Action): Button = Button(context).apply {
        this.text = text
        isAllCaps = false
        textSize = 12f
        minimumHeight = dp(38)
        setTextColor(Color.rgb(209, 213, 219))
        background = GradientDrawable().apply {
            cornerRadius = dpFloat(10)
            setColor(Color.rgb(31, 41, 55))
            setStroke(dp(1), STROKE)
        }
        setOnClickListener {
            when (action) {
                Action.COLLAPSE -> callbacks.onCollapse()
                Action.HIDE -> callbacks.onHide()
            }
        }
    }

    private fun weightedParams(): LayoutParams = LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply {
        marginEnd = dp(4)
        marginStart = dp(4)
    }

    private fun panelBackground(): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dpFloat(20)
        setColor(Color.rgb(10, 15, 26))
        setStroke(dp(1), Color.rgb(34, 197, 94))
    }

    private fun rowBackground(): GradientDrawable = GradientDrawable().apply {
        cornerRadius = dpFloat(10)
        setColor(Color.rgb(24, 33, 48))
        setStroke(dp(1), STROKE)
    }

    private fun dp(value: Int): Int = (value * density).toInt()

    private fun dpFloat(value: Int): Float = value * density

    private enum class Action {
        COLLAPSE,
        HIDE,
    }

    private companion object {
        val GREEN = Color.rgb(34, 197, 94)
        val STROKE = Color.rgb(55, 65, 81)
        val MUTED = Color.rgb(156, 163, 175)
    }
}
