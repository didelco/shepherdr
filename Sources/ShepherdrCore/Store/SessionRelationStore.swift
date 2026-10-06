import Foundation
import Observation

/// Sessions put on hold while others work, such as a planner waiting for the subagents it
/// launched. Device-local presentation preferences, like priorities.
@MainActor @Observable
public final class SessionRelationStore {
    /// Each waiting session and the sessions it waits for, in the order they were added.
    public private(set) var waits: [Agent.ID: [Agent.ID]]
    /// Waiting sessions whose awaited sessions the sidebar hides under them.
    public private(set) var collapsed: Set<Agent.ID>
    @ObservationIgnored private let defaults: UserDefaults
    static let storageKey = "sessionWaits.v1"

    private struct Record: Codable {
        let session: Agent.ID
        let waitingFor: [Agent.ID]
        /// Absent from records saved before sessions nested in the sidebar.
        var collapsed: Bool?
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        var waits: [Agent.ID: [Agent.ID]] = [:]
        var collapsed = Set<Agent.ID>()
        for record in records where Self.isValid(record.session) && waits[record.session] == nil {
            var seen = Set<Agent.ID>()
            let others = record.waitingFor.filter { Self.isValid($0) && $0 != record.session && seen.insert($0).inserted }
            guard !others.isEmpty else { continue }
            waits[record.session] = others
            if record.collapsed == true { collapsed.insert(record.session) }
        }
        self.waits = waits
        self.collapsed = collapsed
    }

    public func waitingFor(_ id: Agent.ID) -> [Agent.ID] { waits[id] ?? [] }

    /// Sessions waiting for this one.
    public func waiters(of id: Agent.ID) -> [Agent.ID] {
        waits.filter { $0.value.contains(id) }.map(\.key).sorted(by: Self.stableOrder)
    }

    public func isWaiting(_ id: Agent.ID, for other: Agent.ID) -> Bool {
        waits[id]?.contains(other) == true
    }

    /// Where the sidebar nests sessions: each awaited session in `order` hangs under the first
    /// session in `order` that waits for it. A wait that would close a loop leaves its session in place.
    public func parents(in order: [Agent.ID]) -> [Agent.ID: Agent.ID] {
        let shown = Set(order)
        var parents: [Agent.ID: Agent.ID] = [:]
        for waiter in order {
            for awaited in waitingFor(waiter) where shown.contains(awaited) && parents[awaited] == nil {
                var ancestor: Agent.ID? = waiter
                while let current = ancestor, current != awaited { ancestor = parents[current] }
                if ancestor == nil { parents[awaited] = waiter }
            }
        }
        return parents
    }

    public func isCollapsed(_ id: Agent.ID) -> Bool { collapsed.contains(id) }

    public func setCollapsed(_ id: Agent.ID, _ isCollapsed: Bool) {
        guard waits[id] != nil, collapsed.contains(id) != isCollapsed else { return }
        if isCollapsed { collapsed.insert(id) } else { collapsed.remove(id) }
        save()
    }

    public func setWaiting(_ id: Agent.ID, for other: Agent.ID, _ waiting: Bool) {
        guard id != other, Self.isValid(id), Self.isValid(other) else { return }
        var others = waits[id] ?? []
        if waiting {
            guard !others.contains(other) else { return }
            others.append(other)
        } else {
            guard others.contains(other) else { return }
            others.removeAll { $0 == other }
        }
        waits[id] = others.isEmpty ? nil : others
        if others.isEmpty { collapsed.remove(id) }
        save()
    }

    public func stopWaiting(_ id: Agent.ID) {
        guard waits[id] != nil else { return }
        waits[id] = nil
        collapsed.remove(id)
        save()
    }

    /// Drops a session that was closed: it no longer waits, and nothing waits for it.
    public func forget(_ id: Agent.ID) {
        var changed = waits.removeValue(forKey: id) != nil
        collapsed.remove(id)
        for (waiter, others) in waits where others.contains(id) {
            let remaining = others.filter { $0 != id }
            waits[waiter] = remaining.isEmpty ? nil : remaining
            if remaining.isEmpty { collapsed.remove(waiter) }
            changed = true
        }
        if changed { save() }
    }

    private static func isValid(_ id: Agent.ID) -> Bool { !id.machineID.isEmpty && !id.terminalID.isEmpty }

    private static func stableOrder(_ lhs: Agent.ID, _ rhs: Agent.ID) -> Bool {
        (lhs.machineID, lhs.terminalID) < (rhs.machineID, rhs.terminalID)
    }

    private func save() {
        // Session identifiers only, like saved priorities.
        let records = waits.keys.sorted(by: Self.stableOrder).map {
            Record(session: $0, waitingFor: waits[$0] ?? [], collapsed: collapsed.contains($0) ? true : nil)
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }
}
