import Foundation
import Observation
import WidgetKit

/// Scroll Battle state: auth, profile, friends leaderboard, invites.
@MainActor
@Observable
final class BattleStore {
    enum Phase: Equatable {
        case idle, loading, notConfigured, signedOut, needsProfile, ready
        case failed(String)
    }

    enum Period: String, CaseIterable, Identifiable {
        case day, week
        var id: String { rawValue }
        var title: String { self == .day ? "today" : "this week" }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case mostCooked, touchGrass
        var id: String { rawValue }
        var title: String { self == .mostCooked ? "most cooked 🔥" : "touch grass 🌱" }
    }

    private(set) var phase: Phase = .idle
    private(set) var profile: Profile?
    private(set) var rows: [LeaderboardRow] = []
    private(set) var lastUpdated: Date?
    var period: Period = .day
    var mode: Mode = .mostCooked
    /// Invite opened before the user had a profile; accepted after onboarding.
    var pendingInviteCode: String?

    private let api = SupabaseAPI.shared
    private let auth = SupabaseAuth.shared

    var sortedRows: [LeaderboardRow] {
        switch mode {
        case .mostCooked: rows.sorted { $0.reels == $1.reels ? $0.handle < $1.handle : $0.reels > $1.reels }
        case .touchGrass: rows.sorted { $0.reels == $1.reels ? $0.handle < $1.handle : $0.reels < $1.reels }
        }
    }

    var friendCount: Int { rows.filter { !$0.isMe }.count }

    // MARK: Lifecycle

    func bootstrapIfNeeded() async {
        switch phase {
        case .idle, .failed: await bootstrap()
        case .ready: await refresh()
        default: break
        }
    }

    func bootstrap() async {
        guard AppEnvironment.isBackendConfigured else { phase = .notConfigured; return }
        guard let session = await auth.currentSession else { phase = .signedOut; return }
        if phase != .ready { phase = .loading }
        do {
            profile = try await api.fetchProfile(id: session.userID)
            guard profile != nil else { phase = .needsProfile; return }
            await SyncService.shared.registerDeviceIfNeeded()
            try await loadLeaderboard()
            phase = .ready
            if let code = pendingInviteCode {
                pendingInviteCode = nil
                _ = try? await accept(code: code)
            }
        } catch BackendError.notSignedIn {
            phase = .signedOut
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        guard phase == .ready else { await bootstrap(); return }
        do { try await loadLeaderboard() } catch { /* keep showing cached rows */ }
    }

    /// Background refresh path (keeps the battle widget fresh).
    func refreshForWidget() async {
        guard AppEnvironment.isBackendConfigured, await auth.isSignedIn else { return }
        try? await loadLeaderboard()
    }

    private struct LeaderboardParams: Encodable {
        let p_period: String
        let p_day: String
    }

    private func loadLeaderboard() async throws {
        let result = try await api.rpc(
            "get_leaderboard",
            params: LeaderboardParams(p_period: period.rawValue, p_day: DayKey.today().rawValue),
            as: [LeaderboardRow].self
        )
        rows = result
        lastUpdated = Date()
        if period == .day { cacheForWidget(result) }
    }

    private func cacheForWidget(_ rows: [LeaderboardRow]) {
        let top = rows.sorted { $0.reels > $1.reels }.prefix(5).map {
            CachedLeaderboard.Row(name: $0.displayName, emoji: $0.emoji, colorHex: $0.color, reels: $0.reels, isMe: $0.isMe)
        }
        SharedStore.shared.write(CachedLeaderboard(day: DayKey.today(), rows: Array(top), updatedAt: Date()), to: .leaderboard)
        WidgetCenter.shared.reloadTimelines(ofKind: "DoomBattle")
    }

    // MARK: Auth

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        _ = try await auth.signInWithApple(idToken: idToken, rawNonce: rawNonce)
        await bootstrap()
    }

    func startAnonymously() async throws {
        _ = try await auth.signInAnonymously()
        await bootstrap()
    }

    func signOut() async {
        await auth.signOut()
        Keychain.remove(.deviceToken, shared: true)
        SharedStore.shared.remove(.leaderboard)
        profile = nil
        rows = []
        phase = AppEnvironment.isBackendConfigured ? .signedOut : .notConfigured
    }

    func deleteAccount() async throws {
        try await api.rpc("delete_account")
        await signOut()
    }

    // MARK: Profile

    func saveProfile(handle: String, displayName: String, emoji: String, color: String) async throws {
        guard let session = await auth.currentSession, let id = UUID(uuidString: session.userID) else {
            throw BackendError.notSignedIn
        }
        let normalized = HandleRules.normalize(handle)
        guard HandleRules.isValid(normalized) else {
            throw BackendError.server("Handles are 3–20 characters: letters, numbers, . and _")
        }
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = Profile(
            id: id,
            handle: normalized,
            displayName: String((trimmedName.isEmpty ? normalized : trimmedName).prefix(30)),
            emoji: emoji,
            color: color,
            dailyGoal: SharedSettings.shared.dailyGoal
        )
        profile = try await api.upsertProfile(draft)
        await SyncService.shared.registerDeviceIfNeeded(force: true)
        try? await loadLeaderboard()
        phase = .ready
        if let code = pendingInviteCode {
            pendingInviteCode = nil
            _ = try? await accept(code: code)
        }
    }

    func updateGoal(_ goal: Int) async {
        guard var current = profile, phase == .ready else { return }
        current.dailyGoal = goal
        if let saved = try? await api.upsertProfile(current) { profile = saved }
    }

    // MARK: Friends

    func inviteURL() async throws -> URL {
        let codes = try await api.rpc("create_invite", params: [String: String](), as: [InviteCode].self)
        guard let code = codes.first?.code else { throw BackendError.server("Couldn't create an invite.") }
        if let base = AppEnvironment.inviteBaseURL { return base.appendingPathComponent(code) }
        return URL(string: "\(AppEnvironment.urlScheme)://invite/\(code)")!
    }

    private struct AcceptParams: Encodable { let p_code: String }
    private struct RemoveParams: Encodable { let p_friend: UUID }

    @discardableResult
    func accept(code: String) async throws -> AcceptedInvite {
        guard phase == .ready else {
            pendingInviteCode = code
            throw BackendError.profileRequired
        }
        let result = try await api.rpc("accept_invite", params: AcceptParams(p_code: code), as: [AcceptedInvite].self)
        guard let friend = result.first else { throw BackendError.invalidInvite }
        try? await loadLeaderboard()
        return friend
    }

    func removeFriend(_ id: UUID) async throws {
        try await api.rpc("remove_friend", params: RemoveParams(p_friend: id))
        rows.removeAll { $0.userID == id }
    }
}
