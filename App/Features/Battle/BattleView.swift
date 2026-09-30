import SwiftUI

struct BattleView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(BattleStore.self) private var battle
    @State private var shareItem: ShareItem?
    @State private var inviteError: String?
    @State private var isCreatingInvite = false

    private let invitePrompts: [(emoji: String, text: String)] = [
        ("💔", "your situationship"),
        ("📱", "the group chat menace"),
        ("🫶", "your bestie who sends 40 reels a day"),
        ("🏋️", "your gym bro who \"doesn't use reels\""),
        ("🧟", "that one friend who's always online"),
    ]

    var body: some View {
        @Bindable var battle = battle
        ScrollView {
            VStack(spacing: 16) {
                header
                switch battle.phase {
                case .notConfigured:
                    offlineCard
                case .signedOut:
                    joinCard
                case .needsProfile:
                    ProfileEditorCard()
                case .idle, .loading:
                    ProgressView().tint(Theme.lime).padding(.top, 60)
                case .failed(let message):
                    failedCard(message)
                case .ready:
                    controls(battle: $battle.period, mode: $battle.mode)
                    podium
                    leaderboard
                    invites
                }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .refreshable { await battle.refresh() }
        .task(id: battle.period) { await battle.bootstrapIfNeeded() }
        .task {
            // Poll while visible so the board feels live.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await battle.refresh()
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [inviteMessage(item.url)])
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("scroll battle ⚔️")
                    .font(Theme.display(28))
                    .foregroundStyle(Theme.text)
                Text(battle.phase == .ready ? "\(battle.friendCount) friends · who's the most cooked?" : "compete with friends. loser touches grass.")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if battle.phase == .ready {
                Button { Task { await createInvite() } } label: {
                    Image(systemName: isCreatingInvite ? "hourglass" : "person.badge.plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Theme.brand))
                }
                .accessibilityLabel("Invite friends")
            }
        }
    }

    private func controls(battle period: Binding<BattleStore.Period>, mode: Binding<BattleStore.Mode>) -> some View {
        VStack(spacing: 10) {
            Picker("Period", selection: period) {
                ForEach(BattleStore.Period.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Mode", selection: mode) {
                ForEach(BattleStore.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var podium: some View {
        let top = Array(battle.sortedRows.prefix(3))
        return HStack(alignment: .bottom, spacing: 10) {
            if top.count > 1 { podiumColumn(top[1], place: 2, height: 90) }
            if let first = top.first { podiumColumn(first, place: 1, height: 125) }
            if top.count > 2 { podiumColumn(top[2], place: 3, height: 70) }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: battle.sortedRows)
    }

    private func podiumColumn(_ row: LeaderboardRow, place: Int, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                Avatar(emoji: row.emoji, colorHex: row.color, size: place == 1 ? 64 : 52)
                if place == 1 {
                    Text(battle.mode == .mostCooked ? "👑" : "🌱")
                        .font(.system(size: 26))
                        .offset(y: -26)
                }
            }
            Text(row.isMe ? "you" : row.displayName)
                .font(Theme.body(13, weight: .heavy))
                .foregroundStyle(row.isMe ? Theme.lime : Theme.text)
                .lineLimit(1)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(place == 1 ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Theme.surfaceHigh))
                .frame(height: height)
                .overlay(
                    VStack(spacing: 2) {
                        Text("\(place)").font(Theme.display(26))
                        Text(Fmt.compact(row.reels)).font(Theme.body(13, weight: .heavy))
                    }
                    .foregroundStyle(place == 1 ? .black : Theme.text)
                )
        }
        .frame(maxWidth: .infinity)
    }

    private var leaderboard: some View {
        Card(padding: 8) {
            VStack(spacing: 0) {
                ForEach(Array(battle.sortedRows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(Theme.body(15, weight: .black))
                            .foregroundStyle(Theme.textFaint)
                            .frame(width: 24)
                        Avatar(emoji: row.emoji, colorHex: row.color, size: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.isMe ? "\(row.displayName) (you)" : row.displayName)
                                .font(Theme.body(15, weight: .heavy))
                                .foregroundStyle(row.isMe ? Theme.lime : Theme.text)
                            Text("@\(row.handle)")
                                .font(Theme.body(12, weight: .semibold))
                                .foregroundStyle(Theme.textFaint)
                        }
                        Spacer()
                        Text(Fmt.compact(row.reels))
                            .font(Theme.display(20))
                            .foregroundStyle(Mood.from(count: row.reels, goal: model.goal).tint)
                            .contentTransition(.numericText(value: Double(row.reels)))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                    .background(row.isMe ? RoundedRectangle(cornerRadius: 16).fill(Theme.lime.opacity(0.08)) : nil)
                    .contextMenu {
                        if !row.isMe {
                            Button("Remove friend", systemImage: "person.fill.xmark", role: .destructive) {
                                Task { try? await battle.removeFriend(row.userID) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var invites: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "add to the battle")
            ForEach(Array(invitePrompts.prefix(max(1, 5 - battle.friendCount)).enumerated()), id: \.offset) { _, prompt in
                Button { Task { await createInvite() } } label: {
                    HStack(spacing: 12) {
                        Text(prompt.emoji).font(.system(size: 24))
                        Text("invite \(prompt.text)")
                            .font(Theme.body(15, weight: .bold))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Text("invite")
                            .font(Theme.body(13, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.brand))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
                }
                .buttonStyle(PressableStyle())
            }
            if let inviteError {
                Text(inviteError).font(Theme.body(13)).foregroundStyle(Theme.red)
            }
        }
    }

    private var offlineCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("battles are offline 🔌").font(Theme.body(18, weight: .black)).foregroundStyle(Theme.text)
                Text("This build isn't connected to a backend yet. Counting, widgets and recaps still work. (Dev: set DS_SUPABASE_URL / DS_SUPABASE_ANON_KEY — see backend/README.md.)")
                    .font(Theme.body(14, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private var joinCard: some View {
        VStack(spacing: 16) {
            GoobView(mood: .kindaCooked, size: 130)
            Text("who scrolls the most? 👀")
                .font(Theme.display(26))
                .foregroundStyle(Theme.text)
            Text("battle your friends daily. only your reel count is shared — never what you watched.")
                .font(Theme.body(15, weight: .semibold))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Button("join the battle") { router.sheet = .joinBattle }
                .buttonStyle(ChunkyButtonStyle())
        }
        .padding(.top, 20)
    }

    private func failedCard(_ message: String) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("couldn't load the battle 😵‍💫").font(Theme.body(17, weight: .black)).foregroundStyle(Theme.text)
                Text(message).font(Theme.body(14)).foregroundStyle(Theme.textDim)
                Button("try again") { Task { await battle.bootstrap() } }
                    .buttonStyle(GhostButtonStyle())
            }
        }
    }

    // MARK: Invites

    private func createInvite() async {
        guard !isCreatingInvite else { return }
        isCreatingInvite = true
        defer { isCreatingInvite = false }
        do {
            let url = try await battle.inviteURL()
            shareItem = ShareItem(url: url)
            inviteError = nil
        } catch {
            inviteError = error.localizedDescription
        }
    }

    private func inviteMessage(_ url: URL) -> String {
        "i'm getting cooked by reels today (\(model.today.total) and counting 🍳). think you scroll less? battle me on Doomscore → \(url.absoluteString)"
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet (ShareLink can't be triggered programmatically).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
