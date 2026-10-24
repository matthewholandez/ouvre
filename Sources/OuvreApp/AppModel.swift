import AppKit
import Foundation
import SwiftUI

@MainActor final class AppModel: ObservableObject {
    @Published var configuration: Configuration
    @Published var browsers: [Browser] = []
    @Published var currentURL: URL?
    @Published var message: String?
    @Published var isPaused = false
    @Published var isDefaultBrowser = false
    @Published var isLaunching = false
    @Published var configurationReadOnly = false

    private(set) var previewLastChoice: Destination?
    let isPreview: Bool
    private let store: ConfigurationStore
    private var pendingURLs: [(url: URL, forcePicker: Bool)] = []
    private var currentToken = UUID()
    var pickerWindow: NSWindow?
    var settingsWindow: NSWindow?

    init(preview: Bool = false) {
        isPreview = preview
        store = (VerificationHooks.isEnabled ? VerificationHooks.configURL : nil)
            .map(ConfigurationStore.init(fileURL:)) ?? ConfigurationStore.applicationStore()
        if preview { configuration = Configuration(); return }
        do { configuration = try store.load() }
        catch {
            configuration = Configuration()
            message = error.localizedDescription
            configurationReadOnly = true
        }
        refreshBrowsers()
        refreshDefaultBrowserStatus()
        VerificationHooks.runBookmarkSmokeTest()
    }

    var visibleDestinations: [Destination] {
        allDestinations.filter { !configuration.hiddenDestinationIDs.contains($0.id) }
    }

    var allDestinations: [Destination] { browsers.flatMap(\.destinations) }

    func refreshBrowsers() {
        guard !isPreview else { return }
        browsers = BrowserCatalog.discover()
    }

    func copyCurrentURL() {
        guard !isPreview, let url = currentURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    func chooseProfileFolder(for browser: Browser) {
        guard !isPreview else { message = "Preview: the native folder chooser opens here."; return }
        guard let relativePath = BrowserSupport.profileDataPaths[browser.bundleID] else { return }
        let expected = BrowserCatalog.profileRoot(relativePath: relativePath)
        let panel = NSOpenPanel()
        panel.title = "Allow Ouvre to read \(browser.name) profiles"
        panel.message = "Choose the \(expected.lastPathComponent) folder. Ouvre reads profile names from Local State and does not change browser data."
        panel.prompt = "Use Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = expected.deletingLastPathComponent()
        panel.begin { [weak self] response in
            guard response == .OK, let selected = panel.url else { return }
            Task { @MainActor in
                do {
                    try ProfileAccessStore.saveSelection(selected, for: browser.bundleID, expectedRoot: expected)
                    self?.refreshBrowsers()
                    self?.message = nil
                } catch { self?.message = error.localizedDescription }
            }
        }
    }

    func save() {
        guard !isPreview else { return }
        guard !configurationReadOnly else {
            message = "Configuration could not be loaded. Fix or move the config file before changing settings."
            return
        }
        do { try store.save(configuration); message = nil }
        catch { message = error.localizedDescription }
    }

    func receive(_ url: URL) {
        enqueue(url, forcePicker: false)
    }

    private func enqueue(_ url: URL, forcePicker: Bool) {
        guard Routing.isWebURL(url) else { return }
        VerificationHooks.record("receive \(url.absoluteString)")
        pendingURLs.append((url, forcePicker))
        if currentURL == nil { processNext() }
    }

    func processNext() {
        guard currentURL == nil, !pendingURLs.isEmpty else { return }
        let request = pendingURLs.removeFirst()
        let url = request.url
        VerificationHooks.record("process \(url.absoluteString)")
        currentURL = url
        currentToken = UUID()
        refreshBrowsers()
        if isPreview { showPicker(); return }
        if !isPaused, !request.forcePicker, case .destination(let destination) = Routing.decision(for: url, configuration: configuration) {
            VerificationHooks.record("route \(destination.id) \(url.absoluteString)")
            isLaunching = true
            let token = currentToken
            Task {
                do {
                    try await BrowserLauncher.open(url, in: destination, browsers: browsers)
                    VerificationHooks.record("launched \(destination.id) \(url.absoluteString)")
                    if currentToken == token { finishCurrent() }
                } catch {
                    guard currentToken == token else { return }
                    isLaunching = false
                    message = error.localizedDescription
                    VerificationHooks.record("failure \(error.localizedDescription)")
                    showPicker()
                }
            }
        } else { VerificationHooks.record("picker \(url.absoluteString)"); showPicker() }
    }

    func choose(_ destination: Destination) {
        guard let url = currentURL, !isLaunching else { return }
        if isPreview { previewLastChoice = destination; dismissPicker(); return }
        isLaunching = true
        let token = currentToken
        Task {
            do {
                try await BrowserLauncher.open(url, in: destination, browsers: browsers)
                VerificationHooks.record("launched \(destination.id) \(url.absoluteString)")
                if currentToken == token { finishCurrent() }
            } catch {
                guard currentToken == token else { return }
                isLaunching = false
                message = error.localizedDescription
                VerificationHooks.record("failure \(error.localizedDescription)")
                showPicker()
            }
        }
    }

    func dismissPicker() {
        VerificationHooks.record("dismiss \(currentURL?.absoluteString ?? "")")
        currentToken = UUID()
        pickerWindow?.orderOut(nil)
        currentURL = nil
        message = nil
        isLaunching = false
        processNext()
    }

    private func finishCurrent() { dismissPicker() }

    func showPicker() {
        guard currentURL != nil else { return }
        if pickerWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 450),
                                  styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Open with Ouvre"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: PickerView(model: self))
            pickerWindow = window
        }
        pickerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "Ouvre Settings"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 500)
            window.center()
            window.contentView = NSHostingView(rootView: SettingsView(model: self))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func testPicker() {
        enqueue(URL(string: "https://example.com/ouvre-test?sample=1#preview")!, forcePicker: true)
    }

    func refreshDefaultBrowserStatus() {
        guard !isPreview else { return }
        let expected = Bundle.main.bundleIdentifier
        isDefaultBrowser = ["http", "https"].allSatisfy { scheme in
            let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "\(scheme)://example.com")!)
            return app.flatMap { Bundle(url: $0)?.bundleIdentifier } == expected
        }
    }

    func makeDefaultBrowser() {
        if isPreview { isDefaultBrowser = true; return }
        guard Bundle.main.bundleIdentifier != nil else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http") { [weak self] error in
            Task { @MainActor in
                if let error { self?.message = error.localizedDescription; return }
                NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https") { [weak self] error in
                    Task { @MainActor in
                        if let error { self?.message = error.localizedDescription }
                        self?.refreshDefaultBrowserStatus()
                    }
                }
            }
        }
    }
}
