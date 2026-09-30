import Foundation

/// Payload for the `ingest` Edge Function. Totals are absolute (not deltas),
/// so retries and duplicate sends are idempotent.
struct IngestPayload: Encodable, Sendable {
    struct AppTotal: Encodable, Sendable {
        let app: String
        let reels: Int
        let watchSeconds: Int
        let adsSkipped: Int
    }

    /// Data mirrored to the user's Live Activity through APNs.
    struct Live: Encodable, Sendable {
        let todayCount: Int
        let sessionCount: Int
        let goal: Int
        let armed: Bool
        let appName: String
        let sessionStarted: Bool
    }

    let day: String
    let tzOffsetMinutes: Int
    let apps: [AppTotal]
    let live: Live?
    let clientTime: Double
    let appVersion: String

    static func make(for record: DayRecord, live: Live?) -> IngestPayload {
        let apps = SourceApp.allCases.compactMap { app -> AppTotal? in
            let reels = record.count(for: app)
            let seconds = record.seconds(for: app)
            guard reels > 0 || seconds > 0 else { return nil }
            // Ads are tracked per day; attribute them to the top app.
            let ads = app == (record.topApp ?? .instagram) ? record.adsSkipped : 0
            return AppTotal(app: app.rawValue, reels: reels, watchSeconds: Int(seconds.rounded()), adsSkipped: ads)
        }
        return IngestPayload(
            day: record.day.rawValue,
            tzOffsetMinutes: TimeZone.current.secondsFromGMT() / 60,
            apps: apps,
            live: live,
            clientTime: Date().timeIntervalSince1970,
            appVersion: AppEnvironment.appVersion
        )
    }
}

enum IngestError: Error {
    case notConfigured
    case http(Int)
}

/// Lightweight client used by the broadcast extension and the app. It
/// authenticates with a scoped, revocable device token (not the user's
/// session), so the extension never touches refresh tokens.
final class IngestClient: @unchecked Sendable {
    static let shared = IngestClient()

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Doomscore/\(AppEnvironment.appVersion)"]
        session = URLSession(configuration: configuration)
    }

    var deviceToken: String? { Keychain.string(for: .deviceToken, shared: true) }

    var isReady: Bool { AppEnvironment.isBackendConfigured && deviceToken != nil }

    private func makeRequest(path: String, method: String, body: Data?) throws -> URLRequest {
        guard let base = AppEnvironment.supabaseURL, let key = AppEnvironment.supabaseAnonKey, let token = deviceToken else {
            throw IngestError.notConfigured
        }
        var request = URLRequest(url: base.appendingPathComponent("functions/v1/\(path)"))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue(token, forHTTPHeaderField: "x-device-token")
        request.httpBody = body
        return request
    }

    func send(_ payload: IngestPayload) async throws {
        let body = try JSONEncoder().encode(payload)
        let request = try makeRequest(path: "ingest", method: "POST", body: body)
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw IngestError.http(status) }
    }

    /// Best-effort synchronous send for `broadcastFinished`, where the process
    /// may be torn down right after returning.
    func sendBlocking(_ payload: IngestPayload, timeout: TimeInterval = 2) {
        guard let body = try? JSONEncoder().encode(payload),
              let request = try? makeRequest(path: "ingest", method: "POST", body: body) else { return }
        let semaphore = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { _, _, _ in semaphore.signal() }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
    }

    enum ActivityTokenKind: String { case update, start }

    /// Registers a Live Activity push token (update or push-to-start).
    func registerActivityToken(_ token: String, kind: ActivityTokenKind) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "token": token,
            "kind": kind.rawValue,
            "env": AppEnvironment.apnsEnvironment,
        ])
        let request = try makeRequest(path: "activity", method: "POST", body: body)
        let (_, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw IngestError.http(status) }
    }

    func unregisterActivityToken(_ token: String) async {
        guard let body = try? JSONSerialization.data(withJSONObject: ["token": token]),
              let request = try? makeRequest(path: "activity", method: "DELETE", body: body) else { return }
        _ = try? await session.data(for: request)
    }
}
