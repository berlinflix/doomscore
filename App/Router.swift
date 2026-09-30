import Foundation
import Observation

/// Navigation state + deep links:
///  doomscore://arm?auto=1&return=instagram   → arm sheet (auto-opens the system picker, bounces back)
///  doomscore://invite/CODE  or  https://<domain>/i/CODE → accept a battle invite
///  doomscore://battle | stats | today | settings | setup | wrapped?period=week
@MainActor
@Observable
final class Router {
    enum Tab: Hashable { case today, battle, stats }

    enum Sheet: Identifiable {
        case arm(auto: Bool, returnTo: SourceApp?)
        case settings
        case setupGuide
        case joinBattle
        case invite(code: String)

        var id: String {
            switch self {
            case .arm: "arm"
            case .settings: "settings"
            case .setupGuide: "setup"
            case .joinBattle: "join"
            case .invite(let code): "invite-\(code)"
            }
        }
    }

    struct WrappedRequest: Identifiable {
        let id = UUID()
        let period: StatsPeriod
        let anchor: Date
    }

    var tab: Tab = .today
    var sheet: Sheet?
    var wrapped: WrappedRequest?
    var showOnboarding = false

    /// Route strings stored by extensions/notifications, e.g. "arm?auto=1".
    func open(route: String) {
        if let url = URL(string: "\(AppEnvironment.urlScheme)://\(route)") { handle(url: url) }
    }

    @discardableResult
    func handle(url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme == AppEnvironment.urlScheme, let host = url.host, !host.isEmpty {
            parts.insert(host, at: 0)
        }
        guard let first = parts.first?.lowercased() else { return false }

        switch first {
        case "arm":
            let returnTo = query["return"].flatMap(SourceApp.init(rawValue:))
            sheet = .arm(auto: query["auto"] == "1", returnTo: returnTo)
        case "today":
            tab = .today
        case "battle":
            tab = .battle
        case "stats":
            tab = .stats
        case "settings":
            sheet = .settings
        case "setup":
            sheet = .setupGuide
        case "wrapped":
            let period = query["period"].flatMap(StatsPeriod.init(rawValue:)) ?? .week
            wrapped = WrappedRequest(period: period, anchor: Date())
        case "invite", "i":
            guard parts.count > 1 else { return false }
            let code = parts[1].uppercased().filter { $0.isLetter || $0.isNumber }
            guard (6...16).contains(code.count) else { return false }
            tab = .battle
            sheet = .invite(code: code)
        default:
            return false
        }
        return true
    }
}
