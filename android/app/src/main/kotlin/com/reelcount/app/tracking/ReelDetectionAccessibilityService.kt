package com.reelcount.app.tracking

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import com.reelcount.app.communication.FloatingBubbleChannel
import com.reelcount.app.overlay.FloatingBubbleService
import com.reelcount.app.storage.BubblePlatform
import java.security.MessageDigest
import java.util.Locale
import java.util.UUID
import kotlin.math.abs

class ReelDetectionAccessibilityService : AccessibilityService() {

    private var currentPackage: String? = null
    private var sessionActive: Boolean = false
    private var lastKey: String? = null
    private val recentKeys = ArrayDeque<String>()

    private var pendingTransition: Boolean = false
    private var transitionEpoch: Int = 0
    private var lastCountedEpoch: Int = -1

    private var lastScrollSource: String? = null
    private var lastScrollX: Int = Int.MIN_VALUE
    private var lastScrollY: Int = Int.MIN_VALUE

    private val lastFailureAt = HashMap<String, Long>()
    private var sessionNonce: String = "session"

    private val detectHandler = Handler(Looper.getMainLooper())
    private var pendingDetect: Runnable? = null
    private var detecting: Boolean = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        isConnected = true
        sessionNonce = UUID.randomUUID().toString().replace("-", "").take(8)
        resetSession(null)
        VideoCounterManager.setDetectionConnected(true)
        FloatingBubbleChannel.notifyTrackingStatusChanged()
        FloatingBubbleService.refreshCounter(applicationContext)
        logStage("SERVICE_CONNECTED", "session=$sessionNonce verbose=$verboseTreeDump")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        val currentEvent = event ?: return
        val packageName = currentEvent.packageName?.toString()?.trim()?.takeIf { it.isNotEmpty() }
            ?: return
        val platform = platformForPackage(packageName) ?: return

        Log.d(TAG, "ACCESSIBILITY_EVENT_RECEIVED type=${eventTypeName(currentEvent.eventType)} package=$packageName")
        try {
            when (currentEvent.eventType) {
                AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> {
                    if (packageName != currentPackage) {
                        resetSession(packageName)
                    }
                    logStage("APP_FOREGROUND", "package=$packageName platform=${platform.key} activity=${currentEvent.className}")
                    scheduleDetect(platform, packageName, SETTLE_DELAY_MS)
                }

                AccessibilityEvent.TYPE_VIEW_SCROLLED -> {
                    trackScroll(currentEvent)
                    scheduleDetect(platform, packageName, 0L)
                }

                AccessibilityEvent.TYPE_VIEW_CLICKED -> scheduleDetect(platform, packageName, SETTLE_DELAY_MS)

                AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> scheduleDetect(platform, packageName, SETTLE_DELAY_MS)
            }
        } catch (error: SecurityException) {
            reportError("Accessibility tree access denied", error)
        } catch (error: RuntimeException) {
            reportError("Detection failed: ${error.message ?: "unknown error"}", error)
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "accessibility service interrupted")
        markDisconnected()
    }

    override fun onDestroy() {
        cancelPendingDetect()
        markDisconnected()
        super.onDestroy()
    }

    private fun scheduleDetect(platform: BubblePlatform, packageName: String, delayMs: Long) {
        cancelPendingDetect()
        val runnable = Runnable {
            pendingDetect = null
            runDetect(platform, packageName)
        }
        pendingDetect = runnable
        detectHandler.postDelayed(runnable, delayMs)
    }

    private fun cancelPendingDetect() {
        pendingDetect?.let { detectHandler.removeCallbacks(it) }
        pendingDetect = null
    }

    private fun runDetect(platform: BubblePlatform, packageName: String) {
        if (detecting) {
            return
        }
        detecting = true
        try {
            detect(platform, packageName)
        } finally {
            detecting = false
        }
    }

    private fun markDisconnected() {
        cancelPendingDetect()
        isConnected = false
        resetSession(null)
        VideoCounterManager.setDetectionConnected(false)
        FloatingBubbleChannel.notifyTrackingStatusChanged()
        FloatingBubbleService.refreshCounter(applicationContext)
    }

    private fun resetSession(packageName: String?) {
        currentPackage = packageName
        sessionActive = false
        lastKey = null
        recentKeys.clear()
        pendingTransition = false
        transitionEpoch = 0
        lastCountedEpoch = -1
        lastScrollSource = null
        lastScrollX = Int.MIN_VALUE
        lastScrollY = Int.MIN_VALUE
    }

    private fun trackScroll(event: AccessibilityEvent) {
        if (!sessionActive && lastKey == null) {
            return
        }
        val magnitude = scrollMagnitude(event)
        if (magnitude >= SCROLL_THRESHOLD) {
            pendingTransition = true
            transitionEpoch++
            Log.d(TAG, "SCROLL_TRANSITION magnitude=$magnitude epoch=$transitionEpoch")
        }
    }

    private fun scrollMagnitude(event: AccessibilityEvent): Int {
        val deltaX = if (android.os.Build.VERSION.SDK_INT >= 28) event.scrollDeltaX else 0
        val deltaY = if (android.os.Build.VERSION.SDK_INT >= 28) event.scrollDeltaY else 0
        var magnitude = maxOf(abs(deltaX), abs(deltaY))
        if (magnitude > 0) {
            return magnitude
        }

        val sourceKey = "${event.source?.viewIdResourceName.orEmpty()}:${event.className}"
        val scrollX = event.scrollX
        val scrollY = event.scrollY
        if (sourceKey != lastScrollSource || scrollX < 0 || scrollY < 0) {
            lastScrollSource = sourceKey
            lastScrollX = scrollX
            lastScrollY = scrollY
            return 0
        }
        magnitude = maxOf(abs(scrollX - lastScrollX), abs(scrollY - lastScrollY))
        lastScrollX = scrollX
        lastScrollY = scrollY
        return magnitude
    }

    private fun detect(platform: BubblePlatform, packageName: String) {
        val root = resolveRoot(packageName)
        if (root == null) {
            logStage("VIEWER_DETECTION_FAILED", "platform=${platform.key} reason=no-root-window")
            return
        }

        logStage("VIEWER_DETECTION_STARTED", "platform=${platform.key}")
        val match = findViewer(platform, root)
        if (match == null) {
            sessionActive = false
            lastKey = null
            logViewerFailure(platform, root)
            return
        }

        sessionActive = true
        logStage("VIEWER_DETECTED", "platform=${platform.key} ${match.evidence}")

        val identity = extractIdentity(match.node)
        if (identity == null) {
            logStage("VIDEO_CONTENT_IDENTIFIED", "platform=${platform.key} identity=none")
            return
        }
        logStage(
            "VIDEO_CONTENT_IDENTIFIED",
            "platform=${platform.key} stable=${identity.stable} label=${identity.label}",
        )

        val baseKey = "${platform.key}:${identity.value}"
        val newByTransition = pendingTransition && transitionEpoch != lastCountedEpoch
        val revisiting = recentKeys.contains(baseKey) && !newByTransition
        val isNew = (baseKey != lastKey || newByTransition) && !revisiting
        logStage(
            "DUPLICATE_CHECK",
            "platform=${platform.key} new=$isNew revisiting=$revisiting " +
                "pending=$pendingTransition epoch=$transitionEpoch label=${identity.label}",
        )
        if (!isNew) {
            return
        }

        val eventId = if (identity.stable) {
            baseKey
        } else {
            "$baseKey#$sessionNonce#$transitionEpoch"
        }
        val result = VideoCounterManager.recordWatchedVideo(applicationContext, platform.key, eventId)

        lastKey = baseKey
        rememberKey(baseKey)
        lastCountedEpoch = transitionEpoch
        pendingTransition = false
        logStage(
            "REEL_RECORDED",
            "platform=${platform.key} recorded=${result.recorded} duplicate=${result.duplicate} " +
                "stable=${identity.stable} label=${identity.label}",
        )
    }

    private fun rememberKey(key: String) {
        recentKeys.remove(key)
        recentKeys.addFirst(key)
        while (recentKeys.size > MAX_RECENT_KEYS) {
            recentKeys.removeLast()
        }
    }

    private fun resolveRoot(packageName: String): AccessibilityNodeInfo? {
        val activeRoot = rootInActiveWindow
        if (activeRoot?.packageName?.toString() == packageName) {
            return activeRoot
        }
        val fromWindows = try {
            windows.firstOrNull { window ->
                window.type == AccessibilityWindowInfo.TYPE_APPLICATION &&
                    (window.isActive || window.isFocused) &&
                    window.root?.packageName?.toString() == packageName
            } ?: windows.firstOrNull { it.root?.packageName?.toString() == packageName }
        } catch (_: RuntimeException) {
            null
        }
        val candidate = fromWindows?.root ?: activeRoot
        return candidate?.takeIf { it.packageName?.toString() == packageName }
    }

    private fun findViewer(platform: BubblePlatform, root: AccessibilityNodeInfo): ViewerMatch? {
        val metrics = resources.displayMetrics
        val rootBounds = Rect().also(root::getBoundsInScreen)
        val screenWidth = if (rootBounds.width() > 0) rootBounds.width() else metrics.widthPixels
        val screenHeight = if (rootBounds.height() > 0) rootBounds.height() else metrics.heightPixels
        var best: ViewerMatch? = null
        var bestArea = 0

        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        var visited = 0

        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val (node, depth) = queue.removeFirst()
            visited++
            val fullscreen = coversScreen(node, screenWidth, screenHeight)
            val directSnapchatViewer = platform == BubblePlatform.SNAPCHAT && !node.isScrollable &&
                node.viewIdResourceName.orEmpty().lowercase(Locale.US).let { id ->
                    id.contains("opera_viewer") || id.contains("spotlight_container")
                }
            if (fullscreen && (node.isScrollable || directSnapchatViewer)) {
                val idHint = findHint(node, viewerIdTokens(platform))
                val textHint = if (idHint == null) findHint(node, viewerTextTokens(platform)) else null
                val hint = idHint ?: textHint
                val pager = isPagerNode(node)
                val allowed = directSnapchatViewer || pager || idHint != null ||
                    (textHint != null && platform in TEXT_HINT_PLATFORMS)
                if (allowed) {
                    val media = countMedia(node, screenWidth, screenHeight, platform)
                    val feedGuard = hint == null && media.total > MAX_VIEWER_MEDIA_NODES
                    if (directSnapchatViewer ||
                        (media.total >= 1 && media.dominant >= 1 && !feedGuard)
                    ) {
                        val bounds = Rect().also(node::getBoundsInScreen)
                        val area = bounds.width() * bounds.height()
                        if (area > bestArea) {
                            bestArea = area
                            best = ViewerMatch(
                                node = node,
                                evidence = "id=${node.viewIdResourceName} class=${node.className} " +
                                    "idHint=$idHint textHint=$textHint pager=$pager " +
                                    "media=${media.total} dominant=${media.dominant}",
                            )
                        }
                    }
                }
            }
            if (depth < MAX_DEPTH) {
                for (index in 0 until node.childCount) {
                    node.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }
        return best
    }

    private fun coversScreen(node: AccessibilityNodeInfo, screenWidth: Int, screenHeight: Int): Boolean {
        val bounds = Rect().also(node::getBoundsInScreen)
        if (bounds.isEmpty) {
            return false
        }
        return bounds.width() >= screenWidth * FULLSCREEN_WIDTH_RATIO &&
            bounds.height() >= screenHeight * FULLSCREEN_HEIGHT_RATIO
    }

    private fun isPagerNode(node: AccessibilityNodeInfo): Boolean {
        val className = node.className?.toString().orEmpty().lowercase(Locale.US)
        val id = node.viewIdResourceName.orEmpty().lowercase(Locale.US)
        return className.contains("viewpager") || id.contains("pager")
    }

    private fun findHint(node: AccessibilityNodeInfo, tokens: List<String>): String? {
        if (tokens.isEmpty()) {
            return null
        }
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(node to 0)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_HINT_NODES) {
            val (current, depth) = queue.removeFirst()
            visited++
            val haystack = buildString {
                append(current.viewIdResourceName.orEmpty()).append(' ')
                append(current.contentDescription?.toString().orEmpty()).append(' ')
                append(current.text?.toString().orEmpty())
            }.lowercase(Locale.US)
            for (token in tokens) {
                if (haystack.contains(token)) {
                    return token
                }
            }
            if (depth < MAX_HINT_DEPTH) {
                for (index in 0 until current.childCount) {
                    current.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }
        return null
    }

    private fun countMedia(
        node: AccessibilityNodeInfo,
        screenWidth: Int,
        screenHeight: Int,
        platform: BubblePlatform,
    ): MediaCount {
        var total = 0
        var dominant = 0
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { queue.add(it to 0) }
        }
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_MEDIA_NODES) {
            val (current, depth) = queue.removeFirst()
            visited++
            if (isMediaLike(current, screenWidth, screenHeight, platform)) {
                total++
                val bounds = Rect().also(current::getBoundsInScreen)
                if (bounds.width() >= screenWidth * DOMINANT_WIDTH_RATIO &&
                    bounds.height() >= screenHeight * DOMINANT_HEIGHT_RATIO
                ) {
                    dominant++
                }
            }
            if (depth < MAX_MEDIA_DEPTH) {
                for (index in 0 until current.childCount) {
                    current.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }
        return MediaCount(total, dominant)
    }

    private fun isMediaLike(
        node: AccessibilityNodeInfo,
        screenWidth: Int,
        screenHeight: Int,
        platform: BubblePlatform,
    ): Boolean {
        val bounds = Rect().also(node::getBoundsInScreen)
        if (bounds.width() < screenWidth * MEDIA_WIDTH_RATIO ||
            bounds.height() < screenHeight * MEDIA_HEIGHT_RATIO
        ) {
            return false
        }
        val className = node.className?.toString().orEmpty().lowercase(Locale.US)
        if (className.contains("imageview") ||
            className.contains("video") ||
            className.contains("textureview") ||
            className.contains("surfaceview") ||
            className.contains("playerview") ||
            className.contains("glsurfaceview")
        ) {
            return true
        }
        val id = node.viewIdResourceName.orEmpty().lowercase(Locale.US)
        if (id.contains("video") || id.contains("player") || id.contains("media") ||
            id.contains("reel") || id.contains("clips") || id.contains("spotlight")
        ) {
            return true
        }
        val description = node.contentDescription?.toString().orEmpty().lowercase(Locale.US)
        return description.contains("video") ||
            description.contains("reel") ||
            description.contains("spotlight") ||
            description.contains("shorts") ||
            (platform == BubblePlatform.FACEBOOK &&
                description.length >= MIN_CAPTION_LENGTH && description.contains('#'))
    }

    private fun extractIdentity(viewer: AccessibilityNodeInfo): ReelIdentity? {
        val authors = ArrayList<String>()
        val captions = ArrayList<String>()
        val others = LinkedHashSet<String>()

        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(viewer to 0)
        var visited = 0
        while (queue.isNotEmpty() && visited < MAX_IDENTITY_NODES) {
            val (current, depth) = queue.removeFirst()
            visited++
            val id = current.viewIdResourceName.orEmpty().lowercase(Locale.US)
            val description = current.contentDescription?.toString().orEmpty()
            val text = current.text?.toString().orEmpty()

            extractAuthor(description)?.let(authors::add)
            extractAuthor(text)?.let(authors::add)
            if (isAuthorField(id)) {
                stableToken(text)?.let(authors::add)
                stableToken(description)?.let(authors::add)
            }
            if (isCaptionField(id)) {
                stableToken(text)?.let(captions::add)
            }
            stableToken(text)?.let(others::add)
            stableToken(description)?.let(others::add)

            if (depth < MAX_IDENTITY_DEPTH) {
                for (index in 0 until current.childCount) {
                    current.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }

        val author = authors.firstOrNull { it.isNotBlank() }
        val caption = captions.firstOrNull { it != author && it.length >= MIN_CAPTION_LENGTH }

        if (author != null || caption != null) {
            val label = author ?: caption.orEmpty()
            val parts = ArrayList<String>(MAX_STRUCTURAL_TOKENS + 2)
            author?.let(parts::add)
            caption?.let(parts::add)
            others.sorted().take(MAX_STRUCTURAL_TOKENS).forEach(parts::add)
            val value = sha256(parts.joinToString("|"))
            return ReelIdentity(value = value, label = label.take(MAX_LABEL_LENGTH), stable = true)
        }

        val structuralTokens = others.sorted().take(MAX_STRUCTURAL_TOKENS)
        if (structuralTokens.isEmpty() && viewer.childCount == 0) {
            return null
        }
        val bounds = Rect().also(viewer::getBoundsInScreen)
        val raw = listOf(
            viewer.className?.toString().orEmpty(),
            viewer.viewIdResourceName.orEmpty(),
            viewer.childCount.toString(),
            (bounds.width() / COARSE_BOUNDS).toString(),
            (bounds.height() / COARSE_BOUNDS).toString(),
            structuralTokens.joinToString(","),
        ).joinToString("|")
        val label = structuralTokens.firstOrNull()?.take(MAX_LABEL_LENGTH) ?: "structural"
        return ReelIdentity(value = sha256(raw), label = label, stable = false)
    }

    private fun isAuthorField(id: String): Boolean =
        id.contains("title") || id.contains("username") || id.contains("user_name") ||
            id.contains("author") || id.contains("creator") || id.contains("channel") ||
            id.contains("handle") || id.contains("nickname")

    private fun isCaptionField(id: String): Boolean =
        id.contains("desc") || id.contains("caption") || id.contains("subtitle") ||
            id.contains("content_text")

    private fun extractAuthor(raw: String): String? {
        if (raw.isBlank()) {
            return null
        }
        val value = normalize(raw)
        for (pattern in AUTHOR_PATTERNS) {
            val match = pattern.find(value) ?: continue
            val candidate = match.groupValues.lastOrNull { it.isNotBlank() }?.trim()
            if (!candidate.isNullOrBlank()) {
                return candidate.take(MAX_LABEL_LENGTH)
            }
        }
        return null
    }

    private fun stableToken(raw: String): String? {
        var token = normalize(raw)
        if (token.isBlank() || SOCIAL_WORD_PATTERN.containsMatchIn(token)) {
            return null
        }
        token = token.replace(DIGITS, " ").replace(WHITESPACE, " ").trim()
        if (token.length < MIN_TOKEN_LENGTH || token.length > MAX_TOKEN_LENGTH) {
            return null
        }
        if (token in GENERIC_TOKENS) {
            return null
        }
        return token
    }

    private fun normalize(value: String): String =
        value.lowercase(Locale.US).replace(WHITESPACE, " ").trim()

    private fun sha256(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }
    }

    private fun logViewerFailure(platform: BubblePlatform, root: AccessibilityNodeInfo) {
        val now = SystemClock.uptimeMillis()
        val last = lastFailureAt[platform.key] ?: 0L
        if (now - last < FAILURE_LOG_INTERVAL_MS) {
            return
        }
        lastFailureAt[platform.key] = now
        logStage("VIEWER_DETECTION_FAILED", "platform=${platform.key} reason=no-viewer-node")
        dumpHierarchy(platform, root)
        logScrollableNodes(platform, root)
    }

    private fun logScrollableNodes(platform: BubblePlatform, root: AccessibilityNodeInfo) {
        val metrics = resources.displayMetrics
        val rootBounds = Rect().also(root::getBoundsInScreen)
        val screenWidth = if (rootBounds.width() > 0) rootBounds.width() else metrics.widthPixels
        val screenHeight = if (rootBounds.height() > 0) rootBounds.height() else metrics.heightPixels
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        var visited = 0
        var found = 0
        while (queue.isNotEmpty() && visited < MAX_NODES) {
            val (node, depth) = queue.removeFirst()
            visited++
            if (node.isScrollable) {
                found++
                if (found <= MAX_SCROLL_LOG) {
                    val bounds = Rect().also(node::getBoundsInScreen)
                    Log.i(
                        TAG,
                        "SCROLLABLE platform=${platform.key} depth=$depth class=${node.className} " +
                            "id=${node.viewIdResourceName} visible=${node.isVisibleToUser} " +
                            "covers=${coversScreen(node, screenWidth, screenHeight)} bounds=$bounds",
                    )
                }
            }
            if (depth < MAX_DEPTH) {
                for (index in 0 until node.childCount) {
                    node.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }
        Log.i(TAG, "SCROLLABLE_SUMMARY platform=${platform.key} visited=$visited scrollable=$found")
    }

    private fun dumpHierarchy(platform: BubblePlatform, root: AccessibilityNodeInfo) {
        val limit = if (verboseTreeDump) VERBOSE_DUMP_LINES else COMPACT_DUMP_LINES
        val queue = ArrayDeque<Pair<AccessibilityNodeInfo, Int>>()
        queue.add(root to 0)
        var emitted = 0
        var visited = 0
        var withId = 0
        var scrollable = 0
        var total = 0
        while (queue.isNotEmpty() && emitted < limit && visited < MAX_NODES) {
            val (node, depth) = queue.removeFirst()
            visited++
            total++
            val id = node.viewIdResourceName.orEmpty()
            val description = node.contentDescription?.toString().orEmpty()
            val text = node.text?.toString().orEmpty()
            if (id.isNotBlank()) {
                withId++
            }
            if (node.isScrollable) {
                scrollable++
            }
            val interesting = node.isScrollable || id.isNotBlank() || description.isNotBlank() || text.isNotBlank()
            if (interesting) {
                val bounds = Rect().also(node::getBoundsInScreen)
                Log.i(
                    TAG,
                    "TREE depth=$depth scroll=${node.isScrollable} class=${node.className} " +
                        "id=$id bounds=$bounds desc=${truncate(description)} text=${truncate(text)}",
                )
                emitted++
            }
            if (depth < MAX_DUMP_DEPTH) {
                for (index in 0 until node.childCount) {
                    node.getChild(index)?.let { queue.add(it to depth + 1) }
                }
            }
        }
        Log.i(
            TAG,
            "TREE_SUMMARY platform=${platform.key} visited=$total withId=$withId scrollable=$scrollable " +
                "emitted=$emitted",
        )
    }

    private fun truncate(value: String): String {
        if (value.isBlank()) {
            return ""
        }
        return value.replace(WHITESPACE, " ").take(MAX_LOG_TEXT_LENGTH)
    }

    private fun logStage(stage: String, detail: String) {
        Log.i(TAG, "$stage $detail")
    }

    private fun platformForPackage(packageName: String): BubblePlatform? = when {
        packageName == "com.instagram.android" ||
            packageName == "com.instagram.barcelona" -> BubblePlatform.INSTAGRAM

        packageName == "com.google.android.youtube" ||
            packageName == "com.google.android.apps.youtube.music" -> BubblePlatform.YOUTUBE

        packageName == "com.facebook.katana" ||
            packageName == "com.facebook.android" ||
            packageName == "com.facebook.lite" -> BubblePlatform.FACEBOOK

        packageName == "com.zhiliaoapp.musically" ||
            packageName.startsWith("com.tiktok.") -> BubblePlatform.TIKTOK

        packageName == "com.snapchat.android" -> BubblePlatform.SNAPCHAT
        else -> null
    }

    private fun viewerIdTokens(platform: BubblePlatform): List<String> = when (platform) {
        BubblePlatform.INSTAGRAM -> listOf("clips_viewer", "clips_media", "clips_swipe")
        BubblePlatform.YOUTUBE -> listOf("reel_recycler", "reel_player", "shorts")
        BubblePlatform.FACEBOOK -> emptyList()
        BubblePlatform.TIKTOK -> listOf(
            "viewpager",
            "video_container",
            "long_press_layout",
            "videomusiccoverblock",
            "video_visible_area",
        )

        BubblePlatform.SNAPCHAT -> listOf("opera_viewer", "spotlight_container", "opera_content")
    }

    private fun viewerTextTokens(platform: BubblePlatform): List<String> = when (platform) {
        BubblePlatform.INSTAGRAM -> listOf("reel by")
        BubblePlatform.YOUTUBE -> listOf("shorts", "reel")
        BubblePlatform.FACEBOOK -> listOf("'s reels", "reels tab details")
        BubblePlatform.TIKTOK -> listOf("video")
        BubblePlatform.SNAPCHAT -> listOf("spotlight")
    }

    private fun reportError(message: String, error: Throwable) {
        Log.w(TAG, "$message (${error.message ?: "no details"})")
        VideoCounterManager.setDetectionError(message)
    }

    private fun eventTypeName(type: Int): String = when (type) {
        AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED -> "WINDOW_STATE_CHANGED"
        AccessibilityEvent.TYPE_VIEW_SCROLLED -> "VIEW_SCROLLED"
        AccessibilityEvent.TYPE_VIEW_CLICKED -> "VIEW_CLICKED"
        AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> "WINDOW_CONTENT_CHANGED"
        else -> type.toString()
    }

    private data class ViewerMatch(val node: AccessibilityNodeInfo, val evidence: String)

    private data class MediaCount(val total: Int, val dominant: Int)

    private data class ReelIdentity(val value: String, val label: String, val stable: Boolean)

    private val verboseTreeDump: Boolean
        get() = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    companion object {
        private const val TAG = "ReelDetection"
        private const val MAX_NODES = 1500
        private const val MAX_DEPTH = 20
        private const val MAX_HINT_NODES = 200
        private const val MAX_HINT_DEPTH = 8
        private const val MAX_MEDIA_NODES = 400
        private const val MAX_MEDIA_DEPTH = 10
        private const val MAX_IDENTITY_NODES = 400
        private const val MAX_IDENTITY_DEPTH = 8
        private const val MAX_DUMP_DEPTH = 12
        private const val MAX_SCROLL_LOG = 25
        private const val COMPACT_DUMP_LINES = 20
        private const val VERBOSE_DUMP_LINES = 60
        private const val MAX_LOG_TEXT_LENGTH = 80
        private const val MAX_RECENT_KEYS = 32
        private const val MAX_STRUCTURAL_TOKENS = 8
        private const val MAX_VIEWER_MEDIA_NODES = 3
        private const val MAX_LABEL_LENGTH = 48
        private const val MIN_TOKEN_LENGTH = 2
        private const val MAX_TOKEN_LENGTH = 140
        private const val MIN_CAPTION_LENGTH = 10
        private const val COARSE_BOUNDS = 64

        private const val FULLSCREEN_WIDTH_RATIO = 0.6
        private const val FULLSCREEN_HEIGHT_RATIO = 0.5
        private const val MEDIA_WIDTH_RATIO = 0.3
        private const val MEDIA_HEIGHT_RATIO = 0.2
        private const val DOMINANT_WIDTH_RATIO = 0.5
        private const val DOMINANT_HEIGHT_RATIO = 0.5

        private const val SCROLL_THRESHOLD = 60
        private const val SETTLE_DELAY_MS = 500L
        private const val FAILURE_LOG_INTERVAL_MS = 3000L

        private val WHITESPACE = Regex("\\s+")
        private val DIGITS = Regex("[0-9]+")
        private val SOCIAL_WORD_PATTERN = Regex(
            "\\b(likes?|comments?|shares?|views?|saves?|reposts?|followers?|plays?|subscribers?)\\b",
        )
        private val TEXT_HINT_PLATFORMS = setOf(BubblePlatform.YOUTUBE, BubblePlatform.FACEBOOK)
        private val AUTHOR_PATTERNS = listOf(
            Regex("reel by ([^.,|]+)"),
            Regex("view (.+?)'s reels"),
            Regex("(.+?), privacy setting public"),
            Regex("original sound .* by ([^.,|]+)"),
            Regex("original sound · ([^.,|]+)"),
            Regex("@[a-z0-9_.]+"),
        )
        private val GENERIC_TOKENS = setOf(
            "like",
            "likes",
            "comment",
            "comments",
            "share",
            "shares",
            "save",
            "saves",
            "more",
            "see translation",
            "sponsored",
            "suggested",
            "follow",
            "following",
            "reels",
            "reel",
            "shorts",
            "short",
            "spotlight",
            "video",
            "videos",
            "instagram",
            "youtube",
            "facebook",
            "tiktok",
            "snapchat",
            "sound",
            "original audio",
            "original sound",
            "audio",
            "see all",
            "next",
            "previous",
            "play",
            "pause",
            "mute",
            "unmute",
            "collapse",
            "hide",
            "back",
            "close",
            "home",
            "search",
            "profile",
            "notifications",
            "create",
            "menu",
            "reels tab details",
            "create a reel",
        )

        @Volatile
        var isConnected: Boolean = false
            private set

        fun isEnabled(context: Context): Boolean {
            val globallyEnabled = try {
                Settings.Secure.getInt(
                    context.contentResolver,
                    Settings.Secure.ACCESSIBILITY_ENABLED,
                    0,
                ) == 1
            } catch (_: Settings.SettingNotFoundException) {
                false
            }
            if (!globallyEnabled) {
                return false
            }

            val configured = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ).orEmpty()
            if (configured.isBlank()) {
                return false
            }

            val component = ComponentName(context, ReelDetectionAccessibilityService::class.java)
            val names = listOf(component.flattenToString(), component.flattenToShortString())
            return configured.split(':').any { entry ->
                names.any { it.equals(entry.trim(), ignoreCase = true) }
            }
        }
    }
}
