import Foundation
import Testing
@testable import ShepherdrCore

struct SSHOptionsTests {
    /// A short folder: a socket's path must fit in 103 bytes, which the temporary folder doesn't leave room for.
    private func scratch() -> URL {
        URL(fileURLWithPath: "/tmp/shepherdr-ssh-\(UUID().uuidString.prefix(8))", isDirectory: true)
    }

    @Test func commandsShareAConnectionOnlyThroughAReadyFolder() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = SSHControlFolder(url: root.appendingPathComponent("ssh"))
        // Not there yet: each command connects on its own, as ssh would fail on a missing folder.
        #expect(SSHOptions.sharing(in: folder) == nil)
        #expect(SSHOptions.command(sharingIn: folder) == SSHOptions.base + SSHOptions.keepAlive)
        #expect(folder.prepare())
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(SSHOptions.command(sharingIn: folder) == SSHOptions.base + SSHOptions.keepAlive
                + ["-o", "ControlMaster=auto", "-o", "ControlPath=\"\(folder.url.path)/%C\"", "-o", "ControlPersist=60"])
        #expect(SSHOptions.command(sharingIn: nil) == SSHOptions.base + SSHOptions.keepAlive)
    }

    @Test func theSecurityOptionsStayInEveryCommand() {
        for options in [SSHOptions.command(sharingIn: nil), SSHOptions.stream] {
            #expect(Array(options.prefix(2)) == ["-T", "-o"])
            for option in ["BatchMode=yes", "StrictHostKeyChecking=yes", "ConnectTimeout=10", "ClearAllForwardings=yes",
                           "ForwardAgent=no", "ServerAliveInterval=10", "ServerAliveCountMax=2"] {
                #expect(options.contains(option), "\(option)")
            }
        }
    }

    @Test func aTerminalStreamNeverSharesItsConnection() throws {
        // Ending a shared session leaves its remote command running: a stream must end with its connection.
        #expect(SSHOptions.stream.contains("ControlMaster=no") && SSHOptions.stream.contains("ControlPath=none"))
        #expect(!SSHOptions.stream.contains("ControlMaster=auto"))
        let machine = Machine(profileID: "p", name: "Remote", target: "me@builder", session: "default", isEnabled: true)
        let command = try TerminalCommand.make(target: TerminalTarget(machine: machine, terminalID: "term_a", title: "", workspace: ""),
                                               mode: .observe, size: .init(), executable: nil)
        #expect(Array(command.arguments.dropLast(3)) == SSHOptions.stream)
    }

    @Test func aFolderOthersCanReadOrALinkIsNeverUsed() throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let open = SSHControlFolder(url: root.appendingPathComponent("open"))
        try FileManager.default.createDirectory(at: open.url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        #expect(!open.isReady)
        let real = SSHControlFolder(url: root.appendingPathComponent("real"))
        #expect(real.prepare())
        let link = SSHControlFolder(url: root.appendingPathComponent("link"))
        try FileManager.default.createSymbolicLink(at: link.url, withDestinationURL: real.url)
        #expect(!link.isReady)
        let file = SSHControlFolder(url: root.appendingPathComponent("file"))
        try Data().write(to: file.url)
        #expect(!file.prepare())
    }

    @Test func aHomeTooDeepForASocketGoesWithoutSharing() {
        // 45 bytes leave room for "/", the 40-character hash and ssh's 17-character temporary suffix.
        let deepest = "/" + String(repeating: "a", count: 44)
        #expect(SSHControlFolder(url: URL(fileURLWithPath: deepest)).fits)
        let deeper = SSHControlFolder(url: URL(fileURLWithPath: deepest + "b"))
        #expect(!deeper.fits)
        #expect(!deeper.prepare())
        #expect(!FileManager.default.fileExists(atPath: deeper.url.path))
        #expect(SSHOptions.sharing(in: deeper) == nil)
    }

    @Test func spacesAndPercentSignsReachSSHIntact() throws {
        let root = URL(fileURLWithPath: "/tmp/shep \(UUID().uuidString.prefix(4))%x", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = SSHControlFolder(url: root)
        #expect(folder.prepare())
        let options = try #require(SSHOptions.sharing(in: folder))
        #expect(options[3] == "ControlPath=\"\(root.path.replacingOccurrences(of: "%", with: "%%"))/%C\"")
    }
}
