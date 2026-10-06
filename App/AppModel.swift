import AppKit
import Foundation
import Observation
import ShepherdrCore
import ShepherdrDictation

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

/// One entry of an expanded group: a session, or a shell placed in the group.
enum GroupMember: Identifiable {
    case session(AgentRow)
    case shell(ShellRow)

    /// Distinct per kind: a shell and the agent Herdr later detects in it share an `Agent.ID`.
    enum ID: Hashable { case session(Agent.ID), shell(Agent.ID) }

    var id: ID {
        switch self {
        case .session(let row): .session(row.id)
        case .shell(let shell): .shell(shell.id)
        }
    }

    var agentID: Agent.ID {
        switch self {
        case .session(let row): row.id
        case .shell(let shell): shell.id
        }
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

/// What a session keeps while you work elsewhere: its prompt editor and its browser tabs.
@MainActor @Observable
final class SessionWorkspace {
    /// The prompt editor is optional; the terminal is where you normally type.
    var isEditorOpen = false
    let browser = SessionBrowser()
}

/// What the New Session sheet starts from: a folder and machine to prefill, and where the
/// session takes its place in the queue once Herdr reports its agent.
struct NewSessionDraft: Identifiable {
    let id = UUID()
    var directory: String?
    var machineID: String?
    var placement: QueueDrop?
}

/// Whether a session on hold can resume: `ready` once none of the sessions it waits for is
/// still working or needs attention.
enum WaitState { case waiting, ready }

/// Window-level navigation and composer state. Drafts and prompt history stay in memory only.
@MainActor @Observable
final class AppModel {
    let cluster: ClusterStore
    let order: SessionOrderStore
    let relations: SessionRelationStore
    var selection: Destination = .overview
    var search = ""
    var drafts: [Agent.ID: String] = [:]
    private(set) var history: [Agent.ID: [String]] = [:]
    /// Incremented to ask the visible prompt editor to take keyboard focus.
    var promptFocusRequest = 0
    /// Incremented to ask the visible terminal to take keyboard focus.
    var terminalFocusRequest = 0
    /// Records and transcribes prompts on this Mac.
    let dictation = Dictation()
    /// The session a recording is for: its transcript lands in that session's prompt editor.
    private(set) var dictationTarget: Agent.ID?
    /// Asks before the one-time speech model download.
    var asksToDownloadSpeechModel = false
    @ObservationIgnored private var speechModelDownloadAccepted = false
    /// Created on first use and kept for the life of the app, so pages survive switching sessions.
    @ObservationIgnored private var workspaces: [Agent.ID: SessionWorkspace] = [:]
    /// The terminal shown in the work area, for menu commands.
    var activeTerminal: TerminalStore?

    /// The New Session sheet, while it is open.
    var newSession: NewSessionDraft?
    private(set) var isCreatingSession = false
    /// The session awaiting close confirmation.
    var closingSession: Agent.ID?
    /// A failed change, presented as an alert.
    var actionFailure: HerdrFailure?
    /// Messages shown on a session after it was created, such as an agent waiting at a startup prompt.
    var sessionNotices: [Agent.ID: String] = [:]

    init(cluster: ClusterStore = ClusterStore(), order: SessionOrderStore = SessionOrderStore(),
         relations: SessionRelationStore = SessionRelationStore()) {
        self.cluster = cluster
        self.order = order
        self.relations = relations
    }

    func workspace(for id: Agent.ID) -> SessionWorkspace {
        if let workspace = workspaces[id] { return workspace }
        let workspace = SessionWorkspace()
        workspaces[id] = workspace
        return workspace
    }

    var rankedRows: [AgentRow] { order.ranked(cluster.agents) }
    /// Sessions matching the filter, in priority order, whether or not their group is collapsed.
    var matchingRows: [AgentRow] { rankedRows.filter { $0.matches(search) } }

    /// The queue as the sidebar shows it. While filtering, groups list only their matching
    /// sessions, unless the group's own name matches.
    var queue: [QueueItem] {
        let items = order.layout(cluster.agents)
        guard !search.isEmpty else { return items }
        return items.compactMap { item in
            switch item {
            case .session(let row):
                return row.matches(search) ? item : nil
            case .group(var group):
                if group.group.name.localizedStandardContains(search) { return item }
                group.rows = group.rows.filter { $0.matches(search) }
                return group.rows.isEmpty && shells(in: group.group).isEmpty ? nil : .group(group)
            }
        }
    }

    /// Sessions shown in the sidebar, in order: ⌘1…⌘9 address these. Collapsed groups hide
    /// theirs, except while filtering.
    var visibleRows: [AgentRow] {
        queue.flatMap { item -> [AgentRow] in
            if case .group(let group) = item, group.group.isCollapsed, search.isEmpty { return [] }
            return item.rows
        }
    }

    /// Items moves are relative to: filtering hides some, collapsing does not.
    private var movableItems: Set<QueueItemID> {
        Set(queue.flatMap { [$0.id] + $0.rows.map { QueueItemID.session($0.id) } })
    }

    private var allShells: [ShellRow] {
        cluster.machines.flatMap { state -> [ShellRow] in
            guard let snapshot = state.snapshot else { return [] }
            let agentTerminals = Set(snapshot.agents.map(\.id.terminalID))
            return snapshot.panes.filter { !agentTerminals.contains($0.terminalID) }
                .map { ShellRow(pane: $0, machine: state.machine, isStale: state.isStale) }
        }
    }

    /// Shells matching the filter.
    var shells: [ShellRow] { allShells.filter { $0.matches(search) } }

    /// Shells placed in a group, such as a session created there whose agent has not started.
    /// Like the group's sessions, all of them show while the filter matches the group's name.
    func shells(in group: SessionGroup) -> [ShellRow] {
        let pool = group.name.localizedStandardContains(search) ? allShells : shells
        let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.members.compactMap { byID[$0] }
    }

    /// A group's sessions and shells, in the group's own order.
    func members(of group: QueueGroupRow) -> [GroupMember] {
        let rows = Dictionary(group.rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let shells = Dictionary(shells(in: group.group).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return group.group.members.compactMap { id in
            rows[id].map(GroupMember.session) ?? shells[id].map(GroupMember.shell)
        }
    }

    /// Shells in no group, listed under Shells.
    var ungroupedShells: [ShellRow] {
        let grouped = Set(groups.flatMap(\.members))
        return shells.filter { !grouped.contains($0.id) }
    }

    var showsMachineNames: Bool { cluster.machines.count > 1 }
    var selectedID: Agent.ID? { if case .session(let id) = selection { id } else { nil } }
    /// Sessions and shells in sidebar order, for stepping through them.
    private var navigableIDs: [Agent.ID] {
        queue.flatMap { item -> [Agent.ID] in
            guard case .group(let group) = item else { return item.rows.map(\.id) }
            if group.group.isCollapsed, search.isEmpty { return [] }
            return members(of: group).map(\.agentID)
        } + ungroupedShells.map(\.id)
    }

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
        focusInput(of: id)
    }

    /// Keyboard focus goes to the terminal, or to the prompt editor when it is open.
    private func focusInput(of id: Agent.ID) {
        if workspace(for: id).isEditorOpen { promptFocusRequest += 1 } else { terminalFocusRequest += 1 }
    }

    func togglePromptEditor() {
        guard let id = selectedID else { return }
        workspace(for: id).isEditorOpen.toggle()
        focusInput(of: id)
    }

    func toggleBrowser() {
        guard let id = selectedID else { return }
        let browser = workspace(for: id).browser
        browser.isVisible.toggle()
        if browser.isVisible && browser.tabs.isEmpty { browser.newTab() }
    }

    /// Links clicked in a session's terminal open in its browser, or in the default browser.
    func openLink(_ url: URL, from id: Agent.ID, external: Bool) {
        if external { NSWorkspace.shared.open(url) } else { workspace(for: id).browser.open(url) }
    }

    // MARK: Dictation

    /// Starts recording for the selected session, or stops and transcribes into its prompt editor.
    func toggleDictation() {
        if dictation.isRecording {
            Task { await finishDictation() }
            return
        }
        guard let id = selectedID, dictation.isReady else { return }
        if !Dictation.isModelInstalled && !speechModelDownloadAccepted {
            asksToDownloadSpeechModel = true
            return
        }
        dictationTarget = id
        workspace(for: id).isEditorOpen = true
        Task { await dictation.start() }
    }

    func acceptSpeechModelDownload() {
        speechModelDownloadAccepted = true
        toggleDictation()
    }

    func cancelDictation() {
        dictation.cancel()
        dictationTarget = nil
    }

    private func finishDictation() async {
        let target = dictationTarget
        let text = await dictation.stop()
        dictationTarget = nil
        guard let target, let text else { return }
        let current = drafts[target] ?? ""
        let separator = current.isEmpty || current.hasSuffix("\n") || current.hasSuffix(" ") ? "" : " "
        drafts[target] = current + separator + text
        workspace(for: target).isEditorOpen = true
        if selectedID == target { promptFocusRequest += 1 }
    }

    // MARK: Sessions on hold

    func waitState(for id: Agent.ID) -> WaitState? {
        let awaited = relations.waitingFor(id)
        guard !awaited.isEmpty else { return nil }
        let busy = awaited.contains { other in
            guard let row = cluster.agents.first(where: { $0.id == other }), !row.isStale else { return false }
            return row.agent.state == .working || row.agent.state == .blocked
        }
        return busy ? .waiting : .ready
    }

    func row(for id: Agent.ID) -> AgentRow? { cluster.agents.first { $0.id == id } }

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

    func startNewSession() {
        newSession = NewSessionDraft()
    }

    /// A new session that joins this group.
    func startNewSession(in group: SessionGroup) {
        newSession = NewSessionDraft(placement: .into(group: group.id))
    }

    /// A new session in the same folder and machine as this one, placed right after it.
    func startNewSession(besides id: Agent.ID) {
        guard let directory = directory(of: id) else { return }
        newSession = NewSessionDraft(directory: directory, machineID: id.machineID, placement: .after(.session(id)))
    }

    func canStartNewSession(besides id: Agent.ID) -> Bool {
        directory(of: id) != nil && onlineMachines.contains { $0.id == id.machineID }
    }

    /// Where a session or shell is working, as Herdr reports it.
    func directory(of id: Agent.ID) -> String? {
        if let row = row(for: id) { return row.agent.directory }
        return cluster.machines.first { $0.id == id.machineID }?.snapshot?.panes
            .first { $0.terminalID == id.terminalID }?.directory
    }

    /// Creates a workspace with a shell in Herdr, then opens it. Returns the failure for the sheet to show.
    func createSession(_ request: NewSessionRequest, onMachine machineID: String,
                       placement: QueueDrop? = nil) async -> HerdrFailure? {
        isCreatingSession = true
        defer { isCreatingSession = false }
        do {
            let created = try await cluster.createSession(request, onMachine: machineID)
            let id = Agent.ID(machineID: machineID, terminalID: created.terminalID)
            if let notice = created.notice { sessionNotices[id] = notice }
            if let placement { order.insert(id, placement) }
            newSession = nil
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
            workspaces.removeValue(forKey: id)?.browser.closeAll()
            relations.forget(id)
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

    func canMove(_ item: QueueItemID?, _ direction: SessionOrderStore.Move) -> Bool {
        order.canMove(item, direction, visible: movableItems)
    }

    func move(_ item: QueueItemID, _ direction: SessionOrderStore.Move) {
        order.move(item, direction, visible: movableItems)
    }

    func canMove(_ id: Agent.ID?, _ direction: SessionOrderStore.Move) -> Bool {
        canMove(id.map(QueueItemID.session), direction)
    }

    func moveSelection(_ direction: SessionOrderStore.Move) {
        if let selectedID { move(.session(selectedID), direction) }
    }

    /// The session or group being dragged in the queue.
    var dragging: QueueItemID?

    func place(_ item: QueueItemID, _ drop: QueueDrop) {
        order.place(item, drop)
    }

    // MARK: Groups

    struct GroupPrompt: Identifiable {
        enum Kind { case create(with: Agent.ID?), rename(String) }
        let id = UUID()
        let kind: Kind
        var name: String
    }

    /// The group being created or renamed, presented as a name prompt.
    var groupPrompt: GroupPrompt?

    var groups: [SessionGroup] { order.groups }

    func promptNewGroup(with session: Agent.ID? = nil) {
        groupPrompt = GroupPrompt(kind: .create(with: session), name: "")
    }

    func promptRename(_ group: SessionGroup) {
        groupPrompt = GroupPrompt(kind: .rename(group.id), name: group.name)
    }

    func commitGroupPrompt() {
        guard let prompt = groupPrompt else { return }
        groupPrompt = nil
        let name = prompt.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch prompt.kind {
        case .create(let session): order.createGroup(named: name, with: session)
        case .rename(let id): order.renameGroup(id, to: name)
        }
    }

    func moveToGroup(_ id: Agent.ID, _ groupID: String?) {
        order.moveToGroup(id, groupID)
    }

    func toggleCollapsed(_ group: SessionGroup) {
        order.setCollapsed(group.id, !group.isCollapsed)
    }

    func ungroup(_ group: SessionGroup) {
        order.ungroup(group.id)
    }

    // MARK: Composer

    func remember(_ prompt: String, for id: Agent.ID) {
        var entries = history[id, default: []]
        if entries.last != prompt { entries.append(prompt) }
        history[id] = Array(entries.suffix(50))
    }

    func prompts(for id: Agent.ID) -> [String] { history[id] ?? [] }
}
