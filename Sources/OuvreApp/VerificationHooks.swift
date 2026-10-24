import Foundation

// Only Debug builds honor these explicit, isolated integration-test overrides.
enum VerificationHooks {
    #if DEBUG
    static var configURL: URL? { path("OUVRE_TEST_CONFIG") }
    static var chromeRoot: URL? { path("OUVRE_TEST_CHROME_ROOT") }
    static var traceURL: URL? { path("OUVRE_TEST_TRACE") }
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
    static func takeCommand() -> String? { nil }
    #endif
}
