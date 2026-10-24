import AppKit
import Foundation

@main struct Launch {
    static func main() async throws {
        let app = URL(fileURLWithPath: CommandLine.arguments[1])
        let url = URL(string: CommandLine.arguments[2])!
        let browser = Browser(bundleID: "com.ouvre.Integration.URLLogger", name: "URL Logger", appURL: app, profiles: [])
        let destination = Destination(bundleID: browser.bundleID, browserName: browser.name)
        try await BrowserLauncher.open(url, in: destination, browsers: [browser])
    }
}
