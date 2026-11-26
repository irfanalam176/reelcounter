package com.reelcount.app.overlay

import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.reelcount.app.MainActivity
import com.reelcount.app.R
import com.reelcount.app.communication.FloatingBubbleChannel
import com.reelcount.app.communication.FloatingBubbleChannel.Event
import com.reelcount.app.storage.BubblePositionKind
import com.reelcount.app.storage.BubblePreferences
import com.reelcount.app.tracking.ReelDetectionAccessibilityService
import com.reelcount.app.tracking.VideoCounterManager

class FloatingBubbleService : Service() {
    private val preferences: BubblePreferences by lazy {
        BubblePreferences(applicationContext)
    }

    private val positionManager: BubblePositionManager by lazy {
        BubblePositionManager(applicationContext, preferences, ::onOverlayPermissionLost)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var collapsedOverlay: ManagedOverlay? = null
    private var expandedOverlay: ManagedOverlay? = null
    private var displayManager: DisplayManager? = null
    private var appOpsManager: AppOpsManager? = null
    private var permissionWatching = false

    private val displayListener = object : DisplayManager.DisplayListener {
        override fun onDisplayAdded(displayId: Int) = Unit

        override fun onDisplayRemoved(displayId: Int) = Unit

        override fun onDisplayChanged(displayId: Int) {
            mainHandler.post {
                if (!canDraw(applicationContext)) {
                    onOverlayPermissionLost()
                    return@post
                }
                handleBoundsChanged()
            }
        }
    }

    private val permissionListener = AppOpsManager.OnOpChangedListener { op, changedPackage ->
        if (op == AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW && changedPackage == packageName) {
            val granted = canDraw(applicationContext)
            mainHandler.post {
                FloatingBubbleChannel.notifyOverlayPermissionChanged(granted)
                if (!granted) {
                    onOverlayPermissionLost()
                }
            }
        }
    }

    private val expandedCallbacks = object : ExpandedBubbleView.Callbacks {
        override fun onCollapse() {
            displayCollapsed()
            notifyEvent(Event.BUBBLE_COLLAPSED)
        }

        override fun onHide() = deactivateAndStop(Event.BUBBLE_HIDDEN)
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startAsForeground()
        registerDisplayListener()
        registerOverlayPermissionWatcher()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == null) {
            return if (restoreAfterRestart()) START_STICKY else START_NOT_STICKY
        }

        when (intent.action) {
            ACTION_STOP -> {
                deactivateAndStop(Event.BUBBLE_STOPPED)
                return START_NOT_STICKY
            }

            ACTION_HIDE -> {
                deactivateAndStop(Event.BUBBLE_HIDDEN)
                return START_NOT_STICKY
            }

            ACTION_START -> {
                displayBubble()
                notifyEvent(Event.BUBBLE_STARTED)
            }

            ACTION_SHOW -> {
                displayBubble()
                notifyEvent(Event.BUBBLE_SHOWN)
            }

            ACTION_EXPAND -> {
                displayExpanded()
                notifyEvent(Event.BUBBLE_EXPANDED)
            }

            ACTION_COLLAPSE -> {
                displayCollapsed()
                notifyEvent(Event.BUBBLE_COLLAPSED)
            }

            ACTION_REFRESH -> refreshViews()

            else -> {
                displayBubble()
                notifyEvent(Event.BUBBLE_STARTED)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        mainHandler.post {
            if (!canDraw(applicationContext)) {
                onOverlayPermissionLost()
                return@post
            }
            handleBoundsChanged()
        }
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        ReelDetectionAccessibilityService.suspendForTaskRemoval(applicationContext)
        deactivateAndStop(Event.BUBBLE_STOPPED)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        unregisterDisplayListener()
        stopOverlayPermissionWatcher()
        removeOverlays()
        isRunning = false
        super.onDestroy()
    }

    private fun restoreAfterRestart(): Boolean {
        if (!canDraw(applicationContext) || !preferences.isBubbleActive) {
            clearPersistentState()
            stopSelf()
            return false
        }
        displayBubble()
        notifyEvent(Event.BUBBLE_STARTED)
        return true
    }

    private fun displayBubble() = withOverlayPermission {
        preferences.isBubbleActive = true
        if (expandedOverlay?.view?.isAttachedToWindow == true) {
            refreshViews()
            return@withOverlayPermission
        }

        ensureCollapsedAttached()
        if (preferences.isExpanded) {
            displayExpanded()
        } else {
            detachExpanded()
            refreshViews()
        }
    }

    private fun displayExpanded() = withOverlayPermission {
        preferences.isBubbleActive = true
        preferences.isExpanded = true
        if (expandedOverlay?.view?.isAttachedToWindow == true) {
            refreshViews()
            return@withOverlayPermission
        }

        val collapsed = ensureCollapsedAttached()
        val expanded = expandedOverlay ?: createExpandedOverlay().also { expandedOverlay = it }
        positionManager.alignExpandedToCollapsed(collapsed, expanded)
        positionManager.savePosition(collapsed)
        positionManager.remove(collapsed)

        if (positionManager.add(expanded)) {
            positionManager.savePosition(expanded)
        } else {
            expandedOverlay = null
        }
        refreshViews()
    }

    private fun displayCollapsed() = withOverlayPermission {
        preferences.isExpanded = false
        detachExpanded()
        ensureCollapsedAttached()
        refreshViews()
    }

    private fun handleBoundsChanged() {
        positionManager.repositionAll(listOfNotNull(collapsedOverlay, expandedOverlay))
        refreshViews()
    }

    private fun ensureCollapsedAttached(): ManagedOverlay {
        val collapsed = collapsedOverlay ?: createCollapsedOverlay().also { collapsedOverlay = it }
        if (positionManager.add(collapsed)) {
            positionManager.savePosition(collapsed)
        }
        return collapsed
    }

    private fun detachExpanded() {
        expandedOverlay?.let { overlay ->
            positionManager.remove(overlay)
            expandedOverlay = null
        }
    }

    private fun removeOverlays() {
        collapsedOverlay?.let { overlay ->
            positionManager.savePosition(overlay)
            positionManager.remove(overlay)
        }
        expandedOverlay?.let { overlay ->
            positionManager.savePosition(overlay)
            positionManager.remove(overlay)
        }
        collapsedOverlay = null
        expandedOverlay = null
    }

    private fun createCollapsedOverlay(): ManagedOverlay {
        val view = FloatingBubbleView(this).apply {
            setCount(preferences.getCounts().total)
            setOnClickListener {
                displayExpanded()
                notifyEvent(Event.BUBBLE_EXPANDED)
            }
        }
        val params = positionManager.createParams(BubblePositionKind.COLLAPSED, view)
        return ManagedOverlay(BubblePositionKind.COLLAPSED, view, params).also { overlay ->
            positionManager.attachDrag(overlay)
        }
    }

    private fun createExpandedOverlay(): ManagedOverlay {
        val view = ExpandedBubbleView(this, expandedCallbacks)
        val params = positionManager.createParams(BubblePositionKind.EXPANDED, view)
        return ManagedOverlay(BubblePositionKind.EXPANDED, view, params).also { overlay ->
            positionManager.attachDrag(
                overlay = overlay,
                touchTarget = view.dragHandle,
                sizeSource = view,
            )
        }.also {
            refreshExpandedView(view)
        }
    }

    private fun refreshViews() {
        val counts = preferences.getCounts()
        (collapsedOverlay?.view as? FloatingBubbleView)?.setCount(counts.total)
        (expandedOverlay?.view as? ExpandedBubbleView)?.let(::refreshExpandedView)
        Log.i(
            TAG,
            "BUBBLE_UPDATED total=${counts.total} instagram=${counts.instagram} " +
                "youtube=${counts.youtube} facebook=${counts.facebook} " +
                "tiktok=${counts.tiktok} snapchat=${counts.snapchat} " +
                "collapsed=${collapsedOverlay != null} expanded=${expandedOverlay != null}",
        )
    }

    private fun refreshExpandedView(view: ExpandedBubbleView) {
        view.setCounts(preferences.getCounts())
        view.setTrackingState(VideoCounterManager.trackingState, VideoCounterManager.trackingMessage)
    }

    private fun deactivateAndStop(eventType: String) {
        clearPersistentState()
        removeOverlays()
        notifyEvent(eventType)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun onOverlayPermissionLost() {
        FloatingBubbleChannel.notifyOverlayPermissionChanged(false)
        deactivateAndStop(Event.BUBBLE_STOPPED)
    }

    private fun clearPersistentState() {
        preferences.isBubbleActive = false
        preferences.isExpanded = false
    }

    private fun notifyEvent(type: String) {
        when (type) {
            Event.COUNTER_CHANGED -> FloatingBubbleChannel.notifyCounterChanged()
            Event.BUBBLE_STARTED -> FloatingBubbleChannel.notifyBubbleStarted()
            Event.BUBBLE_STOPPED -> FloatingBubbleChannel.notifyBubbleStopped()
            Event.BUBBLE_SHOWN -> FloatingBubbleChannel.notifyBubbleShown()
            Event.BUBBLE_HIDDEN -> FloatingBubbleChannel.notifyBubbleHidden()
            Event.BUBBLE_EXPANDED -> FloatingBubbleChannel.notifyBubbleExpanded()
            Event.BUBBLE_COLLAPSED -> FloatingBubbleChannel.notifyBubbleCollapsed()
            Event.TRACKING_STATUS_CHANGED -> FloatingBubbleChannel.notifyTrackingStatusChanged()
            Event.OVERLAY_PERMISSION_CHANGED ->
                FloatingBubbleChannel.notifyOverlayPermissionChanged(canDraw(applicationContext))

            else -> Unit
        }
    }

    private fun withOverlayPermission(action: () -> Unit) {
        if (!canDraw(applicationContext)) {
            onOverlayPermissionLost()
            return
        }
        action()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Floating bubble",
            NotificationManager.IMPORTANCE_LOW,
        )
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun startAsForeground() {
        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                    startForeground(
                        NOTIFICATION_ID,
                        buildNotification(),
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
                    )

                Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
                    startForeground(NOTIFICATION_ID, buildNotification(), 0)

                else ->
                    @Suppress("DEPRECATION")
                    startForeground(NOTIFICATION_ID, buildNotification())
            }
        } catch (_: SecurityException) {
            stopSelf()
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getService(
            this,
            1,
            actionIntent(this, ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopAction = Notification.Action.Builder(
            Icon.createWithResource(this, android.R.drawable.ic_menu_close_clear_cancel),
            "Stop",
            stopIntent,
        ).build()
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Scrollo tracking active")
            .setContentText("Tap to open Scrollo")
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(stopAction)
            .build()
    }

    private fun registerDisplayListener() {
        displayManager = getSystemService(DisplayManager::class.java)
        displayManager?.registerDisplayListener(displayListener, mainHandler)
    }

    private fun unregisterDisplayListener() {
        try {
            displayManager?.unregisterDisplayListener(displayListener)
        } catch (_: IllegalArgumentException) {
        }
        displayManager = null
    }

    private fun registerOverlayPermissionWatcher() {
        appOpsManager = getSystemService(AppOpsManager::class.java)
        try {
            appOpsManager?.startWatchingMode(
                AppOpsManager.OPSTR_SYSTEM_ALERT_WINDOW,
                packageName,
                permissionListener,
            )
            permissionWatching = true
        } catch (_: SecurityException) {
            permissionWatching = false
        }
    }

    private fun stopOverlayPermissionWatcher() {
        if (permissionWatching) {
            try {
                appOpsManager?.stopWatchingMode(permissionListener)
            } catch (_: IllegalArgumentException) {
            }
            permissionWatching = false
        }
        appOpsManager = null
    }

    companion object {
        const val ACTION_START = "com.reelcount.app.overlay.action.START"
        const val ACTION_STOP = "com.reelcount.app.overlay.action.STOP"
        const val ACTION_SHOW = "com.reelcount.app.overlay.action.SHOW"
        const val ACTION_HIDE = "com.reelcount.app.overlay.action.HIDE"
        const val ACTION_EXPAND = "com.reelcount.app.overlay.action.EXPAND"
        const val ACTION_COLLAPSE = "com.reelcount.app.overlay.action.COLLAPSE"
        const val ACTION_REFRESH = "com.reelcount.app.overlay.action.REFRESH"

        private const val NOTIFICATION_ID = 2107
        private const val NOTIFICATION_CHANNEL_ID = "reelcount_floating_bubble"
        private const val TAG = "BubbleUpdate"

        @Volatile
        var isRunning: Boolean = false
            private set

        fun start(context: Context): Boolean {
            if (!canDraw(context)) {
                return false
            }
            BubblePreferences(context).isBubbleActive = true
            dispatchStart(context, ACTION_START)
            return true
        }

        fun stop(context: Context) {
            clearState(context)
            dispatch(context, ACTION_STOP)
        }

        fun show(context: Context): Boolean {
            if (!canDraw(context)) {
                return false
            }
            BubblePreferences(context).isBubbleActive = true
            dispatch(context, ACTION_SHOW)
            return true
        }

        fun hide(context: Context) {
            clearState(context)
            dispatch(context, ACTION_HIDE)
        }

        fun expand(context: Context): Boolean {
            if (!canDraw(context)) {
                return false
            }
            BubblePreferences(context).apply {
                isBubbleActive = true
                isExpanded = true
            }
            dispatch(context, ACTION_EXPAND)
            return true
        }

        fun collapse(context: Context) {
            BubblePreferences(context).isExpanded = false
            dispatch(context, ACTION_COLLAPSE)
        }

        fun refreshCounter(context: Context) {
            dispatch(context, ACTION_REFRESH)
        }

        private fun dispatch(context: Context, action: String) {
            if (!isRunning) {
                return
            }
            context.startService(actionIntent(context, action))
        }

        private fun dispatchStart(context: Context, action: String) {
            val intent = actionIntent(context, action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        private fun clearState(context: Context) {
            BubblePreferences(context).apply {
                isBubbleActive = false
                isExpanded = false
            }
        }

        private fun actionIntent(context: Context, action: String): Intent =
            Intent(context, FloatingBubbleService::class.java).setAction(action)

        private fun canDraw(context: Context): Boolean =
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Settings.canDrawOverlays(context)
    }
}
