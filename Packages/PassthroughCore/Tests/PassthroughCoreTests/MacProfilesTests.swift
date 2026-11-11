import XCTest
@testable import PassthroughCore

final class MacProfilesTests: XCTestCase {
    private func info(_ id: String, running: Bool = true, waiting: String? = nil, title: String? = nil) -> ShellSessionInfo {
        ShellSessionInfo(id: id, title: title ?? id, startedAt: 0, lastOutputAt: 0, running: running, waiting: waiting)
    }

    func testTabMemoryRoundTripAndEmptyRemoves() throws {
        var memory = MacTabMemory()
        let tabs = MacTabs(openTabs: ["a", "b"], active: "b")
        memory.save(tabs, for: "m1")
        XCTAssertEqual(memory.tabs(for: "m1"), tabs)
        XCTAssertEqual(memory.tabs(for: "nope"), MacTabs(openTabs: [], active: nil))
        let decoded = try JSONDecoder().decode(MacTabMemory.self, from: JSONEncoder().encode(memory))
        XCTAssertEqual(decoded, memory)
        memory.save(MacTabs(openTabs: [], active: nil), for: "m1")
        XCTAssertNil(memory.byMac["m1"])
    }

    func testTabMemoryKeepOnly() {
        var memory = MacTabMemory()
        memory.save(MacTabs(openTabs: ["a"], active: "a"), for: "m1")
        memory.save(MacTabs(openTabs: ["b"], active: nil), for: "m2")
        memory.keepOnly(["m2"])
        XCTAssertEqual(Set(memory.byMac.keys), ["m2"])
        memory.forget("m2")
        XCTAssertTrue(memory.byMac.isEmpty)
    }

    func testHiddenPrunedWhenNoLongerListed() {
        var hidden = ShellHiddenSessions()
        hidden.hide("s1", on: "m1")
        hidden.hide("s2", on: "m1")
        hidden.apply(listed: ["s2", "s3"], on: "m1")
        XCTAssertEqual(hidden.byMac["m1"], ["s2"])
        XCTAssertEqual(hidden.visible([info("s2"), info("s3")], on: "m1").map(\.id), ["s3"])
        hidden.apply(listed: [], on: "m1")
        XCTAssertNil(hidden.byMac["m1"])
        hidden.hide("s9", on: "m2")
        hidden.forget("m2")
        XCTAssertTrue(hidden.byMac.isEmpty)
    }

    func testStatusPrecedence() {
        let asking = info("a", waiting: "Edit?", title: "claude")
        let plain = info("b")
        let when = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(MacProfiles.status(sessions: [plain, asking], reachable: true, lastHeard: when, hasShell: true),
                       .asking(title: "claude", question: "Edit?"))
        XCTAssertEqual(MacProfiles.status(sessions: [asking], reachable: true, lastHeard: when, hasShell: false), .noShell)
        XCTAssertEqual(MacProfiles.status(sessions: [plain, info("c", running: false)], reachable: true, lastHeard: nil, hasShell: true),
                       .connected(shells: 1))
        XCTAssertEqual(MacProfiles.status(sessions: nil, reachable: true, lastHeard: nil, hasShell: true), .connected(shells: 0))
        XCTAssertEqual(MacProfiles.status(sessions: nil, reachable: false, lastHeard: when, hasShell: true), .lastHeard(when))
        XCTAssertEqual(MacProfiles.status(sessions: nil, reachable: false, lastHeard: nil, hasShell: true), .connecting)
    }

    func testStatusText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(MacProfiles.statusText(.connected(shells: 0), now: now), "Connected")
        XCTAssertEqual(MacProfiles.statusText(.connected(shells: 1), now: now), "Connected · 1 shell open")
        XCTAssertEqual(MacProfiles.statusText(.connected(shells: 3), now: now), "Connected · 3 shells open")
        XCTAssertEqual(MacProfiles.statusText(.asking(title: "claude", question: "Edit?"), now: now), "claude is asking a question")
        XCTAssertTrue(MacProfiles.statusText(.lastHeard(now.addingTimeInterval(-7200)), now: now).hasPrefix("Last heard "))
        XCTAssertEqual(MacProfiles.statusText(.noShell, now: now), "Paired, no Remote shell")
        XCTAssertEqual(MacProfiles.statusText(.connecting, now: now), "Connecting…")
    }

    func testInitial() {
        XCTAssertEqual(MacProfiles.initial("Work MacBook"), "W")
        XCTAssertEqual(MacProfiles.initial("  mini"), "M")
        XCTAssertEqual(MacProfiles.initial(""), "?")
        XCTAssertEqual(MacProfiles.initial("   "), "?")
    }

    /// Hard-coded: the Kotlin port asserts the same numbers.
    func testColorIndexVectors() {
        XCTAssertEqual(MacProfiles.colorIndex(macID: "mac-A", paletteCount: 6), 4)
        XCTAssertEqual(MacProfiles.colorIndex(macID: "mac-B", paletteCount: 6), 5)
        XCTAssertEqual(MacProfiles.colorIndex(macID: "0F3C9E2A-1111-4222-8333-444455556666", paletteCount: 6), 1)
    }

    func testReopen() {
        XCTAssertEqual(MacProfiles.reopen(lastUsed: "b", available: ["a", "b"]), "b")
        XCTAssertEqual(MacProfiles.reopen(lastUsed: "gone", available: ["a", "b"]), "a")
        XCTAssertEqual(MacProfiles.reopen(lastUsed: nil, available: ["a", "b"]), "a")
        XCTAssertNil(MacProfiles.reopen(lastUsed: "a", available: []))
    }

    func testWatched() {
        let candidates = ["c1", "c2", "c3", "c4", "c5", "c6"]
        let recency = ["c3": 30.0, "c2": 20.0, "c5": 15.0, "c4": 10.0]
        XCTAssertEqual(MacProfiles.watched(candidates: candidates, selected: "c1", recency: recency, pinned: ["c6"]),
                       ["c6", "c3", "c2", "c5", "c4"])
        XCTAssertEqual(MacProfiles.watched(candidates: candidates, selected: "c1", recency: recency, pinned: ["c6"], limit: 2),
                       ["c6", "c3", "c2"])
        // Selected never appears, even pinned; ties keep candidate order.
        XCTAssertEqual(MacProfiles.watched(candidates: candidates, selected: "c6", recency: [:], pinned: ["c6"], limit: 2),
                       ["c1", "c2"])
    }
}
