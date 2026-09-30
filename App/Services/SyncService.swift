import Foundation
import UIKit

/// Keeps the backend in sync with local counts. Local data is the source of
/// truth; the server only ever receives per-day aggregates.
actor SyncService {
    static let shared = SyncService()

    private var registering = false
    private var lastPush = Date.distantPast

    private struct RegisterParams: Encodable { let p_label: String }

    /// Gets a scoped device token (used by the broadcast extension to upload
    /// counts without holding the user's session).
    func registerDeviceIfNeeded(force: Bool = false) async {
        guard AppEnvironment.isBackendConfigured, await SupabaseAuth.shared.isSignedIn else { return }
        if !force, Keychain.string(for: .deviceToken, shared: true) != nil { return }
        guard !registering else { return }
        registering = true
        defer { registering = false }
        do {
            let label = await MainActor.run { UIDevice.current.model }
            let token = try await SupabaseAPI.shared.rpc("register_device", params: RegisterParams(p_label: label), as: String.self)
            Keychain.setString(token, for: .deviceToken, shared: true)
            SharedSettings.shared.deviceRegisteredAt = Date()
            Log.sync.info("device registered")
            await pushRecentDays(force: true)
            await LiveActivityService.shared.reuploadTokens()
        } catch {
            Log.sync.error("device registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-sends the last three days (idempotent absolute totals).
    func pushRecentDays(force: Bool = false) async {
        let client = IngestClient.shared
        guard client.isReady else { return }
        guard force || Date().timeIntervalSince(lastPush) > 60 else { return }
        lastPush = Date()
        let ledger = SharedStore.shared.mergedLedger()
        let today = DayKey.today()
        for offset in 0..<3 {
            let key = today.adding(days: -offset)
            guard let record = ledger[key], record.total > 0 || record.watchSeconds > 0 else { continue }
            do {
                try await client.send(IngestPayload.make(for: record, live: nil))
            } catch {
                Log.sync.error("sync failed for a day: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
