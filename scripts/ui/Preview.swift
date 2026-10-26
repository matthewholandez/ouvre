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
                    if CommandLine.arguments.contains("--settings-only") {
                        try await settingsChecks()
                        NSApp.terminate(nil)
                        return
                    }
                    if !CommandLine.arguments.contains("--interactions-only") { try await captureAll(output: URL(fileURLWithPath: output)) }
                    try await interactionChecks()
                    try await numberShortcutChecks(output: URL(fileURLWithPath: output))
                    try await orderChecks(output: URL(fileURLWithPath: output))
                    try await settingsChecks()
                    try await editorChecks()
                    try await fallbackAndDeleteChecks()
                    try await editorKeyboardCheck()
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


    @MainActor static func sendKey(_ code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = [], repeatKey: Bool = false, to window: NSWindow) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                    context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                    isARepeat: repeatKey, keyCode: code)!
        NSApp.sendEvent(event)
    }

    @MainActor static func numberShortcutChecks(output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for scenario in ["bare", "command", "filtered", "digit-search", "hidden", "ninth", "tenth", "out-of-range", "busy", "repeat", "no-match", "option", "control", "shift", "command-shift", "function"] {
            let model = fixture()
            if ["ninth", "tenth"].contains(scenario) {
                model.browsers = (0..<12).map { Browser(bundleID: "fixture.\($0)", name: "Browser \($0)", appURL: URL(fileURLWithPath: "/Applications/Safari.app"), profiles: []) }
            }
            if scenario == "digit-search" {
                model.browsers = [Browser(bundleID: "fixture.numeric", name: "Browser 2", appURL: URL(fileURLWithPath: "/Applications/Safari.app"), profiles: [])]
            }
            if scenario == "hidden" { model.configuration.hiddenDestinationIDs.insert(model.visibleDestinations[0].id) }
            if scenario == "busy" { model.isLaunching = true }
            let expected = model.visibleDestinations
            let view = NSHostingView(rootView: PickerView(model: model))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 450), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            try await Task.sleep(nanoseconds: 300_000_000)
            guard let field = window.firstResponder as? NSTextView else { fatalError("No picker search focus") }
            if ["filtered", "digit-search", "no-match"].contains(scenario) {
                field.insertText(scenario == "filtered" ? "Work" : scenario == "digit-search" ? "Browser " : "missing", replacementRange: NSRange(location: NSNotFound, length: 0))
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            if scenario == "bare" || scenario == "filtered" {
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("numbered-\(scenario).png"))
            }
            switch scenario {
            case "bare", "hidden", "digit-search": sendKey(19, characters: "2", to: window)
            case "command": sendKey(19, characters: "2", modifiers: .command, to: window)
            case "filtered", "no-match": sendKey(18, characters: "1", modifiers: .command, to: window)
            case "ninth", "out-of-range": sendKey(25, characters: "9", to: window)
            case "tenth":
                for _ in 0..<9 { sendKey(125, characters: "\u{F701}", to: window) }
                sendKey(36, characters: "\r", to: window)
            case "busy": sendKey(18, characters: "1", to: window); sendKey(18, characters: "1", modifiers: .command, to: window)
            case "repeat": sendKey(18, characters: "1", repeatKey: true, to: window)
            default:
                let flags: NSEvent.ModifierFlags = scenario == "option" ? .option : scenario == "control" ? .control : scenario == "shift" ? .shift : scenario == "function" ? .function : [.command, .shift]
                sendKey(18, characters: "1", modifiers: flags, to: window)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            switch scenario {
            case "bare", "command", "hidden": precondition(model.previewLastChoice == expected[1], scenario)
            case "filtered": precondition(model.previewLastChoice?.profileDirectory == "Profile 1", scenario)
            case "ninth": precondition(model.previewLastChoice == expected[8], scenario)
            case "tenth": precondition(model.previewLastChoice == expected[9], scenario)
            case "digit-search":
                precondition(model.previewLastChoice == nil && field.string == "Browser 2", "Digit should be search text")
                sendKey(36, characters: "\r", to: window)
                try await Task.sleep(nanoseconds: 100_000_000)
                precondition(model.previewLastChoice == expected[0], scenario)
            default:
                precondition(model.previewLastChoice == nil && model.currentURL != nil, scenario)
                if ["out-of-range", "busy", "repeat"].contains(scenario) { precondition(field.string.isEmpty, "Unavailable shortcut changed search") }
            }
            print("PASS number shortcut: \(scenario)")
            window.close()
        }
    }

    @MainActor static func interactionChecks() async throws {
        NSApp.appearance = NSAppearance(named: .aqua)
        for scenario in ["arrows", "search", "mouse", "long-list", "escape", "busy", "no-match"] {
            let model = fixture()
            if scenario == "long-list" {
                model.browsers = (0..<16).map { index in
                    Browser(bundleID: "fixture.browser.\(index)", name: "Browser \(index)",
                            appURL: URL(fileURLWithPath: "/Applications/Safari.app"), profiles: [])
                }
            }
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
            if scenario == "long-list" {
                for _ in 0..<12 { sendKey(125, characters: "\u{F701}", to: window) }
            }
            if scenario == "mouse" {
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: 160, y: 450 - 216),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                        clickCount: 1, pressure: 1)!)
                }
            }
            if scenario == "escape" { sendKey(53, characters: "\u{1b}", to: window) }
            else if scenario != "mouse" { sendKey(36, characters: "\r", to: window) }
            try await Task.sleep(nanoseconds: 100_000_000)
            switch scenario {
            case "arrows", "search", "mouse":
                precondition(model.previewLastChoice?.profileDirectory == "Profile 1", "Wrong keyboard-selected destination in \(scenario)")
            case "long-list":
                precondition(model.previewLastChoice?.bundleID == "fixture.browser.12", "Long picker list selected wrong destination")
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
        try await click(740, 281)
        precondition(!model.configuration.showInMenuBar, "Menu bar toggle did not hide")
        try await click(740, 281)
        precondition(model.configuration.showInMenuBar, "Menu bar toggle did not restore")
        try await click(90, 134)
        try await click(740, 188)
        precondition(model.configuration.hiddenDestinationIDs.contains(model.browsers[0].destinations[1].id), "Profile visibility")
        try await click(90, 174)
        try await click(229, 159)
        precondition(!model.configuration.rules[0].isEnabled, "Rule enable")
        try await click(730, 164)
        precondition(model.configuration.rules[1].value == "figma.com", "Rule reorder")
        model.configurationReadOnly = true
        model.setShowInMenuBar(false)
        precondition(model.configuration.showInMenuBar, "Read-only configuration hid the menu bar item")
        print("PASS settings: routing and menu bar toggles, read-only guard, profile visibility, rule enable, reorder, sidebar navigation")
        window.close()
    }

    @MainActor static func orderChecks(output: URL) async throws {
        let model = fixture()
        let settings = NSHostingView(rootView: SettingsView(model: model, page: .browsers))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = settings
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        func click(_ x: CGFloat, _ y: CGFloat) async throws {
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 620 - y),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await click(681, 191) // Work profile's up arrow.
        precondition(model.orderedDestinations(for: model.browsers[0]).first?.profileName == "Work", "Profile up control")
        try await click(751, 126) // Helium browser's down arrow.
        precondition(model.orderedBrowsers.first?.name == "Google Chrome", "Browser down control")
        precondition(model.visibleDestinations.map(\.profileName) == [nil, "Work", "Personal", nil], "Picker order")
        func capture(_ view: NSView, as name: String) throws {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("No bitmap") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
        }
        try capture(settings, as: "ordered-settings.png")
        window.close()

        let picker = NSHostingView(rootView: PickerView(model: model))
        let pickerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 470, height: 450),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        pickerWindow.isReleasedWhenClosed = false
        pickerWindow.contentView = picker
        pickerWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        try capture(picker, as: "ordered-picker.png")
        sendKey(19, characters: "2", to: pickerWindow)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.previewLastChoice?.profileName == "Work", "Second shortcut after reordering")
        print("PASS order: native browser/profile arrows and reordered picker shortcut")
        pickerWindow.close()

        let restored = fixture()
        restored.configuration = model.configuration
        restored.configuration.hiddenDestinationIDs.insert(restored.allDestinations[0].id)
        precondition(restored.visibleDestinations.map(\.profileName) == ["Work", "Personal", nil], "Hidden destination order")
        restored.browsers.removeAll { $0.bundleID == "com.google.Chrome" }
        precondition(restored.visibleDestinations.first?.profileName == "Work", "Missing browser order")
        restored.browsers.append(Browser(bundleID: "fixture.new", name: "New browser",
                                         appURL: URL(fileURLWithPath: "/Applications/Safari.app"), profiles: []))
        precondition(restored.orderedBrowsers.last?.bundleID == "fixture.new", "New browser append")
        print("PASS order: restored settings, hidden/missing destinations, new browser append")

        let before = model.configuration.browserOrder
        model.configurationReadOnly = true
        model.moveBrowser("com.apple.Safari", by: -1)
        precondition(model.configuration.browserOrder == before, "Read-only order mutation")
        print("PASS order: read-only guard")
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

    @MainActor static func fallbackAndDeleteChecks() async throws {
        let model = fixture()
        let view = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        func click(_ x: CGFloat, _ y: CGFloat) async throws {
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 620 - y),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await click(300, 369)
        sendKey(125, characters: "\u{F701}", to: window)
        sendKey(36, characters: "\r", to: window)
        try await Task.sleep(nanoseconds: 250_000_000)
        precondition(model.configuration.fallback != nil, "Fallback picker did not select a destination")
        print("PASS settings: fallback picker selected \(model.configuration.fallback!.id)")

        try await click(90, 174)
        try await click(752, 158)
        let originalCount = model.configuration.rules.count
        precondition(window.sheets.count == 1, "Delete confirmation did not appear")
        func buttons(_ view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) }
        }
        guard let cancel = buttons(window.sheets[0].contentView!).first(where: { $0.title == "Cancel" }) else {
            fatalError("Delete confirmation cancel button missing")
        }
        cancel.performClick(nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(model.configuration.rules.count == originalCount, "Cancelling deleted a rule")
        try await click(752, 158)
        precondition(window.sheets.count == 1, "Delete confirmation did not reopen")
        guard let delete = buttons(window.sheets[0].contentView!).first(where: { $0.title == "Delete rule" }) else {
            fatalError("Delete confirmation button missing")
        }
        delete.performClick(nil)
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(model.configuration.rules.count == originalCount - 1, "Delete confirmation did not remove rule")
        print("PASS settings: destructive rule deletion requires confirmation")
        window.close()
    }

    @MainActor static func editorKeyboardCheck() async throws {
        let model = fixture()
        let originalCount = model.configuration.rules.count
        let view = NSHostingView(rootView: SettingsView(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 620),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        for point in [NSPoint(x: 90, y: 620 - 174), NSPoint(x: 730, y: 620 - 48)] {
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let sheet = window.sheets.first, let sheetView = sheet.contentView else { fatalError("Rule editor sheet missing") }
        func fields(_ view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) }
        }
        guard let field = fields(sheetView).first(where: { $0.isEditable }) else { fatalError("No rule value field") }
        sheet.makeFirstResponder(field)
        guard let editor = sheet.firstResponder as? NSTextView else { fatalError("No rule text editor") }
        editor.insertText("not a domain", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 100_000_000)
        func pressReturn() {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: sheet.windowNumber,
                context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
            NSApp.sendEvent(event)
        }
        pressReturn()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.configuration.rules.count == originalCount && !window.sheets.isEmpty,
                     "Invalid Return should keep the editor open")
        editor.selectAll(nil)
        editor.insertText("example.org", replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(nanoseconds: 100_000_000)
        pressReturn()
        pressReturn()
        try await Task.sleep(nanoseconds: 200_000_000)
        precondition(model.configuration.rules.count == originalCount + 1, "Return failed to save exactly one valid rule")
        print("PASS editor: invalid Return stays open; valid Return saves once")
        window.close()
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
