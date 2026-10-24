import Foundation

public enum ConfigurationStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidData(Error)
    case writeFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Configuration version \(version) is newer than this Ouvre build supports."
        case .invalidData(let error): "Could not read configuration: \(error.localizedDescription)"
        case .writeFailed(let error): "Could not save configuration: \(error.localizedDescription)"
        }
    }
}

public struct ConfigurationStore {
    public let fileURL: URL

    public init(fileURL: URL) { self.fileURL = fileURL }

    public static func applicationStore() -> ConfigurationStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigurationStore(fileURL: support.appendingPathComponent("Ouvre/config.json"))
    }

    public func load() throws -> Configuration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return Configuration() }
        do {
            let config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: fileURL))
            guard config.version == Configuration.currentVersion else {
                throw ConfigurationStoreError.unsupportedVersion(config.version)
            }
            return config
        } catch let error as ConfigurationStoreError {
            throw error
        } catch {
            throw ConfigurationStoreError.invalidData(error)
        }
    }

    public func save(_ configuration: Configuration) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: fileURL, options: .atomic)
        } catch {
            throw ConfigurationStoreError.writeFailed(error)
        }
    }
}
