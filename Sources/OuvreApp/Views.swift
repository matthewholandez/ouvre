import AppKit
import SwiftUI

struct PickerView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var destinations: [Destination] {
        model.visibleDestinations.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Open link with…").font(.title2.bold())
            Text(model.currentURL?.absoluteString ?? "")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            if let message = model.message {
                Text(message).foregroundStyle(.red).font(.caption)
            }
            TextField("Search browsers and profiles", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .onChange(of: query) { _, _ in selection = 0 }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.return) { chooseSelected(); return .handled }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                    ForEach(Array(destinations.enumerated()), id: \.element.id) { index, destination in
                        Button { model.choose(destination) } label: {
                            HStack(spacing: 10) {
                                if let browser = model.browsers.first(where: { $0.bundleID == destination.bundleID }) {
                                    Image(nsImage: browser.icon).resizable().frame(width: 28, height: 28)
                                }
                                VStack(alignment: .leading) {
                                    Text(destination.browserName).fontWeight(.medium)
                                    if let profile = destination.profileName {
                                        Text(profile).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if index == selection { Image(systemName: "return").foregroundStyle(.secondary) }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(index == selection ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isLaunching)
                        .id(destination.id)
                    }
                }
                }
                .onChange(of: selection) { _, index in
                    guard destinations.indices.contains(index) else { return }
                    proxy.scrollTo(destinations[index].id, anchor: .center)
                }
            }
            if destinations.isEmpty { Text("No matching destinations. Refresh browsers in Settings.").foregroundStyle(.secondary) }
            HStack {
                Text("↑↓ Select  ·  Return Open  ·  Esc Dismiss").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.dismissPicker() }
            }
        }
        .padding(20)
        .frame(minWidth: 490, minHeight: 400)
        .onAppear { searchFocused = true }
        .onChange(of: model.currentURL) { _, _ in query = ""; selection = 0; searchFocused = true }
        .onExitCommand { model.dismissPicker() }
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

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    @State private var editingRule: Rule?
    @State private var addingRule = false
    @State private var testURL = "https://example.com/path"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings", selection: $tab) {
                Text("General").tag(0)
                Text("Browsers").tag(1)
                Text("Rules").tag(2)
            }.pickerStyle(.segmented).padding()
            Divider()
            Group {
                switch tab {
                case 0: general
                case 1: browsersView
                default: rulesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let message = model.message {
                Divider()
                Text(message).foregroundStyle(.red).font(.caption).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $addingRule) { RuleEditor(model: model, existing: nil) }
        .sheet(item: $editingRule) { rule in RuleEditor(model: model, existing: rule) }
    }

    private var general: some View {
        Form {
            LabeledContent("Default browser") {
                Text(model.isDefaultBrowser ? "Ouvre is the default browser" : "Ouvre is not the default browser")
                Button("Make default") { model.makeDefaultBrowser() }.disabled(model.isDefaultBrowser)
            }
            LabeledContent("Routing") {
                Toggle("Pause automatic rules", isOn: $model.isPaused)
            }
            LabeledContent("Fallback") {
                Picker("Fallback", selection: Binding(
                    get: { model.configuration.fallback?.id ?? "" },
                    set: { id in
                        model.configuration.fallback = model.allDestinations.first { $0.id == id }
                        model.save()
                    })) {
                    Text("Always ask").tag("")
                    ForEach(model.allDestinations) { destination in Text(destination.displayName).tag(destination.id) }
                    if let fallback = model.configuration.fallback,
                       !model.allDestinations.contains(where: { $0.id == fallback.id }) {
                        Text("\(fallback.displayName) (unavailable)").tag(fallback.id)
                    }
                }.frame(width: 260)
            }
            Text("Links stay on this Mac. Ouvre reads Chromium profile names only; it does not modify browser data or send links to a service.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).disabled(model.configurationReadOnly)
    }

    private var browsersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed destinations").font(.headline)
                Spacer()
                Button("Refresh") { model.refreshBrowsers() }
            }
            Text("Chrome, Helium and other supported Chromium profiles appear when Ouvre can read their Local State metadata. Safari and Firefox open as whole browsers.")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(model.browsers) { browser in
                    Section(browser.name) {
                        if let status = browser.profileStatus.message {
                            Text(status).font(.caption).foregroundStyle(.secondary)
                        }
                        if browser.profileStatus.canChooseFolder {
                            Button("Choose profile folder…") { model.chooseProfileFolder(for: browser) }
                        }
                        ForEach(browser.destinations) { destination in
                            Toggle(destination.profileName ?? "Whole browser", isOn: Binding(
                                get: { !model.configuration.hiddenDestinationIDs.contains(destination.id) },
                                set: { isShown in
                                    if isShown { model.configuration.hiddenDestinationIDs.remove(destination.id) }
                                    else { model.configuration.hiddenDestinationIDs.insert(destination.id) }
                                    model.save()
                                })).disabled(model.configurationReadOnly)
                        }
                    }
                }
            }
        }.padding(20)
    }

    private var rulesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rules run from top to bottom; the first match wins.").font(.headline)
                Spacer()
                Button("Add rule") { addingRule = true }
            }
            List {
                ForEach(model.configuration.rules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { enabled in updateRule(rule) { $0.isEnabled = enabled } }))
                            .labelsHidden()
                        VStack(alignment: .leading) {
                            Text(rule.value).fontWeight(.medium)
                            Text("\(rule.pattern.label) → \(rule.action.label)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editingRule = rule }
                        Button { move(rule, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(model.configuration.rules.first?.id == rule.id)
                        Button { move(rule, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(model.configuration.rules.last?.id == rule.id)
                        Button(role: .destructive) { model.configuration.rules.removeAll { $0.id == rule.id }; model.save() }
                            label: { Image(systemName: "trash") }
                    }
                }
            }
            Divider()
            Text("Test a URL").font(.headline)
            TextField("https://example.com/path", text: $testURL).textFieldStyle(.roundedBorder)
            if let url = URL(string: testURL), Routing.isWebURL(url) {
                Text("Result: \(Routing.decision(for: url, configuration: model.configuration).label)")
                    .font(.caption)
            } else { Text("Enter a valid http or https URL.").font(.caption).foregroundStyle(.secondary) }
        }.padding(20).disabled(model.configurationReadOnly)
    }

    private func updateRule(_ rule: Rule, edit: (inout Rule) -> Void) {
        guard let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        edit(&model.configuration.rules[index]); model.save()
    }
    private func move(_ rule: Rule, by offset: Int) {
        guard let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }),
              model.configuration.rules.indices.contains(index + offset) else { return }
        model.configuration.rules.swapAt(index, index + offset); model.save()
    }
}

private extension RuleAction {
    var label: String { switch self { case .picker: "Ask every time"; case .destination(let destination): destination.displayName } }
}
private extension RoutingDecision {
    var label: String { switch self { case .picker: "Ask every time"; case .destination(let destination): destination.displayName } }
}

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let existing: Rule?
    @State private var pattern: RulePattern = .exactDomain
    @State private var value = ""
    @State private var targetID = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(existing == nil ? "Add rule" : "Edit rule").font(.title2.bold())
            Picker("Match", selection: $pattern) {
                ForEach(RulePattern.allCases, id: \.self) { pattern in Text(pattern.label).tag(pattern) }
            }
            TextField(pattern == .urlPrefix ? "https://example.com/path" : "example.com", text: $value)
                .textFieldStyle(.roundedBorder)
            Picker("Open in", selection: $targetID) {
                Text("Ask every time").tag("")
                ForEach(model.allDestinations) { destination in Text(destination.displayName).tag(destination.id) }
                if case .destination(let previous) = existing?.action,
                   !model.allDestinations.contains(where: { $0.id == previous.id }) {
                    Text("\(previous.displayName) (unavailable)").tag(previous.id)
                }
            }
            if let error = Routing.validationError(pattern: pattern, value: value) {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(Routing.validationError(pattern: pattern, value: value) != nil)
            }
        }
        .padding(24).frame(width: 440)
        .onAppear {
            if let existing {
                pattern = existing.pattern; value = existing.value
                if case .destination(let destination) = existing.action { targetID = destination.id }
            }
        }
    }

    private func save() {
        let chosen = model.allDestinations.first(where: { $0.id == targetID })
        let previous: Destination? = {
            if case .destination(let destination) = existing?.action, destination.id == targetID { return destination }
            return nil
        }()
        let action: RuleAction = (chosen ?? previous).map(RuleAction.destination) ?? .picker
        let rule = Rule(id: existing?.id ?? UUID(), isEnabled: existing?.isEnabled ?? true,
                        pattern: pattern, value: value.trimmingCharacters(in: .whitespacesAndNewlines), action: action)
        if let index = model.configuration.rules.firstIndex(where: { $0.id == rule.id }) {
            model.configuration.rules[index] = rule
        } else { model.configuration.rules.append(rule) }
        model.save(); dismiss()
    }
}
