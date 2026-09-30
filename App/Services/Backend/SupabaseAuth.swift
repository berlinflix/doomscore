import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var isAnonymous: Bool
}

/// Minimal Supabase Auth (GoTrue) client over plain HTTPS — no SDK.
/// Sessions live in the app-private Keychain; refreshes are single-flight so
/// concurrent requests never burn the rotating refresh token twice.
actor SupabaseAuth {
    static let shared = SupabaseAuth()

    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?
    private let http: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        http = URLSession(configuration: configuration)
        if let data = Keychain.data(for: .authSession, shared: false),
           let stored = try? JSONCoding.decoder.decode(AuthSession.self, from: data) {
            session = stored
        }
    }

    var currentSession: AuthSession? { session }
    var isSignedIn: Bool { session != nil }

    /// A non-expired access token, refreshing if needed.
    func accessToken() async throws -> String {
        guard let session else { throw BackendError.notSignedIn }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = session?.refreshToken else { throw BackendError.notSignedIn }
        let task = Task { try await self.requestToken(grant: "refresh_token", body: ["refresh_token": refreshToken]) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            store(fresh)
            return fresh
        } catch BackendError.unauthorized {
            clear()
            throw BackendError.notSignedIn
        }
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws -> AuthSession {
        let fresh = try await requestToken(grant: "id_token", body: [
            "provider": "apple",
            "id_token": idToken,
            "nonce": rawNonce,
        ])
        store(fresh)
        return fresh
    }

    /// Requires "Anonymous sign-ins" enabled in your Supabase Auth settings.
    func signInAnonymously() async throws -> AuthSession {
        let request = try makeRequest(path: "auth/v1/signup", query: [], body: ["data": [String: String]()])
        let fresh = try await send(request)
        store(fresh)
        return fresh
    }

    func signOut() async {
        if let token = session?.accessToken, var request = try? makeRequest(path: "auth/v1/logout", query: [], body: [:]) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await http.data(for: request)
        }
        clear()
    }

    func clear() {
        session = nil
        Keychain.remove(.authSession, shared: false)
    }

    // MARK: Internals

    private func store(_ fresh: AuthSession) {
        session = fresh
        if let data = try? JSONCoding.encoder.encode(fresh) {
            Keychain.set(data, for: .authSession, shared: false)
        }
    }

    private func requestToken(grant: String, body: [String: Any]) async throws -> AuthSession {
        let request = try makeRequest(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)], body: body)
        return try await send(request)
    }

    private func makeRequest(path: String, query: [URLQueryItem], body: [String: Any]) throws -> URLRequest {
        guard let base = AppEnvironment.supabaseURL, let key = AppEnvironment.supabaseAnonKey else {
            throw BackendError.notConfigured
        }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw BackendError.notConfigured }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private struct TokenResponse: Decodable {
        struct User: Decodable {
            let id: String
            let is_anonymous: Bool?
        }
        let access_token: String
        let refresh_token: String
        let expires_in: Double?
        let expires_at: Double?
        let user: User
    }

    private func send(_ request: URLRequest) async throws -> AuthSession {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw BackendError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 400 || status == 401 || status == 403 {
                let mapped = BackendError.from(status: status, body: data)
                if case .server = mapped, request.url?.query?.contains("refresh_token") == true { throw BackendError.unauthorized }
                throw mapped
            }
            throw BackendError.from(status: status, body: data)
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiry: Date
        if let at = token.expires_at {
            expiry = Date(timeIntervalSince1970: at)
        } else {
            expiry = Date().addingTimeInterval(token.expires_in ?? 3600)
        }
        return AuthSession(
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: expiry,
            userID: token.user.id,
            isAnonymous: token.user.is_anonymous ?? false
        )
    }
}
