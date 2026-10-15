import Foundation

/// Keeps the Compass folder in a Git repository, so its history survives this Mac: each run
/// commits the folder, and when you set a remote, ideally a private one, Shepherdr pushes there.
/// A new Mac can start from that remote. Git runs without prompting: SSH keys must already be
/// in your agent, and HTTPS needs a credential helper.
public struct CompassRepository: Sendable {
    public let root: URL
    let runner: any CommandRunning
    let git: URL?

    public init(root: URL) {
        self.init(root: root, runner: ProcessRunner(), git: Self.locateGit())
    }

    init(root: URL, runner: any CommandRunning, git: URL?) {
        self.root = root
        self.runner = runner
        self.git = git
    }

    /// Homebrew's Git first. Apple's `/usr/bin/git` only when the developer tools are there:
    /// without them it opens an installer instead of running.
    static func locateGit() -> URL? {
        for path in ["/opt/homebrew/bin/git", "/usr/local/bin/git"] where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        let tools = ["/Library/Developer/CommandLineTools/usr/bin/git", "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        return tools.contains(where: FileManager.default.isExecutableFile(atPath:)) ? URL(fileURLWithPath: "/usr/bin/git") : nil
    }

    public var isAvailable: Bool { git != nil }

    public var isRepository: Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(".git").path)
    }

    /// Starts the repository if the folder doesn't have one yet.
    public func prepare() async throws {
        guard !isRepository else { return }
        try await run(["init", "-q", "-b", "main"])
    }

    /// Commits whatever changed. False when nothing did.
    @discardableResult
    public func commit(_ message: String) async throws -> Bool {
        try await prepare()
        try await run(["add", "-A"])
        let status = try await run(["status", "--porcelain"])
        guard !status.isEmpty else { return false }
        // Without a Git identity of your own, commits are signed as Shepherdr.
        let named = (try? await run(["config", "user.email"]))?.isEmpty == false
        let identity = named ? [] : ["-c", "user.name=Shepherdr", "-c", "user.email=compass@shepherdr.invalid"]
        try await run(identity + ["commit", "-q", "--no-verify", "-m", message])
        return true
    }

    /// The remote Shepherdr pushes to, if any.
    public func remote() async -> String? {
        try? await run(["remote", "get-url", "origin"]).nonEmptyLine
    }

    public func setRemote(_ url: String?) async throws {
        try await prepare()
        let current = await remote()
        guard let url = url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
            if current != nil { try await run(["remote", "remove", "origin"]) }
            return
        }
        try Self.requireRemote(url)
        if current == nil { try await run(["remote", "add", "origin", url]) }
        else if current != url { try await run(["remote", "set-url", "origin", url]) }
    }

    /// Pushes to the remote. When it has commits this Mac lacks, such as from another Mac,
    /// they are brought in first.
    public func push() async throws {
        guard await remote() != nil else { return }
        let branch = (try? await run(["rev-parse", "--abbrev-ref", "HEAD"]))?.nonEmptyLine ?? "main"
        do {
            try await run(["push", "-q", "-u", "origin", "HEAD"], timeout: 90)
        } catch let failure as HerdrFailure where failure.detail.map(Self.isBehind) == true {
            do {
                try await run(["pull", "-q", "--rebase", "--autostash", "origin", branch], timeout: 90)
            } catch {
                _ = try? await run(["rebase", "--abort"])
                throw HerdrFailure(.unreachable, "The backup has changes that clash with this Mac's.",
                                   detail: "Resolve them with Git in \(root.path), then back up again.")
            }
            try await run(["push", "-q", "-u", "origin", "HEAD"], timeout: 90)
        }
    }

    /// Brings a Compass folder back from its remote, into a folder that doesn't exist yet or is empty.
    public func restore(from url: String) async throws {
        try Self.requireRemote(url)
        let manager = FileManager.default
        if let contents = try? manager.contentsOfDirectory(atPath: root.path), !contents.isEmpty {
            throw HerdrFailure(.incompatible, "\(root.path) isn't empty.",
                               detail: "Move it away first; Shepherdr only restores into an empty folder.")
        }
        try manager.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? manager.removeItem(at: root)
        try await run(["clone", "-q", url, root.path], inFolder: false, timeout: 180)
        // A remote whose HEAD names a branch it doesn't have, such as a bare repository made
        // with `master` that Compass pushed `main` to, clones with nothing checked out.
        guard (try? await run(["rev-parse", "--verify", "-q", "HEAD"])) == nil else { return }
        let branches = try await run(["for-each-ref", "--format=%(refname:short)", "refs/remotes/origin"])
            .split(separator: "\n").map(String.init).filter { $0 != "origin/HEAD" && $0 != "origin" }
        guard let branch = branches.first(where: { $0 == "origin/main" }) ?? branches.first else {
            throw HerdrFailure(.incompatible, "That repository is empty.", detail: "Nothing to restore from \(url).")
        }
        try await run(["checkout", "-q", "-b", String(branch.dropFirst("origin/".count)), "--track", branch])
    }

    /// Whether a GitHub remote is private, asked through GitHub's CLI. Nil when it can't tell.
    public static func isPrivate(_ remote: String, lookup: GitHubLookup = GitHubLookup()) async -> Bool? {
        guard let (owner, repository) = gitHubRepository(remote) else { return nil }
        return await lookup.isPrivate(owner: owner, repository: repository)
    }

    /// `owner/repo` from `git@github.com:owner/repo.git` or `https://github.com/owner/repo`.
    static func gitHubRepository(_ remote: String) -> (String, String)? {
        var path: Substring
        if let range = remote.range(of: "github.com:") ?? remote.range(of: "github.com/") {
            path = remote[range.upperBound...]
        } else {
            return nil
        }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count == 2, parts.allSatisfy({ $0.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil }) else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    static func requireRemote(_ url: String) throws {
        guard !url.hasPrefix("-"), url.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              url.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw HerdrFailure(.incompatible, "That isn't a Git remote.", detail: "Use an SSH or HTTPS URL, such as git@github.com:you/compass.git.")
        }
    }

    static func isBehind(_ detail: String) -> Bool {
        ["rejected", "fetch first", "non-fast-forward"].contains(where: detail.contains)
    }

    @discardableResult
    private func run(_ arguments: [String], inFolder: Bool = true, timeout: TimeInterval = 30) async throws -> String {
        guard let git else {
            throw HerdrFailure(.notInstalled, "Git isn't installed.", detail: "Install the Command Line Tools with xcode-select --install, or Git with Homebrew.")
        }
        // Never ask: there is no one at a terminal to answer.
        let full = ["GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0", git.path] + (inFolder ? ["-C", root.path] : []) + arguments
        let output: CommandOutput
        do {
            output = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/env"), arguments: full, timeout: timeout)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, "Git took too long.", detail: "git \(arguments.first ?? "")")
        }
        guard output.exitCode == 0 else {
            let detail = String(decoding: output.stderr + output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.unreachable, "Git couldn't \(arguments.first ?? "run").", detail: detail.isEmpty ? nil : String(detail.prefix(2_000)))
        }
        return String(decoding: output.stdout, as: UTF8.self)
    }
}

private extension String {
    var nonEmptyLine: String? {
        let line = trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}

extension GitHubLookup {
    /// Whether a repository is private. Nil without the CLI, signed out, or when GitHub doesn't say.
    public func isPrivate(owner: String, repository: String) async -> Bool? {
        guard let executable, !owner.hasPrefix("-"), !repository.hasPrefix("-"),
              let output = try? await runner.run(executable: executable,
                                                 arguments: ["api", "repos/\(owner)/\(repository)", "--jq", ".private"],
                                                 timeout: 20),
              output.exitCode == 0 else { return nil }
        switch String(decoding: output.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }
}
