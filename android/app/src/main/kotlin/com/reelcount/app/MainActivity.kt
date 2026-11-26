package com.reelcount.app

import com.reelcount.app.communication.FloatingBubbleChannel
import com.reelcount.app.notifications.DailyReminderScheduler
import com.reelcount.app.tracking.ReelDetectionAccessibilityService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        ScrolloTaskMonitorService.start(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FloatingBubbleChannel.attach(this, flutterEngine)
        ReelDetectionAccessibilityService.resumeForHost(applicationContext)
        DailyReminderScheduler.rescheduleIfEnabled(applicationContext)
    }

    override fun onResume() {
        super.onResume()
        ReelDetectionAccessibilityService.resumeForHost(applicationContext)
        DailyReminderScheduler.rescheduleIfEnabled(applicationContext)
        FloatingBubbleChannel.onHostResumed()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        FloatingBubbleChannel.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        FloatingBubbleChannel.detach()
        super.onDestroy()
    }
}
