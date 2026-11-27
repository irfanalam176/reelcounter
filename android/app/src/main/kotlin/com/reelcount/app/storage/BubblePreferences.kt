package com.reelcount.app.storage

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject
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

    var dailyTarget: Int
        get() = preferences.getInt(KEY_DAILY_TARGET, DEFAULT_DAILY_TARGET).coerceAtLeast(0)
        set(value) = edit { putInt(KEY_DAILY_TARGET, maxOf(0, value)) }

    var isAppTaskActive: Boolean
        get() = preferences.getBoolean(KEY_APP_TASK_ACTIVE, true)
        set(value) = edit { putBoolean(KEY_APP_TASK_ACTIVE, value) }

    var notificationPermissionRequested: Boolean
        get() = preferences.getBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, false)
        set(value) = edit { putBoolean(KEY_NOTIFICATION_PERMISSION_REQUESTED, value) }

    var dailyReminderEnabled: Boolean
        get() = preferences.getBoolean(KEY_DAILY_REMINDER_ENABLED, false)
        set(value) = edit { putBoolean(KEY_DAILY_REMINDER_ENABLED, value) }

    var dailyReminderHour: Int
        get() = preferences.getInt(KEY_DAILY_REMINDER_HOUR, DEFAULT_REMINDER_HOUR).coerceIn(0, 23)
        set(value) = edit { putInt(KEY_DAILY_REMINDER_HOUR, value.coerceIn(0, 23)) }

    var dailyReminderMinute: Int
        get() = preferences.getInt(KEY_DAILY_REMINDER_MINUTE, DEFAULT_REMINDER_MINUTE).coerceIn(0, 59)
        set(value) = edit { putInt(KEY_DAILY_REMINDER_MINUTE, value.coerceIn(0, 59)) }

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
        resetLimitMilestones()
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

    fun hasNotifiedLimitMilestone(percent: Int): Boolean {
        ensureToday()
        return preferences.getStringSet(KEY_LIMIT_MILESTONES_NOTIFIED, emptySet())
            .orEmpty()
            .contains("${cachedDate.orEmpty()}:$percent")
    }

    fun markLimitMilestoneNotified(percent: Int) {
        ensureToday()
        val values = HashSet(
            preferences.getStringSet(KEY_LIMIT_MILESTONES_NOTIFIED, emptySet()).orEmpty(),
        )
        values.add("${cachedDate.orEmpty()}:$percent")
        edit { putStringSet(KEY_LIMIT_MILESTONES_NOTIFIED, values) }
    }

    fun resetLimitMilestones() {
        edit { remove(KEY_LIMIT_MILESTONES_NOTIFIED) }
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
        val previousDate = preferences.getString(KEY_LAST_DATE, null)
        if (previousDate != today) {
            if (!previousDate.isNullOrBlank()) {
                archiveCounts(
                    BubbleCounts(
                        instagram = preferences.getInt(BubblePlatform.INSTAGRAM.key, 0),
                        youtube = preferences.getInt(BubblePlatform.YOUTUBE.key, 0),
                        facebook = preferences.getInt(BubblePlatform.FACEBOOK.key, 0),
                        tiktok = preferences.getInt(BubblePlatform.TIKTOK.key, 0),
                        snapchat = preferences.getInt(BubblePlatform.SNAPCHAT.key, 0),
                        date = previousDate,
                    ),
                )
            }
            edit {
                putInt(BubblePlatform.INSTAGRAM.key, 0)
                putInt(BubblePlatform.YOUTUBE.key, 0)
                putInt(BubblePlatform.FACEBOOK.key, 0)
                putInt(BubblePlatform.TIKTOK.key, 0)
                putInt(BubblePlatform.SNAPCHAT.key, 0)
                putInt(KEY_TOTAL, 0)
                putString(KEY_LAST_DATE, today)
                remove(KEY_PROCESSED_EVENTS)
                remove(KEY_LIMIT_MILESTONES_NOTIFIED)
            }
        }
        cachedDate = today
    }

    fun getDailyHistory(): List<Map<String, Any>> {
        ensureToday()
        val entries = readHistoryEntries()
        val live = getCounts().toMap().toMutableMap()
        entries[live["date"] as String] = live
        return entries.values
            .sortedBy { it["date"] as String }
            .takeLast(MAX_HISTORY_ENTRIES)
            .map { it.toMap() }
    }

    private fun readHistoryEntries(): MutableMap<String, MutableMap<String, Any>> {
        val entries = LinkedHashMap<String, MutableMap<String, Any>>()
        val stored = preferences.getString(KEY_DAILY_HISTORY, null)
        if (stored.isNullOrBlank()) {
            return entries
        }
        runCatching {
            val array = JSONArray(stored)
            for (index in 0 until array.length()) {
                val item = array.getJSONObject(index)
                val date = item.optString("date").takeIf { it.isNotBlank() } ?: continue
                entries[date] = mutableMapOf(
                    "date" to date,
                    "total" to item.optInt("total", 0),
                    BubblePlatform.INSTAGRAM.key to item.optInt(BubblePlatform.INSTAGRAM.key, 0),
                    BubblePlatform.YOUTUBE.key to item.optInt(BubblePlatform.YOUTUBE.key, 0),
                    BubblePlatform.FACEBOOK.key to item.optInt(BubblePlatform.FACEBOOK.key, 0),
                    BubblePlatform.TIKTOK.key to item.optInt(BubblePlatform.TIKTOK.key, 0),
                    BubblePlatform.SNAPCHAT.key to item.optInt(BubblePlatform.SNAPCHAT.key, 0),
                )
            }
        }
        return entries
    }

    private fun archiveCounts(counts: BubbleCounts) {
        if (counts.total <= 0) {
            return
        }
        val entries = readHistoryEntries()
        entries[counts.date] = counts.toMap().toMutableMap()
        val trimmed = entries.values
            .sortedBy { it["date"] as String }
            .takeLast(MAX_HISTORY_ENTRIES)
        val array = JSONArray()
        trimmed.forEach { array.put(JSONObject(it)) }
        edit { putString(KEY_DAILY_HISTORY, array.toString()) }
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
        const val KEY_DAILY_TARGET = "daily_target"
        const val DEFAULT_DAILY_TARGET = 50
        const val KEY_PROCESSED_EVENTS = "processed_event_ids"
        const val KEY_LIMIT_MILESTONES_NOTIFIED = "limit_milestones_notified"
        const val KEY_APP_TASK_ACTIVE = "app_task_active"
        const val KEY_NOTIFICATION_PERMISSION_REQUESTED = "notification_permission_requested"
        const val KEY_DAILY_REMINDER_ENABLED = "daily_reminder_enabled"
        const val KEY_DAILY_REMINDER_HOUR = "daily_reminder_hour"
        const val KEY_DAILY_REMINDER_MINUTE = "daily_reminder_minute"
        const val KEY_DAILY_HISTORY = "daily_history"
        const val DEFAULT_REMINDER_HOUR = 20
        const val DEFAULT_REMINDER_MINUTE = 0
        const val MAX_HISTORY_ENTRIES = 365
    }
}
