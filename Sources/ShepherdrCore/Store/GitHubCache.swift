import Foundation

/// What GitHub and the machines told Shepherdr about pull requests, issues and repositories: kept
/// in memory while it runs, and written to disk every so often and as it quits, so it doesn't ask
/// again for what it already knows. Each answer keeps when it came, and whoever reads one says how
/// old it may be. Answers older than a month are forgotten.
@MainActor
public final class GitHubCache {
    /// A pull request or issue as GitHub described it.
    public struct Item: Codable, Equatable, Sendable {
        /// Nil when GitHub has no such number there, or you can't see it.
        public let isPullRequest: Bool?
        public let title: String?

        public init(isPullRequest: Bool?, title: String?) {
            self.isPullRequest = isPullRequest
            self.title = title
        }

        public static let missing = Item(isPullRequest: nil, title: nil)
    }

    /// An answer and when it came.
    public struct Dated<Value: Codable & Sendable>: Codable, Sendable {
        public let value: Value
        public let at: Date
    }

    private struct Contents: Codable {
        var version = 1
        var items: [String: Dated<Item>] = [:]
        var checks: [String: Dated<PullRequestChecks>] = [:]
        var issues: [String: Dated<IssueState>] = [:]
        /// The GitHub repository each folder is in, `owner/name`, by machine and folder; nil for a
        /// folder in no GitHub repository.
        var folders: [String: Dated<String?>] = [:]
    }

    private var contents: Contents
    private let file: URL?
    /// Something changed since the cache was last written.
    public private(set) var hasChanges = false
    static let forgetsAfter: TimeInterval = 30 * 24 * 60 * 60

    /// Reads what an earlier launch wrote, if anything. A nil file keeps it in memory only.
    public init(file: URL? = GitHubCache.defaultFile, now: Date = Date()) {
        self.file = file
        var contents = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Contents.self, from: $0) }
            ?? Contents()
        let limit = now.addingTimeInterval(-Self.forgetsAfter)
        contents.items = contents.items.filter { $0.value.at > limit }
        contents.checks = contents.checks.filter { $0.value.at > limit }
        contents.issues = contents.issues.filter { $0.value.at > limit }
        contents.folders = contents.folders.filter { $0.value.at > limit }
        self.contents = contents
    }

    /// In this user's caches folder: macOS may clear it, and Shepherdr only asks again.
    public nonisolated static var defaultFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.theagilemonkeys.Shepherdr", isDirectory: true)
            .appendingPathComponent("github.json")
    }

    // MARK: Pull requests and issues

    /// What GitHub said about a pull request or issue, by `SessionResource.key`, if it said so after `since`.
    public func item(_ key: String, since: Date) -> Item? {
        contents.items[key.lowercased()].flatMap { $0.at >= since ? $0.value : nil }
    }

    public func remember(_ item: Item, for key: String, at date: Date = Date()) {
        let key = key.lowercased()
        guard contents.items[key]?.value != item else { return }
        contents.items[key] = Dated(value: item, at: date)
        hasChanges = true
    }

    /// The last checks GitHub reported for each pull request, and when.
    public var checks: [String: Dated<PullRequestChecks>] { contents.checks }

    public func remember(checks found: [String: PullRequestChecks], at date: Date = Date()) {
        for (key, checks) in found { contents.checks[key.lowercased()] = Dated(value: checks, at: date) }
        if !found.isEmpty { hasChanges = true }
    }

    /// The last state GitHub reported for each issue, and when.
    public var issues: [String: Dated<IssueState>] { contents.issues }

    public func remember(issues found: [String: IssueState], at date: Date = Date()) {
        for (key, state) in found { contents.issues[key.lowercased()] = Dated(value: state, at: date) }
        if !found.isEmpty { hasChanges = true }
    }

    // MARK: Folders

    /// The GitHub repository a folder is in, `owner/name`, if a machine said so after `since`: nil
    /// when it never did, `.some(nil)` for a folder in no GitHub repository.
    public func repository(ofFolder path: String, onMachine machine: String, since: Date) -> String?? {
        guard let dated = contents.folders[Self.folderKey(path, machine)], dated.at >= since else { return nil }
        return .some(dated.value)
    }

    public func remember(repository: String?, ofFolder path: String, onMachine machine: String, at date: Date = Date()) {
        contents.folders[Self.folderKey(path, machine)] = Dated(value: repository?.lowercased(), at: date)
        hasChanges = true
    }

    private static func folderKey(_ path: String, _ machine: String) -> String { "\(machine)\n\(path)" }

    // MARK: Disk

    /// Writes what changed since the last write, atomically, readable only by this user.
    public func save() {
        guard hasChanges, let file, let data = try? JSONEncoder().encode(contents) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        hasChanges = false
    }
}
