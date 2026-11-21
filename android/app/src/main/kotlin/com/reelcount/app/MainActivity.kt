package com.reelcount.app

import com.reelcount.app.communication.FloatingBubbleChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FloatingBubbleChannel.attach(this, flutterEngine)
    }

    override fun onResume() {
        super.onResume()
        FloatingBubbleChannel.onHostResumed()
    }

    override fun onDestroy() {
        FloatingBubbleChannel.detach()
        super.onDestroy()
    }
}
