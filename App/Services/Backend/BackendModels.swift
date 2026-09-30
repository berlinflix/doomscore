import Foundation

enum BackendError: LocalizedError, Equatable {
    case notConfigured
    case notSignedIn
    case unauthorized
    case handleTaken
    case rateLimited
    case invalidInvite
    case ownInvite
    case profileRequired
    case network
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Battles aren't set up in this build yet."
        case .notSignedIn, .unauthorized: "You're signed out. Sign in to battle."
        case .handleTaken: "That handle is taken 😭 try another."
        case .rateLimited: "Slow down bestie — try again in a bit."
        case .invalidInvite: "That invite expired or doesn't exist."
        case .ownInvite: "That's your own invite link 💀"
        case .profileRequired: "Pick a handle first."
        case .network: "No connection. Check your internet."
        case .server(let message): message
        }
    }

    /// Maps PostgREST / GoTrue error bodies to friendly errors.
    static func from(status: Int, body: Data) -> BackendError {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let code = json?["code"] as? String ?? ""
        let message = (json?["message"] as? String) ?? (json?["msg"] as? String)
            ?? (json?["error_description"] as? String) ?? (json?["error"] as? String) ?? "Something broke (\(status))."
        if code == "23505" { return .handleTaken }
        if message.contains("rate_limited") || status == 429 { return .rateLimited }
        if message.contains("invite_self") { return .ownInvite }
        if message.contains("invite_invalid") { return .invalidInvite }
        if message.contains("profile_required") { return .profileRequired }
        if status == 401 || message.contains("not_authenticated") { return .unauthorized }
        return .server(message)
    }
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var handle: String
    var displayName: String
    var emoji: String
    var color: String
    var dailyGoal: Int

    enum CodingKeys: String, CodingKey {
        case id, handle, emoji, color
        case displayName = "display_name"
        case dailyGoal = "daily_goal"
    }
}

struct LeaderboardRow: Decodable, Identifiable, Hashable, Sendable {
    let userID: UUID
    let handle: String
    let displayName: String
    let emoji: String
    let color: String
    let reels: Int
    let isMe: Bool

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case handle, emoji, color, reels
        case userID = "user_id"
        case displayName = "display_name"
        case isMe = "is_me"
    }
}

struct InviteCode: Decodable, Sendable {
    let code: String
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case code = "invite_code"
        case expiresAt = "invite_expires_at"
    }
}

struct AcceptedInvite: Decodable, Sendable {
    let friendID: UUID
    let handle: String
    let displayName: String
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case friendID = "friend_id"
        case handle = "friend_handle"
        case displayName = "friend_display_name"
        case emoji = "friend_emoji"
    }
}

/// Handle rules shared with the database CHECK constraint.
enum HandleRules {
    static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" || $0 == "." }
    }

    static func isValid(_ handle: String) -> Bool {
        (3...20).contains(handle.count) && handle == normalize(handle)
    }

    static func suggestion() -> String {
        let adjectives = ["feral", "sleepy", "chronically", "unhinged", "lowkey", "certified", "delulu", "cozy", "chaotic", "sigma"]
        let nouns = ["goblin", "doomer", "scroller", "gremlin", "npc", "raccoon", "menace", "bean", "froggy", "potato"]
        return "\(adjectives.randomElement()!).\(nouns.randomElement()!)\(Int.random(in: 1...99))"
    }
}
