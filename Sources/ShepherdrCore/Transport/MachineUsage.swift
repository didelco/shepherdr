import Foundation

/// How busy a machine is, in percent: its processors over one second, the memory in use, and the
/// disk holding the home folder. Herdr doesn't report it, so Shepherdr measures it itself: on this
/// Mac directly, and on other machines over SSH. Nil where the machine couldn't tell.
public struct MachineUsage: Equatable, Sendable {
    public let cpu: Int?
    public let memory: Int?
    public let disk: Int?

    public init(cpu: Int?, memory: Int?, disk: Int?) {
        self.cpu = cpu
        self.memory = memory
        self.disk = disk
    }

    /// Measures a machine; nil when it doesn't answer.
    public static func read(_ machine: Machine) async -> MachineUsage? {
        guard let command = command(for: machine),
              let output = try? await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 20),
              output.exitCode == 0 else { return nil }
        return parse(String(decoding: output.stdout, as: UTF8.self))
    }

    /// Reads the line the script prints, such as `shepherdr-usage 12 45 -`.
    static func parse(_ output: String) -> MachineUsage? {
        guard let line = output.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("shepherdr-usage ") }) else { return nil }
        let values = line.split(separator: " ").dropFirst().map { Int($0).map { min(100, max(0, $0)) } }
        guard values.count == 3, values.contains(where: { $0 != nil }) else { return nil }
        return MachineUsage(cpu: values[0], memory: values[1], disk: values[2])
    }

    /// Only tools every Linux and macOS has: /proc or iostat and vm_stat, and df. Memory in use is
    /// what Activity Monitor and `free` count: on macOS app memory, wired and compressed.
    static let script = """
    export LC_ALL=C
    cpu=- mem=- disk=-
    case "$(uname -s)" in
    Linux)
      read -r _ a b c d e f g h _ < /proc/stat
      sleep 1
      read -r _ A B C D E F G H _ < /proc/stat
      total=$(( (A+B+C+D+E+F+G+H) - (a+b+c+d+e+f+g+h) ))
      idle=$(( (D+E) - (d+e) ))
      [ "$total" -gt 0 ] && cpu=$(( (total - idle) * 100 / total ))
      mem=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END {if (t > 0) printf "%d", (t-a)*100/t}' /proc/meminfo)
      ;;
    Darwin)
      cpu=$(iostat -n 0 -c 2 -w 1 | awk 'END {if (NF >= 3) printf "%d", 100-$3}')
      mem=$(vm_stat | awk -v total="$(sysctl -n hw.memsize)" '
        /page size of/ {for (i = 1; i < NF; i++) if ($i == "of") size = $(i+1)}
        /^Anonymous pages/ {anon = $3} /^Pages purgeable/ {purge = $3}
        /^Pages wired down/ {wired = $4} /^Pages occupied by compressor/ {comp = $5}
        END {if (total > 0 && size > 0) printf "%d", (anon-purge+wired+comp)*size*100/total}')
      ;;
    esac
    disk=$(df -P "$HOME" 2>/dev/null | awk 'NR == 2 {sub("%", "", $5); print $5}')
    echo "shepherdr-usage ${cpu:--} ${mem:--} ${disk:--}"
    """

    static func command(for machine: Machine) -> (executable: URL, arguments: [String])? { machine.shell(script) }
}
