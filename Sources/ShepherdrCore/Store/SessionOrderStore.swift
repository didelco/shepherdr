import Foundation
import Observation

/// Device-local presentation preferences. Herdr remains the authority for session data.
@MainActor @Observable
public final class SessionOrderStore {
    public enum Move: Sendable { case up, down, first, last }
    public private(set) var orderedIDs: [Agent.ID]
    @ObservationIgnored private let defaults: UserDefaults
    static let storageKey = "sessionOrder.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Agent.ID].self, from: $0) } ?? []
        var seen = Set<Agent.ID>()
        orderedIDs = saved.filter {
            !$0.machineID.isEmpty && !$0.terminalID.isEmpty && seen.insert($0).inserted
        }
    }

    /// Append discoveries, retaining missing IDs across outages, partial startup and relaunch.
    /// A refresh or lifecycle change must never silently overwrite a user's ordering.
    public func synchronize(with ids: [Agent.ID]) {
        var seen = Set(orderedIDs)
        let added = ids.filter { seen.insert($0).inserted }
        guard !added.isEmpty else { return }
        orderedIDs.append(contentsOf: added)
        save()
    }

    /// Rank only current rows, so vanished sessions do not leave gaps in the dashboard.
    /// Unseen rows retain the caller's initial ordering until discovery is synchronized.
    public func ranked(_ rows: [AgentRow]) -> [AgentRow] {
        let positions = Dictionary(uniqueKeysWithValues: orderedIDs.enumerated().map { ($1, $0) })
        return rows.enumerated().sorted { left, right in
            let lhs = positions[left.element.id] ?? Int.max
            let rhs = positions[right.element.id] ?? Int.max
            return lhs == rhs ? left.offset < right.offset : lhs < rhs
        }.enumerated().map { offset, item in
            var row = item.element
            row.manualPriority = offset + 1
            return row
        }
    }

    public func canMove(_ id: Agent.ID?, _ direction: Move, visibleIDs: [Agent.ID]) -> Bool {
        guard let id else { return false }
        let visible = Set(visibleIDs)
        let subset = orderedIDs.filter { visible.contains($0) }
        guard let index = subset.firstIndex(of: id) else { return false }
        return destination(from: index, count: subset.count, direction: direction) != index
    }

    public func move(_ id: Agent.ID, _ direction: Move, visibleIDs: [Agent.ID]) {
        reorderVisible(visibleIDs) { subset in
            guard let index = subset.firstIndex(of: id) else { return }
            let target = destination(from: index, count: subset.count, direction: direction)
            guard index != target else { return }
            subset.remove(at: index)
            subset.insert(id, at: target)
        }
    }

    /// Drag-and-drop reordering, with offsets relative to `visibleIDs` as a list presents them.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int, visibleIDs: [Agent.ID]) {
        let moving = source.filter { visibleIDs.indices.contains($0) }.map { visibleIDs[$0] }
        guard !moving.isEmpty else { return }
        let anchor = visibleIDs[min(destination, visibleIDs.count)...].first { !moving.contains($0) }
        reorderVisible(visibleIDs) { subset in
            subset.removeAll { moving.contains($0) }
            let index = anchor.flatMap { subset.firstIndex(of: $0) } ?? subset.count
            subset.insert(contentsOf: moving, at: index)
        }
    }

    private func reorderVisible(_ visibleIDs: [Agent.ID], _ change: (inout [Agent.ID]) -> Void) {
        let visible = Set(visibleIDs)
        let slots = orderedIDs.indices.filter { visible.contains(orderedIDs[$0]) }
        var subset = slots.map { orderedIDs[$0] }
        let original = subset
        change(&subset)
        guard subset != original, subset.count == original.count else { return }
        // Filtering never changes the slots occupied by hidden or temporarily absent sessions.
        var reordered = orderedIDs
        for (slot, value) in zip(slots, subset) { reordered[slot] = value }
        orderedIDs = reordered
        save()
    }

    private func destination(from index: Int, count: Int, direction: Move) -> Int {
        switch direction {
        case .up: max(0, index - 1)
        case .down: min(count - 1, index + 1)
        case .first: 0
        case .last: count - 1
        }
    }

    private func save() {
        // Persist identifiers only, never titles, directories, snapshots or terminal contents.
        if let data = try? JSONEncoder().encode(orderedIDs) { defaults.set(data, forKey: Self.storageKey) }
    }
}
