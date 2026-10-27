import Foundation

/// Which sessions work on which GitHub repositories, pull requests and issues: a session can link
/// to several pull requests and issues, and several sessions to one. Worked out from the links each
/// session collected, from its terminal or its pins, and from the repository its folder is in, so
/// it never disagrees with them.
public struct SessionLinks: Sendable {
    private var sessionsByKey: [String: [Agent.ID]] = [:]
    private var sessionsByRepository: [String: [Agent.ID]] = [:]
    /// The repositories sessions work in, in the order of the first session in each.
    public private(set) var repositories: [InboxRepository] = []

    /// - Parameters:
    ///   - sessions: each session and its resources, in the order to list them in.
    ///   - repositories: the repository each session's folder is in, when it is in one on GitHub.
    public init(_ sessions: [(id: Agent.ID, resources: [SessionResource])], repositories: [Agent.ID: InboxRepository] = [:]) {
        for (id, resources) in sessions {
            for resource in resources where resource.github != nil && !resource.isMissing {
                if sessionsByKey[resource.key]?.contains(id) == true { continue }
                sessionsByKey[resource.key, default: []].append(id)
            }
            guard let repository = repositories[id] else { continue }
            if sessionsByRepository[repository.id] == nil { self.repositories.append(repository) }
            sessionsByRepository[repository.id, default: []].append(id)
        }
    }

    /// The sessions working in a repository, by `owner/name`.
    public func sessions(inRepository id: String) -> [Agent.ID] { sessionsByRepository[id.lowercased()] ?? [] }

    /// The sessions linked to a pull request or issue, by `SessionResource.key`.
    public func sessions(for key: String) -> [Agent.ID] { sessionsByKey[key.lowercased()] ?? [] }

    /// The sessions working on an inbox item: those linked to it, and for an issue, those linked to
    /// the pull requests that resolve it.
    public func sessions(for item: GitHubInboxItem) -> [Agent.ID] {
        let keys = [item.key] + item.linkedPullRequests.compactMap { SessionResource(url: $0.url)?.key }
        var found: [Agent.ID] = []
        for id in keys.flatMap(sessions(for:)) where !found.contains(id) { found.append(id) }
        return found
    }
}

/// What an inbox item offers to do about it, from the sessions working on it.
public enum InboxAction: Equatable, Sendable {
    /// An issue no session works on: start one that implements it.
    case implement
    /// A pull request no session works on: start one that reviews it.
    case review
    /// The one session working on it.
    case open(Agent.ID)
    /// Several sessions work on it: choose one.
    case choose([Agent.ID])

    public init(item: GitHubInboxItem, sessions: [Agent.ID]) {
        switch sessions.count {
        case 0: self = item.isPullRequest ? .review : .implement
        case 1: self = .open(sessions[0])
        default: self = .choose(sessions)
        }
    }
}
