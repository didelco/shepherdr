import CryptoKit
import Foundation

/// Compass's folder, `~/.shepherdr/compass`: your prompt and settings, the contract and template
/// Shepherdr brings, the pages the agent writes, and Shepherdr's notes. Each file has an owner,
/// which decides what an update of Shepherdr may overwrite.
public struct CompassFolder: Sendable {
    public let root: URL

    public init(root: URL) { self.root = root }

    /// `~/.shepherdr/compass`, with the home folder the agent tools' scripts see.
    public static func standard(home: URL? = nil) -> CompassFolder {
        let home = home ?? ProcessInfo.processInfo.environment["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return CompassFolder(root: home.appendingPathComponent(".shepherdr/compass", isDirectory: true))
    }

    // MARK: The kit

    /// What Shepherdr brings for Compass: the contract, the page template, the starter prompt
    /// and the Claude Code permissions that let runs go on unattended.
    public struct Kit: Equatable, Sendable {
        public let version: Int
        public let files: [String: String]
    }

    /// Files Shepherdr owns and always rewrites.
    static let owned = ["AGENTS.md", "CLAUDE.md"]
    /// Files Shepherdr rewrites only while you haven't changed them.
    static let maintained = ["template.html", ".claude/settings.json", ".gitignore"]
    /// Files that are yours from the start: written once, never again.
    static let yours = ["prompt.md"]

    public static func bundledKit() throws -> Kit {
        guard let folder = Bundle.module.url(forResource: "Compass", withExtension: nil) else {
            throw HerdrFailure(.notInstalled, "This build of Shepherdr doesn't carry Compass.")
        }
        return try kit(at: folder)
    }

    static func kit(at folder: URL) throws -> Kit {
        var files: [String: String] = [:]
        for name in ["VERSION", "AGENTS.md", "CLAUDE.md", "template.html", "prompt.md", "settings.json", "gitignore"] {
            let url = folder.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw HerdrFailure(.notInstalled, "Compass is incomplete in this build of Shepherdr.", detail: "\(name) is missing.")
            }
            files[name] = text
        }
        guard let version = files["VERSION"].flatMap({ Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }) else {
            throw HerdrFailure(.notInstalled, "Compass is incomplete in this build of Shepherdr.", detail: "VERSION isn't a number.")
        }
        return Kit(version: version, files: files)
    }

    /// Where each kit file goes in the folder.
    static func destination(of kitFile: String) -> String {
        switch kitFile {
        case "settings.json": ".claude/settings.json"
        case "gitignore": ".gitignore"
        default: kitFile
        }
    }

    public static func fingerprint(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Makes the folder and puts the kit in place. Returns the fingerprints of what Shepherdr
    /// wrote, to recognize later the files you changed.
    @discardableResult
    public func prepare(_ kit: Kit, written: [String: String]) throws -> [String: String] {
        let manager = FileManager.default
        for folder in [root, root.appendingPathComponent("days"), root.appendingPathComponent("context"),
                       root.appendingPathComponent(".claude")] {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        var written = written
        for (name, raw) in kit.files where name != "VERSION" {
            let path = Self.destination(of: name)
            let text = contents(of: name, raw)
            let url = root.appendingPathComponent(path)
            let current = try? String(contentsOf: url, encoding: .utf8)
            let shouldWrite: Bool
            if Self.yours.contains(path) {
                shouldWrite = current == nil
            } else if Self.maintained.contains(path) {
                // Untouched since Shepherdr wrote it, or never written.
                shouldWrite = current == nil || current.map(Self.fingerprint) == written[path]
            } else {
                shouldWrite = true
            }
            guard shouldWrite, current != text else {
                if current == text { written[path] = Self.fingerprint(text) }
                continue
            }
            try write(text, to: url)
            written[path] = Self.fingerprint(text)
        }
        if !manager.fileExists(atPath: configURL.path) { try writeConfig(CompassConfig()) }
        return written
    }

    /// Whether a file Shepherdr maintains was changed by you or the agent since it wrote it.
    public func isCustomized(_ path: String, written: [String: String]) -> Bool {
        guard let current = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else { return false }
        return Self.fingerprint(current) != written[path]
    }

    /// Puts Shepherdr's version of a file back, such as the template.
    public func restore(_ path: String, from kit: Kit) throws -> String {
        guard let name = kit.files.keys.first(where: { Self.destination(of: $0) == path }), let raw = kit.files[name] else {
            throw HerdrFailure(.notInstalled, "Shepherdr doesn't bring \(path).")
        }
        let text = contents(of: name, raw)
        try write(text, to: root.appendingPathComponent(path))
        return Self.fingerprint(text)
    }

    /// The home folder this Compass folder is in: `~` in `~/.shepherdr/compass`.
    public var home: URL { root.deletingLastPathComponent().deletingLastPathComponent() }

    /// A kit file as it goes in this folder. Claude Code matches commands as typed, so its
    /// permissions name the tools both by `~` and by the full path.
    func contents(of kitFile: String, _ text: String) -> String {
        kitFile == "settings.json" ? text.replacingOccurrences(of: "{{HOME}}", with: home.path) : text
    }

    // MARK: Settings and notes

    public var configURL: URL { root.appendingPathComponent("compass.json") }
    public var stateURL: URL { root.appendingPathComponent("state.json") }
    public var promptURL: URL { root.appendingPathComponent("prompt.md") }

    public var exists: Bool { FileManager.default.fileExists(atPath: configURL.path) }

    public enum ConfigResult: Equatable, Sendable {
        case missing
        case read(CompassConfig)
        /// The file isn't JSON Shepherdr can read; `detail` says why.
        case unreadable(String)
    }

    public func readConfig() -> ConfigResult {
        guard let data = try? Data(contentsOf: configURL) else { return .missing }
        do { return .read(try JSONDecoder().decode(CompassConfig.self, from: data)) }
        catch { return .unreadable(error.localizedDescription) }
    }

    public func writeConfig(_ config: CompassConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try write(String(decoding: try encoder.encode(config), as: UTF8.self) + "\n", to: configURL)
    }

    public func readState() -> CompassState {
        guard let data = try? Data(contentsOf: stateURL) else { return CompassState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CompassState.self, from: data)) ?? CompassState()
    }

    public func writeState(_ state: CompassState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(state), to: stateURL)
    }

    // MARK: Pages

    /// A day's page, `days/2026-10-15.html`.
    public func page(_ day: String) -> URL { root.appendingPathComponent("days/\(day).html") }
    public func pagePath(_ day: String) -> String { "days/\(day).html" }
    /// Where a day's copies, one per run, are kept.
    public func snapshotFolder(_ day: String) -> URL { root.appendingPathComponent("days/\(day)", isDirectory: true) }
    public func marksURL(_ day: String) -> URL { root.appendingPathComponent("days/\(day).marks.json") }

    /// The days that have a page, newest first.
    public func days() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("days").path)) ?? []
        return names.filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }.filter(Compass.isDay).sorted(by: >)
    }

    /// A day's copies, oldest first, by the time each was taken: `14-00`.
    public func snapshots(_ day: String) -> [(time: String, url: URL)] {
        let folder = snapshotFolder(day)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }.sorted()
            .map { ($0, folder.appendingPathComponent("\($0).html")) }
    }

    /// Keeps a copy of a day's page as a run left it. Returns its path in the folder.
    public func snapshot(_ day: String, at time: String) throws -> String? {
        let source = page(day)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let folder = snapshotFolder(day)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var name = time
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name).html").path) {
            name = "\(time)-\(suffix)"
            suffix += 1
        }
        let target = folder.appendingPathComponent("\(name).html")
        try FileManager.default.copyItem(at: source, to: target)
        return "days/\(day)/\(name).html"
    }

    /// Deletes the copies of days older than `keep` days. The day pages themselves stay.
    public func pruneSnapshots(before cutoff: String) {
        let days = root.appendingPathComponent("days")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: days.path)) ?? []
        for name in names where Compass.isDay(name) && name < cutoff {
            var isFolder: ObjCBool = false
            let url = days.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    public func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    // MARK: Marks

    public func readMarks(_ day: String) -> CompassMarks {
        guard let data = try? Data(contentsOf: marksURL(day)) else { return CompassMarks() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CompassMarks.self, from: data)) ?? CompassMarks()
    }

    public func writeMarks(_ marks: CompassMarks, for day: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try write(encoder.encode(marks), to: marksURL(day))
    }

    // MARK: Context for the agent

    public func writeContext(_ name: String, _ data: Data) throws {
        try write(data, to: root.appendingPathComponent("context/\(name)"))
    }

    // MARK: Writing

    private func write(_ text: String, to url: URL) throws { try write(Data(text.utf8), to: url) }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// What you marked on a day's page, and the sessions you started from it, in
/// `days/<day>.marks.json`. Shepherdr shows them on the page; the agent reads them each run.
public struct CompassMarks: Codable, Equatable, Sendable {
    public struct Started: Codable, Equatable, Sendable {
        /// The session's name, with `@machine` when it isn't on this Mac.
        public let session: String
        public let at: Date

        public init(session: String, at: Date) {
            self.session = session
            self.at = at
        }
    }

    /// Items marked done, with when.
    public var done: [String: Date] = [:]
    /// Items whose session you started, by item.
    public var started: [String: Started] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey { case done, started }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = (try? container.decode([String: Date].self, forKey: .done)) ?? [:]
        started = (try? container.decode([String: Started].self, forKey: .started)) ?? [:]
    }
}
