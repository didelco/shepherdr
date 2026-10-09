import Foundation

/// The folder a new session starts in, checked on its machine, and made there for a new project:
/// on this Mac directly, and on other machines over SSH. Herdr opens a workspace whose folder
/// is missing in the home folder instead, without a word, and doesn't expand `~`.
public enum ProjectFolder {
    /// What a path leads to, with the absolute path it names on that machine.
    public enum State: Equatable, Sendable {
        case folder(String)
        case missing(String)
        case notAFolder(String)
    }

    /// Where a path leads on a machine: `~` is that machine's home, and relative paths start there.
    /// Nil when the machine doesn't answer.
    public static func check(_ path: String, on machine: Machine) async -> State? {
        guard let command = machine.shell(checkScript, arguments: [path]),
              let output = try? await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 20),
              output.exitCode == 0 else { return nil }
        return parse(String(decoding: output.stdout, as: UTF8.self))
    }

    /// Makes the folder, with any missing parents, and an empty Git repository in it.
    public static func create(_ path: String, on machine: Machine) async throws {
        guard let command = machine.shell(createScript, arguments: [path]) else {
            throw HerdrFailure(.incompatible, "The saved SSH target is invalid.")
        }
        let output: CommandOutput
        do {
            output = try await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 30)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, "Creating the project on \(machine.name) took too long.")
        }
        guard output.exitCode == 0 else {
            let detail = String(decoding: output.stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.unreachable, "Could not create the project.", detail: detail.isEmpty ? nil : detail)
        }
    }

    /// Reads what the check script prints last, such as `shepherdr-folder missing /home/me/app`.
    static func parse(_ output: String) -> State? {
        guard let marker = output.range(of: "shepherdr-folder ", options: .backwards) else { return nil }
        var line = output[marker.upperBound...]
        if line.hasSuffix("\n") { line = line.dropLast() }
        guard let space = line.firstIndex(of: " ") else { return nil }
        let path = String(line[line.index(after: space)...])
        guard path.hasPrefix("/") else { return nil }
        switch line[..<space] {
        case "folder": return .folder(path)
        case "missing": return .missing(path)
        case "other": return .notAFolder(path)
        default: return nil
        }
    }

    /// The absolute path `$1` names, in `$folder`.
    private static let resolve = """
    case $1 in
      /*) folder=$1 ;;
      "~") folder=$HOME ;;
      "~/"*) folder=$HOME/${1#"~/"} ;;
      *) folder=$HOME/$1 ;;
    esac
    """

    static let checkScript = resolve + """

    if [ -d "$folder" ]; then state=folder; elif [ -e "$folder" ]; then state=other; else state=missing; fi
    printf 'shepherdr-folder %s %s\\n' "$state" "$folder"
    """

    static let createScript = resolve + """

    mkdir -p -- "$folder" && cd -- "$folder" && git init -q
    """
}
