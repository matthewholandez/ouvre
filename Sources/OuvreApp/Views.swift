import AppKit
import SwiftUI

// The snapshot harness can exercise accessibility fallbacks without changing macOS settings.
struct UIReviewAccessibility {
    let reduceTransparency: Bool
    let increaseContrast: Bool
}
private struct UIReviewAccessibilityKey: EnvironmentKey {
    static let defaultValue: UIReviewAccessibility? = nil
}
extension EnvironmentValues {
    var uiReviewAccessibility: UIReviewAccessibility? {
        get { self[UIReviewAccessibilityKey.self] }
        set { self[UIReviewAccessibilityKey.self] = newValue }
    }
}

// Native glass inherits macOS appearance preferences. Never read private defaults
// or imitate Liquid Glass with a fixed blur/tint.
struct NavigationSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.uiReviewAccessibility) private var review
    func body(content: Content) -> some View {
        if (review?.reduceTransparency ?? reduceTransparency) || (review?.increaseContrast ?? (contrast == .increased)) {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        } else {
            glass(content)
        }
    }
    @ViewBuilder private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        #endif
    }
}

struct BrowserIcon: View {
    let browser: Browser?
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let browser {
                Image(nsImage: browser.icon).resizable()
            } else {
                Image(systemName: "globe").resizable().scaledToFit().padding(4)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct Notice: View {
    let title: String
    let message: String
    var symbol = "exclamationmark.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(28)
    }
}

struct PickerView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    private var destinations: [Destination] {
        model.visibleDestinations.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Open link").font(.system(size: 20, weight: .semibold))
                    Text(model.currentURL?.host ?? "Choose a destination")
                        .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { model.copyCurrentURL() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless).help("Copy full link")
                    .accessibilityLabel("Copy full link").disabled(model.currentURL == nil)
                Button { model.dismissPicker() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).help("Dismiss link (Esc)")
                    .accessibilityLabel("Dismiss link")
            }.padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 16)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Color(nsColor: .secondaryLabelColor))
                TextField("Search browsers and profiles", text: $query).textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onChange(of: query) { _, _ in selection = 0 }
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                    .onKeyPress(.return) { chooseSelected(); return .handled }
                    .onKeyPress(characters: CharacterSet(charactersIn: "123456789"), phases: [.down, .repeat]) { press in
                        let modifiers = press.modifiers
                        guard modifiers == .command || (modifiers.isEmpty && query.isEmpty) else { return .ignored }
                        // Consume unavailable numbers too: an empty search stays empty.
                        if press.phase == .down, let number = Int(press.characters), !model.isLaunching,
                           destinations.indices.contains(number - 1) {
                            model.choose(destinations[number - 1])
                        }
                        return .handled
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(11).modifier(NavigationSurface()).padding(.horizontal, 16).padding(.bottom, 12)
            if let message = model.message {
                Notice(title: "Couldn’t open this link", message: message)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                            destinationRow(destination, index: index).id(destination.id)
                        }
                        if destinations.isEmpty {
                            EmptyState(symbol: "magnifyingglass", title: query.isEmpty ? "No destinations yet" : "No matches",
                                       detail: query.isEmpty ? "Show a browser or profile in Settings to open this link." : "Try another browser or profile name.")
                        }
                    }.padding(.horizontal, 12).padding(.vertical, 4)
                }.onChange(of: selection) { _, index in
                    guard destinations.indices.contains(index) else { return }
                    proxy.scrollTo(destinations[index].id)
                }
            }
            Divider().padding(.top, 8)
            HStack(spacing: 12) {
                if model.isLaunching {
                    ProgressView().controlSize(.small)
                    Text("Opening…").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(query.isEmpty ? "1–9 to open  ·  ↑↓ to select  ·  ↵ to open" : "⌘1–9 to open  ·  ↑↓ to select  ·  ↵ to open")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Settings…") { model.showSettings() }.buttonStyle(.link).font(.system(size: 11))
            }.padding(.horizontal, 20).padding(.vertical, 13)
        }
        .frame(minWidth: 430, minHeight: 330)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { searchFocused = true }
        .onChange(of: model.currentURL) { _, _ in query = ""; selection = 0; searchFocused = true }
        .onChange(of: destinations.map(\.id)) { _, _ in selection = min(selection, max(0, destinations.count - 1)) }
        .onExitCommand { model.dismissPicker() }
        .help(model.currentURL?.absoluteString ?? "Choose where to open your link")
    }
    private func destinationRow(_ destination: Destination, index: Int) -> some View {
        Button { model.choose(destination) } label: {
            HStack(spacing: 12) {
                BrowserIcon(browser: model.browsers.first { $0.bundleID == destination.bundleID }, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(destination.profileName ?? destination.browserName).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(destination.profileName == nil ? "Browser default" : destination.browserName)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if index < 9 {
                    Text("\(query.isEmpty ? "" : "⌘")\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                        .accessibilityLabel("Shortcut \(query.isEmpty ? "" : "Command ")\(index + 1)")
                }
                if index == selection {
                    Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .background(index == selection ? Color.accentColor.opacity(contrast == .increased ? 0.25 : 0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(index == selection ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1))
        }.buttonStyle(.plain).disabled(model.isLaunching)
            .accessibilityLabel("Open in \(destination.displayName)")
            .accessibilityAddTraits(index == selection ? [.isSelected] : [])
    }
    private func moveSelection(_ offset: Int) {
        guard !destinations.isEmpty else { return }
        selection = max(0, min(destinations.count - 1, selection + offset))
    }
    private func chooseSelected() {
        guard destinations.indices.contains(selection) else { return }
        model.choose(destinations[selection])
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", browsers = "Browsers", rules = "Rules"
    var id: Self { self }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .browsers: "globe"; case .rules: "arrow.triangle.branch" }
    }
    var subtitle: String {
        switch self {
        case .general: "A home for every link."
        case .browsers: "Choose what appears in your picker."
        case .rules: "Send familiar links straight to the right place."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State var page: SettingsPage = .general
    @State private var editingRule: Rule?
    @State private var addingRule = false
    @State private var testURL = ""
    @State private var pendingDelete: Rule?
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(page.rawValue).font(.system(size: 24, weight: .semibold))
                        Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if page == .browsers {
                        Button { model.refreshBrowsers() } label: { Image(systemName: "arrow.clockwise") }
                            .help("Refresh browsers and profiles").accessibilityLabel("Refresh browsers and profiles")
                    } else if page == .rules {
                        Button { addingRule = true } label: { Label("Add rule", systemImage: "plus") }
                            .disabled(model.configurationReadOnly)
                    }
                }.padding(24)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if model.configurationReadOnly {
                            Notice(title: "Settings are read-only", message: model.configurationMessage ?? "Your saved settings could not be loaded. Repair the configuration file, then reopen Ouvre.")
                        } else if let message = model.configurationMessage {
                            Notice(title: "Couldn’t save settings", message: message)
                        }
                        if page == .general, let message = model.defaultBrowserMessage {
                            Notice(title: "Default browser setup needs attention", message: message)
                        }
                        if page == .browsers, let message = model.profileAccessMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                Notice(title: "Couldn’t access browser profiles", message: message)
                                Button("Dismiss") { model.profileAccessMessage = nil }
                            }
                        }
                        switch page {
                        case .general: general
                        case .browsers: browsers
                        case .rules: rules
                        }
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 700, minHeight: 500)
        .sheet(isPresented: $addingRule) { RuleEditor(model: model, existing: nil) }
        .sheet(item: $editingRule) { rule in RuleEditor(model: model, existing: rule) }
        .alert("Delete this rule?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete rule", role: .destructive) {
                if let rule = pendingDelete { model.configuration.rules.removeAll { $0.id == rule.id }; model.save() }
                pendingDelete = nil
            }
        } message: { Text(pendingDelete?.value ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refreshDefaultBrowserStatus() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 9) {
                Image(systemName: "arrow.up.right.square").font(.system(size: 22, weight: .medium)).foregroundStyle(.tint)
                Text("Ouvre").font(.system(size: 18, weight: .semibold))
            }.padding(.horizontal, 12).padding(.top, 8)
            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { item in
                    Button { page = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).foregroundStyle(Color(nsColor: .secondaryLabelColor)).frame(width: 18)
                            Text(item.rawValue).font(.system(size: 13, weight: page == item ? .medium : .regular)).foregroundStyle(Color(nsColor: .labelColor))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12).padding(.vertical, 10)
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                            .background(page == item ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }.padding(5).modifier(NavigationSurface())
            Spacer()
            Label("On this Mac", systemImage: "lock").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 12)
        }.padding(14).frame(width: 180).frame(maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: model.isDefaultBrowser ? "checkmark.circle.fill" : "arrow.up.right.square")
                        .font(.system(size: 27, weight: .light)).foregroundStyle(model.isDefaultBrowser ? Color.green : Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.isDefaultBrowser ? "Ready for your links" : "Make Ouvre your link handler").font(.system(size: 13, weight: .semibold))
                        Text(model.isDefaultBrowser ? "Links from other apps come here first." : "Choose a browser or profile when you open a link.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !model.isDefaultBrowser {
                        Button("Set up…") { model.makeDefaultBrowser() }.controlSize(.regular)
                    }
                }
            }
            SettingsCard {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic routing").font(.system(size: 13, weight: .medium))
                            Text(model.isPaused ? "Paused. Every link opens the picker." : "Use your rules before showing the picker.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Automatic routing", isOn: Binding(get: { !model.isPaused }, set: { model.isPaused = !$0 }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Text("When no rule matches").font(.system(size: 13, weight: .medium))
                        Picker("When no rule matches", selection: Binding(get: { model.configuration.fallback?.id ?? "" }, set: { id in
                            model.configuration.fallback = model.allDestinations.first { $0.id == id }; model.save()
                        })) {
                            Text("Show the picker").tag("")
                            ForEach(model.allDestinations) { Text($0.displayName).tag($0.id) }
                            if let fallback = model.configuration.fallback, !model.allDestinations.contains(where: { $0.id == fallback.id }) {
                                Text("\(fallback.displayName) — unavailable").tag(fallback.id)
                            }
                        }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading).disabled(model.configurationReadOnly)
                    }
                }
            }
            HStack {
                Button("Try the picker") { model.testPicker() }
                Spacer()
                Text("No account. No link history.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
    private var browsers: some View {
        VStack(spacing: 12) {
            if model.browsers.isEmpty {
                EmptyState(symbol: "globe", title: "No browsers found", detail: "Install a browser, then refresh to look again.")
            }
            ForEach(Array(model.orderedBrowsers.enumerated()), id: \.element.id) { browserIndex, browser in
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            BrowserIcon(browser: browser)
                            Text(browser.name).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if !browser.profiles.isEmpty {
                                Text("\(browser.profiles.count) \(browser.profiles.count == 1 ? "profile" : "profiles")")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            orderButton("Move \(browser.name) up", symbol: "arrow.up", disabled: browserIndex == 0) {
                                model.moveBrowser(browser.bundleID, by: -1)
                            }
                            orderButton("Move \(browser.name) down", symbol: "arrow.down", disabled: browserIndex == model.orderedBrowsers.count - 1) {
                                model.moveBrowser(browser.bundleID, by: 1)
                            }
                        }
                        if let message = browser.profileStatus.message {
                            VStack(alignment: .leading, spacing: 9) {
                                Label(browser.profileStatus.canChooseFolder ? "Allow access to profiles" : "Profiles unavailable",
                                      systemImage: browser.profileStatus.canChooseFolder ? "folder.badge.questionmark" : "exclamationmark.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(browser.profileStatus.canChooseFolder ? "Choose this browser’s profile folder so Ouvre can read its profile names." : message)
                                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if browser.profileStatus.canChooseFolder {
                                    Button("Choose folder…") { model.chooseProfileFolder(for: browser) }
                                        .accessibilityLabel("Choose profile folder for \(browser.name)")
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(Array(model.orderedDestinations(for: browser).enumerated()), id: \.element.id) { destinationIndex, destination in
                            HStack {
                                Text(destination.profileName ?? "Browser default").font(.system(size: 12)).lineLimit(2)
                                Spacer()
                                if browser.destinations.count > 1 {
                                    orderButton("Move \(destination.displayName) up", symbol: "arrow.up", disabled: destinationIndex == 0) {
                                        model.moveDestination(destination.id, in: browser, by: -1)
                                    }
                                    orderButton("Move \(destination.displayName) down", symbol: "arrow.down", disabled: destinationIndex == browser.destinations.count - 1) {
                                        model.moveDestination(destination.id, in: browser, by: 1)
                                    }
                                }
                                Toggle("Show \(destination.displayName) in picker", isOn: Binding(get: {
                                    !model.configuration.hiddenDestinationIDs.contains(destination.id)
                                }, set: { shown in
                                    if shown { model.configuration.hiddenDestinationIDs.remove(destination.id) }
                                    else { model.configuration.hiddenDestinationIDs.insert(destination.id) }
                                    model.save()
                                })).labelsHidden().toggleStyle(.switch).controlSize(.mini).disabled(model.configurationReadOnly)
                            }.padding(.leading, 38)
                        }
                    }
                }
            }
            Text("Arrows set the browser and profile order in the picker. Switches control visibility. Rules can still use hidden destinations.")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func orderButton(_ label: String, symbol: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 18, height: 18) }
            .buttonStyle(.borderless).controlSize(.small)
            .accessibilityLabel(label).help(label)
            .disabled(disabled || model.configurationReadOnly)
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.configuration.rules.isEmpty {
                SettingsCard {
                    EmptyState(symbol: "arrow.triangle.branch", title: "A little less choosing", detail: "Add a rule to open a website in its usual browser or profile.")
                }
            } else {
                Text("First match wins. Change the order with the arrow controls.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                SettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(model.configuration.rules.enumerated()), id: \.element.id) { index, rule in
                            if index > 0 { Divider().padding(.vertical, 12) }
                            ruleRow(rule, index: index)
                        }
                    }
                }.disabled(model.configurationReadOnly)
            }
            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Test a link", systemImage: "link").font(.system(size: 13, weight: .semibold))
                    TextField("", text: $testURL, prompt: Text(verbatim: "https://example.com")).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("URL to test against your rules")
                    if testURL.isEmpty {
                        Text("See where a link would open without opening it.").font(.system(size: 11)).foregroundStyle(.secondary)
                    } else if let url = URL(string: testURL), Routing.isWebURL(url) {
                        let rule = model.configuration.rules.first { $0.isEnabled && Routing.matches($0, url: url) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Routing.decision(for: url, configuration: model.configuration).label).font(.system(size: 12, weight: .medium))
                            Text(rule.map { "Matched \($0.value)" } ?? "No matching rule · using your fallback")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if model.isPaused { Text("Routing is paused; incoming links will show the picker.").font(.caption).foregroundStyle(.secondary) }
                        }.accessibilityElement(children: .combine)
                    } else {
                        Label("Enter a complete http or https URL.", systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    private func ruleRow(_ rule: Rule, index: Int) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle("Enable rule for \(rule.value)", isOn: Binding(get: { rule.isEnabled }, set: { enabled in
                if let i = model.configuration.rules.firstIndex(where: { $0.id == rule.id }) { model.configuration.rules[i].isEnabled = enabled; model.save() }
            })).labelsHidden().toggleStyle(.checkbox)
            Button { editingRule = rule } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.value).font(.system(size: 12, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    Text(rule.action.label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Edit rule")
            VStack(spacing: 4) {
                Button { move(rule, by: -1) } label: { Image(systemName: "chevron.up") }
                    .disabled(index == 0).accessibilityLabel("Move \(rule.value) up")
                Button { move(rule, by: 1) } label: { Image(systemName: "chevron.down") }
                    .disabled(index == model.configuration.rules.count - 1).accessibilityLabel("Move \(rule.value) down")
            }.buttonStyle(.borderless).font(.system(size: 10))
            Button { pendingDelete = rule } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).help("Delete rule").accessibilityLabel("Delete rule for \(rule.value)")
        }
    }
    private func move(_ rule: Rule, by offset: Int) {
        guard let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }), model.configuration.rules.indices.contains(index + offset) else { return }
        model.configuration.rules.swapAt(index, index + offset); model.save()
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.07)))
    }
}

private extension RuleAction {
    var label: String { switch self { case .picker: "Show the picker"; case .destination(let destination): destination.displayName } }
}
private extension RoutingDecision {
    var label: String { switch self { case .picker: "Show the picker"; case .destination(let destination): destination.displayName } }
}

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let existing: Rule?
    @State private var pattern: RulePattern = .exactDomain
    @State private var value = ""
    @State private var targetID = ""
    @State private var attempted = false
    @State private var isSaving = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(existing == nil ? "New rule" : "Edit rule").font(.system(size: 21, weight: .semibold))
                Text("Give a website a preferred destination.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("WHEN A LINK MATCHES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Match type", selection: $pattern) {
                    ForEach(RulePattern.allCases, id: \.self) { Text($0.label).tag($0) }
                }.labelsHidden()
                TextField("", text: $value, prompt: Text(verbatim: pattern == .urlPrefix ? "https://example.com/work/" : "example.com")).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Domain or URL pattern")
                    .onSubmit { save() }
                if !value.isEmpty || attempted, let error = Routing.validationError(pattern: pattern, value: value) {
                    Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text(pattern == .domainAndSubdomains ? "Includes this domain and all of its subdomains." : pattern == .urlPrefix ? "Match the beginning of a URL. Include http:// or https://." : "Only this domain, without subdomains.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("OPEN IN").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Destination", selection: $targetID) {
                    Text("Show the picker").tag("")
                    ForEach(model.allDestinations) { Text($0.displayName).tag($0.id) }
                    if case .destination(let previous) = existing?.action, !model.allDestinations.contains(where: { $0.id == previous.id }) {
                        Text("\(previous.displayName) — unavailable").tag(previous.id)
                    }
                }.labelsHidden()
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add rule" : "Save changes") { save() }
                    .keyboardShortcut(.defaultAction).disabled(Routing.validationError(pattern: pattern, value: value) != nil || model.configurationReadOnly || isSaving)
            }
        }.padding(26).frame(width: 420).background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let existing {
                pattern = existing.pattern; value = existing.value
                if case .destination(let destination) = existing.action { targetID = destination.id }
            }
        }
    }
    private func save() {
        attempted = true
        guard !isSaving, Routing.validationError(pattern: pattern, value: value) == nil, !model.configurationReadOnly else { return }
        isSaving = true
        let chosen = model.allDestinations.first { $0.id == targetID }
        let previous: Destination? = {
            if case .destination(let destination) = existing?.action, destination.id == targetID { return destination }
            return nil
        }()
        let action: RuleAction = (chosen ?? previous).map(RuleAction.destination) ?? .picker
        let rule = Rule(id: existing?.id ?? UUID(), isEnabled: existing?.isEnabled ?? true,
                        pattern: pattern, value: value.trimmingCharacters(in: .whitespacesAndNewlines), action: action)
        if let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }) { model.configuration.rules[index] = rule }
        else { model.configuration.rules.append(rule) }
        model.save(); dismiss()
    }
}

/// A noninteractive summary inside the standard AppKit menu. Actions remain native menu items.
@MainActor final class StatusMenuHeader: NSView {
    private let title = NSTextField(labelWithString: "Ouvre")
    private let detail = NSTextField(labelWithString: "")
    private let icon = NSImageView()

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 280, height: 62))
        icon.frame = NSRect(x: 18, y: 20, width: 26, height: 26)
        icon.image = NSImage(systemSymbolName: "arrow.up.right.square", accessibilityDescription: nil)
        icon.contentTintColor = .labelColor
        title.frame = NSRect(x: 56, y: 32, width: 210, height: 18)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.frame = NSRect(x: 56, y: 13, width: 210, height: 16)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityChildren([])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(paused: Bool, isDefault: Bool, destinationCount: Int) {
        if !isDefault && paused { detail.stringValue = "Setup needed · Routing paused" }
        else if !isDefault { detail.stringValue = "Setup needed · Open Settings" }
        else if paused { detail.stringValue = "Paused · Picker for every link" }
        else { detail.stringValue = "Routing active · \(destinationCount) \(destinationCount == 1 ? "destination" : "destinations")" }
        setAccessibilityLabel("Ouvre. \(detail.stringValue)")
    }
}
