import AppKit
import MTMCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            PlaylistSettingsTab()
                .tabItem { Label(L("settings.tab.playlists"), systemImage: "music.note.list") }
            RulesSettingsTab()
                .tabItem { Label(L("settings.tab.rules"), systemImage: "checklist") }
            IdentificationSettingsTab()
                .tabItem { Label(L("settings.tab.identify"), systemImage: "waveform.and.magnifyingglass") }
            WritePolicySettingsTab()
                .tabItem { Label(L("settings.tab.writePolicy"), systemImage: "square.and.pencil") }
            GeneralSettingsTab()
                .tabItem { Label(L("settings.tab.general"), systemImage: "gearshape") }
        }
        .frame(width: 600, height: 520)
    }
}

private struct PlaylistSettingsTab: View {
    @Environment(AppState.self) private var state
    @State private var model: PlaylistPickerViewModel?
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let model {
                PlaylistPickerView(model: model)
                HStack {
                    Spacer()
                    Button(L("common.revert")) { model.selection = Set(state.selectedIDs) }
                        .disabled(!model.isDirty)
                    Button(L("common.applyRescan")) {
                        if state.hasHistory { confirmReset = true } else { Task { await model.apply() } }
                    }
                    .disabled(!model.hasSelection || !model.isDirty)
                }
            }
        }
        .padding(20)
        .alert(L("settings.playlist.confirmTitle"), isPresented: $confirmReset) {
            Button(L("settings.playlist.confirmChange"), role: .destructive) { Task { await model?.apply() } }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(PlaylistSelectionSheet.resetMessage)
        }
        .task {
            let model = PlaylistPickerViewModel(state: state)
            self.model = model
            await model.load()
        }
    }
}

private struct RulesSettingsTab: View {
    @Environment(AppState.self) private var state
    @State private var rules = CompletenessRules()
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.rules.placeholdersAsEmpty"), isOn: $rules.treatPlaceholdersAsEmpty)
                Toggle(L("settings.rules.filenameAsEmpty"), isOn: $rules.treatFilenameLikeTitleAsEmpty)
                    .disabled(!rules.treatPlaceholdersAsEmpty)
                Text(L("settings.rules.filenameNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("settings.rules.artistPlaceholders")) { StringListEditor(items: $rules.artistPlaceholders) }
            Section(L("settings.rules.albumPlaceholders")) { StringListEditor(items: $rules.albumPlaceholders) }
            Section(L("settings.rules.titlePatterns")) { StringListEditor(items: $rules.titlePlaceholderPatterns) }
            Section {
                HStack {
                    Button(L("common.defaults")) { rules = CompletenessRules() }
                    Spacer()
                    Button(L("common.applyRescan")) { Task { await state.updateRules(rules) } }
                        .disabled(rules == state.settings.rules)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if !loaded {
                rules = state.settings.rules
                loaded = true
            }
        }
    }
}

private struct StringListEditor: View {
    @Binding var items: [String]
    @State private var newItem = ""

    var body: some View {
        ForEach(items.indices, id: \.self) { index in
            HStack {
                Text(items[index]).lineLimit(1).truncationMode(.middle).help(items[index])
                Spacer()
                Button {
                    items.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        HStack {
            TextField(L("common.add"), text: $newItem)
                .onSubmit(add)
            Button(L("common.add"), action: add)
                .disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func add() {
        let value = newItem.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !items.contains(value) else { return }
        items.append(value)
        newItem = ""
    }
}

private struct IdentificationSettingsTab: View {
    @Environment(AppState.self) private var state
    @State private var apiKey = ""
    @State private var keyConfigured = false
    @State private var message: String?

    var body: some View {
        @Bindable var state = state
        Form {
            Section(L("settings.id.sources")) {
                LabeledContent("MusicBrainz", value: L("settings.id.musicbrainzAlways"))
                Toggle(L("settings.id.useITunes"), isOn: $state.settings.identification.useITunes)
                Toggle(L("settings.id.useAcoustID"), isOn: $state.settings.identification.useAcoustID)
            }
            Section {
                SecureField(L("settings.id.apiKeyField"), text: $apiKey)
                HStack {
                    Text(keyConfigured ? L("settings.id.keySaved") : L("settings.id.keyNone"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(apiKey.isEmpty && keyConfigured ? L("settings.id.deleteKey") : L("common.save")) { saveKey() }
                        .disabled(apiKey.isEmpty && !keyConfigured)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: {
                Text("AcoustID")
            } footer: {
                Text(L("settings.id.acoustidFooter")).font(.caption)
            }
            Section(L("settings.id.display")) {
                Toggle(L("settings.id.preferKorean"), isOn: $state.settings.identification.preferKoreanArtistNames)
                TextField(L("settings.id.mbContact"), text: $state.settings.musicBrainzContact)
                Text(L("settings.id.mbContactNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { keyConfigured = state.isAcoustIDConfigured }
    }

    private func saveKey() {
        do {
            try state.saveAcoustIDKey(apiKey)
            keyConfigured = !apiKey.isEmpty
            message = apiKey.isEmpty ? L("settings.id.keyDeleted") : L("settings.id.keySavedMsg")
            apiKey = ""
        } catch {
            message = Lf("settings.id.saveFailed", error.localizedDescription)
        }
    }
}

private struct WritePolicySettingsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        Form {
            Section {
                ForEach(ProposalField.allCases, id: \.self) { field in
                    Picker(field.label, selection: Binding(
                        get: { state.settings.writePolicies.policy(for: field) },
                        set: { state.settings.writePolicies.set($0, for: field) }
                    )) {
                        ForEach(FieldWritePolicy.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }
            } footer: {
                Text(L("settings.write.footer"))
                    .font(.caption)
            }
            if ProposalField.allCases.contains(where: { state.settings.writePolicies.policy(for: $0) == .replaceIfDifferent }) {
                Label(L("settings.write.warning"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Section {
                Button(L("settings.write.allDefaults")) { state.settings.writePolicies = WritePolicies() }
                Button(L("settings.write.allFillEmpty")) { state.settings.writePolicies = .fillEmptyOnly }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var state
    @State private var showOnboarding = false

    var body: some View {
        @Bindable var state = state
        Form {
            Section(L("settings.general.help")) {
                LabeledContent(L("settings.general.onboarding")) {
                    Button(L("settings.general.showOnboarding")) { showOnboarding = true }
                }
                if UpdateFeature.isAvailable {
                    LabeledContent(L("settings.general.updates")) {
                        Button(L("update.check")) { UpdateFeature.checkForUpdates() }
                    }
                }
            }
            Section(L("settings.general.display")) {
                Picker(L("settings.general.theme"), selection: $state.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Label($0.label, systemImage: $0.icon).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(L("settings.general.language"), selection: $state.settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section(L("settings.general.applySection")) {
                Toggle(L("settings.general.completionAlert"), isOn: $state.settings.showApplyCompletionAlert)
                Toggle(L("settings.general.allowLowRes"), isOn: $state.settings.allowLowResolutionArtwork)
                Text(L("settings.general.lowResNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("settings.general.safety")) {
                Toggle(Lf("settings.general.writeGuard", AppSettings.writeGuardLimit.formatted()), isOn: $state.settings.writeGuardEnabled)
                Text(L("settings.general.writeGuardNote"))
                    .font(.caption).foregroundStyle(.secondary)
                Toggle(L("settings.general.fullBackup"), isOn: $state.settings.fullFileBackup)
                Text(Lf("settings.general.fullBackupNote", ByteCountFormatter.string(fromByteCount: state.fileBackupSize(), countStyle: .file)))
                    .font(.caption).foregroundStyle(.secondary)
                Picker(L("settings.general.snapshotRetention"), selection: $state.settings.snapshotRetentionDays) {
                    Text(L("retention.7")).tag(7)
                    Text(L("retention.30")).tag(30)
                    Text(L("retention.90")).tag(90)
                    Text(L("retention.365")).tag(365)
                    Text(L("retention.forever")).tag(0)
                }
                Text(L("settings.general.snapshotRetentionNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("settings.general.data")) {
                LabeledContent(L("settings.general.dataFolder")) {
                    Button(L("settings.general.showInFinder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([AppDatabase.defaultDirectory])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(mode: .replay) { showOnboarding = false }
                .environment(state)
                .themed(state.settings.appearance)
                .frame(width: 800, height: 600)
        }
    }
}
