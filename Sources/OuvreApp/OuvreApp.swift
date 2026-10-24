import AppKit
import Combine
import SwiftUI

@main struct OuvreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var statusItem: NSStatusItem?
    private var verificationTimer: Timer?
    private var pauseObservation: AnyCancellable?
    private let menuHeader = StatusMenuHeader()

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
        menu.delegate = self
        menu.autoenablesItems = false
        let heading = NSMenuItem()
        heading.view = menuHeader
        menu.addItem(heading)
        menu.addItem(.separator())
        addMenuItem("Pause routing", symbol: "pause.circle", action: #selector(togglePaused(_:)), to: menu)
        menu.addItem(.separator())
        addMenuItem("Try the picker…", symbol: "cursorarrow.click", action: #selector(testPicker), to: menu)
        addMenuItem("Refresh browsers", symbol: "arrow.clockwise", action: #selector(refreshBrowsers), to: menu)
        menu.addItem(.separator())
        addMenuItem("Settings…", symbol: "gearshape", action: #selector(openSettings), key: ",", to: menu)
        addMenuItem("Quit Ouvre", symbol: "power", action: #selector(quit), key: "q", to: menu)
        self.statusItem = item
        item.menu = menu
        pauseObservation = model.$isPaused.sink { [weak self] paused in
            self?.updateStatusButton(paused: paused)
        }
        updateMenu(menu)
        if VerificationHooks.isEnabled {
            verificationTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let command = VerificationHooks.takeCommand() else { return }
                    if command == "dismiss" { self.model.dismissPicker() }
                    else { self.runMenuVerificationCommand(command) }
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

    private func addMenuItem(_ title: String, symbol: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.image?.size = NSSize(width: 16, height: 16)
        menu.addItem(item)
    }

    private func updateStatusButton(paused: Bool) {
        let label = paused ? "Ouvre — routing paused" : "Ouvre"
        statusItem?.button?.image = NSImage(systemSymbolName: paused ? "pause.circle" : "arrow.up.right.square", accessibilityDescription: label)
        statusItem?.button?.toolTip = label
    }

    private func updateMenu(_ menu: NSMenu) {
        menuHeader.update(paused: model.isPaused, isDefault: model.isDefaultBrowser, destinationCount: model.visibleDestinations.count)
        if let item = menu.items.first(where: { $0.action == #selector(togglePaused(_:)) }) {
            item.title = model.isPaused ? "Resume routing" : "Pause routing"
            item.image = NSImage(systemSymbolName: model.isPaused ? "play.circle" : "pause.circle", accessibilityDescription: nil)
            item.image?.size = NSSize(width: 16, height: 16)
        }
        if let item = menu.items.first(where: { $0.action == #selector(testPicker) }) {
            item.title = model.currentURL == nil ? "Try the picker…" : "Show pending link…"
            item.toolTip = model.currentURL == nil ? "Preview the picker with an example.com link." : "Return to the link waiting for a browser."
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.refreshDefaultBrowserStatus()
        updateMenu(menu)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.currentURL != nil { model.showPicker() } else { model.showSettings() }
        return true
    }

    @objc private func openSettings() { model.showSettings() }
    @objc private func testPicker() {
        if model.currentURL != nil { model.showPicker() } else { model.testPicker() }
    }
    @objc private func refreshBrowsers() { model.refreshBrowsers() }
    @objc private func togglePaused(_ sender: NSMenuItem) {
        model.isPaused.toggle()
        if let menu = sender.menu { updateMenu(menu) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func runMenuVerificationCommand(_ command: String) {
        #if DEBUG
        guard command.hasPrefix("menu-"), let menu = statusItem?.menu else { return }
        menuWillOpen(menu)
        let action: Selector?
        switch command {
        case "menu-toggle-pause": action = #selector(togglePaused(_:))
        case "menu-picker": action = #selector(testPicker)
        case "menu-settings": action = #selector(openSettings)
        case "menu-refresh": action = #selector(refreshBrowsers)
        case "menu-state": action = nil
        default: return
        }
        if let action, let index = menu.items.firstIndex(where: { $0.action == action }) {
            menu.performActionForItem(at: index)
        }
        menuWillOpen(menu)
        let pauseTitle = menu.items.first(where: { $0.action == #selector(togglePaused(_:)) })?.title ?? "missing"
        let pickerTitle = menu.items.first(where: { $0.action == #selector(testPicker) })?.title ?? "missing"
        VerificationHooks.record("menu paused=\(model.isPaused) pause-title=\(pauseTitle) picker-title=\(pickerTitle) header=\(menuHeader.accessibilityLabel() ?? "") tooltip=\(statusItem?.button?.toolTip ?? "") settings-visible=\(model.settingsWindow?.isVisible == true) current-url=\(model.currentURL?.absoluteString ?? "none")")
        #endif
    }
}
