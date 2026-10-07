import Foundation

struct TerminalCommand: Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]

    static func make(target: TerminalTarget, mode: TerminalMode, size: TerminalSize,
                     executable: URL?, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard target.machine.isEnabled, !target.terminalID.isEmpty,
              !target.terminalID.hasPrefix("-"), !target.machine.session.isEmpty,
              !target.machine.session.hasPrefix("-"),
              target.terminalID.rangeOfCharacter(from: .controlCharacters) == nil,
              target.machine.session.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw HerdrFailure(.incompatible, "The terminal target is unavailable or invalid.")
        }
        var clean = environment
        for key in ["HERDR_SESSION", "HERDR_SOCKET_PATH", "HERDR_PANE_ID", "HERDR_WORKSPACE_ID", "HERDR_TAB_ID"] {
            clean.removeValue(forKey: key)
        }
        clean["SSH_ASKPASS_REQUIRE"] = "never"
        clean["NO_COLOR"] = "1"
        let arguments = ["--session", target.machine.session, "terminal", "session", mode.subcommand,
                         target.terminalID, "--cols", String(size.columns), "--rows", String(size.rows)]
            + (mode == .takeover ? ["--takeover"] : [])
        if target.machine.isLocal {
            return Self(executable: try executable ?? ExecutableLocator().locate(), arguments: arguments, environment: clean)
        }
        guard let sshTarget = target.machine.target, !sshTarget.isEmpty, !sshTarget.hasPrefix("-"),
              sshTarget.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) == nil else {
            throw HerdrFailure(.incompatible, "The saved SSH target is invalid.")
        }
        // --machine cannot forward terminal session streams. Run the same installed Herdr CLI
        // over SSH without a PTY. Only fixed script text and individually quoted arguments enter
        // the remote login shell; terminal input stays JSON on stdin, never shell source.
        let script = """
        unset HERDR_SESSION HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_WORKSPACE_ID HERDR_TAB_ID
        shepherdr_herdr=$(command -v herdr 2>/dev/null) || shepherdr_herdr=
        if [ -z "$shepherdr_herdr" ]; then
          for shepherdr_candidate in "$HOME/.local/bin/herdr" /opt/homebrew/bin/herdr /usr/local/bin/herdr "$HOME/.cargo/bin/herdr"; do
            if [ -x "$shepherdr_candidate" ]; then shepherdr_herdr=$shepherdr_candidate; break; fi
          done
        fi
        if [ -z "$shepherdr_herdr" ]; then echo 'Herdr is not installed or not on the remote PATH.' >&2; exit 127; fi
        exec "$shepherdr_herdr" \(arguments.map(quote).joined(separator: " "))
        """
        return Self(executable: URL(fileURLWithPath: "/usr/bin/ssh"),
                    arguments: ["-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                                "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
                                "-o", "ClearAllForwardings=yes", "-o", "ForwardAgent=no", "--", sshTarget,
                                "sh -c \(quote(script))"], environment: clean)
    }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
