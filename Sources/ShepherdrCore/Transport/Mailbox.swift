import Foundation

/// Collects the letters agents leave in `~/.shepherdr/outbox` on a machine: on this Mac directly,
/// and on other machines over the same SSH connection Shepherdr already uses. Machines never
/// connect back; Shepherdr always fetches.
///
/// A trip prints the waiting letters as one stream: `L <id>` starts a letter, and each
/// `F <bytes> <path>` line is followed by that many bytes of the file and a newline. Only regular
/// files with the names `shepherdr` writes cross. Shepherdr keeps the letters on this Mac first,
/// then moves them to `outbox/.collected` there, so a failed trip only collects them again.
public enum Mailbox {
    /// The letters of one trip, and whether more were left for the next one.
    public struct Delivery: Equatable, Sendable {
        public var letters: [Collected]
        public var hasMore: Bool
    }

    /// A letter as it arrived: its files by path inside it, or why it couldn't be read.
    public struct Collected: Equatable, Sendable {
        public let id: String
        public let contents: [String: Data]
    }

    /// Bytes one trip brings at most: a letter's attachments stop at 5 MB.
    static let tripLimit = 7 * 1_024 * 1_024
    static let lettersPerTrip = 50

    /// Prints waiting letters, oldest first, until the trip's limits. Both scripts run in the C locale:
    /// otherwise bash, /bin/sh on some Linux systems, takes ranges such as `[A-Z]` from the collation
    /// of the locale SSH passes along.
    static let collectScript = """
    export LC_ALL=C
    box="$HOME/.shepherdr/outbox"
    limit=$1
    echo 'shepherdr-mail 1'
    total=0
    count=0
    more=0
    if [ -d "$box" ]; then
      for letter in "$box"/*; do
        [ -d "$letter" ] || continue
        id=${letter##*/}
        case $id in '' | *[!A-Za-z0-9-]*) continue ;; esac
        if [ "$count" -ge \(lettersPerTrip) ]; then more=1; break; fi
        size=0
        for file in "$letter/letter.json" "$letter/message.md" "$letter"/files/*; do
          [ -f "$file" ] && [ ! -h "$file" ] || continue
          size=$((size + $(wc -c < "$file")))
        done
        if [ "$count" -gt 0 ] && [ $((total + size)) -gt "$limit" ]; then more=1; break; fi
        total=$((total + size))
        count=$((count + 1))
        echo "L $id"
        for file in "$letter/letter.json" "$letter/message.md" "$letter"/files/*; do
          [ -f "$file" ] && [ ! -h "$file" ] || continue
          name=${file#"$letter"/}
          case $name in letter.json | message.md | files/[A-Za-z0-9_-]*) ;; *) continue ;; esac
          case $name in files/*/* | *[!A-Za-z0-9._/-]*) continue ;; esac
          echo "F $(($(wc -c < "$file"))) $name"
          cat "$file"
          echo
        done
      done
    fi
    echo "D $more"
    """

    /// Moves collected letters out of the way, and clears what was collected over a week ago.
    static let acknowledgeScript = """
    export LC_ALL=C
    box="$HOME/.shepherdr/outbox"
    [ -d "$box" ] || { echo shepherdr-acknowledged; exit 0; }
    mkdir -p "$box/.collected"
    for id in "$@"; do
      case $id in '' | *[!A-Za-z0-9-]*) continue ;; esac
      [ -d "$box/$id" ] || continue
      rm -rf "$box/.collected/$id"
      mv "$box/$id" "$box/.collected/$id" && touch "$box/.collected/$id"
    done
    find "$box/.collected" -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} + 2>/dev/null
    find "$box" -mindepth 1 -maxdepth 1 -name '.tmp-*' -mtime +1 -exec rm -rf {} + 2>/dev/null
    echo shepherdr-acknowledged
    """

    public static func collect(from machine: Machine) async throws -> Delivery {
        guard let command = machine.shell(collectScript, arguments: [String(tripLimit)]) else {
            throw HerdrFailure(.incompatible, "Shepherdr can't reach \(machine.name) over SSH.")
        }
        let output = try await run(command, on: machine, action: "collect letters from")
        return try parse(output.stdout)
    }

    public static func acknowledge(_ ids: [String], on machine: Machine) async throws {
        let ids = ids.filter(Letter.isValidID)
        guard !ids.isEmpty else { return }
        guard let command = machine.shell(acknowledgeScript, arguments: ids) else {
            throw HerdrFailure(.incompatible, "Shepherdr can't reach \(machine.name) over SSH.")
        }
        let output = try await run(command, on: machine, action: "file the letters on")
        guard String(decoding: output.stdout, as: UTF8.self).contains("shepherdr-acknowledged") else {
            throw HerdrFailure(.unreachable, "Could not file the letters on \(machine.name).")
        }
    }

    static func run(_ command: (executable: URL, arguments: [String]), on machine: Machine, action: String) async throws -> CommandOutput {
        let output: CommandOutput
        do {
            output = try await ProcessRunner().run(executable: command.executable, arguments: command.arguments, timeout: 60)
        } catch CommandError.timedOut {
            throw HerdrFailure(.unreachable, "\(machine.name) took too long to answer.")
        } catch CommandError.outputTooLarge {
            throw HerdrFailure(.incompatible, "The letters from \(machine.name) are over the limit.")
        }
        guard output.exitCode == 0 else {
            let detail = String(decoding: output.stderr.prefix(2_048), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw HerdrFailure(.unreachable, "Could not \(action) \(machine.name).", detail: detail.isEmpty ? nil : detail)
        }
        return output
    }

    /// Reads a trip's stream. Anything out of place ends it as incompatible: the stream comes
    /// from a script Shepherdr wrote, so a surprise means something else answered.
    static func parse(_ data: Data) throws -> Delivery {
        let bytes = [UInt8](data)
        var index = 0
        func line() throws -> String {
            guard let end = bytes[index...].firstIndex(of: 0x0A) else { throw incompatible }
            defer { index = end + 1 }
            return String(decoding: bytes[index..<end], as: UTF8.self)
        }
        let incompatible = HerdrFailure(.incompatible, "The machine's answer wasn't a list of letters.")
        // Login banners and shell startup output may come first.
        while try line() != "shepherdr-mail 1" {}
        var letters: [Collected] = []
        var current: (id: String, contents: [String: Data])?
        while index < bytes.count {
            let header = try line()
            let fields = header.split(separator: " ", maxSplits: 2).map(String.init)
            switch fields.first {
            case "L":
                guard fields.count == 2, fields[1].range(of: #"^[A-Za-z0-9-]{1,80}$"#, options: .regularExpression) != nil else { throw incompatible }
                if let current { letters.append(Collected(id: current.id, contents: current.contents)) }
                current = (fields[1], [:])
            case "F":
                guard fields.count == 3, current != nil, let size = Int(fields[1]), size >= 0, size <= tripLimit,
                      fields[2] == "letter.json" || fields[2] == "message.md" || Letter.isValidFile(fields[2]),
                      index + size < bytes.count, bytes[index + size] == 0x0A else { throw incompatible }
                current?.contents[fields[2]] = Data(bytes[index..<(index + size)])
                index += size + 1
            case "D":
                guard fields.count == 2 else { throw incompatible }
                if let current { letters.append(Collected(id: current.id, contents: current.contents)) }
                return Delivery(letters: letters, hasMore: fields[1] == "1")
            default:
                throw incompatible
            }
        }
        throw incompatible
    }

    // MARK: Letters kept on this Mac

    /// Where collected letters are kept: `~/.shepherdr/inbox/<machine>/<id>`. Handoffs point
    /// agents on this Mac at their files there. The home folder is the one the tools' scripts
    /// see, `$HOME`, so both agree on where `~/.shepherdr` is.
    public static func inbox(home: URL? = nil) -> URL {
        let home = home ?? ProcessInfo.processInfo.environment["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".shepherdr/inbox", isDirectory: true)
    }

    /// The folder of a machine's letters: its name, made safe for a path.
    public static func folderName(for machine: Machine) -> String {
        machine.isLocal ? "local" : FileDrop.safeName(machine.name)
    }

    /// Keeps a letter's files on this Mac, readable only by you. Returns its folder.
    public static func keep(_ letter: Collected, from machine: Machine, in inbox: URL) throws -> URL {
        let folder = inbox.appendingPathComponent(folderName(for: machine), isDirectory: true)
            .appendingPathComponent(letter.id, isDirectory: true)
        let manager = FileManager.default
        try? manager.removeItem(at: folder)
        try manager.createDirectory(at: folder.appendingPathComponent("files"), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        for (path, data) in letter.contents {
            // The stream's parser already allowed only these names; check again before writing.
            guard path == "letter.json" || path == "message.md" || Letter.isValidFile(path) else { continue }
            let url = folder.appendingPathComponent(path)
            guard url.standardizedFileURL.path.hasPrefix(folder.standardizedFileURL.path + "/") else { continue }
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return folder
    }

    /// Clears letters kept for over a month.
    public static func tidy(_ inbox: URL, olderThan age: TimeInterval = 30 * 86_400, now: Date = Date()) {
        let manager = FileManager.default
        guard let machines = try? manager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil) else { return }
        for machine in machines {
            guard let letters = try? manager.contentsOfDirectory(at: machine, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for letter in letters where Letter.isValidID(letter.lastPathComponent) {
                let date = (try? letter.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
                if now.timeIntervalSince(date) > age { try? manager.removeItem(at: letter) }
            }
        }
    }
}
