import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BattleStore.self) private var battle
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var goal = 100
    @State private var strictMode = SharedSettings.shared.strictPrivacyMode
    @State private var nudges = SharedSettings.shared.nudgesEnabled
    @State private var diagnostics = SharedSettings.shared.diagnosticsEnabled
    @State private var confirmReset = false
    @State private var confirmDelete = false
    @State private var exportURL: URL?
    @State private var accountError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("daily cap") {
                    Stepper(value: $goal, in: 10...1000, step: 10) {
                        HStack {
                            Text("cap")
                            Spacer()
                            Text("\(goal) reels").foregroundStyle(Theme.textDim)
                        }
                    }
                    .onChange(of: goal) { _, value in model.setGoal(value) }
                }

                Section {
                    HStack {
                        Label(model.isArmed ? "counter is on" : "counter is off", systemImage: model.isArmed ? "record.circle.fill" : "record.circle")
                            .foregroundStyle(model.isArmed ? Theme.lime : Theme.textDim)
                        Spacer()
                        if model.isArmed {
                            Button("stop", role: .destructive) { model.stopCounting() }
                        } else {
                            Button("arm") {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .arm(auto: false, returnTo: nil) }
                            }
                        }
                    }
                    NavigationLink("auto-start setup") { AutomationGuideView() }
                    Toggle("nudge me if the counter's off", isOn: $nudges)
                        .onChange(of: nudges) { _, value in SharedSettings.shared.nudgesEnabled = value }
                } header: {
                    Text("counting")
                }

                Section {
                    ForEach(SourceApp.tracked) { app in
                        Toggle(isOn: Binding(
                            get: { model.trackedApps.contains(app) },
                            set: { model.setTracked(app, enabled: $0) }
                        )) {
                            Label(app.displayName, systemImage: app.symbol)
                        }
                    }
                } header: {
                    Text("count these apps")
                }

                Section {
                    Toggle("strict privacy mode", isOn: $strictMode)
                        .onChange(of: strictMode) { _, value in model.setStrictPrivacy(value) }
                } header: {
                    Text("privacy")
                } footer: {
                    Text("Doomscore reads the screen on-device only to spot swipes, ads and repeats — frames are never saved or uploaded. Strict mode goes further: it only looks while a Shortcuts automation says a reels app is open (needs the auto-start setup).")
                }

                battleSection

                Section("your data") {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("export CSV", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = model.exportCSV() } label: { Label("prepare CSV export", systemImage: "tablecells") }
                    }
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("reset all local data", systemImage: "trash")
                    }
                }

                Section {
                    Toggle("detector diagnostics", isOn: $diagnostics)
                        .onChange(of: diagnostics) { _, value in model.setDiagnostics(value) }
                    if diagnostics {
                        NavigationLink("open detector lab") { DetectorLabView() }
                    }
                } header: {
                    Text("advanced")
                } footer: {
                    Text("Shows live detector decisions (numbers only, never screen content). Useful for tuning.")
                }

                Section {
                    LabeledContent("version", value: AppEnvironment.appVersion)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("done") { dismiss() } }
            }
            .onAppear { goal = model.goal }
            .confirmationDialog("reset everything?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("reset local data", role: .destructive) { model.resetAllData() }
            } message: {
                Text("Deletes your local history, streaks and recaps on this phone. Battle totals on the server stay until you delete your account.")
            }
            .confirmationDialog("delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("delete account", role: .destructive) {
                    Task {
                        do { try await battle.deleteAccount() } catch { accountError = error.localizedDescription }
                    }
                }
            } message: {
                Text("Removes your profile, friends and all synced totals from the server. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private var battleSection: some View {
        Section {
            switch battle.phase {
            case .ready, .needsProfile, .failed:
                if let profile = battle.profile {
                    HStack(spacing: 12) {
                        Avatar(emoji: profile.emoji, colorHex: profile.color, size: 36)
                        VStack(alignment: .leading) {
                            Text(profile.displayName)
                            Text("@\(profile.handle)").font(.footnote).foregroundStyle(Theme.textDim)
                        }
                    }
                    NavigationLink("edit profile") {
                        ScrollView { ProfileEditorCard().padding(20) }.screenBackground()
                    }
                }
                Button("sign out") { Task { await battle.signOut() } }
                Button("delete account", role: .destructive) { confirmDelete = true }
            case .signedOut:
                Button("join the battle") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .joinBattle }
                }
            case .notConfigured:
                Text("Battles need a backend (see backend/README.md).").foregroundStyle(Theme.textDim)
            case .idle, .loading:
                ProgressView()
            }
            if let accountError {
                Text(accountError).foregroundStyle(Theme.red)
            }
        } header: {
            Text("battle account")
        }
    }
}

/// Live detector numbers written by the broadcast extension (debug aid).
struct DetectorLabView: View {
    @State private var diagnostics: DetectorDiagnostics?

    var body: some View {
        List {
            if let d = diagnostics {
                Section("pipeline") {
                    LabeledContent("updated", value: d.updatedAt.formatted(date: .omitted, time: .standard))
                    LabeledContent("frames analysed", value: "\(d.framesProcessed)")
                    LabeledContent("fps", value: String(format: "%.1f", d.processedFPS))
                    LabeledContent("ocr runs", value: "\(d.ocrRuns) · \(Int(d.lastOCRMillis)) ms")
                    LabeledContent("free memory", value: String(format: "%.0f MB", d.availableMemoryMB))
                }
                Section("detector") {
                    LabeledContent("context", value: "\(d.context) \(d.contextApp ?? "")")
                    LabeledContent("layout score", value: "\(d.lastScore)")
                    LabeledContent("swipes ↑ / ↓", value: "\(d.swipesForward) / \(d.swipesBackward)")
                    LabeledContent("last decision", value: d.lastDecision)
                    LabeledContent("counted · ads · rewatch", value: "\(d.counted) · \(d.adsSkipped) · \(d.rewatchesSkipped)")
                }
                Section("recent") {
                    ForEach(d.recentEvents, id: \.self) { Text($0).font(.system(.footnote, design: .monospaced)) }
                }
            } else {
                Text("No diagnostics yet. Arm the counter and scroll a few reels.")
                    .foregroundStyle(Theme.textDim)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("detector lab")
        .task {
            while !Task.isCancelled {
                diagnostics = SharedStore.shared.diagnostics
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}
