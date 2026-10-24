import Foundation

@main struct Prepare {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let chromeRoot = root.appendingPathComponent("Chrome", isDirectory: true)
        try FileManager.default.createDirectory(at: chromeRoot.appendingPathComponent("Default", isDirectory: true), withIntermediateDirectories: true)
        let selection = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "default"
        let directory = selection == "missing" ? "Missing" : (selection == "second" ? "Profile 1" : "Default")
        if directory == "Profile 1" {
            try FileManager.default.createDirectory(at: chromeRoot.appendingPathComponent(directory), withIntermediateDirectories: true)
        }
        let metadata = #"{"profile":{"info_cache":{"Default":{"name":"Isolated Default"},"Profile 1":{"name":"Isolated Second"}}}}"#
        try Data(metadata.utf8).write(to: chromeRoot.appendingPathComponent("Local State"))
        let destination = Destination(bundleID: "com.google.Chrome", browserName: "Google Chrome", profileDirectory: directory,
                                      profileName: directory == "Default" ? "Isolated Default" : "Isolated Second")
        let config = Configuration(rules: [Rule(pattern: .domainAndSubdomains, value: "example.com", action: .destination(destination))])
        try ConfigurationStore(fileURL: root.appendingPathComponent("config.json")).save(config)
        print("root=\(root.path)")
        print("chromeRoot=\(chromeRoot.path)")
    }
}
