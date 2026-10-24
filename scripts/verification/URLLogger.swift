import AppKit
import Foundation

final class Delegate: NSObject, NSApplicationDelegate {
    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(getURL(_:withReplyEvent:)),
                                                       forEventClass: AEEventClass(kInternetEventClass),
                                                       andEventID: AEEventID(kAEGetURL))
    }
    @objc func getURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else { return }
        log(text)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach { log($0.absoluteString) }
    }
    private func log(_ text: String) {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "VerificationLogPath") as? String else { return }
        let url = URL(fileURLWithPath: path)
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data((text + "\n").utf8))
    }
}

let delegate = Delegate()
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
