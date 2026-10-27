import Foundation

/// Which GitHub repository each folder is in, asked of the machine the folders are on: this Mac
/// directly, others over SSH. A folder anywhere inside a repository counts. Its `origin` remote
/// names the repository, or else the first remote on GitHub.
public enum FolderRepositories {
    /// By folder, as given: its repository, or nil for a folder in no repository on GitHub. Nil when
    /// the machine doesn't answer.
    public static func lookUp(_ folders: [String], on machine: Machine) async -> [String: GitHubRepository?]? {
        guard !folders.isEmpty, let command = machine.shell(script, arguments: folders),
              let output = try? await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 20),
              output.exitCode == 0 else { return nil }
        return parse(String(decoding: output.stdout, as: UTF8.self), folders: folders)
    }

    static let script = """
    for folder in "$@"; do
      url=
      if [ -d "$folder" ]; then
        url=$(git -C "$folder" remote get-url origin 2>/dev/null) || url=
        if [ -z "$url" ]; then
          url=$(git -C "$folder" remote 2>/dev/null | while IFS= read -r remote; do
            candidate=$(git -C "$folder" remote get-url "$remote" 2>/dev/null)
            case $candidate in *github.com[:/]*) printf '%s' "$candidate"; break ;; esac
          done)
        fi
      fi
      printf 'shepherdr-folder %s\\t%s\\n' "$folder" "$url"
    done
    """

    /// Every folder asked about gets an answer; one the script didn't mention is in no repository.
    static func parse(_ output: String, folders: [String]) -> [String: GitHubRepository?] {
        var found: [String: GitHubRepository?] = Dictionary(uniqueKeysWithValues: folders.map { ($0, nil) })
        for line in output.split(separator: "\n") where line.hasPrefix("shepherdr-folder ") {
            let fields = line.dropFirst("shepherdr-folder ".count).split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, found.keys.contains(String(fields[0])) else { continue }
            // updateValue keeps a folder in no repository; assigning nil would drop it.
            found.updateValue(GitHubReference(String(fields[1]))?.repository, forKey: String(fields[0]))
        }
        return found
    }
}
