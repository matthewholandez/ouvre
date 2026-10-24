import AppKit
import SwiftUI

@main struct OuvreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var verificationTimer: Timer?

    override init() {
        super.init()
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                       forEventClass: AEEventClass(kInternetEventClass),
                                                       andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: "Ouvre")
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Test picker…", action: #selector(testPicker), keyEquivalent: "")
        menu.addItem(withTitle: "Refresh browsers", action: #selector(refreshBrowsers), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause routing", action: #selector(togglePaused), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ouvre", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        self.statusItem = item
        item.menu = menu
        if VerificationHooks.isEnabled {
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    if VerificationHooks.takeCommand() == "dismiss" { self?.model.dismissPicker() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  !VerificationHooks.isEnabled,
                  !UserDefaults.standard.bool(forKey: "hasOpenedSettings"),
                  self.model.currentURL == nil else { return }
            UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
            self.model.showSettings()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { model.receive(url) }
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: string) else { return }
        model.receive(url)
    }

    @objc private func openSettings() { model.showSettings() }
    @objc private func testPicker() { model.testPicker() }
    @objc private func refreshBrowsers() { model.refreshBrowsers() }
    @objc private func togglePaused(_ sender: NSMenuItem) {
        model.isPaused.toggle()
        sender.title = model.isPaused ? "Resume routing" : "Pause routing"
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
