import Foundation
import Observation
import ShepherdrCore

enum Destination: Hashable {
    case overview
    /// An agent session or a plain shell pane; both are addressed by machine and terminal ID.
    case session(Agent.ID)
}

/// A pane without a detected agent. It can be opened, but it is not part of the priority queue.
struct ShellRow: Identifiable, Equatable {
    let pane: TerminalPane
    let machine: Machine
    let isStale: Bool
    var id: Agent.ID { .init(machineID: machine.id, terminalID: pane.terminalID) }

    func matches(_ query: String) -> Bool {
        query.isEmpty || [pane.workspaceName, pane.title, machine.name].contains { $0.localizedStandardContains(query) }
    }
}

/// Everything the work area needs to present one session.
struct SessionContext {
    let target: TerminalTarget
    let machine: MachineState
    let agent: AgentRow?
    let paneID: String
    var title: String { agent?.title ?? "shell" }
    var isStale: Bool { machine.isStale }
    var canConnect: Bool { machine.connection == .online }
}

/// Window-level navigation and composer state. Drafts and prompt history stay in memory only.
@MainActor @Observable
final class AppModel {
    let cluster: ClusterStore
    let order: SessionOrderStore
    var selection: Destination = .overview
    var search = ""
    var drafts: [Agent.ID: String] = [:]
    private(set) var history: [Agent.ID: [String]] = [:]
    /// Incremented to ask the visible composer to take keyboard focus.
    var promptFocusRequest = 0
    /// The terminal shown in the work area, for menu commands.
    var activeTerminal: TerminalStore?

    var showsNewSession = false
    private(set) var isCreatingSession = false
    /// The session awaiting close confirmation.
    var closingSession: Agent.ID?
    /// A failed change, presented as an alert.
    var actionFailure: HerdrFailure?
    /// Messages shown on a session after it was created, such as an agent waiting at a startup prompt.
    var sessionNotices: [Agent.ID: String] = [:]

    init(cluster: ClusterStore = ClusterStore(), order: SessionOrderStore = SessionOrderStore()) {
        self.cluster = cluster
        self.order = order
    }

    var rankedRows: [AgentRow] { order.ranked(cluster.agents) }
    var visibleRows: [AgentRow] { rankedRows.filter { $0.matches(search) } }

    var shells: [ShellRow] {
        cluster.machines.flatMap { state -> [ShellRow] in
            guard let snapshot = state.snapshot else { return [] }
            let agentTerminals = Set(snapshot.agents.map(\.id.terminalID))
            return snapshot.panes.filter { !agentTerminals.contains($0.terminalID) }
                .map { ShellRow(pane: $0, machine: state.machine, isStale: state.isStale) }
        }
        .filter { $0.matches(search) }
    }

    var showsMachineNames: Bool { cluster.machines.count > 1 }
    var selectedID: Agent.ID? { if case .session(let id) = selection { id } else { nil } }
    private var navigableIDs: [Agent.ID] { visibleRows.map(\.id) + shells.map(\.id) }

    func context(for id: Agent.ID) -> SessionContext? {
        guard let machine = cluster.machines.first(where: { $0.id == id.machineID }) else { return nil }
        if let row = cluster.agents.first(where: { $0.id == id }) {
            return SessionContext(target: TerminalTarget(machine: machine.machine, terminalID: id.terminalID,
                                                         title: row.title, workspace: row.workspace),
                                  machine: machine, agent: row, paneID: row.agent.paneID)
        }
        guard let pane = machine.snapshot?.panes.first(where: { $0.terminalID == id.terminalID }) else { return nil }
        return SessionContext(target: TerminalTarget(machine: machine.machine, terminalID: id.terminalID,
                                                     title: pane.title, workspace: pane.workspaceName),
                              machine: machine, agent: nil, paneID: pane.paneID)
    }

    // MARK: Navigation

    func open(_ id: Agent.ID) {
        selection = .session(id)
        promptFocusRequest += 1
    }

    /// ⌘1…⌘9 address the visible queue by position.
    func open(position: Int) {
        guard visibleRows.indices.contains(position) else { return }
        open(visibleRows[position].id)
    }

    func step(_ delta: Int) {
        let ids = navigableIDs
        guard !ids.isEmpty else { return }
        guard let current = selectedID, let index = ids.firstIndex(of: current) else {
            open(delta > 0 ? ids[0] : ids[ids.count - 1])
            return
        }
        open(ids[(index + delta + ids.count) % ids.count])
    }

    // MARK: Creating and closing sessions

    var onlineMachines: [MachineState] { cluster.machines.filter { $0.connection == .online } }

    /// Creates a workspace (and agent) in Herdr, then opens it. Returns the failure for the sheet to show.
    func createSession(_ request: NewSessionRequest, onMachine machineID: String) async -> HerdrFailure? {
        isCreatingSession = true
        defer { isCreatingSession = false }
        do {
            let created = try await cluster.createSession(request, onMachine: machineID)
            let id = Agent.ID(machineID: machineID, terminalID: created.terminalID)
            if let notice = created.notice { sessionNotices[id] = notice }
            showsNewSession = false
            open(id)
            return nil
        } catch {
            return Self.failure(error)
        }
    }

    func requestClose(_ id: Agent.ID?) {
        if let id, context(for: id) != nil { closingSession = id }
    }

    /// Ends the pane in Herdr after the user confirmed. Leaving the view first detaches this client.
    func closeSession(_ id: Agent.ID) async {
        closingSession = nil
        guard let context = context(for: id) else { return }
        if selectedID == id { selection = .overview }
        do {
            try await cluster.closeSession(paneID: context.paneID, onMachine: id.machineID)
            drafts[id] = nil
            sessionNotices[id] = nil
        } catch {
            actionFailure = Self.failure(error)
        }
    }

    // MARK: Machines

    func perform(_ change: () async throws -> Void) async -> HerdrFailure? {
        do { try await change(); return nil }
        catch { return Self.failure(error) }
    }

    static func failure(_ error: Error) -> HerdrFailure {
        error as? HerdrFailure ?? HerdrFailure(.unreachable, error.localizedDescription)
    }

    // MARK: Active session

    var canToggleLive: Bool {
        guard let terminal = activeTerminal, terminal.status != .connecting else { return false }
        return selectedID.flatMap(context(for:))?.canConnect == true
    }

    func toggleLive() {
        guard canToggleLive, let terminal = activeTerminal else { return }
        terminal.open(mode: terminal.mode == .observe ? .control : .observe)
    }

    // MARK: Priorities

    func canMove(_ id: Agent.ID?, _ direction: SessionOrderStore.Move) -> Bool {
        order.canMove(id, direction, visibleIDs: visibleRows.map(\.id))
    }

    func move(_ id: Agent.ID, _ direction: SessionOrderStore.Move) {
        order.move(id, direction, visibleIDs: visibleRows.map(\.id))
    }

    func moveSelection(_ direction: SessionOrderStore.Move) {
        if let selectedID { move(selectedID, direction) }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        order.move(fromOffsets: source, toOffset: destination, visibleIDs: visibleRows.map(\.id))
    }

    // MARK: Composer

    func remember(_ prompt: String, for id: Agent.ID) {
        var entries = history[id, default: []]
        if entries.last != prompt { entries.append(prompt) }
        history[id] = Array(entries.suffix(50))
    }

    func prompts(for id: Agent.ID) -> [String] { history[id] ?? [] }
}
