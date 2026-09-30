import Foundation

/// PostgREST calls against your own Supabase project. Row-Level Security on
/// the server decides what each user can read/write; the client just sends
/// the user's JWT.
struct SupabaseAPI: Sendable {
    static let shared = SupabaseAPI()

    private let http: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    private struct Empty: Encodable {}

    // MARK: RPC

    func rpc<Result: Decodable>(_ function: String, params: some Encodable, as type: Result.Type) async throws -> Result {
        let data = try await perform(path: "rest/v1/rpc/\(function)", method: "POST", body: try JSONEncoder().encode(params))
        do {
            return try JSONDecoder().decode(Result.self, from: data)
        } catch {
            throw BackendError.server("Unexpected response from \(function).")
        }
    }

    func rpc(_ function: String, params: some Encodable) async throws {
        _ = try await perform(path: "rest/v1/rpc/\(function)", method: "POST", body: try JSONEncoder().encode(params))
    }

    func rpc(_ function: String) async throws {
        try await rpc(function, params: Empty())
    }

    // MARK: Profiles

    func fetchProfile(id: String) async throws -> Profile? {
        let data = try await perform(
            path: "rest/v1/profiles",
            method: "GET",
            query: [
                URLQueryItem(name: "id", value: "eq.\(id)"),
                URLQueryItem(name: "select", value: "id,handle,display_name,emoji,color,daily_goal"),
            ]
        )
        return try JSONDecoder().decode([Profile].self, from: data).first
    }

    func upsertProfile(_ profile: Profile) async throws -> Profile {
        let data = try await perform(
            path: "rest/v1/profiles",
            method: "POST",
            query: [URLQueryItem(name: "on_conflict", value: "id")],
            body: try JSONEncoder().encode(profile),
            prefer: "resolution=merge-duplicates,return=representation"
        )
        guard let saved = try JSONDecoder().decode([Profile].self, from: data).first else {
            throw BackendError.server("Couldn't save your profile.")
        }
        return saved
    }

    // MARK: Transport

    private func perform(
        path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        prefer: String? = nil,
        isRetry: Bool = false
    ) async throws -> Data {
        guard let base = AppEnvironment.supabaseURL, let key = AppEnvironment.supabaseAnonKey else {
            throw BackendError.notConfigured
        }
        let token = try await SupabaseAuth.shared.accessToken()
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw BackendError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await http.data(for: request)
        } catch {
            throw BackendError.network
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, !isRetry {
            try await SupabaseAuth.shared.refresh()
            return try await perform(path: path, method: method, query: query, body: body, prefer: prefer, isRetry: true)
        }
        guard (200..<300).contains(status) else { throw BackendError.from(status: status, body: data) }
        return data
    }
}
