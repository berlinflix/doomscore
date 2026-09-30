import Foundation

/// Build-time configuration injected through each target's Info.plist
/// (values come from Config/Base.xcconfig via project.yml).
enum AppEnvironment {
    private static func string(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Treat untouched template placeholders as "not configured".
        if value.isEmpty || value.hasPrefix("YOUR_") || value.contains("YOUR-") || value.hasPrefix("$(") {
            return nil
        }
        return value
    }

    static let appGroupID: String = string("DSAppGroupID") ?? "group.com.yourcompany.doomscore"
    static let broadcastExtensionID: String? = string("DSBroadcastExtensionID")
    static let supabaseURL: URL? = string("DSSupabaseURL").flatMap(URL.init(string:))
    static let supabaseAnonKey: String? = string("DSSupabaseAnonKey")
    static let inviteBaseURL: URL? = string("DSInviteBaseURL").flatMap(URL.init(string:))
    static let remoteConfigURL: URL? = string("DSRemoteConfigURL").flatMap(URL.init(string:))

    static let urlScheme = "doomscore"

    static var isBackendConfigured: Bool { supabaseURL != nil && supabaseAnonKey != nil }

    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    /// APNs environment the build talks to. Debug builds use the sandbox;
    /// TestFlight and App Store builds use production.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
