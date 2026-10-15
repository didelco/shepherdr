import Foundation

/// Files dropped on a terminal, made available to the agent running there: their paths are typed
/// into its prompt, and on another machine each file is copied there first.
public enum FileDrop {
    /// Characters a path may keep as they are; anything else is escaped with a backslash, as macOS
    /// terminals insert dropped files.
    private static let plain = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._/~+@%=:,")

    public static func escaped(_ path: String) -> String {
        path.unicodeScalars.map { plain.contains($0) || $0.value > 127 ? String($0) : "\\\($0)" }.joined()
    }

    /// What a drop types: each path as its own bracketed paste, which is how Claude Code and Codex
    /// tell a pasted image path from typing and attach the image, with spaces between them.
    public static func paste(_ paths: [String]) -> Data {
        let pastes = paths.map { path in
            Data("\u{1b}[200~".utf8) + Data(escaped(path).replacingOccurrences(of: "\u{1b}", with: "").utf8) + Data("\u{1b}[201~".utf8)
        }
        return pastes.reduce(into: Data()) { result, paste in
            if !result.isEmpty { result.append(Data(" ".utf8)) }
            result.append(paste)
        }
    }

    /// A file name that is safe in a shell on any machine, keeping its extension.
    static func safeName(_ name: String) -> String {
        let safe = String(name.unicodeScalars.map { scalar in
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._").contains(scalar)
                ? Character(scalar) : "_"
        })
        let trimmed = safe.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "file" : String(trimmed.prefix(120))
    }

    /// The SSH command that copies standard input to `~/.cache/shepherdr/drops/<folder>/<name>` on
    /// a machine and prints that path. Drops older than a week are cleared on the way.
    static func uploadCommand(name: String, folder: String, sshTarget: String) -> (executable: URL, arguments: [String]) {
        let file = "$HOME/.cache/shepherdr/drops/\(folder)/\(safeName(name))"
        let script = """
        umask 077
        find "$HOME/.cache/shepherdr/drops" -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null
        mkdir -p "$HOME/.cache/shepherdr/drops/\(folder)" && cat > "\(file)" && printf '%s' "\(file)"
        """
        return (URL(fileURLWithPath: "/usr/bin/ssh"),
                ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                 "--", sshTarget, "sh -c \(TerminalCommand.quote(script))"])
    }

    /// Copies a file to a remote machine over SSH and returns its path there.
    public static func upload(_ file: URL, to machine: Machine) async throws -> String {
        guard let target = machine.checkedSSHTarget else { throw HerdrFailure(.incompatible, "The saved SSH target is invalid.") }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw HerdrFailure(.incompatible, "Only files can be copied to \(machine.name).") }
        guard (values.fileSize ?? 0) <= 200_000_000 else { throw HerdrFailure(.incompatible, "\(file.lastPathComponent) is over 200 MB.") }
        let command = uploadCommand(name: file.lastPathComponent, folder: UUID().uuidString, sshTarget: target)
        let output: CommandOutput
        do {
            output = try await ProcessRunner().run(executable: command.executable, arguments: command.arguments,
                                                   timeout: 300, input: file)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, "Copying \(file.lastPathComponent) to \(machine.name) took too long.")
        }
        let path = String(decoding: output.stdout, as: UTF8.self)
        guard output.exitCode == 0, path.hasPrefix("/") else {
            let detail = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.unreachable, "Could not copy \(file.lastPathComponent) to \(machine.name).", detail: detail.isEmpty ? nil : detail)
        }
        return path
    }
}
