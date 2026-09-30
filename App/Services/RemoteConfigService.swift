import Foundation

/// Pulls detector overrides (keywords, zones, thresholds) from
/// `DS_REMOTE_CONFIG_URL` so detection can be fixed without an app update when
/// a reels app changes its UI. The JSON may be partial — it's deep-merged over
/// the built-in defaults and validated before the extension sees it.
enum RemoteConfigService {
    private static let lastFetchKey = "remoteConfigFetchedAt"

    static func refreshIfNeeded(force: Bool = false) async {
        guard let url = AppEnvironment.remoteConfigURL else { return }
        let defaults = SharedSettings.shared.defaults
        if !force, let last = defaults.object(forKey: lastFetchKey) as? Date, Date().timeIntervalSince(last) < 6 * 3600 { return }
        defaults.set(Date(), forKey: lastFetchKey)

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 256_000,
              let config = merged(over: DetectorConfig(), with: data) else { return }

        SharedStore.shared.write(config, to: .detectorConfig)
        DarwinCenter.shared.post(DarwinName.settingsChanged)
        Log.app.info("detector config updated")
    }

    static func merged(over base: DetectorConfig, with patchData: Data) -> DetectorConfig? {
        guard let baseData = try? JSONEncoder().encode(base),
              let baseObject = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any],
              let patch = try? JSONSerialization.jsonObject(with: patchData) as? [String: Any] else { return nil }
        let combined = deepMerge(baseObject, patch)
        guard let combinedData = try? JSONSerialization.data(withJSONObject: combined),
              let config = try? JSONDecoder().decode(DetectorConfig.self, from: combinedData),
              config.version == DetectorConfig.currentVersion else { return nil }
        return config
    }

    private static func deepMerge(_ base: [String: Any], _ patch: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in patch {
            if let nested = value as? [String: Any], let existing = result[key] as? [String: Any] {
                result[key] = deepMerge(existing, nested)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
