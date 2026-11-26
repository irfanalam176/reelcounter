package com.reelcount.app.communication

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import com.reelcount.app.notifications.DailyReminderScheduler
import com.reelcount.app.overlay.FloatingBubbleService
import com.reelcount.app.storage.BubblePreferences
import com.reelcount.app.storage.BubbleStorageException
import com.reelcount.app.tracking.ReelDetectionAccessibilityService
import com.reelcount.app.tracking.VideoCounterManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

object FloatingBubbleChannel {
    const val METHOD_CHANNEL = "com.reelcount.app/floating_bubble"
    const val EVENT_CHANNEL = "com.reelcount.app/floating_bubble_events"

    object Method {
        const val CHECK_OVERLAY_PERMISSION = "checkOverlayPermission"
        const val REQUEST_OVERLAY_PERMISSION = "requestOverlayPermission"
        const val START_FLOATING_BUBBLE = "startFloatingBubble"
        const val STOP_FLOATING_BUBBLE = "stopFloatingBubble"
        const val SHOW_FLOATING_BUBBLE = "showFloatingBubble"
        const val HIDE_FLOATING_BUBBLE = "hideFloatingBubble"
        const val EXPAND_FLOATING_BUBBLE = "expandFloatingBubble"
        const val COLLAPSE_FLOATING_BUBBLE = "collapseFloatingBubble"
        const val RESET_COUNTER = "resetCounter"
        const val GET_COUNTER = "getCounter"
        const val GET_DAILY_TARGET = "getDailyTarget"
        const val SET_DAILY_TARGET = "setDailyTarget"
        const val GET_BUBBLE_STATUS = "getBubbleStatus"
        const val RECORD_WATCHED_VIDEO = "recordWatchedVideo"
        const val CHECK_ACCESSIBILITY_PERMISSION = "checkAccessibilityPermission"
        const val REQUEST_ACCESSIBILITY_PERMISSION = "requestAccessibilityPermission"
        const val CHECK_BACKGROUND_ACTIVITY = "checkBackgroundActivity"
        const val REQUEST_BACKGROUND_ACTIVITY = "requestBackgroundActivity"
        const val REQUEST_AUTO_BACKGROUND_START = "requestAutoBackgroundStart"
        const val CHECK_PAUSE_APP_ACTIVITY = "checkPauseAppActivity"
        const val REQUEST_PAUSE_APP_ACTIVITY = "requestPauseAppActivity"
        const val GET_DAILY_HISTORY = "getDailyHistory"
        const val CHECK_NOTIFICATION_PERMISSION = "checkNotificationPermission"
        const val REQUEST_NOTIFICATION_PERMISSION = "requestNotificationPermission"
        const val OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
        const val GET_DAILY_REMINDER = "getDailyReminder"
        const val SET_DAILY_REMINDER = "setDailyReminder"
    }

    object Event {
        const val COUNTER_CHANGED = "counterChanged"
        const val BUBBLE_STARTED = "bubbleStarted"
        const val BUBBLE_STOPPED = "bubbleStopped"
        const val BUBBLE_SHOWN = "bubbleShown"
        const val BUBBLE_HIDDEN = "bubbleHidden"
        const val BUBBLE_EXPANDED = "bubbleExpanded"
        const val BUBBLE_COLLAPSED = "bubbleCollapsed"
        const val OVERLAY_PERMISSION_CHANGED = "overlayPermissionChanged"
        const val TRACKING_STATUS_CHANGED = "trackingStatusChanged"
    }

    private const val ERROR_NO_CONTEXT = "CHANNEL_UNAVAILABLE"
    private const val ERROR_UNSUPPORTED = "UNSUPPORTED_ANDROID_VERSION"
    private const val ERROR_NO_PERMISSION = "OVERLAY_PERMISSION_MISSING"
    private const val ERROR_SERVICE_NOT_RUNNING = "SERVICE_NOT_RUNNING"
    private const val ERROR_SERVICE_CALL = "SERVICE_COMMUNICATION_FAILED"
    private const val ERROR_INVALID_ARGUMENTS = "INVALID_ARGUMENTS"
    private const val ERROR_STORAGE = "STORAGE_UNAVAILABLE"
    private const val ERROR_TRACKING = "TRACKING_OPERATION_FAILED"
    private const val BACKGROUND_ACTIVITY_ALLOWED = "allowed"
    private const val BACKGROUND_ACTIVITY_RESTRICTED = "restricted"
    private const val BACKGROUND_ACTIVITY_UNKNOWN = "unknown"
    private const val PAUSE_APP_ACTIVITY_DISABLED = "disabled"
    private const val PAUSE_APP_ACTIVITY_ENABLED = "enabled"
    private const val PAUSE_APP_ACTIVITY_UNKNOWN = "unknown"
    private const val REQUEST_NOTIFICATION_PERMISSION_CODE = 2109

    private val mainHandler = Handler(Looper.getMainLooper())
    private var applicationContext: Context? = null
    private var hostActivity: Activity? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var lastPermissionGranted: Boolean? = null
    private var lastAccessibilityEnabled: Boolean? = null
    private var lastEventSignature: String? = null

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        applicationContext = context.applicationContext
        hostActivity = context as? Activity
        lastPermissionGranted = hasOverlayPermission(applicationContext!!)
        lastAccessibilityEnabled = ReelDetectionAccessibilityService.isEnabled(applicationContext!!)
        lastEventSignature = null

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            handle(call.method, call.arguments, result)
        }

        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                lastEventSignature = null
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
                lastEventSignature = null
            }
        })
    }

    fun detach() {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        eventSink = null
        applicationContext = null
        hostActivity = null
        lastPermissionGranted = null
        lastAccessibilityEnabled = null
        lastEventSignature = null
    }

    fun onHostResumed() {
        val context = applicationContext ?: return
        val granted = hasOverlayPermission(context)
        val previous = lastPermissionGranted
        lastPermissionGranted = granted
        if (previous != null && previous != granted) {
            notifyOverlayPermissionChanged(granted)
        }

        val accessibilityEnabled = ReelDetectionAccessibilityService.isEnabled(context)
        val previousAccessibility = lastAccessibilityEnabled
        lastAccessibilityEnabled = accessibilityEnabled
        if (previousAccessibility != null && previousAccessibility != accessibilityEnabled) {
            notifyTrackingStatusChanged()
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQUEST_NOTIFICATION_PERMISSION_CODE) {
            return
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults.first() == PackageManager.PERMISSION_GRANTED
        applicationContext?.let { context ->
            if (granted) {
                DailyReminderScheduler.rescheduleIfEnabled(context)
            }
        }
    }

    fun notifyCounterChanged() = sendEvent(Event.COUNTER_CHANGED)

    fun notifyBubbleStarted() = sendEvent(Event.BUBBLE_STARTED)

    fun notifyBubbleStopped() = sendEvent(Event.BUBBLE_STOPPED)

    fun notifyBubbleShown() = sendEvent(Event.BUBBLE_SHOWN)

    fun notifyBubbleHidden() = sendEvent(Event.BUBBLE_HIDDEN)

    fun notifyBubbleExpanded() = sendEvent(Event.BUBBLE_EXPANDED)

    fun notifyBubbleCollapsed() = sendEvent(Event.BUBBLE_COLLAPSED)

    fun notifyOverlayPermissionChanged(granted: Boolean) {
        lastPermissionGranted = granted
        sendEvent(Event.OVERLAY_PERMISSION_CHANGED)
    }

    fun notifyTrackingStatusChanged() = sendEvent(Event.TRACKING_STATUS_CHANGED)

    private fun handle(method: String, arguments: Any?, result: MethodChannel.Result) {
        val context = applicationContext
        if (context == null) {
            result.error(ERROR_NO_CONTEXT, "Flutter channel is not attached", null)
            return
        }

        when (method) {
            Method.CHECK_OVERLAY_PERMISSION -> result.success(hasOverlayPermission(context))

            Method.REQUEST_OVERLAY_PERMISSION -> result.success(requestOverlayPermission(context))

            Method.START_FLOATING_BUBBLE ->
                withPermission(context, result) { serviceContext ->
                    safeService(result) { FloatingBubbleService.start(serviceContext) }
                }

            Method.STOP_FLOATING_BUBBLE ->
                withRunningService(result) {
                    safeService(result) {
                        FloatingBubbleService.stop(context)
                        true
                    }
                }

            Method.SHOW_FLOATING_BUBBLE ->
                withRunningService(result) {
                    withPermission(context, result) { serviceContext ->
                        safeService(result) { FloatingBubbleService.show(serviceContext) }
                    }
                }

            Method.HIDE_FLOATING_BUBBLE ->
                withRunningService(result) {
                    safeService(result) {
                        FloatingBubbleService.hide(context)
                        true
                    }
                }

            Method.EXPAND_FLOATING_BUBBLE ->
                withRunningService(result) {
                    withPermission(context, result) { serviceContext ->
                        safeService(result) { FloatingBubbleService.expand(serviceContext) }
                    }
                }

            Method.COLLAPSE_FLOATING_BUBBLE ->
                withRunningService(result) {
                    safeService(result) {
                        FloatingBubbleService.collapse(context)
                        true
                    }
                }

            Method.RESET_COUNTER ->
                safeStorage(result) {
                    val counter = BubblePreferences(context).resetCounts()
                    FloatingBubbleService.refreshCounter(context)
                    notifyCounterChanged()
                    counter.toMap()
                }

            Method.GET_COUNTER ->
                safeStorage(result) { BubblePreferences(context).getCounts().toMap() }

            Method.GET_DAILY_TARGET ->
                safeStorage(result) { BubblePreferences(context).dailyTarget }

            Method.SET_DAILY_TARGET -> {
                val rawTarget = arguments as? Number
                if (rawTarget == null) {
                    result.error(ERROR_INVALID_ARGUMENTS, "target must be a number", null)
                } else {
                    safeStorage(result) {
                        BubblePreferences(context).dailyTarget = rawTarget.toInt()
                        FloatingBubbleService.refreshCounter(context)
                        notifyCounterChanged()
                        BubblePreferences(context).dailyTarget
                    }
                }
            }

            Method.GET_BUBBLE_STATUS ->
                safeStorage(result) { readStatus(context) }

            Method.RECORD_WATCHED_VIDEO -> {
                val args = arguments as? Map<*, *>
                val platformKey = args?.get("platform") as? String
                val rawEventId = args?.get("eventId")
                when {
                    platformKey.isNullOrBlank() -> result.error(
                        ERROR_INVALID_ARGUMENTS,
                        "platform must be one of instagram, youtube, facebook, tiktok, snapchat",
                        null,
                    )

                    rawEventId != null && rawEventId !is String -> result.error(
                        ERROR_INVALID_ARGUMENTS,
                        "eventId must be a string when supplied",
                        null,
                    )

                    else -> safeTracking(result) {
                        VideoCounterManager.recordWatchedVideo(
                            context = context,
                            platformKey = platformKey,
                            eventId = rawEventId as? String,
                        ).toMap()
                    }
                }
            }

            Method.CHECK_ACCESSIBILITY_PERMISSION ->
                result.success(ReelDetectionAccessibilityService.isEnabled(context))

            Method.REQUEST_ACCESSIBILITY_PERMISSION -> result.success(openAccessibilitySettings(context))

            Method.CHECK_BACKGROUND_ACTIVITY ->
                result.success(backgroundActivityStatus(context))

            Method.REQUEST_BACKGROUND_ACTIVITY ->
                result.success(openBackgroundActivitySettings(context))

            Method.REQUEST_AUTO_BACKGROUND_START ->
                result.success(openAutoBackgroundStartSettings(context))

            Method.CHECK_PAUSE_APP_ACTIVITY ->
                result.success(pauseAppActivityStatus(context))

            Method.REQUEST_PAUSE_APP_ACTIVITY ->
                result.success(openPauseAppActivitySettings(context))

            Method.GET_DAILY_HISTORY ->
                safeStorage(result) { BubblePreferences(context).getDailyHistory() }

            Method.CHECK_NOTIFICATION_PERMISSION ->
                result.success(DailyReminderScheduler.hasPermission(context))

            Method.REQUEST_NOTIFICATION_PERMISSION ->
                result.success(requestNotificationPermission(context))

            Method.OPEN_NOTIFICATION_SETTINGS ->
                result.success(DailyReminderScheduler.openNotificationSettings(context))

            Method.GET_DAILY_REMINDER ->
                safeStorage(result) { dailyReminderMap(context) }

            Method.SET_DAILY_REMINDER -> {
                val args = arguments as? Map<*, *>
                val rawEnabled = args?.get("enabled") as? Boolean
                val rawHour = (args?.get("hour") as? Number)?.toInt()
                val rawMinute = (args?.get("minute") as? Number)?.toInt()
                when {
                    rawEnabled == null || rawHour == null || rawMinute == null ->
                        result.error(
                            ERROR_INVALID_ARGUMENTS,
                            "enabled, hour and minute are required",
                            null,
                        )

                    else -> safeStorage(result) {
                        val preferences = BubblePreferences(context)
                        preferences.dailyReminderEnabled = rawEnabled
                        preferences.dailyReminderHour = rawHour
                        preferences.dailyReminderMinute = rawMinute
                        DailyReminderScheduler.schedule(
                            context,
                            enabled = rawEnabled,
                            hour = preferences.dailyReminderHour,
                            minute = preferences.dailyReminderMinute,
                        )
                        dailyReminderMap(context)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun withPermission(
        context: Context,
        result: MethodChannel.Result,
        action: (Context) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error(ERROR_UNSUPPORTED, "Floating bubble requires Android 8.0 or newer", null)
            return
        }
        if (!Settings.canDrawOverlays(context)) {
            result.error(ERROR_NO_PERMISSION, "Display over other apps permission is missing", null)
            return
        }
        action(context)
    }

    private fun withRunningService(result: MethodChannel.Result, action: () -> Unit) {
        if (!FloatingBubbleService.isRunning) {
            result.error(ERROR_SERVICE_NOT_RUNNING, "Floating bubble service is not running", null)
            return
        }
        action()
    }

    private fun <T> safeService(result: MethodChannel.Result, action: () -> T) {
        try {
            result.success(action())
        } catch (error: SecurityException) {
            result.error(ERROR_SERVICE_CALL, error.message ?: "Service call was denied", null)
        } catch (error: IllegalStateException) {
            result.error(ERROR_SERVICE_CALL, error.message ?: "Service is unavailable", null)
        } catch (error: RuntimeException) {
            result.error(ERROR_SERVICE_CALL, error.message ?: "Service communication failed", null)
        }
    }

    private fun <T> safeStorage(result: MethodChannel.Result, action: () -> T) {
        try {
            result.success(action())
        } catch (error: BubbleStorageException) {
            result.error(ERROR_STORAGE, error.message ?: "Storage operation failed", null)
        } catch (error: RuntimeException) {
            result.error(ERROR_STORAGE, error.message ?: "Storage operation failed", null)
        }
    }

    private fun <T> safeTracking(result: MethodChannel.Result, action: () -> T) {
        try {
            result.success(action())
        } catch (error: BubbleStorageException) {
            result.error(ERROR_STORAGE, error.message ?: "Storage operation failed", null)
        } catch (error: IllegalArgumentException) {
            result.error(ERROR_INVALID_ARGUMENTS, error.message ?: "Invalid detection event", null)
        } catch (error: RuntimeException) {
            result.error(ERROR_TRACKING, error.message ?: "Detection event could not be recorded", null)
        }
    }

    private fun hasOverlayPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Settings.canDrawOverlays(context)

    private fun requestNotificationPermission(context: Context): Boolean {
        if (DailyReminderScheduler.hasPermission(context)) {
            return true
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return false
        }
        val preferences = BubblePreferences(context)
        if (preferences.notificationPermissionRequested) {
            return false
        }
        val activity = hostActivity ?: return false
        preferences.notificationPermissionRequested = true
        activity.requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION_PERMISSION_CODE,
        )
        return false
    }

    private fun dailyReminderMap(context: Context): Map<String, Any> {
        val preferences = BubblePreferences(context)
        return mapOf(
            "enabled" to preferences.dailyReminderEnabled,
            "hour" to preferences.dailyReminderHour,
            "minute" to preferences.dailyReminderMinute,
            "permissionGranted" to DailyReminderScheduler.hasPermission(context),
        )
    }

    private fun requestOverlayPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val withPackage = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
            data = Uri.fromParts("package", context.packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(withPackage)
            true
        } catch (_: ActivityNotFoundException) {
            try {
                context.startActivity(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            } catch (_: SecurityException) {
                false
            } catch (_: ActivityNotFoundException) {
                false
            }
        } catch (_: SecurityException) {
            false
        }
    }

    private fun openAccessibilitySettings(context: Context): Boolean {
        val settings = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return try {
            context.startActivity(settings)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun backgroundActivityStatus(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return BACKGROUND_ACTIVITY_UNKNOWN
        }
        val powerManager = context.getSystemService(PowerManager::class.java)
            ?: return BACKGROUND_ACTIVITY_UNKNOWN
        return if (powerManager.isIgnoringBatteryOptimizations(context.packageName)) {
            BACKGROUND_ACTIVITY_ALLOWED
        } else {
            BACKGROUND_ACTIVITY_RESTRICTED
        }
    }

    private fun openBackgroundActivitySettings(context: Context): Boolean {
        val packageUri = Uri.parse("package:${context.packageName}")
        val request = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = packageUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val list = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        val details = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = packageUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return startSettingsIntent(context, request) ||
            startSettingsIntent(context, list) ||
            startSettingsIntent(context, details)
    }

    private fun openAutoBackgroundStartSettings(context: Context): Boolean {
        val brand = "${Build.BRAND} ${Build.MANUFACTURER}".lowercase(Locale.ROOT)
        val intents = when {
            brand.contains("xiaomi") || brand.contains("poco") || brand.contains("redmi") ->
                listOf(
                    componentIntent(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity",
                    ),
                )

            brand.contains("asus") ->
                listOf(
                    componentIntent(
                        "com.asus.mobilemanager",
                        "com.asus.mobilemanager.autostart.AutoStartActivity",
                    ),
                    componentIntent(
                        "com.asus.mobilemanager",
                        "com.asus.mobilemanager.powersaver.PowerSaverSettings",
                    ),
                )

            brand.contains("letv") ->
                listOf(
                    componentIntent(
                        "com.letv.android.letvsafe",
                        "com.letv.android.letvsafe.AutobootManageActivity",
                    ),
                )

            brand.contains("honor") ->
                listOf(
                    componentIntent(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity",
                    ),
                )

            brand.contains("huawei") ->
                listOf(
                    componentIntent(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                    ),
                    componentIntent(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity",
                    ),
                )

            brand.contains("oppo") || brand.contains("realme") ->
                listOf(
                    componentIntent(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                    ),
                    componentIntent(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity",
                    ),
                    componentIntent(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.startupapp.StartupAppListActivity",
                    ),
                )

            brand.contains("vivo") || brand.contains("iqoo") ->
                listOf(
                    componentIntent(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                    ),
                    componentIntent(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                    ),
                    componentIntent(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
                    ),
                )

            brand.contains("nokia") ->
                listOf(
                    componentIntent(
                        "com.evenwell.powersaving.g3",
                        "com.evenwell.powersaving.g3.exception.PowerSaverExceptionActivity",
                    ),
                )

            brand.contains("samsung") ->
                listOf(
                    componentIntent(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity",
                    ),
                    componentIntent(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.battery.ui.usage.CheckableAppListActivity",
                    ),
                    componentIntent(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.battery.ui.BatteryActivity",
                    ),
                )

            brand.contains("oneplus") ->
                listOf(
                    componentIntent(
                        "com.oneplus.security",
                        "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                    ),
                )

            brand.contains("infinix") || brand.contains("tecno") ->
                listOf(
                    componentIntent(
                        "com.transsion.phonemaster",
                        "com.cyin.himgr.autostart.AutoStartActivity",
                    ),
                )

            else -> emptyList()
        }
        return intents.any { safeStartSettingsIntent(context, it) } ||
            safeStartSettingsIntent(context, appDetailsIntent(context)) ||
            safeStartSettingsIntent(
                context,
                Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
    }

    private fun componentIntent(packageName: String, className: String): Intent =
        Intent().setComponent(ComponentName(packageName, className))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    private fun appDetailsIntent(context: Context): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun pauseAppActivityStatus(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            return PAUSE_APP_ACTIVITY_UNKNOWN
        }
        return try {
            if (context.packageManager.isAutoRevokeWhitelisted(context.packageName)) {
                PAUSE_APP_ACTIVITY_DISABLED
            } else {
                PAUSE_APP_ACTIVITY_ENABLED
            }
        } catch (_: Exception) {
            PAUSE_APP_ACTIVITY_UNKNOWN
        }
    }

    private fun openPauseAppActivitySettings(context: Context): Boolean =
        safeStartSettingsIntent(context, appDetailsIntent(context)) ||
            safeStartSettingsIntent(
                context,
                Intent(Settings.ACTION_MANAGE_APPLICATIONS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )

    private fun safeStartSettingsIntent(context: Context, intent: Intent): Boolean =
        try {
            if (intent.component != null &&
                context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).isEmpty()
            ) {
                false
            } else {
                context.startActivity(intent)
                true
            }
        } catch (_: Exception) {
            false
        }

    private fun startSettingsIntent(context: Context, intent: Intent): Boolean =
        try {
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }

    private fun readStatus(context: Context): Map<String, Any> {
        val preferences = BubblePreferences(context)
        val permissionGranted = hasOverlayPermission(context)
        val serviceRunning = FloatingBubbleService.isRunning
        val bubbleVisible = preferences.isBubbleActive && serviceRunning && permissionGranted
        val status = linkedMapOf<String, Any>()
        status["bubbleVisible"] = bubbleVisible
        status["expanded"] = preferences.isExpanded && bubbleVisible
        status["overlayPermissionGranted"] = permissionGranted
        status["backgroundActivityStatus"] = backgroundActivityStatus(context)
        status["serviceRunning"] = serviceRunning
        val accessibilityEnabled = ReelDetectionAccessibilityService.isEnabled(context)
        val serviceConnected = ReelDetectionAccessibilityService.isConnected
        val detectionState = VideoCounterManager.trackingState
        status["accessibilityEnabled"] = accessibilityEnabled
        status["accessibilityServiceRunning"] = serviceConnected
        status["detectionState"] = detectionState
        status["detectionMessage"] = VideoCounterManager.trackingMessage
        status["trackingEngineConnected"] = VideoCounterManager.isTrackingEngineConnected
        status["trackingState"] = detectionState
        status["trackingMessage"] = VideoCounterManager.trackingMessage
        status["trackingActive"] = detectionState == "active" && bubbleVisible
        status["counter"] = preferences.getCounts().toMap()
        return status
    }

    private fun sendEvent(type: String) {
        mainHandler.post {
            val context = applicationContext ?: return@post
            val sink = eventSink ?: return@post
            val status = readStatus(context)
            val signature = eventSignature(type, status)
            if (signature == lastEventSignature) {
                return@post
            }
            lastEventSignature = signature
            sink.success(
                mapOf(
                    "type" to type,
                    "status" to status,
                ),
            )
        }
    }

    private fun eventSignature(type: String, status: Map<*, *>): String {
        val counter = status["counter"] as? Map<*, *>
        return listOf(
            type,
            status["bubbleVisible"],
            status["expanded"],
            status["overlayPermissionGranted"],
            status["backgroundActivityStatus"],
            status["serviceRunning"],
            status["accessibilityEnabled"],
            status["accessibilityServiceRunning"],
            status["detectionState"],
            status["detectionMessage"],
            status["trackingEngineConnected"],
            status["trackingState"],
            counter?.get("total"),
            counter?.get("instagram"),
            counter?.get("youtube"),
            counter?.get("facebook"),
            counter?.get("tiktok"),
            counter?.get("snapchat"),
            counter?.get("date"),
        ).joinToString("|")
    }
}
