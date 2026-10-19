import Foundation

/// The options of every SSH connection Shepherdr opens itself. It never asks for anything, only
/// connects to hosts already trusted, and forwards nothing. Commands to a machine share one
/// connection, as Herdr's own `--machine` calls do, instead of a full handshake every few seconds.
/// A terminal's stream keeps a connection of its own: ending a shared session leaves its remote
/// command running, and ending a stream must release the terminal.
public enum SSHOptions {
    /// Without a terminal, never prompting, only to trusted hosts, nothing forwarded.
    static let base = ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                       "-o", "ClearAllForwardings=yes", "-o", "ForwardAgent=no"]
    /// A connection that stops answering, as after the Mac slept or changed networks, ends within
    /// about 20 seconds, so nothing waits on it for long.
    static let keepAlive = ["-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2"]
    /// How long a shared connection stays open after its last command.
    static let persist = 60

    /// For commands: shared through `folder` when it is ready.
    static func command(sharingIn folder: SSHControlFolder? = .shared) -> [String] {
        base + keepAlive + (folder.flatMap(sharing) ?? [])
    }

    /// For a terminal's stream: never shared, even when the user's own SSH settings share connections.
    static let stream = base + keepAlive + ["-o", "ControlMaster=no", "-o", "ControlPath=none"]

    /// The options that share connections through a folder, or nil when ssh couldn't use it: it
    /// isn't there yet, isn't private, or its path is too long for a socket.
    static func sharing(in folder: SSHControlFolder) -> [String]? {
        guard folder.isReady else { return nil }
        // ssh reads the value as a line of its configuration: quoted for spaces, % escaped.
        let path = folder.url.path.replacingOccurrences(of: "%", with: "%%")
        return ["-o", "ControlMaster=auto", "-o", "ControlPath=\"\(path)/%C\"", "-o", "ControlPersist=\(persist)"]
    }

    /// Makes the folder shared connections live in. Shepherdr calls it once as it starts; until
    /// then, and wherever it can't, each command connects on its own.
    public static func prepareSharing() {
        _ = SSHControlFolder.shared.prepare()
    }
}

/// Where shared connections' sockets live: `~/.shepherdr/ssh`, readable only by you. ssh names each
/// after a 40-character hash of the connection, and creates it with a 17-character temporary
/// suffix first, and a socket's path can't be longer than 103 bytes: a folder deeper than 45 bytes,
/// under a very long home, goes without sharing.
public struct SSHControlFolder: Sendable {
    let url: URL

    init(url: URL) { self.url = url }

    /// In the home folder the agent tools' scripts see, `$HOME`.
    static var shared: SSHControlFolder {
        let home = ProcessInfo.processInfo.environment["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return SSHControlFolder(url: home.appendingPathComponent(".shepherdr/ssh", isDirectory: true))
    }

    /// Whether a socket in it fits: the folder, `/`, the hash and the temporary suffix.
    var fits: Bool {
        let path = url.path
        return path.hasPrefix("/") && !path.contains("\"") && path.rangeOfCharacter(from: .controlCharacters) == nil
            && path.utf8.count + 1 + 40 + 17 <= 103
    }

    /// A folder of yours that only you can read, not a link to one.
    var isReady: Bool {
        guard fits, let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return false }
        return attributes[.type] as? FileAttributeType == .typeDirectory
            && (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
            && ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777) & 0o077 == 0
    }

    /// Makes the folder, private, with `~/.shepherdr` if it isn't there yet. Returns whether ssh can use it.
    @discardableResult
    func prepare() -> Bool {
        guard fits else { return false }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        return isReady
    }
}
