import Foundation

/// What each session's work area looked like when you left it, so a restart brings it back: its
/// browser tabs, the selected one, whether the browser and the prompt editor were open, and the
/// links collected from it. Only URLs and session identifiers are saved, never prompts or terminal text.
@MainActor
public final class SessionStateStore {
    public struct State: Codable, Equatable, Sendable {
        public var tabs: [URL] = []
        public var selectedTab: Int?
        public var showsBrowser = false
        public var showsEditor = false
        public var resources: [SessionResource] = []

        public init() {}

        var isEmpty: Bool { tabs.isEmpty && !showsBrowser && !showsEditor && resources.isEmpty }
    }

    private struct Record: Codable {
        let session: Agent.ID
        let state: State
    }

    static let storageKey = "sessionState.v1"
    static let selectionKey = "lastSession.v1"
    private let defaults: UserDefaults
    private var states: [Agent.ID: State]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let records = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        states = Dictionary(records.map { ($0.session, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    public func state(for id: Agent.ID) -> State { states[id] ?? State() }

    public func set(_ state: State, for id: Agent.ID) {
        guard states[id] != state, !(state.isEmpty && states[id] == nil) else { return }
        states[id] = state.isEmpty ? nil : state
        save()
    }

    /// Drops a session that was closed.
    public func forget(_ id: Agent.ID) {
        guard states.removeValue(forKey: id) != nil else { return }
        save()
    }

    /// The session that was open when Shepherdr quit.
    public var lastSelection: Agent.ID? {
        get { defaults.data(forKey: Self.selectionKey).flatMap { try? JSONDecoder().decode(Agent.ID.self, from: $0) } }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) { defaults.set(data, forKey: Self.selectionKey) }
            else { defaults.removeObject(forKey: Self.selectionKey) }
        }
    }

    private func save() {
        let records = states.keys.sorted { ($0.machineID, $0.terminalID) < ($1.machineID, $1.terminalID) }
            .map { Record(session: $0, state: states[$0]!) }
        if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.storageKey) }
    }
}
