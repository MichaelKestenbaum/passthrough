import XCTest
@testable import PassthroughCore

final class AppLinkTests: XCTestCase {
    func testEachLinkRoundTrips() {
        let id = UUID().uuidString
        let macID = "6C1F2B9A-mac id/with?odd&chars"
        for link in [AppLink.mac(nil), .mac(macID), .keepAwake, .vpnOn, .session(id, mac: nil), .session(id, mac: macID)] {
            XCTAssertEqual(AppLink(url: link.url), link, link.url.absoluteString)
        }
    }

    /// Links from builds before activities named their Mac still open, meaning the Mac selected now.
    func testOldLinksWithoutAMacStillWork() {
        let id = UUID().uuidString
        XCTAssertEqual(AppLink(url: URL(string: "passthrough://mac")!), .mac(nil))
        XCTAssertEqual(AppLink(url: URL(string: "passthrough://session/\(id)")!), .session(id, mac: nil))
        XCTAssertEqual(AppLink.mac(nil).url.absoluteString, "passthrough://mac")
        XCTAssertEqual(AppLink.session(id, mac: nil).url.absoluteString, "passthrough://session/\(id)")
    }

    func testMacIDIsCarried() {
        let id = UUID().uuidString
        XCTAssertEqual(AppLink(url: URL(string: "passthrough://mac?mac=m1")!), .mac("m1"))
        XCTAssertEqual(AppLink(url: URL(string: "passthrough://session/\(id)?mac=m2")!), .session(id, mac: "m2"))
        // Other query items are ignored.
        XCTAssertEqual(AppLink(url: URL(string: "passthrough://mac?x=1&mac=m1")!), .mac("m1"))
    }

    /// Nothing lowers protection from a link: there is no VPN-off or sleep link to forge.
    func testOnlyOurLinks() {
        let long = String(repeating: "a", count: 65)
        for text in ["passthrough://vpn-off", "passthrough://keep-awake-off", "https://mac", "other://mac",
                     "passthrough://session/not-a-uuid", "passthrough://session/", "passthrough://",
                     "passthrough://mac?mac=", "passthrough://mac?mac", "passthrough://mac?mac=\(long)"] {
            XCTAssertNil(AppLink(url: URL(string: text)!), text)
        }
    }
}
