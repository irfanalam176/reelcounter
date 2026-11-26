package com.reelcount.app

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import com.reelcount.app.tracking.ReelDetectionAccessibilityService

class ScrolloTaskMonitorService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ReelDetectionAccessibilityService.resumeForHost(applicationContext)
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        ReelDetectionAccessibilityService.suspendForTaskRemoval(applicationContext)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        fun start(context: Context) {
            context.startService(Intent(context, ScrolloTaskMonitorService::class.java))
        }
    }
}
