import Foundation

/// A project's heading in the queue: the sessions of one project in the top level, or in one group.
public struct ProjectRunID: Hashable, Codable, Sendable {
    /// The group the heading is in; nil at the top level.
    public let group: String?
    public let project: String

    public init(group: String?, project: String) {
        self.group = group
        self.project = project
    }
}

/// Gathers the sessions of each project in a list. A project is a repository: its main checkout
/// and its worktrees, on any machine. A project with two or more items in a list keeps all of them
/// where its first one is, in their order; lone items and items without a project stay in place.
public enum ProjectRuns {
    /// One place in a gathered list: an item on its own, or a project's run of two or more.
    public enum Segment<Item> {
        case single(Item)
        case project(String, [Item])

        public var items: [Item] {
            switch self {
            case .single(let item): [item]
            case .project(_, let items): items
            }
        }
    }

    /// The list as it shows when projects are gathered.
    public static func segments<Item>(_ items: [Item], project: (Item) -> String?) -> [Segment<Item>] {
        let names = items.map(project)
        var counts: [String: Int] = [:]
        for name in names.compactMap({ $0 }) { counts[name, default: 0] += 1 }
        var runs: [String: Int] = [:]
        var result: [Segment<Item>] = []
        for (item, name) in zip(items, names) {
            guard let name, counts[name, default: 0] > 1 else {
                result.append(.single(item))
                continue
            }
            if let index = runs[name], case .project(_, let members) = result[index] {
                result[index] = .project(name, members + [item])
            } else {
                runs[name] = result.count
                result.append(.project(name, [item]))
            }
        }
        return result
    }

    /// The items in gathered order.
    public static func gathered<Item>(_ items: [Item], project: (Item) -> String?) -> [Item] {
        segments(items, project: project).flatMap(\.items)
    }
}

extension ProjectRuns.Segment: Equatable where Item: Equatable {}
extension ProjectRuns.Segment: Sendable where Item: Sendable {}
