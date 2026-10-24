import XCTest
@testable import OuvreCore

final class ProfileMetadataTests: XCTestCase {
    func testMalformedAndMissingFieldsAreIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Default"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(ProfileMetadata.parse(Data("broken".utf8), root: root), [])
        XCTAssertEqual(ProfileMetadata.parse(Data("{}".utf8), root: root), [])
        let data = Data(#"{"profile":{"info_cache":{"Default":{"name":"Work"},"Profile 1":{},"../escape":{"name":"Bad"},"Missing":{"name":"Absent"}}}}"#.utf8)
        XCTAssertEqual(ProfileMetadata.parse(data, root: root), [ProfileDescriptor(directory: "Default", name: "Work")])
    }

    func testOnlyRealNonEphemeralDirectoriesAppear() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Default", "Profile 1", "Profile 2"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data().write(to: root.appendingPathComponent("File"))
        let data = Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 1":{"name":"Ephemeral","is_ephemeral":true},"Profile 2":{"name":"Hidden","is_omitted_from_profile_list":true},"File":{"name":"Not directory"}}}}"#.utf8)
        XCTAssertEqual(ProfileMetadata.parse(data, root: root), [ProfileDescriptor(directory: "Default", name: "Personal")])
        XCTAssertFalse(ProfileMetadata.isSafeDirectory("../../Private"))
        XCTAssertFalse(ProfileMetadata.isSafeDirectory("Profile/1"))
    }
}
