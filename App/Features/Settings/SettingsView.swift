import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(BattleStore.self) private var battle
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var goal = 100
    @State private var nudges = SharedSettings.shared.nudgesEnabled
    @State private var recaps = SharedSettings.shared.recapsEnabled
    @State private var paceReset = false
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

                autoSection

                Section {
                    NavigationLink("instant island (Shortcuts)") { AutomationGuideView() }
                    Toggle("nightly report + weekly recap", isOn: $recaps)
                        .onChange(of: recaps) { _, value in model.setRecapsEnabled(value) }
                    Toggle("remind me if tracking is off", isOn: $nudges)
                        .onChange(of: nudges) { _, value in SharedSettings.shared.nudgesEnabled = value }
                } header: {
                    Text("island & notifications")
                }

                battleSection

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("export CSV", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportURL = model.exportCSV() } label: { Label("prepare CSV export", systemImage: "tablecells") }
                    }
                    if let privacy = AppEnvironment.privacyPolicyURL {
                        Link(destination: privacy) { Label("privacy policy", systemImage: "hand.raised.fill") }
                    }
                    Button(role: .destructive) { confirmReset = true } label: {
                        Label("reset all local data", systemImage: "trash")
                    }
                } header: {
                    Text("your data")
                } footer: {
                    Text("Auto mode only receives minutes of use from Screen Time — never what's on your screen.")
                }

                Section {
                    NavigationLink("Screen Time diagnostics") { ScreenTimeDiagnosticsView() }
                    NavigationLink("exact mode (screen broadcast)") { ExactModeView() }
                } header: {
                    Text("advanced")
                } footer: {
                    Text("Exact mode is optional and off unless you start it here. It needs an iOS screen broadcast, so Doomscore never asks for it on its own.")
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
    private var autoSection: some View {
        let service = model.screenTime
        let picked = ScreenTimeSlot.allCases.filter { service.hasApp(for: $0) }.map(\.app.displayName)
        Section {
            if service.isAuthorized {
                Toggle("track automatically", isOn: Binding(
                    get: { service.enabled },
                    set: { $0 ? service.enable() : service.disable() }
                ))
                NavigationLink {
                    ScrollView {
                        VStack(spacing: 16) {
                            ScreenTimeConnectCard()
                            Text("Screen Time tracks minutes for the apps you pick here. Pick only the app itself — not a whole category.")
                                .font(Theme.body(13, weight: .semibold))
                                .foregroundStyle(Theme.textDim)
                        }
                        .padding(20)
                    }
                    .screenBackground()
                    .navigationTitle("tracked apps")
                } label: {
                    LabeledContent("apps", value: picked.isEmpty ? "none yet" : picked.joined(separator: " + "))
                }
                NavigationLink {
                    ScrollView { ScrollStylePicker().padding(20) }
                        .screenBackground()
                        .navigationTitle("scroll style")
                } label: {
                    LabeledContent("scroll style", value: SharedSettings.shared.scrollStyle.title)
                }
                LabeledContent("pace", value: String(format: "%.1f reels/min · %@", model.pace(for: .instagram), model.paceSource.label))
                Button(model.paceSource == .guess ? "take the 30-sec pace test" : "redo the pace test") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .paceTest }
                }
                if model.paceSource != .guess {
                    Button("forget my measured pace") {
                        model.resetPace()
                        paceReset.toggle()
                    }
                }
            } else {
                ScreenTimeConnectCard(showsTikTok: false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        } header: {
            Text("auto mode (Screen Time)")
        } footer: {
            Text("iOS reports how many minutes Instagram/TikTok are open; Doomscore multiplies by your pace. Nothing on your screen is ever seen. Estimates show with ≈ — the pace test makes them much closer.")
        }
        .id(paceReset)
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
                Text("No diagnostics yet. Start exact mode and scroll a few reels.")
                    .foregroundStyle(Theme.textDim)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("detector lab")
        .task {
            while !Task.isCancelled {
                diagnostics = await Task.detached(priority: .utility) { SharedStore.shared.diagnostics }.value
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// The optional screen-broadcast counter, kept out of the way: nothing in
/// the app offers it except this page.
struct ExactModeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var strictMode = SharedSettings.shared.strictPrivacyMode
    @State private var autoPrompt = SharedSettings.shared.preciseAutoPrompt
    @State private var diagnostics = SharedSettings.shared.diagnosticsEnabled

    var body: some View {
        Form {
            Section {
                HStack {
                    Label(model.isArmed ? "exact mode is on" : "exact mode is off", systemImage: model.isArmed ? "record.circle.fill" : "record.circle")
                        .foregroundStyle(model.isArmed ? Theme.lime : Theme.textDim)
                    Spacer()
                    if model.isArmed {
                        Button("stop", role: .destructive) { model.stopCounting() }
                    } else {
                        Button("start") { router.sheet = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { router.sheet = .arm(auto: false, returnTo: nil) } }
                    }
                }
            } footer: {
                Text("Counts every single reel (skipping ads and rewatches) by analysing a screen broadcast on your phone. iOS shows its screen-broadcast prompt and a red pill while it runs. Nothing is recorded or uploaded. Auto mode never needs this.")
            }

            Section("exact mode counts these apps") {
                ForEach(SourceApp.tracked) { app in
                    Toggle(isOn: Binding(
                        get: { model.trackedApps.contains(app) },
                        set: { model.setTracked(app, enabled: $0) }
                    )) {
                        Label(app.displayName, systemImage: app.symbol)
                    }
                }
            }

            Section {
                Toggle("offer exact mode when I open a reels app", isOn: $autoPrompt)
                    .onChange(of: autoPrompt) { _, value in SharedSettings.shared.preciseAutoPrompt = value }
                Toggle("strict privacy mode", isOn: $strictMode)
                    .onChange(of: strictMode) { _, value in model.setStrictPrivacy(value) }
                Toggle("detector diagnostics", isOn: $diagnostics)
                    .onChange(of: diagnostics) { _, value in model.setDiagnostics(value) }
                if diagnostics {
                    NavigationLink("open detector lab") { DetectorLabView() }
                }
            } footer: {
                Text("Strict mode only analyses while a Shortcuts automation says a reels app is open. Diagnostics show detector decisions as numbers only.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("exact mode")
    }
}

/// Is iOS actually waking the Screen Time extension? Everything needed to
/// debug a count that won't move.
struct ScreenTimeDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var info: Info?

    struct Info: Sendable {
        var sharedContainer: Bool
        var state: ScreenTimeState?
        var callbacks: Int
        var lastCallbackAt: Date?
        var lastEvent: String?
        var lastOutcome: String?
    }

    var body: some View {
        let service = model.screenTime
        List {
            Section("setup") {
                LabeledContent("Screen Time access", value: "\(service.status)")
                LabeledContent("tracking switched on", value: service.enabled ? "yes" : "no")
                ForEach(ScreenTimeSlot.allCases) { slot in
                    LabeledContent(slot.app.displayName, value: service.hasApp(for: slot) ? "picked" : "not picked")
                }
                LabeledContent("shared storage", value: info.map { $0.sharedContainer ? "ok" : "MISSING (App Group)" } ?? "…")
                LabeledContent("iOS is monitoring", value: service.monitoredActivities.isEmpty ? "nothing" : service.monitoredActivities.joined(separator: ", "))
                if let error = service.lastError {
                    Text(error).foregroundStyle(Theme.orange)
                }
            }
            Section("extension") {
                LabeledContent("callbacks received", value: "\(info?.callbacks ?? 0)")
                LabeledContent("last callback", value: info?.lastCallbackAt.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "never")
                LabeledContent("last event", value: info?.lastEvent ?? "—")
                LabeledContent("last result", value: info?.lastOutcome ?? "—")
            }
            if let state = info?.state {
                Section("today") {
                    let today = state[DayKey.today()]
                    ForEach(ScreenTimeSlot.allCases) { slot in
                        let app = slot.app.rawValue
                        LabeledContent(slot.app.displayName, value: "\(today?.minutes[app] ?? 0) min · ≈\(Int((today?.estimatedReels[app] ?? 0).rounded())) reels")
                    }
                    ForEach(state.registrations.sorted { $0.key < $1.key }, id: \.key) { entry in
                        LabeledContent("counting \(entry.key) since", value: "\(entry.value.registeredAt.formatted(date: .omitted, time: .shortened)) (+\(entry.value.baselineMinutes) min)")
                    }
                    if let rearm = state.needsRearmSince {
                        LabeledContent("iOS fired early", value: rearm.formatted(date: .omitted, time: .shortened))
                    }
                }
            }
            Section {
                Button("restart tracking") {
                    service.ensureMonitoring(force: true)
                    Task { await load() }
                }
            } footer: {
                Text("Callbacks arrive after each full minute of use, sometimes a few minutes late. If \"callbacks received\" stays 0 after 3+ minutes in Instagram, iOS isn't waking the extension — rebuild the app and check the Screen Time App ID has Family Controls and App Groups.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .navigationTitle("Screen Time diagnostics")
        .task {
            service.refreshDiagnostics()
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func load() async {
        info = await Task.detached(priority: .utility) {
            let store = SharedStore.shared
            let settings = SharedSettings.shared
            return Info(
                sharedContainer: store.isSharedContainer,
                state: store.screenTime,
                callbacks: settings.monitorCallbacks,
                lastCallbackAt: settings.monitorLastCallbackAt,
                lastEvent: settings.monitorLastEvent,
                lastOutcome: settings.monitorLastOutcome
            )
        }.value
    }
}
