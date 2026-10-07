import Foundation

/// File-based store in the App Group container, shared by the app, the widget
/// extension, the Screen Time monitor and the broadcast extension. Writes are
/// atomic (temp file + rename) and go through `NSFileCoordinator`, so a
/// process killed mid-write can never corrupt history. Reads skip the
/// coordinator: an atomic rename means a reader always sees a whole file, and
/// coordinated reads could stall the main thread behind another process's write.
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
        case screenTimeHistory = "screen-time-history.jsonl"
        case screenTimeSelections = "screen-time-selections.json"
    }

    let directory: URL
    /// False when the App Group entitlement is missing (data then can't be
    /// shared between the app and its extensions).
    let isSharedContainer: Bool

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
            isSharedContainer = true
        } else if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppEnvironment.appGroupID) {
            self.directory = group.appendingPathComponent("Doomscore", isDirectory: true)
            isSharedContainer = true
        } else {
            // Unit tests / misconfigured entitlements: fall back to a private folder.
            self.directory = FileManager.default.temporaryDirectory.appendingPathComponent("Doomscore", isDirectory: true)
            isSharedContainer = false
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
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: data)
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

    // MARK: Screen Time history (append-only, JSON Lines)

    /// Appends finished days without reading the file — cheap enough for the
    /// Screen Time extension's 6 MB memory limit.
    func appendScreenTimeHistory(_ days: [ScreenTimeDay]) {
        let lines = days.compactMap { try? JSONCoding.encoder.encode($0) }
        guard !lines.isEmpty else { return }
        var chunk = Data()
        for line in lines {
            chunk.append(line)
            chunk.append(0x0A)
        }
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url(for: .screenTimeHistory), options: .forMerging, error: &coordinationError) { url in
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: chunk)
        }
    }

    /// Finished days (app only — can be large). The latest copy of a day wins.
    func screenTimeHistory() -> [DayKey: ScreenTimeDay] {
        guard let data = try? Data(contentsOf: url(for: .screenTimeHistory)) else { return [:] }
        var days: [DayKey: ScreenTimeDay] = [:]
        for line in data.split(separator: 0x0A) where !line.isEmpty {
            guard let day = try? JSONCoding.decoder.decode(ScreenTimeDay.self, from: Data(line)) else { continue }
            if let existing = days[day.day], existing.updatedAt > day.updatedAt { continue }
            days[day.day] = day
        }
        return days
    }

    /// Every Screen Time day: history plus the live state (which wins).
    func screenTimeDays() -> [DayKey: ScreenTimeDay] {
        var days = screenTimeHistory()
        if let state = screenTime {
            for day in state.days.values { days[day.day] = day }
        }
        return days
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
    /// Reads the whole history — app and widgets only, never the Screen Time
    /// extension.
    func mergedLedger() -> Ledger {
        var ledger = exactLedger()
        for day in screenTimeDays().values {
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
