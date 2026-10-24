import AppKit
import Foundation

struct Browser: Identifiable {
    let bundleID: String
    let name: String
    let appURL: URL
    let profiles: [ProfileDescriptor]
    var profileStatus: ProfileScanStatus = .unsupported
    var id: String { bundleID }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path) }
    var destinations: [Destination] {
        if profiles.isEmpty { return [Destination(bundleID: bundleID, browserName: name)] }
        return profiles.map { Destination(bundleID: bundleID, browserName: name, profileDirectory: $0.directory, profileName: $0.name) }
    }
}

enum ProfileScanStatus {
    case unsupported
    case ready
    case accessRequired(String)
    case unavailable(String)

    var message: String? {
        switch self {
        case .unsupported, .ready: nil
        case .accessRequired(let text), .unavailable(let text): text
        }
    }
    var canChooseFolder: Bool {
        if case .accessRequired = self { return true }
        return false
    }
}

struct ProfileScan {
    let profiles: [ProfileDescriptor]
    let status: ProfileScanStatus
}

enum BrowserCatalog {
    static let chromium = BrowserSupport.profileDataPaths
    static let supportedBrowserIDs = BrowserSupport.knownBrowserIDs

    static func discover() -> [Browser] {
        let workspace = NSWorkspace.shared
        let sample = URL(string: "https://example.com")!
        var urls = workspace.urlsForApplications(toOpen: sample)
        for bundleID in supportedBrowserIDs.sorted() {
            if let url = workspace.urlForApplication(withBundleIdentifier: bundleID) { urls.append(url) }
        }
        var found: [String: Browser] = [:]
        for appURL in urls {
            guard let bundle = Bundle(url: appURL), let id = bundle.bundleIdentifier,
                  isBrowserLike(bundle: bundle, bundleID: id),
                  id != Bundle.main.bundleIdentifier,
                  !id.lowercased().contains("browserosaurus"),
                  !id.lowercased().contains("velja"),
                  !id.lowercased().contains("choosy"),
                  !id.lowercased().contains("openin"),
                  !id.lowercased().contains("finicky") else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? appURL.deletingPathExtension().lastPathComponent
            let scan = chromium[id].map { discoverProfiles(relativePath: $0, bundleID: id) }
                ?? ProfileScan(profiles: [], status: .unsupported)
            VerificationHooks.recordScan("catalog \(id) profiles=\(scan.profiles.count)")
            found[id] = Browser(bundleID: id, name: name, appURL: appURL,
                                profiles: scan.profiles, profileStatus: scan.status)
        }
        return found.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func isBrowserLike(bundle: Bundle, bundleID: String) -> Bool {
        if supportedBrowserIDs.contains(bundleID) { return true }
        guard let types = bundle.object(forInfoDictionaryKey: "CFBundleDocumentTypes") as? [[String: Any]] else { return false }
        return types.contains { type in
            let extensions = type["CFBundleTypeExtensions"] as? [String] ?? []
            let contentTypes = type["LSItemContentTypes"] as? [String] ?? []
            return extensions.contains(where: { ["html", "htm", "xhtml"].contains($0.lowercased()) }) ||
                contentTypes.contains(where: { ["public.html", "public.xhtml"].contains($0.lowercased()) })
        }
    }

    static func profileRoot(relativePath: String) -> URL {
        if relativePath == "Google/Chrome", VerificationHooks.isEnabled, let root = VerificationHooks.chromeRoot {
            return root
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(relativePath, isDirectory: true)
    }

    static func discoverProfiles(relativePath: String, bundleID: String) -> ProfileScan {
        let root = profileRoot(relativePath: relativePath)
        if !VerificationHooks.isEnabled, ProfileAccessStore.bookmarkNeedsRefresh(for: bundleID, expectedRoot: root) {
            return ProfileScan(profiles: [], status: .accessRequired("Saved access to \(nameFor(bundleID)) profiles expired. Choose its profile folder again."))
        }
        return ProfileAccessStore.withRoot(bundleID: bundleID, defaultRoot: root) { selectedRoot in
            let localState = selectedRoot.appendingPathComponent("Local State")
            let data: Data
            do { data = try Data(contentsOf: localState) }
            catch {
                let nsError = error as NSError
                VerificationHooks.recordScan("scan \(relativePath) root=\(selectedRoot.path) error=\(nsError.domain)/\(nsError.code)")
                let denied = (nsError.domain == NSCocoaErrorDomain && nsError.code == 257) ||
                    (nsError.domain == NSPOSIXErrorDomain && [1, 13].contains(nsError.code))
                let status: ProfileScanStatus = denied
                    ? .accessRequired("macOS denied access to \(nameFor(bundleID)). Choose its profile folder to show profiles.")
                    : .unavailable("Could not read \(nameFor(bundleID)) profile metadata: \(error.localizedDescription)")
                return ProfileScan(profiles: [], status: status)
            }
            let profiles = ProfileMetadata.parse(data, root: selectedRoot)
            VerificationHooks.recordScan("scan \(relativePath) root=\(selectedRoot.path) bytes=\(data.count) profiles=\(profiles.count)")
            let status: ProfileScanStatus = profiles.isEmpty
                ? .unavailable("No readable profiles were found in \(nameFor(bundleID)) metadata.") : .ready
            return ProfileScan(profiles: profiles, status: status)
        }
    }

    private static func nameFor(_ bundleID: String) -> String {
        switch bundleID {
        case "com.google.Chrome": "Chrome"
        case "net.imput.helium": "Helium"
        default: "the browser"
        }
    }
}

enum BrowserLauncher {
    enum LaunchError: LocalizedError {
        case missingBrowser
        case missingProfile
        case invalidProfile
        case missingExecutable
        case launchFailed(Int32)
        var errorDescription: String? {
            switch self {
            case .missingBrowser: "The selected browser is no longer installed. Choose another destination."
            case .missingProfile: "This browser profile is no longer available. Choose another destination."
            case .invalidProfile: "The selected browser profile is invalid. Choose another destination."
            case .missingExecutable: "The browser executable could not be found."
            case .launchFailed(let status): "The browser exited with status \(status). Choose another destination."
            }
        }
    }

    static func open(_ url: URL, in destination: Destination, browsers: [Browser]) async throws {
        guard let browser = browsers.first(where: { $0.bundleID == destination.bundleID }) else { throw LaunchError.missingBrowser }
        if let directory = destination.profileDirectory {
            guard let relativePath = BrowserCatalog.chromium[destination.bundleID],
                  ProfileMetadata.isSafeDirectory(directory) else { throw LaunchError.invalidProfile }
            guard browser.profiles.contains(where: { $0.directory == directory }) else { throw LaunchError.missingProfile }
            let process = try ProfileAccessStore.withRoot(bundleID: destination.bundleID,
                                                          defaultRoot: BrowserCatalog.profileRoot(relativePath: relativePath)) { root in
                try startProfileProcess(url, directory: directory, browser: browser, root: root,
                                        extraArguments: destination.bundleID == "com.google.Chrome" ? VerificationHooks.chromeArguments : [])
            }
            try await Task.sleep(nanoseconds: 250_000_000)
            if !process.isRunning, process.terminationStatus != 0 {
                throw LaunchError.launchFailed(process.terminationStatus)
            }
        } else {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.allowsRunningApplicationSubstitution = false
            try await NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: configuration)
        }
    }

    @discardableResult
    static func startProfileProcess(_ url: URL, directory: String, browser: Browser,
                                    root: URL, extraArguments: [String] = []) throws -> Process {
        guard ProfileMetadata.isSafeDirectory(directory) else { throw LaunchError.invalidProfile }
        guard ProfileMetadata.directoryExists(directory, root: root) else { throw LaunchError.missingProfile }
        let executableName = (Bundle(url: browser.appURL)?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String) ?? ""
        let executable = browser.appURL.appendingPathComponent("Contents/MacOS", isDirectory: true).appendingPathComponent(executableName)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw LaunchError.missingExecutable }
        let process = Process()
        process.executableURL = executable
        process.arguments = extraArguments + ["--profile-directory=\(directory)", url.absoluteString]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
