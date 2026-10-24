import Foundation

/// Persists only a read-only bookmark to a folder the user chose explicitly.
enum ProfileAccessStore {
    enum AccessError: LocalizedError {
        case wrongFolder(expected: String)
        case noProfiles

        var errorDescription: String? {
            switch self {
            case .wrongFolder(let expected): "Choose the browser profile folder named \(expected)."
            case .noProfiles: "That folder has no readable browser profiles."
            }
        }
    }

    static func withRoot<T>(bundleID: String, defaultRoot: URL, _ body: (URL) throws -> T) rethrows -> T {
        // The integration harness must never fall through to a saved real-browser bookmark.
        if VerificationHooks.isEnabled { return try body(defaultRoot) }
        guard let data = UserDefaults.standard.data(forKey: key(bundleID)) else {
            return try body(defaultRoot)
        }
        var isStale = false
        guard let selected = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale), !isStale,
              selected.standardizedFileURL.resolvingSymlinksInPath() == defaultRoot.standardizedFileURL.resolvingSymlinksInPath() else {
            return try body(defaultRoot)
        }
        let hasScope = selected.startAccessingSecurityScopedResource()
        defer { if hasScope { selected.stopAccessingSecurityScopedResource() } }
        return try body(selected)
    }

    static func bookmarkNeedsRefresh(for bundleID: String, expectedRoot: URL) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: key(bundleID)) else { return false }
        var isStale = false
        guard let selected = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale) else { return true }
        return isStale || selected.standardizedFileURL.resolvingSymlinksInPath() != expectedRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func saveSelection(_ selected: URL, for bundleID: String, expectedRoot: URL) throws {
        let actual = selected.standardizedFileURL.resolvingSymlinksInPath()
        let expected = expectedRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard actual == expected else { throw AccessError.wrongFolder(expected: expectedRoot.lastPathComponent) }
        let hasScope = selected.startAccessingSecurityScopedResource()
        defer { if hasScope { selected.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: selected.appendingPathComponent("Local State"))
        guard !ProfileMetadata.parse(data, root: selected).isEmpty else { throw AccessError.noProfiles }
        let bookmark = try selected.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                                 includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: key(bundleID))
    }

    private static func key(_ bundleID: String) -> String { "profileFolderBookmark.\(bundleID)" }
}
