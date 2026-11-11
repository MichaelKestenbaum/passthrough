package dev.dpatel.passthrough.ui.shell

import dev.dpatel.passthrough.core.ShellSessionInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MacProfilesTests {
    private fun info(id: String, running: Boolean = true, waiting: String? = null, title: String? = null) =
        ShellSessionInfo(id, title ?: id, startedAt = 0.0, lastOutputAt = 0.0, running = running, waiting = waiting)

    @Test fun tabMemoryRoundTripAndEmptyRemoves() {
        var memory = MacTabMemory()
        val tabs = MacTabs(openTabs = listOf("a", "b"), active = "b")
        memory = memory.save(tabs, "m1")
        assertEquals(tabs, memory.tabs("m1"))
        assertEquals(MacTabs(emptyList(), null), memory.tabs("nope"))
        val decoded = MacTabMemory.fromJson(memory.toJson())
        assertEquals(memory, decoded)
        memory = memory.save(MacTabs(emptyList(), null), "m1")
        assertNull(memory.byMac["m1"])
    }

    @Test fun tabMemoryKeepOnly() {
        var memory = MacTabMemory()
        memory = memory.save(MacTabs(listOf("a"), "a"), "m1")
        memory = memory.save(MacTabs(listOf("b"), null), "m2")
        memory = memory.keepOnly(setOf("m2"))
        assertEquals(setOf("m2"), memory.byMac.keys)
        memory = memory.forget("m2")
        assertTrue(memory.byMac.isEmpty())
    }

    @Test fun hiddenPrunedWhenNoLongerListed() {
        var hidden = ShellHiddenSessions()
        hidden = hidden.hide("s1", "m1")
        hidden = hidden.hide("s2", "m1")
        hidden = hidden.apply(listOf("s2", "s3"), "m1")
        assertEquals(setOf("s2"), hidden.byMac["m1"])
        assertEquals(listOf("s3"), hidden.visible(listOf(info("s2"), info("s3")), "m1").map { it.id })
        hidden = hidden.apply(emptyList(), "m1")
        assertNull(hidden.byMac["m1"])
        hidden = hidden.hide("s9", "m2")
        hidden = hidden.forget("m2")
        assertTrue(hidden.byMac.isEmpty())
    }

    @Test fun statusPrecedence() {
        val asking = info("a", waiting = "Edit?", title = "claude")
        val plain = info("b")
        val whenMillis = 100_000L
        assertEquals(
            MacStatus.Asking(title = "claude", question = "Edit?"),
            MacProfiles.status(listOf(plain, asking), reachable = true, lastHeardMillis = whenMillis, hasShell = true),
        )
        assertEquals(MacStatus.NoShell, MacProfiles.status(listOf(asking), reachable = true, lastHeardMillis = whenMillis, hasShell = false))
        assertEquals(
            MacStatus.Connected(shells = 1),
            MacProfiles.status(listOf(plain, info("c", running = false)), reachable = true, lastHeardMillis = null, hasShell = true),
        )
        assertEquals(MacStatus.Connected(shells = 0), MacProfiles.status(null, reachable = true, lastHeardMillis = null, hasShell = true))
        assertEquals(MacStatus.LastHeard(whenMillis), MacProfiles.status(null, reachable = false, lastHeardMillis = whenMillis, hasShell = true))
        assertEquals(MacStatus.Connecting, MacProfiles.status(null, reachable = false, lastHeardMillis = null, hasShell = true))
    }

    @Test fun statusText() {
        val now = 1_000_000_000_000L
        assertEquals("Connected", MacProfiles.statusText(MacStatus.Connected(0), now))
        assertEquals("Connected · 1 shell open", MacProfiles.statusText(MacStatus.Connected(1), now))
        assertEquals("Connected · 3 shells open", MacProfiles.statusText(MacStatus.Connected(3), now))
        assertEquals("claude is asking a question", MacProfiles.statusText(MacStatus.Asking("claude", "Edit?"), now))
        val fake = { then: Long, at: Long -> "fake(${at - then})" }
        assertEquals("Last heard fake(7200000)", MacProfiles.statusText(MacStatus.LastHeard(now - 7_200_000L), now, fake))
        assertEquals("Paired, no Remote shell", MacProfiles.statusText(MacStatus.NoShell, now))
        assertEquals("Connecting…", MacProfiles.statusText(MacStatus.Connecting, now))
    }

    @Test fun initial() {
        assertEquals("W", MacProfiles.initial("Work MacBook"))
        assertEquals("M", MacProfiles.initial("  mini"))
        assertEquals("?", MacProfiles.initial(""))
        assertEquals("?", MacProfiles.initial("   "))
    }

    @Test fun initialIsTheFirstGraphemeUppercased() {
        // Precomposed and decomposed é both give one cluster, uppercased.
        assertEquals("É", MacProfiles.initial("été mac"))
        assertEquals("É", MacProfiles.initial("étude"))
        // A ZWJ emoji sequence is one grapheme: the whole family/person glyph stays.
        assertEquals("👩‍💻", MacProfiles.initial("👩‍💻 Studio"))
    }

    /** Hard-coded: the Swift original asserts the same numbers. */
    @Test fun colorIndexVectors() {
        assertEquals(4, MacProfiles.colorIndex("mac-A", paletteCount = 6))
        assertEquals(5, MacProfiles.colorIndex("mac-B", paletteCount = 6))
        assertEquals(1, MacProfiles.colorIndex("0F3C9E2A-1111-4222-8333-444455556666", paletteCount = 6))
    }

    @Test fun reopen() {
        assertEquals("b", MacProfiles.reopen("b", listOf("a", "b")))
        assertEquals("a", MacProfiles.reopen("gone", listOf("a", "b")))
        assertEquals("a", MacProfiles.reopen(null, listOf("a", "b")))
        assertNull(MacProfiles.reopen("a", emptyList()))
    }

    @Test fun watched() {
        val candidates = listOf("c1", "c2", "c3", "c4", "c5", "c6")
        val recency = mapOf("c3" to 30.0, "c2" to 20.0, "c5" to 15.0, "c4" to 10.0)
        assertEquals(
            listOf("c6", "c3", "c2", "c5", "c4"),
            MacProfiles.watched(candidates, "c1", recency, pinned = setOf("c6")),
        )
        assertEquals(
            listOf("c6", "c3", "c2"),
            MacProfiles.watched(candidates, "c1", recency, pinned = setOf("c6"), limit = 2),
        )
        // Selected never appears, even pinned; ties keep candidate order.
        assertEquals(
            listOf("c1", "c2"),
            MacProfiles.watched(candidates, "c6", emptyMap(), pinned = setOf("c6"), limit = 2),
        )
    }

    @Test fun watchedIgnoresPinnedNotInCandidates() {
        assertEquals(
            listOf("c3", "c2"),
            MacProfiles.watched(listOf("c1", "c2", "c3"), "c1", mapOf("c3" to 2.0, "c2" to 1.0), pinned = setOf("gone")),
        )
    }
}
