package com.reelcount.app.storage

import android.content.Context
import android.content.SharedPreferences
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class BubbleStorageException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

enum class BubblePlatform(val key: String, val label: String) {
    INSTAGRAM("instagram", "Instagram"),
    YOUTUBE("youtube", "YouTube Shorts"),
    FACEBOOK("facebook", "Facebook Reels"),
    TIKTOK("tiktok", "TikTok"),
    SNAPCHAT("snapchat", "Snapchat Spotlight");

    companion object {
        fun fromKey(key: String?): BubblePlatform? = entries.firstOrNull { it.key == key }
    }
}

data class BubbleCounts(
    val instagram: Int = 0,
    val youtube: Int = 0,
    val facebook: Int = 0,
    val tiktok: Int = 0,
    val snapchat: Int = 0,
    val date: String = "",
) {
    val total: Int
        get() = instagram + youtube + facebook + tiktok + snapchat

    fun countFor(platform: BubblePlatform): Int = when (platform) {
        BubblePlatform.INSTAGRAM -> instagram
        BubblePlatform.YOUTUBE -> youtube
        BubblePlatform.FACEBOOK -> facebook
        BubblePlatform.TIKTOK -> tiktok
        BubblePlatform.SNAPCHAT -> snapchat
    }

    fun incremented(platform: BubblePlatform): BubbleCounts = when (platform) {
        BubblePlatform.INSTAGRAM -> copy(instagram = instagram + 1)
        BubblePlatform.YOUTUBE -> copy(youtube = youtube + 1)
        BubblePlatform.FACEBOOK -> copy(facebook = facebook + 1)
        BubblePlatform.TIKTOK -> copy(tiktok = tiktok + 1)
        BubblePlatform.SNAPCHAT -> copy(snapchat = snapchat + 1)
    }

    fun reset(): BubbleCounts = BubbleCounts(date = date)

    fun toMap(): Map<String, Any> = mapOf(
        "total" to total,
        BubblePlatform.INSTAGRAM.key to instagram,
        BubblePlatform.YOUTUBE.key to youtube,
        BubblePlatform.FACEBOOK.key to facebook,
        BubblePlatform.TIKTOK.key to tiktok,
        BubblePlatform.SNAPCHAT.key to snapchat,
        "date" to date,
    )
}

data class BubblePosition(val x: Int, val y: Int, val width: Int, val height: Int)

enum class BubblePositionKind(val keyPrefix: String) {
    COLLAPSED("collapsed"),
    EXPANDED("expanded");

    internal fun key(part: String): String = "${keyPrefix}_$part"
}

class BubblePreferences(context: Context) {
    private val preferences: SharedPreferences = try {
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    } catch (error: RuntimeException) {
        throw BubbleStorageException("Unable to initialize bubble storage", error)
    }

    private var cachedDate: String? = null

    var isBubbleActive: Boolean
        get() = preferences.getBoolean(KEY_ACTIVE, false)
        set(value) = edit { putBoolean(KEY_ACTIVE, value) }

    var isExpanded: Boolean
        get() = preferences.getBoolean(KEY_EXPANDED, false)
        set(value) = edit { putBoolean(KEY_EXPANDED, value) }

    var selectedPlatform: BubblePlatform
        get() {
            val stored = preferences.getString(KEY_SELECTED_PLATFORM, null)
            return BubblePlatform.fromKey(stored) ?: BubblePlatform.INSTAGRAM
        }
        set(value) = edit { putString(KEY_SELECTED_PLATFORM, value.key) }

    val lastCounterDate: String
        get() {
            ensureToday()
            return cachedDate.orEmpty()
        }

    fun getCounts(): BubbleCounts {
        ensureToday()
        val counts = BubbleCounts(
            instagram = preferences.getInt(BubblePlatform.INSTAGRAM.key, 0),
            youtube = preferences.getInt(BubblePlatform.YOUTUBE.key, 0),
            facebook = preferences.getInt(BubblePlatform.FACEBOOK.key, 0),
            tiktok = preferences.getInt(BubblePlatform.TIKTOK.key, 0),
            snapchat = preferences.getInt(BubblePlatform.SNAPCHAT.key, 0),
            date = cachedDate.orEmpty(),
        )
        if (preferences.getInt(KEY_TOTAL, -1) != counts.total) {
            edit { putInt(KEY_TOTAL, counts.total) }
        }
        return counts
    }

    fun incrementPlatform(platform: BubblePlatform): BubbleCounts {
        val updated = getCounts().incremented(platform).copy(date = lastCounterDate)
        setCounts(updated)
        return updated
    }

    fun resetCounts(): BubbleCounts {
        val cleared = BubbleCounts(date = lastCounterDate)
        setCounts(cleared)
        return cleared
    }

    fun hasProcessedEvent(eventId: String): Boolean {
        ensureToday()
        return preferences.getStringSet(KEY_PROCESSED_EVENTS, emptySet()).orEmpty().contains(eventId)
    }

    fun markProcessedEvent(eventId: String) {
        ensureToday()
        val ids = HashSet(preferences.getStringSet(KEY_PROCESSED_EVENTS, emptySet()).orEmpty())
        ids.add(eventId)
        edit { putStringSet(KEY_PROCESSED_EVENTS, ids) }
    }

    fun getPosition(kind: BubblePositionKind): BubblePosition? {
        val x = preferences.getInt(kind.key("x"), Int.MIN_VALUE)
        val y = preferences.getInt(kind.key("y"), Int.MIN_VALUE)
        val width = preferences.getInt(kind.key("width"), Int.MIN_VALUE)
        val height = preferences.getInt(kind.key("height"), Int.MIN_VALUE)
        if (x == Int.MIN_VALUE || y == Int.MIN_VALUE || width <= 0 || height <= 0) {
            return null
        }
        return BubblePosition(x, y, width, height)
    }

    fun savePosition(kind: BubblePositionKind, position: BubblePosition) = edit {
        putInt(kind.key("x"), position.x)
        putInt(kind.key("y"), position.y)
        putInt(kind.key("width"), position.width)
        putInt(kind.key("height"), position.height)
    }

    private fun setCounts(counts: BubbleCounts) = edit {
        putInt(BubblePlatform.INSTAGRAM.key, counts.instagram)
        putInt(BubblePlatform.YOUTUBE.key, counts.youtube)
        putInt(BubblePlatform.FACEBOOK.key, counts.facebook)
        putInt(BubblePlatform.TIKTOK.key, counts.tiktok)
        putInt(BubblePlatform.SNAPCHAT.key, counts.snapchat)
        putInt(KEY_TOTAL, counts.total)
        putString(KEY_LAST_DATE, counts.date.ifBlank { lastCounterDate })
    }

    @Synchronized
    private fun ensureToday() {
        val today = todayKey()
        if (cachedDate == today && preferences.getString(KEY_LAST_DATE, null) == today) {
            return
        }
        if (preferences.getString(KEY_LAST_DATE, null) != today) {
            edit {
                putInt(BubblePlatform.INSTAGRAM.key, 0)
                putInt(BubblePlatform.YOUTUBE.key, 0)
                putInt(BubblePlatform.FACEBOOK.key, 0)
                putInt(BubblePlatform.TIKTOK.key, 0)
                putInt(BubblePlatform.SNAPCHAT.key, 0)
                putInt(KEY_TOTAL, 0)
                putString(KEY_LAST_DATE, today)
                remove(KEY_PROCESSED_EVENTS)
            }
        }
        cachedDate = today
    }

    private fun edit(block: SharedPreferences.Editor.() -> Unit) {
        try {
            preferences.edit().apply(block).apply()
        } catch (error: RuntimeException) {
            throw BubbleStorageException("Unable to persist bubble preferences", error)
        }
    }

    private fun todayKey(): String = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    private companion object {
        const val PREFS_NAME = "reelcounter_bubble"
        const val KEY_TOTAL = "counter_total"
        const val KEY_LAST_DATE = "last_counter_date"
        const val KEY_ACTIVE = "bubble_active"
        const val KEY_EXPANDED = "bubble_expanded"
        const val KEY_SELECTED_PLATFORM = "selected_platform"
        const val KEY_PROCESSED_EVENTS = "processed_event_ids"
    }
}
