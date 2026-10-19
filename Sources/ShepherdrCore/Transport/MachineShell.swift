import Foundation

extension Machine {
    /// The saved SSH target, when it can only be read as a host and never as an option.
    var checkedSSHTarget: String? {
        guard let target, !target.isEmpty, !target.hasPrefix("-"),
              target.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) == nil else { return nil }
        return target
    }

    /// Runs a POSIX sh script with arguments: on this Mac directly, and on other machines over SSH,
    /// noninteractively, without forwarding anything, and over the connection Shepherdr's other
    /// commands to that machine share. Nil for a disabled machine or an unsafe target.
    func shell(_ script: String, arguments: [String] = []) -> (executable: URL, arguments: [String])? {
        if isLocal { return (URL(fileURLWithPath: "/bin/sh"), ["-c", script, "sh"] + arguments) }
        guard isEnabled, let target = checkedSSHTarget else { return nil }
        let command = (["sh -c", TerminalCommand.quote(script), "sh"] + arguments.map(TerminalCommand.quote)).joined(separator: " ")
        return (URL(fileURLWithPath: "/usr/bin/ssh"), SSHOptions.command() + ["--", target, command])
    }

    /// Runs a POSIX sh script read from standard input, the same way: for scripts too long for a
    /// command line, such as the agent tools' installer.
    func shellReadingStandardInput() -> (executable: URL, arguments: [String])? {
        if isLocal { return (URL(fileURLWithPath: "/bin/sh"), ["-s"]) }
        guard isEnabled, let target = checkedSSHTarget else { return nil }
        return (URL(fileURLWithPath: "/usr/bin/ssh"), SSHOptions.command() + ["--", target, "sh -s"])
    }
}
