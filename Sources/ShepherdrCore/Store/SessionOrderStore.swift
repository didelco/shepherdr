import Foundation
import Observation

/// Something the user can prioritize in the queue: one session, or a group of sessions.
public enum QueueItemID: Hashable, Sendable {
    case session(Agent.ID)
    case group(String)
}

/// A user-defined set of sessions with its own internal order. What it means (a project,
/// a client, personal work…) is up to the user.
public struct SessionGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var isCollapsed: Bool
    public var members: [Agent.ID]

    public init(id: String = UUID().uuidString, name: String, isCollapsed: Bool = false, members: [Agent.ID] = []) {
        self.id = id
        self.name = name
        self.isCollapsed = isCollapsed
        self.members = members
    }
}

/// Where a dragged session or group lands.
public enum QueueDrop: Hashable, Sendable {
    case before(QueueItemID)
    case after(QueueItemID)
    /// Appends a session to a group.
    case into(group: String)
    /// The end of the top level.
    case end

    var target: QueueItemID? {
        switch self {
        case .before(let item), .after(let item): item
        case .into(let group): .group(group)
        case .end: nil
        }
    }
}

/// A group as the queue presents it: its current sessions, in the group's order.
public struct QueueGroupRow: Identifiable, Equatable, Sendable {
    public let group: SessionGroup
    public var rows: [AgentRow]
    public var id: String { group.id }
}

/// One top-level position in the queue.
public enum QueueItem: Identifiable, Equatable, Sendable {
    case session(AgentRow)
    case group(QueueGroupRow)

    public var id: QueueItemID {
        switch self {
        case .session(let row): .session(row.id)
        case .group(let group): .group(group.id)
        }
    }

    /// The sessions at this position, in priority order.
    public var rows: [AgentRow] {
        switch self {
        case .session(let row): [row]
        case .group(let group): group.rows
        }
    }
}

/// Device-local presentation preferences. Herdr remains the authority for session data.
@MainActor @Observable
public final class SessionOrderStore {
    public enum Move: Sendable { case up, down, first, last }

    /// A top-level position: groups move as a unit, like a single session.
    public enum Entry: Equatable, Sendable {
        case session(Agent.ID)
        case group(SessionGroup)

        var id: QueueItemID {
            switch self {
            case .session(let id): .session(id)
            case .group(let group): .group(group.id)
            }
        }
    }

    public private(set) var entries: [Entry]
    /// Whether each project's sessions gather under a heading, at the top level and in each group.
    public var gathersProjects: Bool {
        didSet { if gathersProjects != oldValue { defaults.set(gathersProjects, forKey: Self.gathersProjectsKey) } }
    }
    /// Project headings the user collapsed.
    public private(set) var collapsedProjects: Set<ProjectRunID>
    @ObservationIgnored private let defaults: UserDefaults
    static let storageKey = "sessionOrder.v2"
    /// 0.3–0.5 saved a flat list of session identifiers.
    static let legacyStorageKey = "sessionOrder.v1"
    static let gathersProjectsKey = "gathersProjects"
    static let collapsedProjectsKey = "collapsedProjects.v1"

    private struct Record: Codable {
        var session: Agent.ID?
        var group: SessionGroup?
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved: [Entry]
        if let data = defaults.data(forKey: Self.storageKey) {
            let records = (try? JSONDecoder().decode([Record].self, from: data)) ?? []
            saved = records.compactMap { record in record.group.map(Entry.group) ?? record.session.map(Entry.session) }
        } else {
            let legacy = defaults.data(forKey: Self.legacyStorageKey)
                .flatMap { try? JSONDecoder().decode([Agent.ID].self, from: $0) } ?? []
            saved = legacy.map(Entry.session)
        }
        entries = Self.normalized(saved)
        gathersProjects = defaults.bool(forKey: Self.gathersProjectsKey)
        collapsedProjects = Set(defaults.data(forKey: Self.collapsedProjectsKey)
            .flatMap { try? JSONDecoder().decode([ProjectRunID].self, from: $0) } ?? [])
    }

    /// Every saved session in priority order, with groups expanded in place.
    public var orderedIDs: [Agent.ID] {
        entries.flatMap { entry -> [Agent.ID] in
            switch entry {
            case .session(let id): [id]
            case .group(let group): group.members
            }
        }
    }

    public var groups: [SessionGroup] {
        entries.compactMap { if case .group(let group) = $0 { group } else { nil } }
    }

    public func group(containing id: Agent.ID) -> SessionGroup? {
        groups.first { $0.members.contains(id) }
    }

    /// Append discoveries, retaining missing IDs across outages, partial startup and relaunch.
    /// A refresh or lifecycle change must never silently overwrite a user's ordering.
    public func synchronize(with ids: [Agent.ID]) {
        var seen = Set(orderedIDs)
        let added = ids.filter { seen.insert($0).inserted }
        guard !added.isEmpty else { return }
        entries.append(contentsOf: added.map(Entry.session))
        save()
    }

    /// The queue as presented: current sessions numbered in priority order, inside their groups.
    /// Vanished sessions leave no gaps, groups remain when empty, and rows not yet synchronized
    /// follow in the caller's order. With `projects`, each session's project, the sessions of a
    /// project gather where its first one is, at the top level and in each group, and are
    /// numbered as they show.
    public func layout(_ rows: [AgentRow], projects: [Agent.ID: String]? = nil) -> [QueueItem] {
        let current = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var placed = Set<Agent.ID>()
        var priority = 0
        func numbered(_ id: Agent.ID, in group: String?) -> AgentRow? {
            guard var row = current[id], placed.insert(id).inserted else { return nil }
            priority += 1
            row.manualPriority = priority
            row.groupID = group
            return row
        }
        let saved = Set(orderedIDs)
        let top = gathered(entries + rows.map(\.id).filter { !saved.contains($0) }.map(Entry.session), projects)
        return top.compactMap { entry in
            switch entry {
            case .session(let id):
                numbered(id, in: nil).map(QueueItem.session)
            case .group(let group):
                .group(QueueGroupRow(group: group, rows: group.members.compactMap { numbered($0, in: group.id) }))
            }
        }
    }

    /// Current sessions in priority order, numbered from 1.
    public func ranked(_ rows: [AgentRow], projects: [Agent.ID: String]? = nil) -> [AgentRow] {
        layout(rows, projects: projects).flatMap(\.rows)
    }

    // MARK: Keyboard and menu moves

    /// Sessions move among their group's members, or among top-level positions. Moves are
    /// relative to `visible` items, so filtering never changes the slots of hidden items.
    ///
    /// With `projects` gathered, a project's heading is one position in its list: a session moves
    /// among the visible sessions of its project when the heading shows (two or more of them),
    /// and anything else steps over the whole project.
    public func canMove(_ item: QueueItemID?, _ direction: Move, visible: Set<QueueItemID>,
                        projects: [Agent.ID: String]? = nil) -> Bool {
        guard let item else { return false }
        return moved(.item(item), direction, visible: visible, projects: projects) != nil
    }

    public func move(_ item: QueueItemID, _ direction: Move, visible: Set<QueueItemID>, projects: [Agent.ID: String]? = nil) {
        if let change = moved(.item(item), direction, visible: visible, projects: projects) { apply(change) }
    }

    /// Whether a project's heading can move: it shows only with two or more visible sessions.
    public func canMove(_ project: ProjectRunID, _ direction: Move, visible: Set<QueueItemID>, projects: [Agent.ID: String]) -> Bool {
        moved(.project(project), direction, visible: visible, projects: projects) != nil
    }

    /// Moves a project's heading, with all its sessions, among the positions of its list.
    public func move(_ project: ProjectRunID, _ direction: Move, visible: Set<QueueItemID>, projects: [Agent.ID: String]) {
        if let change = moved(.project(project), direction, visible: visible, projects: projects) { apply(change) }
    }

    public func canMove(_ id: Agent.ID?, _ direction: Move, visibleIDs: [Agent.ID]) -> Bool {
        canMove(id.map(QueueItemID.session), direction, visible: visibleItems(visibleIDs))
    }

    public func move(_ id: Agent.ID, _ direction: Move, visibleIDs: [Agent.ID]) {
        move(.session(id), direction, visible: visibleItems(visibleIDs))
    }

    /// Visible sessions, plus the groups that show any of them.
    func visibleItems(_ ids: [Agent.ID]) -> Set<QueueItemID> {
        let sessions = Set(ids)
        let shownGroups = groups.filter { $0.members.contains(where: sessions.contains) }.map { QueueItemID.group($0.id) }
        return Set(ids.map(QueueItemID.session)).union(shownGroups)
    }

    private enum Mover {
        case item(QueueItemID)
        case project(ProjectRunID)
    }

    /// The list a move reorders, and its new order; nil when nothing would move.
    private func moved(_ mover: Mover, _ direction: Move, visible: Set<QueueItemID>,
                       projects: [Agent.ID: String]?) -> (group: String?, items: [QueueItemID])? {
        let scope: String?
        switch mover {
        case .item(let item):
            guard visible.contains(item) else { return nil }
            if case .session(let id) = item { scope = group(containing: id)?.id } else { scope = nil }
        case .project(let run):
            scope = run.group
        }
        let list: [QueueItemID]
        if let scope {
            guard let group = groups.first(where: { $0.id == scope }) else { return nil }
            list = group.members.map(QueueItemID.session)
        } else {
            list = entries.map(\.id)
        }
        let segments = ProjectRuns.segments(list) { item in
            if case .session(let id) = item { projects?[id] } else { nil }
        }
        func shown(_ items: [QueueItemID]) -> Int { items.filter(visible.contains).count }
        let index: Int
        switch mover {
        case .item(let item):
            guard let found = segments.firstIndex(where: { $0.items.contains(item) }) else { return nil }
            // Under a heading, a session moves among its project's sessions.
            if case .project(let name, let members) = segments[found], shown(members) > 1 {
                guard let position = members.firstIndex(of: item),
                      let reordered = Self.reordered(members, moving: position, direction, isShown: visible.contains) else { return nil }
                var result = segments
                result[found] = .project(name, reordered)
                return (scope, result.flatMap(\.items))
            }
            index = found
        case .project(let run):
            guard let found = segments.firstIndex(where: {
                if case .project(let name, let members) = $0 { name == run.project && shown(members) > 1 } else { false }
            }) else { return nil }
            index = found
        }
        guard let reordered = Self.reordered(segments, moving: index, direction, isShown: { shown($0.items) > 0 }) else { return nil }
        return (scope, reordered.flatMap(\.items))
    }

    /// Moves an element among the shown ones, which take each other's slots; hidden ones keep
    /// theirs. Nil when the element is hidden or already where the move would take it.
    static func reordered<Element>(_ items: [Element], moving index: Int, _ direction: Move,
                                   isShown: (Element) -> Bool) -> [Element]? {
        let slots = items.indices.filter { isShown(items[$0]) }
        guard let position = slots.firstIndex(of: index) else { return nil }
        let target = destination(from: position, count: slots.count, direction: direction)
        guard target != position else { return nil }
        var shown = slots.map { items[$0] }
        shown.insert(shown.remove(at: position), at: target)
        var result = items
        for (slot, value) in zip(slots, shown) { result[slot] = value }
        return result
    }

    private func apply(_ change: (group: String?, items: [QueueItemID])) {
        if let groupID = change.group {
            updateGroup(groupID) { group in
                group.members = change.items.compactMap { if case .session(let id) = $0 { id } else { nil } }
            }
        } else {
            let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            let reordered = change.items.compactMap { byID[$0] }
            guard reordered != entries else { return }
            entries = reordered
            save()
        }
    }

    /// Entries with each project's sessions gathered, at the top level and in each group.
    private func gathered(_ entries: [Entry], _ projects: [Agent.ID: String]?) -> [Entry] {
        guard let projects else { return entries }
        return ProjectRuns.gathered(entries) { entry in
            if case .session(let id) = entry { projects[id] } else { nil }
        }.map { entry in
            guard case .group(var group) = entry else { return entry }
            group.members = ProjectRuns.gathered(group.members) { projects[$0] }
            return .group(group)
        }
    }

    /// Saves the order as it shows while projects are gathered, so drops land where they are shown.
    private func gather(_ projects: [Agent.ID: String]) {
        let result = gathered(entries, projects)
        guard result != entries else { return }
        entries = result
        save()
    }

    // MARK: Drag and drop

    /// Moves a session or group next to a target, or a session into a group. Groups never
    /// nest: a group dropped among another group's sessions lands next to that group. With
    /// `projects` gathered, the order is first saved as it shows.
    public func place(_ item: QueueItemID, _ drop: QueueDrop, projects: [Agent.ID: String]? = nil) {
        guard item != drop.target else { return }
        if let projects { gather(projects) }
        var result = entries
        let moving: Entry
        switch item {
        case .session(let id):
            guard orderedIDs.contains(id) else { return }
            result = result.compactMap { entry in
                switch entry {
                case .session(let other): return other == id ? nil : entry
                case .group(var group): group.members.removeAll { $0 == id }; return .group(group)
                }
            }
            moving = .session(id)
        case .group:
            guard let index = result.firstIndex(where: { $0.id == item }) else { return }
            moving = result.remove(at: index)
        }

        func topIndex(_ target: QueueItemID) -> Int? { result.firstIndex { $0.id == target } }
        func groupIndex(containing id: Agent.ID) -> Int? {
            result.firstIndex { if case .group(let group) = $0 { group.members.contains(id) } else { false } }
        }

        switch drop {
        case .end:
            result.append(moving)
        case .into(let groupID):
            guard let index = topIndex(.group(groupID)), case .group(var group) = result[index] else { return }
            if case .session(let id) = moving {
                group.members.append(id)
                result[index] = .group(group)
            } else {
                result.insert(moving, at: index + 1)
            }
        case .before(let target), .after(let target):
            let offset = drop == .after(target) ? 1 : 0
            if case .session(let targetID) = target, let index = groupIndex(containing: targetID),
               case .group(var group) = result[index] {
                if case .session(let id) = moving, let member = group.members.firstIndex(of: targetID) {
                    group.members.insert(id, at: member + offset)
                    result[index] = .group(group)
                } else {
                    result.insert(moving, at: index + offset)
                }
            } else if let index = topIndex(target) {
                result.insert(moving, at: index + offset)
            } else {
                return
            }
        }
        guard result != entries else { return }
        entries = result
        save()
    }

    /// Places a session Herdr may not report as an agent yet, such as a shell just created, so
    /// it takes that spot once it does. Until then it keeps the spot like a missing session.
    public func insert(_ id: Agent.ID, _ drop: QueueDrop, projects: [Agent.ID: String]? = nil) {
        if !orderedIDs.contains(id) {
            entries.append(.session(id))
            save()
        }
        place(.session(id), drop, projects: projects)
    }

    // MARK: Groups

    /// A new group takes its first session's place in the queue, or the top when created empty.
    @discardableResult
    public func createGroup(named name: String, with session: Agent.ID? = nil) -> String {
        let created = SessionGroup(name: name)
        var index = 0
        if let session {
            if let position = entries.firstIndex(of: .session(session)) {
                index = position
            } else if let container = group(containing: session),
                      let position = entries.firstIndex(where: { $0.id == .group(container.id) }) {
                index = position + 1
            }
        }
        entries.insert(.group(created), at: index)
        if let session { place(.session(session), .into(group: created.id)) }
        save()
        return created.id
    }

    /// Moves a session into a group, or out of its group to just after it when `groupID` is nil.
    public func moveToGroup(_ id: Agent.ID, _ groupID: String?) {
        if let groupID {
            guard group(containing: id)?.id != groupID else { return }
            place(.session(id), .into(group: groupID))
        } else if let container = group(containing: id) {
            place(.session(id), .after(.group(container.id)))
        }
    }

    public func renameGroup(_ id: String, to name: String) {
        updateGroup(id) { $0.name = name }
    }

    public func setCollapsed(_ id: String, _ isCollapsed: Bool) {
        updateGroup(id) { $0.isCollapsed = isCollapsed }
    }

    /// Dissolves a group, leaving its sessions in its place and in their order.
    public func ungroup(_ id: String) {
        guard let index = entries.firstIndex(where: { $0.id == .group(id) }),
              case .group(let group) = entries[index] else { return }
        entries.replaceSubrange(index...index, with: group.members.map(Entry.session))
        save()
    }

    // MARK: Projects

    public func isCollapsed(_ project: ProjectRunID) -> Bool { collapsedProjects.contains(project) }

    public func setCollapsed(_ project: ProjectRunID, _ isCollapsed: Bool) {
        guard collapsedProjects.contains(project) != isCollapsed else { return }
        if isCollapsed { collapsedProjects.insert(project) } else { collapsedProjects.remove(project) }
        // Group identifiers and project names only, like the rest of the order.
        let sorted = collapsedProjects.sorted { ($0.group ?? "", $0.project) < ($1.group ?? "", $1.project) }
        if let data = try? JSONEncoder().encode(sorted) { defaults.set(data, forKey: Self.collapsedProjectsKey) }
    }

    private func updateGroup(_ id: String, _ change: (inout SessionGroup) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == .group(id) }),
              case .group(var group) = entries[index] else { return }
        let original = group
        change(&group)
        guard group != original else { return }
        entries[index] = .group(group)
        save()
    }

    // MARK: Storage

    /// Drops empty identifiers and keeps the first occurrence of every session and group.
    static func normalized(_ entries: [Entry]) -> [Entry] {
        var sessions = Set<Agent.ID>()
        var groups = Set<String>()
        func keep(_ id: Agent.ID) -> Bool {
            !id.machineID.isEmpty && !id.terminalID.isEmpty && sessions.insert(id).inserted
        }
        return entries.compactMap { entry in
            switch entry {
            case .session(let id):
                return keep(id) ? entry : nil
            case .group(var group):
                guard !group.id.isEmpty, groups.insert(group.id).inserted else { return nil }
                group.members = group.members.filter(keep)
                return .group(group)
            }
        }
    }

    private static func destination(from index: Int, count: Int, direction: Move) -> Int {
        switch direction {
        case .up: max(0, index - 1)
        case .down: min(count - 1, index + 1)
        case .first: 0
        case .last: count - 1
        }
    }

    private func save() {
        // Identifiers, group names and collapse state only: never titles, directories, snapshots
        // or terminal contents.
        let records = entries.map { entry in
            switch entry {
            case .session(let id): Record(session: id)
            case .group(let group): Record(group: group)
            }
        }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }
}
