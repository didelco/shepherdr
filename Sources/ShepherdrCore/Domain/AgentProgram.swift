import Foundation

/// The agent working in a session, from the label Herdr detects it by, such as `claude` or `codex`:
/// its name and the mark its own interface shows, so each session says which agent runs there.
public struct AgentProgram: Equatable, Sendable {
    /// Herdr's label, such as `claude`, or what an agent Herdr doesn't know calls itself.
    public let label: String
    public let name: String
    /// The mark the agent's own banner shows, such as Claude Code's ✻ and Codex's >_; ◇ otherwise.
    public let glyph: String

    public init(label: String) {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = Self.known[label.lowercased()]
        self.label = label.isEmpty ? "agent" : label
        name = known?.name ?? (label.isEmpty ? "Unknown agent" : label)
        glyph = known?.glyph ?? "◇"
    }

    /// Herdr's agent labels, from its detector.
    private static let known: [String: (name: String, glyph: String)] = [
        "claude": ("Claude Code", "✻"),
        "codex": ("Codex", ">_"),
        "gemini": ("Gemini CLI", "✦"),
        "pi": ("pi", "◇"),
        "omp": ("omp", "◇"),
        "cursor": ("Cursor Agent", "◇"),
        "devin": ("Devin", "◇"),
        "agy": ("Antigravity", "◇"),
        "cline": ("Cline", "◇"),
        "mastracode": ("Mastra Code", "◇"),
        "opencode": ("opencode", "◇"),
        "copilot": ("GitHub Copilot", "◇"),
        "kimi": ("Kimi Code", "◇"),
        "kiro": ("Kiro", "◇"),
        "droid": ("Droid", "◇"),
        "amp": ("Amp", "◇"),
        "grok": ("Grok", "◇"),
        "hermes": ("Hermes", "◇"),
        "kilo": ("Kilo Code", "◇"),
        "qodercli": ("Qoder", "◇"),
        "qwen": ("Qwen Code", "◇"),
        "letta": ("Letta Code", "◇"),
        "maki": ("maki", "◇"),
        "muse": ("Muse", "◇"),
    ]
}

extension Agent {
    public var program: AgentProgram { AgentProgram(label: kind) }
}
