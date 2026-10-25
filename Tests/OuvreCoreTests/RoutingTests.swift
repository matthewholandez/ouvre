import XCTest
@testable import OuvreCore

final class RoutingTests: XCTestCase {
    func testDomainBoundaryAndOrder() {
        let destination = Destination(bundleID: "com.apple.Safari", browserName: "Safari")
        let config = Configuration(rules: [
            Rule(pattern: .exactDomain, value: "example.com", action: .destination(destination)),
            Rule(pattern: .domainAndSubdomains, value: "example.com", action: .picker)
        ])
        XCTAssertEqual(Routing.decision(for: URL(string: "https://example.com/a")!, configuration: config), .destination(destination))
        XCTAssertEqual(Routing.decision(for: URL(string: "https://sub.example.com/a")!, configuration: config), .picker)
        XCTAssertFalse(Routing.matches(config.rules[1], url: URL(string: "https://example.com.evil.test")!))
        XCTAssertTrue(Routing.matches(config.rules[0], url: URL(string: "https://example.com./a")!))
        XCTAssertNotNil(Routing.validationError(pattern: .exactDomain, value: "example..com"))
        XCTAssertNotNil(Routing.validationError(pattern: .exactDomain, value: "bad@host"))
    }

    func testPrefixValidatesOrigin() {
        let rule = Rule(pattern: .urlPrefix, value: "https://example.com/portal", action: .picker)
        XCTAssertTrue(Routing.matches(rule, url: URL(string: "https://example.com/portal/docs")!))
        XCTAssertFalse(Routing.matches(rule, url: URL(string: "https://example.com.evil.test/portal")!))
        XCTAssertFalse(Routing.matches(rule, url: URL(string: "http://example.com/portal")!))
        XCTAssertFalse(Routing.matches(rule, url: URL(string: "https://example.com:8443/portal")!))
        XCTAssertTrue(Routing.matches(rule, url: URL(string: "https://example.com/portal?x=1#frag")!))
        XCTAssertNotNil(Routing.validationError(pattern: .urlPrefix, value: "https://example.com/#work"))
        XCTAssertFalse(Routing.matches(Rule(pattern: .urlPrefix, value: "https://example.com/#work", action: .picker), url: URL(string: "https://example.com/#personal")!))
        let queryRule = Rule(pattern: .urlPrefix, value: "https://example.com/foo?x=1", action: .picker)
        XCTAssertTrue(Routing.matches(queryRule, url: URL(string: "https://example.com/foo?x=12#frag")!))
        XCTAssertFalse(Routing.matches(queryRule, url: URL(string: "https://example.com/foobar?x=1")!))
        XCTAssertFalse(Routing.isWebURL(URL(string: "https://")!))
    }

    func testDisabledRuleAndFallback() {
        let destination = Destination(bundleID: "org.mozilla.firefox", browserName: "Firefox")
        let config = Configuration(rules: [Rule(isEnabled: false, pattern: .exactDomain, value: "example.com", action: .picker)], fallback: destination)
        XCTAssertEqual(Routing.decision(for: URL(string: "https://example.com")!, configuration: config), .destination(destination))
    }

    func testStoreRoundTripAndUnsupportedVersion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
        XCTAssertEqual(try store.load().rules.count, 0)
        let config = Configuration(rules: [Rule(pattern: .exactDomain, value: "example.com", action: .picker)])
        try store.save(config)
        XCTAssertEqual(try store.load().rules.first?.value, "example.com")
        try store.save(Configuration(version: 999))
        XCTAssertThrowsError(try store.load())
    }

    func testSavedOrderKeepsMissingIDsAndAppendsNewIDs() {
        let saved = ["browser.a", "browser.absent", "browser.b"]
        XCTAssertEqual(SavedOrder.applied(["browser.a", "browser.b", "browser.new"], saved: saved),
                       ["browser.a", "browser.b", "browser.new"])
        let moved = SavedOrder.moving("browser.b", by: -1,
                                      available: ["browser.a", "browser.b", "browser.new"], saved: saved)!
        XCTAssertEqual(moved, ["browser.b", "browser.absent", "browser.a", "browser.new"])
        XCTAssertEqual(SavedOrder.applied(["browser.a", "browser.absent", "browser.b", "browser.new"], saved: moved),
                       ["browser.b", "browser.absent", "browser.a", "browser.new"])
        XCTAssertNil(SavedOrder.moving("browser.b", by: -1, available: ["browser.b", "browser.a"], saved: moved))
    }

    func testOldConfigurationDecodesAndNewOrderPersists() throws {
        let old = Data(#"{"version":1,"rules":[],"hiddenDestinationIDs":[],"fallback":null}"#.utf8)
        var configuration = try JSONDecoder().decode(Configuration.self, from: old)
        XCTAssertTrue(configuration.browserOrder.isEmpty)
        XCTAssertTrue(configuration.destinationOrder.isEmpty)
        configuration.browserOrder = ["browser.b", "browser.a"]
        configuration.destinationOrder = ["browser.b": ["browser.b|Profile 1", "browser.b|Default"]]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(fileURL: directory.appendingPathComponent("config.json"))
        try store.save(configuration)
        let reloaded = try store.load()
        XCTAssertEqual(reloaded.browserOrder, configuration.browserOrder)
        XCTAssertEqual(reloaded.destinationOrder, configuration.destinationOrder)
        XCTAssertThrowsError(try JSONDecoder().decode(Configuration.self, from: Data(#"{"version":1,"hiddenDestinationIDs":[]}"#.utf8)))
    }
}
