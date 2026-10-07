import Foundation
import Testing
@testable import ShepherdrCore

struct FileDropTests {
    @Test func pathsAreEscapedLikeMacTerminalsDoAndPastedOneByOne() {
        #expect(FileDrop.escaped("/Users/me/Screenshot 2026-10-07 at 14.30.png") == #"/Users/me/Screenshot\ 2026-10-07\ at\ 14.30.png"#)
        #expect(FileDrop.escaped("/tmp/it's (draft)&.md") == #"/tmp/it\'s\ \(draft\)\&.md"#)
        #expect(FileDrop.escaped("/tmp/café.png") == "/tmp/café.png")
        let paste = String(decoding: FileDrop.paste(["/a b.png", "/c.png"]), as: UTF8.self)
        #expect(paste == "\u{1b}[200~/a\\ b.png\u{1b}[201~ \u{1b}[200~/c.png\u{1b}[201~")
    }

    @Test func remoteNamesAreSafe() {
        #expect(FileDrop.safeName("Screenshot 2026-10-07 at 14.30.png") == "Screenshot_2026-10-07_at_14.30.png")
        #expect(FileDrop.safeName("$(rm -rf ~)'.png") == "__rm_-rf____.png")
        #expect(FileDrop.safeName("...") == "file")
    }

    @Test func theUploadStoresStandardInputAndPrintsItsPath() async throws {
        let command = FileDrop.uploadCommand(name: "my shot.png", folder: "F1", sshTarget: "builder")
        #expect(command.executable.path == "/usr/bin/ssh")
        #expect(command.arguments.prefix(2) == ["-T", "-o"])
        #expect(command.arguments.contains("BatchMode=yes") && command.arguments.contains("StrictHostKeyChecking=yes"))
        #expect(Array(command.arguments.suffix(3).prefix(2)) == ["--", "builder"])
        // Run what the remote shell would run, with a scratch home.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let source = home.appendingPathComponent("source.png")
        try Data([1, 2, 3]).write(to: source)
        let remote = try #require(command.arguments.last)
        let output = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/usr/bin/env"),
                                                   arguments: ["HOME=\(home.path)", "/bin/sh", "-c", remote],
                                                   timeout: 5, input: source)
        let path = String(decoding: output.stdout, as: UTF8.self)
        #expect(output.exitCode == 0)
        #expect(path == home.path + "/.cache/shepherdr/drops/F1/my_shot.png")
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == Data([1, 2, 3]))
    }
}
