package com.reelcount.app.tracking

import android.content.Context
import android.util.Log
import com.reelcount.app.communication.FloatingBubbleChannel
import com.reelcount.app.notifications.DailyLimitNotifier
import com.reelcount.app.overlay.FloatingBubbleService
import com.reelcount.app.storage.BubbleCounts
import com.reelcount.app.storage.BubblePlatform
import com.reelcount.app.storage.BubblePreferences

data class VideoRecordResult(
    val recorded: Boolean,
    val duplicate: Boolean,
    val counter: BubbleCounts,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "recorded" to recorded,
        "duplicate" to duplicate,
        "counter" to counter.toMap(),
    )
}

object VideoCounterManager {
    private const val TAG = "VideoCounterManager"

    @Volatile
    private var serviceConnected: Boolean = false

    @Volatile
    private var detectionError: String? = null

    @Volatile
    private var appTaskActive: Boolean = false

    val isTrackingEngineConnected: Boolean
        get() = serviceConnected

    val trackingState: String
        get() = when {
            !appTaskActive -> "stopped"
            detectionError != null -> "error"
            serviceConnected -> "active"
            else -> "waiting"
        }

    val trackingMessage: String
        get() = when {
            !appTaskActive -> "Tracking stopped because Scrollo was closed"
            detectionError != null -> detectionError ?: "Detection error"
            serviceConnected -> "Tracking active"
            else -> "Tracking engine not connected"
        }

    fun setAppTaskActive(context: Context, active: Boolean) {
        val previousState = trackingState
        val previousMessage = trackingMessage
        appTaskActive = active
        notifyIfChanged(previousState, previousMessage)
    }

    fun isAppTaskActive(context: Context): Boolean = appTaskActive

    fun setTrackingEngineConnected(connected: Boolean) = setDetectionConnected(connected)

    fun setDetectionConnected(connected: Boolean) {
        val previousState = trackingState
        val previousMessage = trackingMessage
        serviceConnected = connected
        detectionError = null
        notifyIfChanged(previousState, previousMessage)
    }

    fun setDetectionError(message: String?) {
        val previousState = trackingState
        val previousMessage = trackingMessage
        detectionError = message?.trim()?.takeIf { it.isNotEmpty() }
        notifyIfChanged(previousState, previousMessage)
    }

    private fun notifyIfChanged(previousState: String, previousMessage: String) {
        if (trackingState == previousState && trackingMessage == previousMessage) {
            return
        }
        Log.i(TAG, "detection state=$trackingState message=$trackingMessage")
        FloatingBubbleChannel.notifyTrackingStatusChanged()
    }

    fun recordWatchedVideo(
        context: Context,
        platformKey: String?,
        eventId: String? = null,
    ): VideoRecordResult {
        val platform = BubblePlatform.fromKey(platformKey)
            ?: throw IllegalArgumentException(
                "platform must be one of instagram, youtube, facebook, tiktok, snapchat",
            )

        val preferences = BubblePreferences(context)
        val normalizedEventId = eventId?.trim()?.takeIf { it.isNotEmpty() }
        if (normalizedEventId != null && preferences.hasProcessedEvent(normalizedEventId)) {
            Log.d(TAG, "duplicate event skipped platform=${platform.key} event=$normalizedEventId")
            return VideoRecordResult(
                recorded = false,
                duplicate = true,
                counter = preferences.getCounts(),
            )
        }

        val updated = preferences.incrementPlatform(platform)
        if (normalizedEventId != null) {
            preferences.markProcessedEvent(normalizedEventId)
        }
        runCatching {
            DailyLimitNotifier.notifyReached(
                context,
                preferences,
                updated.total,
                preferences.dailyTarget,
            )
        }.onFailure { error ->
            Log.w(TAG, "daily limit milestone notification failed: ${error.message}")
        }

        FloatingBubbleService.refreshCounter(context)
        FloatingBubbleChannel.notifyCounterChanged()
        Log.i(
            TAG,
            "COUNTER_UPDATED platform=${platform.key} total=${updated.total} " +
                "instagram=${updated.instagram} youtube=${updated.youtube} " +
                "facebook=${updated.facebook} tiktok=${updated.tiktok} snapchat=${updated.snapchat} " +
                "event=$normalizedEventId",
        )
        return VideoRecordResult(recorded = true, duplicate = false, counter = updated)
    }
}
