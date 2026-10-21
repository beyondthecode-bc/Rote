import Foundation

/// Owns `state.json`. Writes are debounced; unreadable files are moved aside (spec §10).
public actor StateStore {
    public enum LoadResult: Sendable, Equatable {
        case fresh
        case loaded(CoachState)
        case recovered(corruptFileName: String)
    }

    /// Bytes a `state.json` may have before it is moved aside unread. A heavy year of use is a
    /// few megabytes; a file this size was not written by Rote (audit M1).
    public static let defaultMaxFileSize = 64 * 1024 * 1024

    private let fileURL: URL
    private let debounce: Duration
    private let maxFileSize: Int
    private let onWriteFailure: @Sendable (any Error) -> Void
    private var pending: Task<Void, Never>?
    private var latest: CoachState?

    /// `onWriteFailure` hears about every debounced or flushed write that fails. The state stays
    /// in memory, so the next change or `flush()` tries again; `saveNow` throws instead.
    public init(fileURL: URL, debounce: Duration = .seconds(2), maxFileSize: Int = StateStore.defaultMaxFileSize, onWriteFailure: @escaping @Sendable (any Error) -> Void = { _ in }) {
        self.fileURL = fileURL
        self.debounce = debounce
        self.maxFileSize = maxFileSize
        self.onWriteFailure = onWriteFailure
    }

    /// `~/Library/Application Support/Rote/state.json`
    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Rote", isDirectory: true).appendingPathComponent("state.json")
    }

    /// A file that is unreadable, from a newer build, over `maxFileSize`, or carries a value Rote
    /// never writes (see `CoachStateDecodingReport`) is moved aside and the result is `.recovered`.
    public func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .fresh }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int ?? 0
            guard size <= maxFileSize else { return quarantine() }
            let data = try Data(contentsOf: fileURL)
            let report = CoachStateDecodingReport()
            let decoder = Self.makeDecoder()
            decoder.userInfo[CoachState.decodingReportKey] = report
            let state = try decoder.decode(CoachState.self, from: data)
            guard state.schemaVersion <= CoachState.currentSchemaVersion, report.isEmpty else { return quarantine() }
            return .loaded(state)
        } catch {
            return quarantine()
        }
    }

    private func quarantine() -> LoadResult {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let name = "state.corrupt-\(stamp).json"
        let destination = fileURL.deletingLastPathComponent().appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
        return .recovered(corruptFileName: name)
    }

    /// Remembers `state` and writes it once nothing else arrives for `debounce`.
    public func scheduleSave(_ state: CoachState) {
        latest = state
        pending?.cancel()
        pending = Task { [debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self.writeLatest()
        }
    }

    /// Writes whatever is pending right now. Call on quit. A failure goes to `onWriteFailure`.
    public func flush() {
        pending?.cancel()
        pending = nil
        writeLatest()
    }

    public func saveNow(_ state: CoachState) throws {
        latest = state
        try write(state)
    }

    private func writeLatest() {
        guard let latest else { return }
        do {
            try write(latest)
        } catch {
            onWriteFailure(error)
        }
    }

    private func write(_ state: CoachState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
