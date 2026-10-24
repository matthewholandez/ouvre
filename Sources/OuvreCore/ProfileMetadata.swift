import Foundation

public struct ProfileDescriptor: Equatable, Sendable {
    public let directory: String
    public let name: String
    public init(directory: String, name: String) { self.directory = directory; self.name = name }
}

public enum ProfileMetadata {
    public static func isSafeDirectory(_ directory: String) -> Bool {
        guard !directory.isEmpty, directory != ".", directory != ".." else { return false }
        return !directory.contains("/") && !directory.contains("\\") && !directory.contains("\0")
    }

    public static func directoryExists(_ directory: String, root: URL) -> Bool {
        guard isSafeDirectory(directory) else { return false }
        var isDirectory: ObjCBool = false
        let path = root.appendingPathComponent(directory).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    public static func parse(_ data: Data, root: URL) -> [ProfileDescriptor] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = object["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any] else { return [] }
        return cache.compactMap { directory, raw -> ProfileDescriptor? in
            guard directoryExists(directory, root: root),
                  let metadata = raw as? [String: Any],
                  metadata["is_ephemeral"] as? Bool != true,
                  metadata["is_omitted_from_profile_list"] as? Bool != true,
                  let name = metadata["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return ProfileDescriptor(directory: directory, name: name)
        }.sorted { left, right in
            if left.directory == "Default" { return true }
            if right.directory == "Default" { return false }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }
}
