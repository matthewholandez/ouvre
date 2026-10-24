import Foundation

// Only Debug builds honor these explicit, isolated integration-test overrides.
enum VerificationHooks {
    #if DEBUG
    static var configURL: URL? { path("OUVRE_TEST_CONFIG") }
    static var chromeRoot: URL? { path("OUVRE_TEST_CHROME_ROOT") }
    static var traceURL: URL? { path("OUVRE_TEST_TRACE") }
    static var bookmarkTestRoot: URL? { path("OUVRE_TEST_BOOKMARK_ROOT") }
    static var commandURL: URL? { traceURL?.deletingLastPathComponent().appendingPathComponent("command.txt") }
    static var chromeArguments: [String] {
        guard isEnabled, let root = chromeRoot else { return [] }
        return ["--user-data-dir=\(root.path)", "--remote-debugging-port=0",
                "--no-first-run", "--no-default-browser-check"]
    }
    static var isEnabled: Bool { configURL != nil && chromeRoot != nil && traceURL != nil }

    private static func path(_ key: String) -> URL? {
        guard let value = ProcessInfo.processInfo.environment[key], value.hasPrefix("/"), !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value)
    }

    static func record(_ event: String) {
        guard isEnabled, let file = traceURL else { return }
        append(event, to: file)
    }
    static func recordScan(_ event: String) {
        guard let file = traceURL else { return }
        append(event, to: file)
    }
    static func runBookmarkSmokeTest() {
        guard let root = bookmarkTestRoot, traceURL != nil else { return }
        let bundleID = "com.example.ouvre.bookmark-smoke-test"
        defer { UserDefaults.standard.removeObject(forKey: "profileFolderBookmark.\(bundleID)") }
        do {
            try ProfileAccessStore.saveSelection(root, for: bundleID, expectedRoot: root)
            let count = try ProfileAccessStore.withRoot(bundleID: bundleID, defaultRoot: root) { selected in
                ProfileMetadata.parse(try Data(contentsOf: selected.appendingPathComponent("Local State")), root: selected).count
            }
            recordScan("bookmark-test profiles=\(count)")
        } catch { recordScan("bookmark-test error=\((error as NSError).domain)/\((error as NSError).code) \(error.localizedDescription)") }
    }
    private static func append(_ event: String, to file: URL) {
        let line = "\(Date().timeIntervalSince1970) \(event)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
    static func takeCommand() -> String? {
        guard isEnabled, let file = commandURL, let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #else
    static var configURL: URL? { nil }
    static var chromeRoot: URL? { nil }
    static var chromeArguments: [String] { [] }
    static var isEnabled: Bool { false }
    static func record(_ event: String) {}
    static func recordScan(_ event: String) {}
    static func runBookmarkSmokeTest() {}
    static func takeCommand() -> String? { nil }
    #endif
}
