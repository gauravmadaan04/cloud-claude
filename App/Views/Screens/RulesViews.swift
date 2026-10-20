import AppKit
import HavenCore
import SwiftUI

/// "Your Rules" on the Clean Up page: the rules you made, ready-made ideas, and a button for a new one.
struct CustomRulesSection: View {
    @Environment(\.theme) private var theme
    private var prefs: Prefs { .shared }
    private var model: AppModel { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Your Rules", subtitle: "Tidy files the way you like, automatically") {
                Button {
                    model.editingRule = CustomRule(name: "New Rule", enabled: false,
                                                   folders: [(LaunchOptions.current.homeForRoots as NSString).appendingPathComponent("Downloads")],
                                                   conditions: [.source("*")],
                                                   action: .move(to: (LaunchOptions.current.homeForRoots as NSString).appendingPathComponent("Documents"), byMonth: false))
                } label: {
                    Label("New Rule", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("rules.new")
            }
            ForEach(prefs.customRules) { rule in
                CustomRuleCard(rule: rule)
            }
            let ideas = CustomRulePlanner.suggestions(home: LaunchOptions.current.homeForRoots)
                .filter { idea in !prefs.customRules.contains { $0.name == idea.name } }
            if !ideas.isEmpty {
                Text(prefs.customRules.isEmpty ? "Start from an idea" : "More ideas")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                    ForEach(ideas, id: \.name) { idea in
                        Button { model.editingRule = idea } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: ruleSymbol(idea.action))
                                    .foregroundStyle(theme.accent)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(idea.name).fontWeight(.semibold)
                                    Text(CustomRulePlanner.describe(idea, home: LaunchOptions.current.homeForRoots))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle(theme, padding: 12)
                            .interactiveCard()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("rules.idea.\(idea.name)")
                    }
                }
            }
        }
    }
}

func ruleSymbol(_ action: CustomRuleAction) -> String {
    switch action {
    case .move: return "folder.badge.plus"
    case .rename: return "pencil"
    case .addToCollection: return "square.stack"
    case .trash: return "trash"
    }
}

struct CustomRuleCard: View {
    let rule: CustomRule
    @Environment(\.theme) private var theme
    @State private var matching = 0
    @State private var running = false
    private var prefs: Prefs { .shared }

    var body: some View {
        let isOn = Binding(
            get: { prefs.customRules.first { $0.id == rule.id }?.enabled ?? false },
            set: { on in
                guard let i = prefs.customRules.firstIndex(where: { $0.id == rule.id }) else { return }
                prefs.customRules[i].enabled = on
                if on {
                    let updated = prefs.customRules[i]
                    Task { await CustomRulesRunner.shared.run(updated) }
                }
            }
        )
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: ruleSymbol(rule.action))
                .font(.title3)
                .foregroundStyle(theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).font(.headline)
                Text(CustomRulePlanner.describe(rule, collectionName: { CollectionStore.shared.collection($0)?.name }))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(matching == 0 ? "Nothing to do right now." : "Right now this would act on \(HavenFormat.count(matching, "file")).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .accessibilityIdentifier("rule.preview.\(rule.name)")
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityIdentifier("rule.toggle.\(rule.name)")
                HStack(spacing: 8) {
                    Button("Edit") { AppModel.shared.editingRule = rule }
                        .accessibilityIdentifier("rule.edit.\(rule.name)")
                    Button(running ? "Running…" : "Run Now") {
                        running = true
                        Task {
                            let n = await CustomRulesRunner.shared.run(rule)
                            running = false
                            AppModel.shared.showToast(n == 0 ? "“\(rule.name)”: nothing to do" : "“\(rule.name)” tidied \(HavenFormat.count(n, "file"))",
                                                      symbol: ruleSymbol(rule.action))
                        }
                    }
                    .disabled(running || matching == 0)
                    .accessibilityIdentifier("rule.run.\(rule.name)")
                }
                .buttonStyle(.borderless)
                .font(.callout)
            }
        }
        .cardStyle(theme, padding: 14)
        .task(id: "\(LibraryStore.shared.version)|\(rule.hashValue)") {
            matching = await CustomRulesRunner.shared.plan(rule).count
        }
    }
}

/// Make or change a rule: where to look, what to look for, what to do. Shows what it would do right now.
struct RuleEditorView: View {
    @State var rule: CustomRule
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var preview: [CustomRuleStep] = []
    @State private var confirmDelete = false
    private var prefs: Prefs { .shared }
    private var home: String { LaunchOptions.current.homeForRoots }
    private var isNew: Bool { !prefs.customRules.contains { $0.id == rule.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Rule" : "Edit Rule")
                .font(.system(size: 20, weight: .bold, design: theme.headingDesign))
            TextField("Name", text: $rule.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ruleEditor.name")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    group("Look at files right in") { foldersEditor }
                    group("When a file") { conditionsEditor }
                    group("Then") { actionEditor }
                }
                .padding(.vertical, 2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(CustomRulePlanner.describe(rule, collectionName: { CollectionStore.shared.collection($0)?.name }, home: home))
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ruleEditor.sentence")
                Text(previewText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier("ruleEditor.preview")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                if !isNew {
                    Button("Delete Rule", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(rule.name.trimmingCharacters(in: .whitespaces).isEmpty || rule.folders.isEmpty)
                    .accessibilityIdentifier("ruleEditor.save")
            }
        }
        .padding(22)
        .frame(width: 620, height: 660)
        .task(id: rule) {
            try? await Task.sleep(for: .milliseconds(120))
            if Task.isCancelled { return }
            preview = await CustomRulesRunner.shared.plan(rule)
        }
        .confirmationDialog("Delete “\(rule.name)”?", isPresented: $confirmDelete) {
            Button("Delete Rule", role: .destructive) {
                prefs.customRules.removeAll { $0.id == rule.id }
                CustomRulesRunner.shared.forget(rule.id)
                dismiss()
            }
        } message: {
            Text("Files it already tidied stay where they are.")
        }
        .accessibilityIdentifier("ruleEditor")
    }

    private var previewText: String {
        if rule.conditions.contains(where: { !$0.isComplete }) { return "Fill in every condition to see what this would do." }
        if preview.isEmpty { return "Right now no files match." }
        let names = preview.prefix(3).map(\.item.name).joined(separator: ", ")
        return "Right now this matches \(HavenFormat.count(preview.count, "file")): \(names)\(preview.count > 3 ? "…" : "")"
    }

    private func save() {
        rule.name = rule.name.trimmingCharacters(in: .whitespaces)
        if let i = prefs.customRules.firstIndex(where: { $0.id == rule.id }) {
            prefs.customRules[i] = rule
        } else {
            prefs.customRules.append(rule)
        }
        dismiss()
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: Folders

    private var foldersEditor: some View {
        HStack(alignment: .center, spacing: 6) {
            ForEach(rule.folders, id: \.self) { folder in
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill").foregroundStyle(theme.accent)
                    Text((folder as NSString).lastPathComponent)
                    Button { rule.folders.removeAll { $0 == folder } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .help(tildePath(folder))
            }
            Menu {
                ForEach(["Downloads", "Desktop", "Documents", "Pictures"], id: \.self) { name in
                    let path = (home as NSString).appendingPathComponent(name)
                    Button(name) { if !rule.folders.contains(path) { rule.folders.append(path) } }
                }
                Divider()
                Button("Choose a Folder…") {
                    if let path = chooseFolder(), !rule.folders.contains(path) { rule.folders.append(path) }
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .fixedSize()
            Spacer()
        }
    }

    // MARK: Conditions

    private var conditionsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rule.conditions.indices, id: \.self) { i in
                ConditionRow(condition: Binding(
                    get: { i < rule.conditions.count ? rule.conditions[i] : .isScreenshot },
                    set: { if i < rule.conditions.count { rule.conditions[i] = $0 } }
                )) {
                    rule.conditions.remove(at: i)
                }
            }
            Menu {
                ForEach(RuleCondition.Field.allCases) { field in
                    Button(field.title) { rule.conditions.append(field.defaultCondition) }
                }
            } label: {
                Label(rule.conditions.isEmpty ? "Add a Condition" : "And…", systemImage: "plus")
            }
            .fixedSize()
            .accessibilityIdentifier("ruleEditor.addCondition")
            if rule.conditions.isEmpty {
                Text(rule.action == .trash ? "A rule that moves files to the Trash needs at least one condition."
                                           : "With no conditions, the rule acts on every file in these folders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Action

    private var actionKind: Binding<CustomRuleAction.Kind> {
        Binding(
            get: { rule.action.kind },
            set: { kind in
                guard kind != rule.action.kind else { return }
                switch kind {
                case .move: rule.action = .move(to: (home as NSString).appendingPathComponent("Documents"), byMonth: false)
                case .rename: rule.action = .rename(.smart)
                case .addToCollection:
                    let id = CollectionStore.shared.collections.first?.id ?? CollectionStore.shared.create(name: rule.name)
                    rule.action = .addToCollection(id)
                case .trash: rule.action = .trash
                }
            }
        )
    }

    private var actionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Action", selection: actionKind) {
                ForEach(CustomRuleAction.Kind.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("ruleEditor.action")
            switch rule.action {
            case .move(let to, let byMonth):
                HStack {
                    Image(systemName: "folder").foregroundStyle(theme.accent)
                    Text(tildePath(to)).lineLimit(1).truncationMode(.middle)
                    Button("Choose…") {
                        if let path = chooseFolder() { rule.action = .move(to: path, byMonth: byMonth) }
                    }
                }
                Toggle("Into a folder for each month (2026-10 October…)", isOn: Binding(
                    get: { byMonth },
                    set: { rule.action = .move(to: to, byMonth: $0) }
                ))
            case .rename(let template):
                TextField("Pattern", text: Binding(
                    get: { template.pattern },
                    set: { var t = template; t.pattern = $0; rule.action = .rename(t) }
                ))
                .textFieldStyle(.roundedBorder)
                Text("{date} date · {title} title read from the file · {name} current name · {n} number · {source} where it came from")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Each file is renamed once by this rule, never again.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            case .addToCollection(let id):
                HStack {
                    Picker("Collection", selection: Binding(get: { id }, set: { rule.action = .addToCollection($0) })) {
                        ForEach(CollectionStore.shared.collections) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("New Collection") {
                        rule.action = .addToCollection(CollectionStore.shared.create(name: rule.name))
                    }
                }
            case .trash:
                Label("Files go to the Trash. You can put them back from Activity.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseFolder() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

/// One "when" line: what to check, and the value to check for.
struct ConditionRow: View {
    @Binding var condition: RuleCondition
    let remove: () -> Void

    private var field: Binding<RuleCondition.Field> {
        Binding(get: { condition.field }, set: { if $0 != condition.field { condition = $0.defaultCondition } })
    }

    private var sources: [DownloadSource] {
        var seen = Set<String>()
        let present = LibraryStore.shared.derived.sources.map(\.source)
        return (SourceClassifier.knownSources + present).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        HStack(spacing: 8) {
            Picker("Condition", selection: field) {
                ForEach(RuleCondition.Field.allCases) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .frame(width: 190)
            value
            Spacer(minLength: 0)
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove this condition")
        }
    }

    @ViewBuilder
    private var value: some View {
        switch condition {
        case .source(let id):
            Picker("Source", selection: Binding(get: { id }, set: { condition = .source($0) })) {
                Text("Anywhere (any download)").tag("*")
                Divider()
                ForEach(sources) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
        case .kind(let kind):
            Picker("Kind", selection: Binding(get: { kind }, set: { condition = .kind($0) })) {
                ForEach(FileKind.allCases.filter { $0 != .folder }, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        case .nameContains(let s):
            TextField("a word", text: Binding(get: { s }, set: { condition = .nameContains($0) }))
                .textFieldStyle(.roundedBorder)
        case .textContains(let s):
            TextField("a word", text: Binding(get: { s }, set: { condition = .textContains($0) }))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ruleEditor.textWord")
        case .extensionIs(let e):
            TextField("pdf", text: Binding(get: { e }, set: { condition = .extensionIs($0) }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
        case .olderThan(let days):
            Stepper("\(HavenFormat.count(days, "day")) ago", value: Binding(get: { days }, set: { condition = .olderThan(days: $0) }), in: 1...3650)
        case .notOpenedFor(let days):
            Stepper(HavenFormat.count(days, "day"), value: Binding(get: { days }, set: { condition = .notOpenedFor(days: $0) }), in: 1...3650)
        case .biggerThan(let mb):
            Stepper("\(mb) MB", value: Binding(get: { mb }, set: { condition = .biggerThan(megabytes: $0) }), in: 1...100_000)
        case .isScreenshot:
            EmptyView()
        }
    }
}
