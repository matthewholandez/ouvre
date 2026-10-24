import AppKit
import Foundation

@main struct EarlyExit {
    static func main() async throws {
        let appURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = Destination(bundleID: "com.google.Chrome", browserName: "Failing Chrome",
                                      profileDirectory: "Default", profileName: "Disposable")
        let browser = Browser(bundleID: destination.bundleID, name: destination.browserName,
                              appURL: appURL, profiles: [ProfileDescriptor(directory: "Default", name: "Disposable")])
        do {
            try await BrowserLauncher.open(URL(string: "https://example.com/ouvre-early-exit")!,
                                           in: destination, browsers: [browser])
            fputs("Expected launch failure but got success\n", stderr)
            exit(1)
        } catch BrowserLauncher.LaunchError.launchFailed(let status) where status == 42 {
            print("Caught early browser exit status 42")
        }
    }
}
