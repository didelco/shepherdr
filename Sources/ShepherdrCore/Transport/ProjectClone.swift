import Foundation

/// A GitHub repository's clone on a machine: found among the folders you already have, or cloned
/// into its projects folder, with pull requests' commits fetched into it. On this Mac directly, on
/// other machines over SSH. Git never asks for anything: a clone or fetch that needs a password fails.
public enum ProjectClone {
    /// Where the repository's clone is, or would go.
    public enum Location: Equatable, Sendable {
        /// Already cloned there, with the remote that points at the repository.
        case cloned(path: String, remote: String)
        /// Nothing there yet, or an empty folder: cloning goes there.
        case free(String)
        /// Something else is there.
        case taken(String)
    }

    /// Looks for the repository in the folder it would be cloned into, then in other checkouts, such
    /// as those sessions work in. Paths may start with `~`, that machine's home. Nil when the
    /// machine doesn't answer.
    public static func locate(_ repository: GitHubRepository, in destination: String, orAmong candidates: [String] = [],
                              on machine: Machine) async -> Location? {
        guard let command = machine.shell(locateScript, arguments: [destination] + candidates),
              let output = try? await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 20),
              output.exitCode == 0 else { return nil }
        return location(of: repository, in: inspection(String(decoding: output.stdout, as: UTF8.self)))
    }

    /// Clones the repository into a folder that is free. A repository given as an SSH remote is cloned
    /// from it; otherwise over HTTPS, through the GitHub CLI when it is signed in there.
    public static func clone(_ repository: GitHubRepository, into path: String, on machine: Machine) async throws {
        guard let command = machine.shell(cloneScript, arguments: [repository.fullName, path, repository.sshRemote ?? ""]) else {
            throw HerdrFailure(.incompatible, "The saved SSH target is invalid.")
        }
        try await run(command, timeout: 600, failure: "Could not clone \(repository.fullName).",
                      tooLong: "Cloning \(repository.fullName) on \(machine.name) took too long.")
    }

    /// Fetches a pull request's commits into a clone and returns the ref to start its worktree from:
    /// its branch, when it lives in the repository and still exists, else GitHub's `pull/N/head`.
    public static func fetch(pullRequest number: Int, branch: String?, from remote: String, in path: String,
                             on machine: Machine) async throws -> String {
        guard let command = machine.shell(fetchScript, arguments: [path, remote, String(number), branch ?? ""]) else {
            throw HerdrFailure(.incompatible, "The saved SSH target is invalid.")
        }
        let output = try await run(command, timeout: 300, failure: "Could not fetch pull request #\(number).",
                                   tooLong: "Fetching pull request #\(number) on \(machine.name) took too long.")
        let text = String(decoding: output.stdout, as: UTF8.self)
        guard let marker = text.range(of: "shepherdr-base ", options: .backwards) else {
            throw HerdrFailure(.unreachable, "Could not fetch pull request #\(number).")
        }
        return String(text[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    private static func run(_ command: (executable: URL, arguments: [String]), timeout: TimeInterval, failure: String,
                            tooLong: String) async throws -> CommandOutput {
        let output: CommandOutput
        do {
            output = try await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: timeout)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, tooLong)
        }
        guard output.exitCode == 0 else {
            let detail = String(decoding: output.stderr.suffix(2_048), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.unreachable, failure, detail: detail.isEmpty ? nil : detail)
        }
        return output
    }

    /// One folder as the locate script found it.
    struct Inspected: Equatable {
        enum State: String { case repository, empty, folder, other, missing }
        let state: State
        let path: String
        /// The repository's remotes, by name.
        var remotes: [(name: String, url: String)] = []

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.state == rhs.state && lhs.path == rhs.path && lhs.remotes.map(\.name) == rhs.remotes.map(\.name)
                && lhs.remotes.map(\.url) == rhs.remotes.map(\.url)
        }
    }

    /// Reads the locate script's lines: `shepherdr-clone <state> <path>`, each repository followed by
    /// its `shepherdr-remote <name>\t<url>` lines. Anything else, such as a login banner, is skipped.
    static func inspection(_ output: String) -> [Inspected] {
        var found: [Inspected] = []
        // Remotes belong to the repository line right before them, and only to one that was read.
        var collecting = false
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if let rest = line.dropPrefix("shepherdr-clone ") {
                collecting = false
                guard let space = rest.firstIndex(of: " "), let state = Inspected.State(rawValue: String(rest[..<space])) else { continue }
                let path = String(rest[rest.index(after: space)...])
                guard path.hasPrefix("/") else { continue }
                found.append(Inspected(state: state, path: path))
                collecting = state == .repository
            } else if collecting, let rest = line.dropPrefix("shepherdr-remote "), let tab = rest.firstIndex(of: "\t") {
                found[found.count - 1].remotes.append((String(rest[..<tab]), String(rest[rest.index(after: tab)...])))
            }
        }
        return found
    }

    /// The first folder with a remote pointing at the repository, else what the destination, listed
    /// first, holds. A remote named `origin` wins over others pointing there too.
    static func location(of repository: GitHubRepository, in inspected: [Inspected]) -> Location? {
        for folder in inspected where folder.state == .repository {
            let matching = folder.remotes.filter { repository.isRemote($0.url) }
            if let remote = matching.first(where: { $0.name == "origin" }) ?? matching.first {
                return .cloned(path: folder.path, remote: remote.name)
            }
        }
        guard let destination = inspected.first else { return nil }
        switch destination.state {
        case .missing, .empty: return .free(destination.path)
        case .repository, .folder, .other: return .taken(destination.path)
        }
    }

    /// The absolute path `$1` names, in `$folder`: `~` is this machine's home, and relative paths start there.
    private static let absolute = """
    absolute() {
      case $1 in
        /*) folder=$1 ;;
        "~") folder=$HOME ;;
        "~/"*) folder=$HOME/${1#"~/"} ;;
        *) folder=$HOME/$1 ;;
      esac
    }

    """

    /// Git and the GitHub CLI fail instead of asking for a password or a host key.
    private static let quiet = """
    export GIT_TERMINAL_PROMPT=0 GH_PROMPT_DISABLED=1 GIT_SSH_COMMAND='ssh -o BatchMode=yes'

    """

    /// A folder counts as a repository only at its top, not inside another repository.
    static let locateScript = absolute + """
    for path in "$@"; do
      absolute "$path"
      if [ -d "$folder" ]; then
        top=$(git -C "$folder" rev-parse --show-toplevel 2>/dev/null) || top=
        here=$(cd -P -- "$folder" 2>/dev/null && pwd -P) || here=
        if [ -n "$top" ] && [ "$(cd -P -- "$top" 2>/dev/null && pwd -P)" = "$here" ]; then
          printf 'shepherdr-clone repository %s\\n' "$folder"
          git -C "$folder" remote 2>/dev/null | while IFS= read -r remote; do
            printf 'shepherdr-remote %s\\t%s\\n' "$remote" "$(git -C "$folder" remote get-url "$remote" 2>/dev/null)"
          done
        elif [ -z "$(ls -A -- "$folder" 2>/dev/null)" ]; then
          printf 'shepherdr-clone empty %s\\n' "$folder"
        else
          printf 'shepherdr-clone folder %s\\n' "$folder"
        fi
      elif [ -e "$folder" ]; then
        printf 'shepherdr-clone other %s\\n' "$folder"
      else
        printf 'shepherdr-clone missing %s\\n' "$folder"
      fi
    done
    """

    static let cloneScript = absolute + quiet + """
    absolute "$2"
    mkdir -p -- "$(dirname -- "$folder")" || exit 1
    if [ -n "$3" ]; then
      git clone -q -- "$3" "$folder"
    elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
      gh repo clone "$1" "$folder" -- -q
    else
      git clone -q -- "https://github.com/$1.git" "$folder"
    fi
    """

    /// The branch goes to its usual remote-tracking ref; GitHub's ref for the pull request, which
    /// also covers forks and deleted branches, to `<remote>/pull/<number>`.
    static let fetchScript = absolute + quiet + """
    absolute "$1"
    cd -- "$folder" || exit 1
    if [ -n "$4" ] && git fetch -q -- "$2" "+refs/heads/$4:refs/remotes/$2/$4" 2>/dev/null; then
      printf 'shepherdr-base %s/%s\\n' "$2" "$4"
    else
      git fetch -q -- "$2" "+refs/pull/$3/head:refs/remotes/$2/pull/$3" || exit 1
      printf 'shepherdr-base %s/pull/%s\\n' "$2" "$3"
    fi
    """
}

private extension Substring {
    func dropPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }
}
