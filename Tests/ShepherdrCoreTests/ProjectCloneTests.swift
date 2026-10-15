import Foundation
import Testing
@testable import ShepherdrCore

struct GitHubReferenceTests {
    private let shepherdr = GitHubRepository(owner: "theam", name: "shepherdr")!

    @Test func repositoriesAndPullRequestsAreReadFromLinksAndRemotes() {
        for link in ["https://github.com/theam/shepherdr", "https://github.com/theam/shepherdr.git", "github.com/theam/shepherdr/",
                     "http://www.GitHub.com/theam/shepherdr/tree/main/docs", " https://github.com/theam/shepherdr?tab=readme \n",
                     "https://github.com/theam/shepherdr/pulls", "https://github.com/theam/shepherdr/issues/7"] {
            #expect(GitHubReference(link) == .repository(shepherdr), "\(link)")
        }
        for link in ["https://github.com/theam/shepherdr/pull/12", "https://github.com/theam/shepherdr/pull/12/files#diff-1",
                     "github.com/theam/shepherdr/pull/12/checks?check_run_id=3"] {
            #expect(GitHubReference(link) == .pullRequest(shepherdr, number: 12), "\(link)")
        }
        let ssh = GitHubReference("git@github.com:theam/shepherdr.git")
        #expect(ssh?.repository.fullName == "theam/shepherdr")
        #expect(ssh?.repository.sshRemote == "git@github.com:theam/shepherdr.git")
        #expect(GitHubReference("ssh://git@github.com/theam/shepherdr")?.repository.sshRemote == "ssh://git@github.com/theam/shepherdr")
    }

    @Test func foldersAndOtherLinksAreNotGitHubReferences() {
        for text in ["~/projects/shepherdr", "/srv/github.com/theam/shepherdr", "shepherdr", "https://gitlab.com/theam/shepherdr",
                     "https://github.com/theam", "https://github.com/-theam/shepherdr", "https://github.com/theam/..",
                     "git@github.com:theam/shepherdr/pull/12", "https://github.com/the am/x"] {
            #expect(GitHubReference(text) == nil, "\(text)")
        }
        // Not a pull request's number: the repository.
        #expect(GitHubReference("https://github.com/theam/shepherdr/pull/abc") == .repository(shepherdr))
        #expect(GitHubReference("https://github.com/theam/shepherdr/pull/0") == .repository(shepherdr))
    }

    @Test func remotesMatchTheRepositoryHoweverTheyAreWritten() {
        for remote in ["https://github.com/theam/shepherdr.git", "git@github.com:Theam/Shepherdr.git", "ssh://git@github.com/theam/shepherdr",
                       "https://github.com/theam/shepherdr"] {
            #expect(shepherdr.isRemote(remote), "\(remote)")
        }
        for remote in ["https://github.com/didelco/shepherdr.git", "https://gitlab.com/theam/shepherdr.git", "/srv/git/shepherdr.git", ""] {
            #expect(!shepherdr.isRemote(remote), "\(remote)")
        }
    }

    @Test func aForksPullRequestGetsABranchOfItsOwn() {
        let own = PullRequestHead(branch: "fix-login", isSameRepository: true, title: "Fix login", state: "open")
        let fork = PullRequestHead(branch: "main", isSameRepository: false, title: "Fix login", state: "open")
        #expect(PullRequestHead.localBranch(for: 12, head: own) == "fix-login")
        #expect(PullRequestHead.localBranch(for: 12, head: fork) == "pr-12")
        #expect(PullRequestHead.localBranch(for: 12, head: nil) == "pr-12")
    }

    @Test func gitHubsAnswersGiveTheBranch() {
        #expect(GitHubLookup.head(fromFields: "fix-login\ttheam/shepherdr\tfalse\topen\tFix the\\tlogin\n", in: shepherdr)
                == PullRequestHead(branch: "fix-login", isSameRepository: true, title: "Fix the\\tlogin", state: "open"))
        #expect(GitHubLookup.head(fromFields: "main\tdidelco/shepherdr\ttrue\tclosed\tSuggest folders", in: shepherdr)
                == PullRequestHead(branch: "main", isSameRepository: false, title: "Suggest folders", state: "merged"))
        // A deleted fork has no repository.
        #expect(GitHubLookup.head(fromFields: "main\t\tfalse\tclosed\tGone", in: shepherdr)?.isSameRepository == false)
        #expect(GitHubLookup.head(fromFields: "-x\ttheam/shepherdr\tfalse\topen\tNope", in: shepherdr) == nil)
        #expect(GitHubLookup.head(fromFields: "gh: Not Found (HTTP 404)", in: shepherdr) == nil)

        let json = #"{"head":{"ref":"agent-tools","repo":{"full_name":"theam/shepherdr"}},"state":"closed","title":"Agent tools","merged_at":"2026-10-15T13:00:00Z"}"#
        #expect(GitHubLookup.head(fromJSON: Data(json.utf8), in: shepherdr)
                == PullRequestHead(branch: "agent-tools", isSameRepository: true, title: "Agent tools", state: "merged"))
        let fork = #"{"head":{"ref":"main","repo":null},"state":"open","title":"From a deleted fork","merged_at":null}"#
        #expect(GitHubLookup.head(fromJSON: Data(fork.utf8), in: shepherdr)?.isSameRepository == false)
    }
}

struct ProjectCloneTests {
    private let shepherdr = GitHubRepository(owner: "theam", name: "shepherdr")!

    @Test func theLocateScriptsLinesSayWhatEachFolderHolds() {
        let lines = """
        Welcome to builder!
        shepherdr-clone missing /home/me/projects/shepherdr
        shepherdr-clone repository /home/me/src/shepherdr
        shepherdr-remote upstream\tgit@github.com:theam/shepherdr.git
        shepherdr-remote origin\thttps://github.com/me/shepherdr.git
        shepherdr-clone folder relative/path
        shepherdr-remote stray\thttps://github.com/theam/shepherdr
        """
        #expect(ProjectClone.inspection(lines) == [
            .init(state: .missing, path: "/home/me/projects/shepherdr"),
            .init(state: .repository, path: "/home/me/src/shepherdr",
                  remotes: [("upstream", "git@github.com:theam/shepherdr.git"), ("origin", "https://github.com/me/shepherdr.git")]),
        ])
    }

    @Test func aCloneIsFoundByAnyRemotePointingAtTheRepository() {
        func repository(_ path: String, _ remotes: [(String, String)]) -> ProjectClone.Inspected {
            .init(state: .repository, path: path, remotes: remotes.map { (name: $0.0, url: $0.1) })
        }
        let fork = repository("/p/shepherdr", [("origin", "https://github.com/me/shepherdr.git"),
                                               ("upstream", "https://github.com/theam/shepherdr.git")])
        #expect(ProjectClone.location(of: shepherdr, in: [fork]) == .cloned(path: "/p/shepherdr", remote: "upstream"))
        let both = repository("/p/shepherdr", [("mirror", "git@github.com:theam/shepherdr.git"), ("origin", "https://github.com/theam/shepherdr")])
        #expect(ProjectClone.location(of: shepherdr, in: [both]) == .cloned(path: "/p/shepherdr", remote: "origin"))
        // The destination comes first, but a clone elsewhere is found too.
        let elsewhere = repository("/src/shepherdr", [("origin", "git@github.com:theam/shepherdr.git")])
        #expect(ProjectClone.location(of: shepherdr, in: [.init(state: .missing, path: "/p/shepherdr"), elsewhere])
                == .cloned(path: "/src/shepherdr", remote: "origin"))
        #expect(ProjectClone.location(of: shepherdr, in: [.init(state: .missing, path: "/p/shepherdr")]) == .free("/p/shepherdr"))
        #expect(ProjectClone.location(of: shepherdr, in: [.init(state: .empty, path: "/p/shepherdr")]) == .free("/p/shepherdr"))
        for state in [ProjectClone.Inspected.State.folder, .other] {
            #expect(ProjectClone.location(of: shepherdr, in: [.init(state: state, path: "/p/shepherdr")]) == .taken("/p/shepherdr"))
        }
        let other = repository("/p/shepherdr", [("origin", "https://github.com/me/other.git")])
        #expect(ProjectClone.location(of: shepherdr, in: [other]) == .taken("/p/shepherdr"))
        #expect(ProjectClone.location(of: shepherdr, in: []) == nil)
    }

    /// Clones, finds and fetches for real, from a local repository standing in for GitHub.
    @Test func aRepositoryIsClonedOnceAndItsPullRequestsFetched() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-clone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let upstream = base.appendingPathComponent("upstream.git").path
        let work = base.appendingPathComponent("work").path
        try await git("init", "-q", "--bare", upstream)
        try await git("init", "-q", work)
        try await git("-C", work, "commit", "-q", "--allow-empty", "-m", "first")
        try await git("-C", work, "push", "-q", upstream, "HEAD:refs/heads/main", "HEAD:refs/heads/fix-login", "HEAD:refs/pull/7/head")
        try await git("-C", upstream, "symbolic-ref", "HEAD", "refs/heads/main")

        // An SSH remote is cloned as given; a local path stands in for one here.
        let repository = try #require(GitHubRepository(owner: "theam", name: "shepherdr", sshRemote: upstream))
        let destination = base.appendingPathComponent("projects/shepherdr").path
        let elsewhere = base.appendingPathComponent("src/shepherdr").path
        #expect(await ProjectClone.locate(repository, in: destination, orAmong: [elsewhere], on: .local) == .free(destination))
        try await ProjectClone.clone(repository, into: destination, on: .local)
        // Its origin is the local path, so only a remote with GitHub's URL says it is the repository.
        #expect(await ProjectClone.locate(repository, in: destination, on: .local) == .taken(destination))
        try await git("-C", destination, "remote", "add", "github", "git@github.com:theam/shepherdr.git")
        #expect(await ProjectClone.locate(repository, in: destination, on: .local) == .cloned(path: destination, remote: "github"))

        // An existing branch is fetched to its usual ref; a missing one falls back to GitHub's pull/N/head.
        #expect(try await ProjectClone.fetch(pullRequest: 7, branch: "fix-login", from: "origin", in: destination, on: .local)
                == "origin/fix-login")
        #expect(try await ProjectClone.fetch(pullRequest: 7, branch: "deleted", from: "origin", in: destination, on: .local)
                == "origin/pull/7")
        #expect(try await ProjectClone.fetch(pullRequest: 7, branch: nil, from: "origin", in: destination, on: .local) == "origin/pull/7")
        try await git("-C", destination, "rev-parse", "--verify", "-q", "refs/remotes/origin/pull/7")
        await #expect(throws: HerdrFailure.self) {
            _ = try await ProjectClone.fetch(pullRequest: 8, branch: nil, from: "origin", in: destination, on: .local)
        }

        // A folder inside another repository, or with something in it, is taken.
        let inside = destination + "/docs"
        try FileManager.default.createDirectory(atPath: inside, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: inside + "/notes.md"))
        #expect(await ProjectClone.locate(repository, in: inside, on: .local) == .taken(inside))
        await #expect(throws: HerdrFailure.self) { try await ProjectClone.clone(repository, into: inside, on: .local) }
    }

    @discardableResult
    private func git(_ arguments: String...) async throws -> CommandOutput {
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/git"),
                                                   arguments: ["-c", "user.name=Test", "-c", "user.email=test@example.com",
                                                               "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"] + arguments,
                                                   timeout: 30)
        guard output.exitCode == 0 else {
            throw HerdrFailure(.unreachable, "git \(arguments.joined(separator: " ")) failed",
                               detail: String(decoding: output.stderr, as: UTF8.self))
        }
        return output
    }
}
