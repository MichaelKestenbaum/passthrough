package dev.dpatel.passthrough.ui.shell

import dev.dpatel.passthrough.core.ShellSessionInfo
import dev.dpatel.passthrough.core.isAsking
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Plain-Kotlin port of Swift's MacProfiles.swift (PassthroughCore). Times are Unix millis here, not Date. */

/** A Mac's open shell tabs and which one was showing. */
@Serializable
data class MacTabs(val openTabs: List<String>, val active: String?)

/** The tabs each paired Mac had open, so switching Macs brings them back. */
@Serializable
data class MacTabMemory(val byMac: Map<String, MacTabs> = emptyMap()) {
    /** Remembers [tabs] for the Mac; nothing open and nothing active forgets it. */
    fun save(tabs: MacTabs, macID: String): MacTabMemory {
        val empty = tabs.openTabs.isEmpty() && tabs.active == null
        return copy(byMac = if (empty) byMac - macID else byMac + (macID to tabs))
    }

    fun tabs(macID: String): MacTabs = byMac[macID] ?: MacTabs(emptyList(), null)

    fun forget(macID: String): MacTabMemory = copy(byMac = byMac - macID)

    /** Drops Macs no longer paired. */
    fun keepOnly(macIDs: Set<String>): MacTabMemory = copy(byMac = byMac.filterKeys { it in macIDs })

    fun toJson(): String = Json.encodeToString(MacTabMemory.serializer(), this)

    companion object {
        fun fromJson(json: String): MacTabMemory = Json.decodeFromString(MacTabMemory.serializer(), json)
    }
}

/** Sessions the phone hid from a Mac's list, per Mac. */
@Serializable
data class ShellHiddenSessions(val byMac: Map<String, Set<String>> = emptyMap()) {
    fun hide(id: String, macID: String): ShellHiddenSessions =
        copy(byMac = byMac + (macID to (byMac[macID].orEmpty() + id)))

    /** Forgets hidden sessions the Mac no longer lists. */
    fun apply(listed: List<String>, macID: String): ShellHiddenSessions {
        val hidden = byMac[macID] ?: return this
        val kept = hidden.intersect(listed.toSet())
        return copy(byMac = if (kept.isEmpty()) byMac - macID else byMac + (macID to kept))
    }

    fun visible(sessions: List<ShellSessionInfo>, macID: String): List<ShellSessionInfo> {
        val hidden = byMac[macID].orEmpty()
        return sessions.filter { it.id !in hidden }
    }

    fun forget(macID: String): ShellHiddenSessions = copy(byMac = byMac - macID)
}

/** What a Mac's row in the switcher says about it. */
sealed interface MacStatus {
    /** Reachable; the number of running sessions. */
    data class Connected(val shells: Int) : MacStatus
    data class Asking(val title: String, val question: String) : MacStatus
    /** Last heard at [millis] (Unix millis). */
    data class LastHeard(val millis: Long) : MacStatus
    /** Paired for internet only. */
    object NoShell : MacStatus
    object Connecting : MacStatus
}

object MacProfiles {
    fun status(sessions: List<ShellSessionInfo>?, reachable: Boolean, lastHeardMillis: Long?, hasShell: Boolean): MacStatus {
        if (!hasShell) return MacStatus.NoShell
        val asking = sessions?.firstOrNull { it.isAsking }
        val question = asking?.waiting
        if (asking != null && question != null) return MacStatus.Asking(asking.title, question)
        if (reachable) return MacStatus.Connected(sessions?.count { it.running } ?: 0)
        if (lastHeardMillis != null) return MacStatus.LastHeard(lastHeardMillis)
        return MacStatus.Connecting
    }

    fun statusText(status: MacStatus, nowMillis: Long): String = when (status) {
        is MacStatus.Connected -> when (status.shells) {
            0 -> "Connected"
            1 -> "Connected · 1 shell open"
            else -> "Connected · ${status.shells} shells open"
        }
        is MacStatus.Asking -> "${status.title} is asking a question"
        is MacStatus.LastHeard -> "Last heard ${relative(status.millis, nowMillis)}"
        MacStatus.NoShell -> "Paired, no Remote shell"
        MacStatus.Connecting -> "Connecting…"
    }

    /**
     * English relative time, approximating RelativeDateTimeFormatter's named style
     * (Swift) without Android types. Future times read as "now".
     */
    private fun relative(then: Long, now: Long): String {
        val seconds = (now - then) / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        val days = hours / 24
        return when {
            seconds < 60 -> "now"
            minutes < 60 -> plural(minutes, "minute") + " ago"
            hours < 24 -> plural(hours, "hour") + " ago"
            days == 1L -> "yesterday"
            else -> plural(days, "day") + " ago"
        }
    }

    private fun plural(count: Long, unit: String): String = if (count == 1L) "1 $unit" else "$count ${unit}s"

    /** The avatar letter: the name's first letter, uppercased; "?" without one. */
    fun initial(macName: String): String {
        val trimmed = macName.trim()
        if (trimmed.isEmpty()) return "?"
        return String(Character.toChars(trimmed.codePointAt(0))).uppercase()
    }

    /**
     * A stable palette slot per Mac: FNV-1a (32-bit) over the ID's UTF-8, mod
     * [paletteCount]. The Swift app computes the same.
     */
    fun colorIndex(macID: String, paletteCount: Int): Int {
        var hash = 2_166_136_261L
        for (byte in macID.toByteArray(Charsets.UTF_8)) {
            hash = ((hash xor (byte.toLong() and 0xFFL)) * 16_777_619L) and 0xFFFF_FFFFL
        }
        return (hash % paletteCount).toInt()
    }

    /** The Mac to open on launch: the last used one if still paired, else the first. */
    fun reopen(lastUsed: String?, available: List<String>): String? =
        if (lastUsed != null && lastUsed in available) lastUsed else available.firstOrNull()

    /**
     * The Macs whose sessions to watch besides the selected one: every pinned
     * Mac, then up to [limit] of the rest, most recently used first (ties keep
     * candidate order). Pinned IDs count only when they are also in
     * [candidates]: those are the Macs with a usable shell credential, and a
     * Mac without one can't be dialed, so a stale pin is ignored.
     */
    fun watched(
        candidates: List<String>,
        selected: String?,
        recency: Map<String, Double>,
        pinned: Set<String>,
        limit: Int = 4,
    ): List<String> {
        val others = candidates.filter { it != selected }
        val pinnedFirst = others.filter { it in pinned }
        val rest = others.filter { it !in pinned }
            .sortedByDescending { recency[it] ?: 0.0 }
            .take(maxOf(limit, 0))
        return pinnedFirst + rest
    }
}
