package com.reelcount.app.notifications

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import com.reelcount.app.MainActivity
import com.reelcount.app.R
import com.reelcount.app.storage.BubblePreferences
import java.util.Calendar

object DailyReminderScheduler {
    private const val TAG = "DailyReminderScheduler"
    const val CHANNEL_ID = "reelcount_daily_reminders"
    const val ACTION_SHOW_REMINDER = "com.reelcount.app.SHOW_DAILY_REMINDER"
    private const val REQUEST_CODE = 2108
    private const val INTERVAL_DAY_MS = 24L * 60L * 60L * 1000L

    private val titles = arrayOf(
        "Ready to Scroll Smarter?",
        "Your Scrollo Reminder",
        "A Little Reminder from Scrollo",
    )

    private val messages = arrayOf(
        "Open Scrollo before your scrolling session and let us keep track of those reels!",
        "About to explore some reels? Start Scrollo first so your daily count stays accurate.",
        "Your reels aren't going to count themselves! Open Scrollo and start tracking.",
    )

    fun hasPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        return context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) {
            return
        }
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Daily reminders",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Friendly reminders to open Scrollo before a scrolling session"
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(channel)
    }

    fun rescheduleIfEnabled(context: Context) {
        val preferences = BubblePreferences(context)
        val enabled = preferences.dailyReminderEnabled && hasPermission(context)
        schedule(
            context,
            enabled = enabled,
            hour = preferences.dailyReminderHour,
            minute = preferences.dailyReminderMinute,
        )
    }

    fun schedule(context: Context, enabled: Boolean, hour: Int, minute: Int) {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val pendingIntent = reminderPendingIntent(context)
        manager.cancel(pendingIntent)
        if (!enabled || !hasPermission(context)) {
            return
        }
        createChannel(context)
        val triggerAt = nextTriggerAt(hour, minute)
        runCatching {
            manager.setRepeating(
                AlarmManager.RTC_WAKEUP,
                triggerAt,
                INTERVAL_DAY_MS,
                pendingIntent,
            )
            Log.i(TAG, "daily reminder scheduled hour=$hour minute=$minute")
        }.onFailure { error ->
            Log.w(TAG, "daily reminder scheduling failed: ${error.message}")
        }
    }

    fun showNotification(context: Context) {
        if (!hasPermission(context)) {
            return
        }
        createChannel(context)
        val index = Calendar.getInstance().get(Calendar.DAY_OF_YEAR) % titles.size
        val openApp = PendingIntent.getActivity(
            context,
            0,
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
            .setContentTitle(titles[index])
            .setContentText(messages[index])
            .setStyle(Notification.BigTextStyle().bigText(messages[index]))
            .setContentIntent(openApp)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build()
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.notify(REQUEST_CODE, notification)
    }

    fun openNotificationSettings(context: Context): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = android.net.Uri.fromParts("package", context.packageName, null)
            }
        }
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun reminderPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, DailyReminderReceiver::class.java).apply {
            action = ACTION_SHOW_REMINDER
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun nextTriggerAt(hour: Int, minute: Int): Long {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour.coerceIn(0, 23))
            set(Calendar.MINUTE, minute.coerceIn(0, 59))
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DATE, 1)
            }
        }
        return calendar.timeInMillis
    }
}
