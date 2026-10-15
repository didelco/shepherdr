import Foundation

extension Machine {
    /// The saved SSH target, when it can only be read as a host and never as an option.
    var checkedSSHTarget: String? {
        guard let target, !target.isEmpty, !target.hasPrefix("-"),
              target.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }
        return target
    }

    /// Runs a POSIX sh script with arguments: on this Mac directly, and on other machines over SSH,
    /// noninteractively and without forwarding anything. Nil for a disabled machine or an unsafe target.
    func shell(_ script: String, arguments: [String] = []) -> (executable: URL, arguments: [String])? {
        if isLocal { return (URL(fileURLWithPath: "/bin/sh"), ["-c", script, "sh"] + arguments) }
        guard isEnabled, let target = checkedSSHTarget else { return nil }
        let command = (["sh -c", TerminalCommand.quote(script), "sh"] + arguments.map(TerminalCommand.quote)).joined(separator: " ")
        return (URL(fileURLWithPath: "/usr/bin/ssh"),
                ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                 "-o", "ClearAllForwardings=yes", "-o", "ForwardAgent=no", "--", target, command])
    }
}
