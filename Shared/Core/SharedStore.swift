import Foundation

/// File-based store in the App Group container, shared by the app, the widget
/// extension, the Screen Time monitor and the broadcast extension. Every access goes through
/// `NSFileCoordinator` and writes are atomic, so a process being killed
/// mid-write can never corrupt history.
final class SharedStore: @unchecked Sendable {
    static let shared = SharedStore()

    enum File: String, CaseIterable {
        case ledger = "ledger.json"
        case live = "live.json"
        case hint = "foreground-hint.json"
        case leaderboard = "leaderboard-cache.json"
        case detectorConfig = "detector-config.json"
        case diagnostics = "diagnostics.json"
        case seenReels = "seen-reels.json"
        case screenTime = "screen-time.json"
        case screenTimeSelections = "screen-time-selections.json"
    }

    let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupID) {
            self.directory = group.appendingPathComponent("Doomscore", isDirectory: true)
        } else {
            // Unit tests / misconfigured entitlements: fall back to a private folder.
            self.directory = FileManager.default.temporaryDirectory.appendingPathComponent("Doomscore", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: self.directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
    }

    func url(for file: File) -> URL { directory.appendingPathComponent(file.rawValue) }

    // MARK: Generic access

    func read<T: Decodable>(_ type: T.Type, from file: File) -> T? {
        var result: T?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url(for: file), options: [], error: &coordinationError) { url in
            guard let data = try? Data(contentsOf: url) else { return }
            result = try? JSONCoding.decoder.decode(T.self, from: data)
        }
        return result
    }

    func write<T: Encodable>(_ value: T, to file: File) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url(for: file), options: .forReplacing, error: &coordinationError) { url in
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Coordinated read-modify-write.
    func update<T: Codable>(_ type: T.Type, in file: File, default makeDefault: () -> T, _ body: (inout T) -> Void) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url(for: file), options: .forMerging, error: &coordinationError) { url in
            var value = (try? Data(contentsOf: url)).flatMap { try? JSONCoding.decoder.decode(T.self, from: $0) } ?? makeDefault()
            body(&value)
            if let data = try? JSONCoding.encoder.encode(value) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    /// Cheap change check (no decoding).
    func modificationDate(of file: File) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url(for: file).path))?[.modificationDate] as? Date
    }

    func remove(_ file: File) {
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url(for: file), options: .forDeleting, error: &coordinationError) { url in
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Wipes history. The Screen Time app picks survive (they're settings).
    func removeAll() { File.allCases.filter { $0 != .screenTimeSelections }.forEach(remove) }

    // MARK: Convenience

    var ledger: Ledger { read(Ledger.self, from: .ledger) ?? Ledger() }
    var live: LiveState? { read(LiveState.self, from: .live) }
    var hint: ForegroundHint? { read(ForegroundHint.self, from: .hint) }
    var leaderboard: CachedLeaderboard? { read(CachedLeaderboard.self, from: .leaderboard) }
    var diagnostics: DetectorDiagnostics? { read(DetectorDiagnostics.self, from: .diagnostics) }
    var screenTime: ScreenTimeState? { read(ScreenTimeState.self, from: .screenTime) }

    /// Exact (precise-mode) history with the broadcast extension's in-flight
    /// "today" merged in. The live file is written every few hundred ms while
    /// the ledger is flushed less often.
    func exactLedger() -> Ledger {
        var ledger = self.ledger
        if let live {
            let key = live.today.day
            if let stored = ledger[key] {
                if live.today.updatedAt >= stored.updatedAt { ledger[key] = live.today }
            } else {
                ledger[key] = live.today
            }
        }
        return ledger
    }

    /// Everything the user sees: exact counts plus Screen Time estimates.
    func mergedLedger() -> Ledger {
        var ledger = exactLedger()
        guard let screenTime else { return ledger }
        for day in screenTime.days.values {
            ledger[day.day] = day.merged(into: ledger[day.day] ?? DayRecord(day: day.day))
        }
        return ledger
    }

    /// An exact record with that day's Screen Time estimate added.
    func effective(_ exact: DayRecord) -> DayRecord {
        guard let day = screenTime?[exact.day] else { return exact }
        return day.merged(into: exact)
    }

    /// Today's exact (precise-mode only) record.
    func exactTodayRecord(now: Date = Date()) -> DayRecord {
        let key = DayKey(now)
        return exactLedger()[key] ?? DayRecord(day: key)
    }

    /// Today's record as shown to the user (empty if nothing counted yet).
    func todayRecord(now: Date = Date()) -> DayRecord {
        let key = DayKey(now)
        return mergedLedger()[key] ?? DayRecord(day: key)
    }

    /// Whether the broadcast extension is running right now.
    func isArmed(now: Date = Date()) -> Bool { live?.isArmed(now: now) ?? false }
}
