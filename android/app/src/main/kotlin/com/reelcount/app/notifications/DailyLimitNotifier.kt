package com.reelcount.app.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import com.reelcount.app.MainActivity
import com.reelcount.app.R
import com.reelcount.app.storage.BubblePreferences

object DailyLimitNotifier {
    const val CHANNEL_ID = "reelcount_daily_limit_milestones_sound"

    private val MILESTONES = intArrayOf(50, 90, 100)

    fun notifyReached(
        context: Context,
        preferences: BubblePreferences,
        count: Int,
        target: Int,
    ) {
        if (target <= 0 || count <= 0 || !DailyReminderScheduler.hasPermission(context)) {
            return
        }
        createChannel(context)
        val usage = count * 100.0 / target
        MILESTONES.forEach { milestone ->
            if (usage < milestone || preferences.hasNotifiedLimitMilestone(milestone)) {
                return@forEach
            }
            showNotification(context, milestone, count, target)
            preferences.markLimitMilestoneNotified(milestone)
        }
    }

    private fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Daily limit milestones",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Updates when today's reel limit reaches 50%, 90%, and 100%"
            enableVibration(false)
            setSound(Settings.System.DEFAULT_NOTIFICATION_URI, Notification.AUDIO_ATTRIBUTES_DEFAULT)
        }
        manager.createNotificationChannel(channel)
    }

    private fun showNotification(context: Context, milestone: Int, count: Int, target: Int) {
        val title = when (milestone) {
            50 -> "Halfway to your daily limit"
            90 -> "90% of your daily limit"
            else -> "Daily limit reached"
        }
        val message = "You've watched $milestone% of today's limit ($count of $target reels)."
        val openApp = PendingIntent.getActivity(
            context,
            milestone,
            Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(message)
            .setStyle(Notification.BigTextStyle().bigText(message))
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setDefaults(Notification.DEFAULT_SOUND)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.notify(milestone, notification)
    }
}
