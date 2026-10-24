import AppKit
import SwiftUI

// Isolated fixtures: no configuration reads/writes, URL launches, or browser scans.
@MainActor func fixture() -> AppModel {
    let model = AppModel(preview: true)
    model.browsers = [
        Browser(bundleID: "net.imput.helium", name: "Helium", appURL: URL(fileURLWithPath: "/Applications/Helium.app"),
                profiles: [ProfileDescriptor(directory: "Default", name: "Personal"), ProfileDescriptor(directory: "Profile 1", name: "Work")], profileStatus: .ready),
        Browser(bundleID: "com.google.Chrome", name: "Google Chrome", appURL: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
                profiles: [], profileStatus: .accessRequired("macOS denied access to Chrome.")),
        Browser(bundleID: "com.apple.Safari", name: "Safari", appURL: URL(fileURLWithPath: "/Applications/Safari.app"), profiles: [])
    ]
    model.configuration.rules = [
        Rule(pattern: .domainAndSubdomains, value: "figma.com", action: .destination(model.browsers[0].destinations[1])),
        Rule(pattern: .exactDomain, value: "github.com", action: .destination(model.browsers[0].destinations[1])),
        Rule(isEnabled: false, pattern: .exactDomain, value: "youtube.com", action: .picker)
    ]
    model.currentURL = URL(string: "https://www.figma.com/design/example?node-id=12-34#canvas")!
    return model
}

@main struct UIReview {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/ouvre-ui-review"
        DispatchQueue.main.async {
            Task { @MainActor in
                do {
                    if !CommandLine.arguments.contains("--interactions-only") { try await captureAll(output: URL(fileURLWithPath: output)) }
                    try await interactionChecks()
                    try await settingsChecks()
                    try await editorChecks()
                    let errors = fixture()
                    errors.configurationMessage = "Configuration failure"
                    errors.profileAccessMessage = "Profile failure"
                    errors.defaultBrowserMessage = "Setup failure"
                    errors.message = "Link failure"
                    errors.dismissPicker()
                    precondition(errors.message == nil)
                    precondition(errors.configurationMessage != nil && errors.profileAccessMessage != nil && errors.defaultBrowserMessage != nil)
                    errors.makeDefaultBrowser()
                    precondition(errors.defaultBrowserMessage == nil && errors.profileAccessMessage != nil)
                    print("PASS errors: independent lifetimes and successful setup recovery")
                }
                catch { print("Snapshot failed: \(error)"); exit(1) }
                app.terminate(nil)
            }
        }
        app.run()
    }


    @MainActor static func sendKey(_ code: UInt16, characters: String, to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                    isARepeat: false, keyCode: code)!
        window.sendEvent(event)
    }

    @MainActor static func interactionChecks() async throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        for scenario in ["arrows", "search", "escape", "busy", "no-match"] {
            let model = fixture()
            if scenario == "busy" { model.isLaunching = true }
            let view = NSHostingView(rootView: PickerView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            if scenario == "search" || scenario == "no-match" {
                guard let field = window.firstResponder as? NSTextView else { fatalError("Picker search did not receive keyboard focus") }
                field.insertText(scenario == "search" ? "Work" : "no-matching-profile", replacementRange: NSRange(location: NSNotFound, length: 0))
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if scenario == "arrows" { sendKey(125, characters: "\u{F701}", to: window) }
            if scenario == "escape" { sendKey(53, characters: "\u{1b}", to: window) }
            else { sendKey(36, characters: "\r", to: window) }
            try await Task.sleep(nanoseconds: 100_000_000)
            switch scenario {
            case "arrows", "search":
                precondition(model.previewLastChoice?.profileDirectory == "Profile 1", "Wrong keyboard-selected destination in \(scenario)")
            case "escape": precondition(model.currentURL == nil, "Escape did not dismiss")
            default: precondition(model.currentURL != nil && model.previewLastChoice == nil, "Unexpected launch in \(scenario)")
            }
            print("PASS interaction: \(scenario)")
            window.close()
        }
    }

    @MainActor static func settingsChecks() async throws {
        let model = fixture()
        let view = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        func click(_ x: CGFloat, _ y: CGFloat) async throws {
            let location = NSPoint(x: x, y: 620 - y)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                window.sendEvent(event)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await click(740, 214)
        precondition(model.isPaused, "Routing toggle")
        try await click(90, 134)
        try await click(740, 188)
        precondition(model.configuration.hiddenDestinationIDs.contains(model.browsers[0].destinations[1].id), "Profile visibility")
        try await click(90, 174)
        try await click(229, 159)
        precondition(!model.configuration.rules[0].isEnabled, "Rule enable")
        try await click(730, 164)
        precondition(model.configuration.rules[1].value == "figma.com", "Rule reorder")
        print("PASS settings: routing toggle, profile visibility, rule enable, reorder, sidebar navigation")
        window.close()
    }

    @MainActor static func editorChecks() async throws {
        for editing in [false, true] {
            let model = fixture()
            let originalCount = model.configuration.rules.count
            let view = NSHostingView(rootView: RuleEditor(model: model, existing: editing ? model.configuration.rules[0] : nil))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            func fields(_ view: NSView) -> [NSTextField] {
                (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
            }
            guard let field = fields(view).first(where: { $0.isEditable }) else { fatalError("No editor field") }
            window.makeFirstResponder(field)
            guard let editor = window.firstResponder as? NSTextView else { fatalError("No text editor") }
            editor.selectAll(nil)
            editor.insertText("not a domain", replacementRange: NSRange(location: NSNotFound, length: 0))
            try await Task.sleep(nanoseconds: 100_000_000)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 350, y: 38), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            precondition(model.configuration.rules.count == originalCount && model.configuration.rules[0].value == "figma.com", "Invalid editor value saved")
            editor.selectAll(nil)
            editor.insertText("example.org", replacementRange: NSRange(location: NSNotFound, length: 0))
            try await Task.sleep(nanoseconds: 100_000_000)
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 350, y: 38), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            precondition(model.configuration.rules.count == originalCount + (editing ? 0 : 1), "Wrong rule count")
            precondition(model.configuration.rules[editing ? 0 : originalCount].value == "example.org", "Editor failed to save")
            print("PASS editor: \(editing ? "edit" : "add") and invalid input")
            window.close()
        }
    }

    @MainActor static func captureAll(output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for mode in ["light", "dark", "reduced", "contrast"] {
            NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : mode == "contrast" ? .accessibilityHighContrastAqua : .aqua)
            for screen in ["general", "browsers", "rules", "rules-empty", "editor", "picker", "picker-empty", "picker-error", "picker-busy", "read-only", "small-general", "small-rules", "browsers-empty", "editor-new", "general-link-error", "setup-error", "profile-error"] {
                let model = fixture()
                let size: NSSize
                let content: AnyView
                switch screen {
                case "editor", "editor-new":
                    size = NSSize(width: 472, height: 380)
                    content = AnyView(RuleEditor(model: model, existing: screen == "editor-new" ? nil : model.configuration.rules[0]))
                case "picker", "picker-empty", "picker-error", "picker-busy":
                    if screen == "picker-empty" { model.configuration.hiddenDestinationIDs = Set(model.allDestinations.map(\.id)) }
                    if screen == "picker-error" { model.message = "This browser profile is no longer available. Choose another destination." }
                    if screen == "picker-busy" { model.isLaunching = true }
                    size = NSSize(width: 470, height: 450)
                    content = AnyView(PickerView(model: model))
                default:
                    if screen == "general-link-error" { model.message = "The file couldn’t be opened."; model.isDefaultBrowser = true }
                    if screen == "setup-error" { model.defaultBrowserMessage = "macOS could not make Ouvre the handler for HTTP links. Try Set up again, or choose Ouvre in System Settings." }
                    if screen == "profile-error" { model.profileAccessMessage = "Could not access Google Chrome profiles. Choose the profile folder again." }
                    if screen == "browsers-empty" { model.browsers = [] }
                    if screen == "rules-empty" { model.configuration.rules = [] }
                    if screen == "read-only" { model.configurationReadOnly = true; model.configurationMessage = "Your saved settings could not be loaded. Your configuration has been preserved." }
                    let page: SettingsPage = (screen.hasPrefix("browsers") || screen == "profile-error") ? .browsers : screen.contains("rules") ? .rules : .general
                    size = screen.hasPrefix("small") ? NSSize(width: 700, height: 500) : NSSize(width: 800, height: 620)
                    content = AnyView(SettingsView(model: model, page: page))
                }
                let view = NSHostingView(rootView: content
                    .environment(\.colorScheme, mode == "dark" ? .dark : .light)
                    .environment(\.uiReviewAccessibility, UIReviewAccessibility(reduceTransparency: mode == "reduced", increaseContrast: mode == "contrast")))
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
                window.title = "Ouvre UI verification — \(screen)"
                window.isReleasedWhenClosed = false
                window.contentView = view
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(nanoseconds: 300_000_000)
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No PNG") }
                try data.write(to: output.appendingPathComponent("\(mode)-\(screen).png"))
                print("Captured \(mode)-\(screen) \(Int(view.bounds.width))×\(Int(view.bounds.height))")
                window.orderOut(nil)
                window.close()
            }
        }
    }
}
