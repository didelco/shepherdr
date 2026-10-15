import Foundation

/// A GitHub repository or pull request given where New Session expects a folder:
/// `https://github.com/theam/shepherdr`, `git@github.com:theam/shepherdr.git` or
/// `https://github.com/theam/shepherdr/pull/12/files`.
public enum GitHubReference: Equatable, Sendable {
    case repository(GitHubRepository)
    case pullRequest(GitHubRepository, number: Int)

    public var repository: GitHubRepository {
        switch self {
        case .repository(let repository), .pullRequest(let repository, _): repository
        }
    }

    public init?(_ text: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var path: Substring
        var remote: String?
        if let rest = Self.dropPrefix("git@github.com:", from: text) {
            path = rest
            remote = text
        } else if let rest = Self.dropPrefix("ssh://git@github.com/", from: text) {
            path = rest
            remote = text
        } else {
            var rest = Substring(text)
            for scheme in ["https://", "http://"] {
                if let stripped = Self.dropPrefix(scheme, from: String(rest)) { rest = stripped; break }
            }
            if let stripped = Self.dropPrefix("www.", from: String(rest)) { rest = stripped }
            guard let stripped = Self.dropPrefix("github.com/", from: String(rest)) else { return nil }
            path = stripped
        }
        if let end = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = path[..<end] }
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        var name = parts[1]
        if name.lowercased().hasSuffix(".git") { name.removeLast(4) }
        guard let repository = GitHubRepository(owner: parts[0], name: name, sshRemote: remote) else { return nil }
        if remote == nil, parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]), number > 0 {
            self = .pullRequest(repository, number: number)
        } else {
            // SSH remotes carry nothing after the repository.
            guard remote == nil || parts.count == 2 else { return nil }
            self = .repository(repository)
        }
    }

    private static func dropPrefix(_ prefix: String, from text: String) -> Substring? {
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        return text.dropFirst(prefix.count)
    }
}

public struct GitHubRepository: Hashable, Sendable {
    public let owner: String
    public let name: String
    /// The SSH remote it was given as, so it is cloned the same way; nil for web links.
    public let sshRemote: String?

    public init?(owner: String, name: String, sshRemote: String? = nil) {
        // GitHub's own rules: owners are letters, digits and inner hyphens; names add . and _.
        guard owner.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$"#, options: .regularExpression) != nil,
              name.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil,
              name != ".", name != ".." else { return nil }
        self.owner = owner
        self.name = name
        self.sshRemote = sshRemote
    }

    /// `theam/shepherdr`.
    public var fullName: String { "\(owner)/\(name)" }
    public var webURL: URL { URL(string: "https://github.com/\(fullName)")! }

    public func pullRequestURL(_ number: Int) -> URL { URL(string: "https://github.com/\(fullName)/pull/\(number)")! }

    /// Whether a Git remote's URL is this repository, over HTTPS or SSH, with or without `.git`.
    /// GitHub ignores case in both parts.
    public func isRemote(_ url: String) -> Bool {
        guard case .repository(let other)? = GitHubReference(url) else { return false }
        return other.owner.lowercased() == owner.lowercased() && other.name.lowercased() == name.lowercased()
    }
}

/// The branch a pull request comes from, as GitHub reports it.
public struct PullRequestHead: Equatable, Sendable {
    public let branch: String
    /// Whether the branch lives in the repository itself; a fork's branch doesn't.
    public let isSameRepository: Bool
    public let title: String
    /// `open`, `closed` or `merged`.
    public let state: String

    public init(branch: String, isSameRepository: Bool, title: String, state: String) {
        self.branch = branch
        self.isSameRepository = isSameRepository
        self.title = title
        self.state = state
    }

    /// The local branch a worktree of the pull request uses: its own branch, or `pr-12` for a fork's,
    /// whose name could be anything, `main` included.
    public static func localBranch(for number: Int, head: PullRequestHead?) -> String {
        guard let head, head.isSameRepository else { return "pr-\(number)" }
        return head.branch
    }
}
