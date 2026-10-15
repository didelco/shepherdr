import CryptoKit
import Foundation
import SystemConfiguration

/// The machines `shepherdr` knows about, as Shepherdr writes them to `~/.shepherdr/machines` on
/// each machine with the agent tools. Each machine gets its own view: where it is, and how it
/// reaches every other machine. Only names and routes travel: never hosts, users or keys. Herdr
/// profile IDs only go to this Mac's own list, the one place they mean anything.
///
/// The file is tab-separated, after a header with a revision that changes with the content:
///
///     # shepherdr machines 1 rev 3f2a9c1b7e04 2026-10-15T10:15:02Z
///     buildbox	here	-
///     Studio	shepherdr	-
public enum MachineList {
    public enum Route: String, Sendable {
        /// The machine the list is on.
        case here
        /// Its Herdr reaches the machine through a saved profile: only on this Mac.
        case direct
        /// Only Shepherdr reaches it, after the user approves.
        case shepherdr
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let route: Route
        public let profile: String?
    }

    public static let format = 1

    /// The list for one machine: itself first, then this Mac, then the others in Herdr's order.
    /// Disabled machines are left out. A machine that doesn't share the list only sees itself.
    public static func entries(for perspective: Machine, machines: [Machine], macName: String, shares: Bool = true) -> [Entry] {
        let enabled = withLocal(machines).filter(\.isEnabled)
        let names = uniqueNames(enabled, macName: macName)
        let ordered = [perspective] + enabled.filter(\.isLocal) + enabled.filter { !$0.isLocal }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.id).inserted }.compactMap { machine in
            guard let name = names[machine.id] else { return nil }
            if machine.id == perspective.id { return Entry(name: name, route: .here, profile: nil) }
            guard shares else { return nil }
            if perspective.isLocal, let profile = machine.profileID { return Entry(name: name, route: .direct, profile: profile) }
            return Entry(name: name, route: .shepherdr, profile: nil)
        }
    }

    /// The name a machine goes by in the lists.
    public static func name(of machine: Machine, among machines: [Machine], macName: String) -> String {
        uniqueNames(withLocal(machines + [machine]), macName: macName)[machine.id] ?? clean(machine.name)
    }

    /// Machines with this Mac among them, each once.
    static func withLocal(_ machines: [Machine]) -> [Machine] {
        var seen = Set<String>()
        return ([Machine.local] + machines).filter { seen.insert($0.id).inserted }
    }

    /// The name each machine goes by in the lists: one line of text, unique ignoring case.
    public static func uniqueNames(_ machines: [Machine], macName: String) -> [String: String] {
        var result: [String: String] = [:]
        var taken = Set<String>()
        for machine in machines where result[machine.id] == nil {
            let base = clean(machine.isLocal ? macName : machine.name)
            var name = base
            var number = 2
            while !taken.insert(name.lowercased()).inserted {
                name = "\(base) \(number)"
                number += 1
            }
            result[machine.id] = name
        }
        return result
    }

    /// A name without tabs or line breaks, which the file can't hold.
    static func clean(_ name: String) -> String {
        let flat = String(name.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
            .trimmingCharacters(in: .whitespaces)
        let collapsed = flat.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return collapsed.isEmpty ? "machine" : String(collapsed.prefix(64))
    }

    static func body(_ entries: [Entry]) -> String {
        entries.map { "\($0.name)\t\($0.route.rawValue)\t\($0.profile ?? "-")\n" }.joined()
    }

    /// Changes whenever the list does, so a check can tell whether a machine's copy is current.
    public static func revision(of entries: [Entry]) -> String {
        SHA256.hash(data: Data(body(entries).utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    public static func render(_ entries: [Entry], at date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return "# shepherdr machines \(format) rev \(revision(of: entries)) \(formatter.string(from: date))\n" + body(entries)
    }

    /// The name this Mac goes by in the lists until you choose one: its computer name, as
    /// Sharing settings show it. Read without a network lookup.
    public static var defaultMacName: String {
        clean(SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac")
    }
}
