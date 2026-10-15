import Foundation
import Testing
@testable import ShepherdrCore

struct ProjectFolderTests {
    @Test func theCheckSaysWhereAPathLeads() {
        #expect(ProjectFolder.parse("shepherdr-folder missing /home/me/my app\n") == .missing("/home/me/my app"))
        #expect(ProjectFolder.parse("Welcome to builder!\nshepherdr-folder folder /srv/app\n") == .folder("/srv/app"))
        #expect(ProjectFolder.parse("shepherdr-folder other /etc/hosts") == .notAFolder("/etc/hosts"))
        #expect(ProjectFolder.parse("shepherdr-folder missing app") == nil)
        #expect(ProjectFolder.parse("sh: printf: not found") == nil)
    }

    @Test func aNewProjectIsAFolderWithAGitRepository() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-project-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let project = base.appendingPathComponent("it's new/app").path
        #expect(await ProjectFolder.check(project, on: .local) == .missing(project))
        try await ProjectFolder.create(project, on: .local)
        #expect(await ProjectFolder.check(project, on: .local) == .folder(project))
        #expect(FileManager.default.fileExists(atPath: project + "/.git/HEAD"))
        let file = base.appendingPathComponent("notes.txt").path
        try Data().write(to: URL(fileURLWithPath: file))
        #expect(await ProjectFolder.check(file, on: .local) == .notAFolder(file))
        await #expect(throws: HerdrFailure.self) { try await ProjectFolder.create(file + "/app", on: .local) }
        #expect(await ProjectFolder.check("~", on: .local) == .folder(NSHomeDirectory()))
    }

    @Test func otherMachinesAreAskedOverSSHWithTildeAsTheirHome() async throws {
        let name = "shepherdr-missing-\(UUID().uuidString)/it's"
        let remote = try #require(Fixture.remote.shell(ProjectFolder.checkScript, arguments: ["~/\(name)"]))
        #expect(remote.executable.path == "/usr/bin/ssh")
        #expect(Array(remote.arguments.suffix(3).prefix(2)) == ["--", "builder"])
        // The remote shell reads the command as this one does.
        let command = try #require(remote.arguments.last)
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command], timeout: 10)
        #expect(ProjectFolder.parse(String(decoding: output.stdout, as: UTF8.self)) == .missing(NSHomeDirectory() + "/" + name))
    }
}
