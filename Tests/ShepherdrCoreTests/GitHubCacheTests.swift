import Foundation
import Testing
@testable import ShepherdrCore

@MainActor
struct GitHubCacheTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func scratchFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-cache-\(UUID().uuidString)/github.json")
    }

    @Test func answersLastUntilTheyAreTooOldForWhoAsks() {
        let cache = GitHubCache(file: nil, now: now)
        let key = "github.com/theam/shepherdr#12"
        cache.remember(GitHubCache.Item(isPullRequest: true, title: "Fix the login"), for: key, at: now)
        #expect(cache.item("GitHub.com/Theam/Shepherdr#12", since: now.addingTimeInterval(-60))?.title == "Fix the login")
        #expect(cache.item(key, since: now.addingTimeInterval(1)) == nil)
        cache.remember(.missing, for: "github.com/theam/shepherdr#999", at: now)
        #expect(cache.item("github.com/theam/shepherdr#999", since: .distantPast) == .missing)
        // A folder in no repository is an answer too.
        cache.remember(repository: nil, ofFolder: "/tmp/notes", onMachine: "local", at: now)
        cache.remember(repository: "Theam/Shepherdr", ofFolder: "/src/shepherdr", onMachine: "remote:box", at: now)
        #expect(cache.repository(ofFolder: "/tmp/notes", onMachine: "local", since: .distantPast) == .some(nil))
        #expect(cache.repository(ofFolder: "/src/shepherdr", onMachine: "remote:box", since: .distantPast) == .some("theam/shepherdr"))
        #expect(cache.repository(ofFolder: "/src/shepherdr", onMachine: "local", since: .distantPast) == nil)
    }

    @Test func whatItKnowsSurvivesARestartForAMonth() throws {
        let file = scratchFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let cache = GitHubCache(file: file, now: now)
        #expect(!cache.hasChanges)
        cache.remember(GitHubCache.Item(isPullRequest: false, title: "Crash on wake"), for: "github.com/a/b#1", at: now)
        cache.remember(checks: ["github.com/a/b#2": PullRequestChecks(passed: 3, failed: 0, running: 0, isOpen: false, isMerged: true, head: "abc")],
                       at: now.addingTimeInterval(-40 * 24 * 3600))
        cache.remember(issues: ["github.com/a/b#1": .completed], at: now)
        #expect(cache.hasChanges)
        cache.save()
        #expect(!cache.hasChanges)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)

        let reopened = GitHubCache(file: file, now: now)
        #expect(reopened.item("github.com/a/b#1", since: .distantPast)?.title == "Crash on wake")
        #expect(reopened.issues["github.com/a/b#1"]?.value == .completed)
        // Older than a month: forgotten.
        #expect(reopened.checks.isEmpty)
        // Nothing to write when nothing changed.
        try FileManager.default.removeItem(at: file)
        reopened.save()
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func foldersNameTheirRepositoryByItsRemote() {
        let output = """
        shepherdr-folder /src/shepherdr\tgit@github.com:theam/shepherdr.git
        shepherdr-folder /src/api\thttps://github.com/Theam/API
        shepherdr-folder /src/gitlab\thttps://gitlab.com/theam/tool.git
        shepherdr-folder /notes\t
        shepherdr-folder /elsewhere\thttps://github.com/x/y
        """
        let found = FolderRepositories.parse(output, folders: ["/src/shepherdr", "/src/api", "/src/gitlab", "/notes", "/missing"])
        #expect(found.count == 5)
        #expect(found["/src/shepherdr"]??.fullName == "theam/shepherdr")
        #expect(found["/src/api"]??.fullName.lowercased() == "theam/api")
        #expect(found["/src/gitlab"] == .some(nil))
        #expect(found["/notes"] == .some(nil))
        #expect(found["/missing"] == .some(nil))
        #expect(found["/elsewhere"] == nil)
    }
}
