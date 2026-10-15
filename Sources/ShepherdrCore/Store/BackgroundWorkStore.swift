import Foundation
import Observation

/// What the agents that are not working left running, such as watchers and dev servers, session by session.
@MainActor @Observable
public final class BackgroundWorkStore {
    public private(set) var commands: [Agent.ID: [BackgroundCommand]] = [:]
    @ObservationIgnored private let client: any HerdrClient
    @ObservationIgnored private let read: @Sendable ([Int], Machine) async -> [BackgroundWork.Process]?
    /// The shell each pane started with. It lives as long as the pane, so Herdr is asked once.
    @ObservationIgnored private var shells: [Agent.ID: Int] = [:]
    @ObservationIgnored private var isRefreshing = false

    public convenience init(client: any HerdrClient = CLIHerdrClient()) {
        self.init(client: client, read: { await BackgroundWork.read(under: $0, on: $1) })
    }

    init(client: any HerdrClient, read: @escaping @Sendable ([Int], Machine) async -> [BackgroundWork.Process]?) {
        self.client = client
        self.read = read
    }

    /// Looks again under every agent that is not working, one process listing per machine.
    public func refresh(_ rows: [AgentRow], machines: [Machine]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let idle = rows.filter { !$0.isStale && $0.agent.state != .working }
        let byMachine = Dictionary(grouping: idle, by: \.id.machineID)
        await withTaskGroup(of: Void.self) { group in
            for machine in machines {
                guard let rows = byMachine[machine.id] else { continue }
                group.addTask { await self.refresh(rows, on: machine) }
            }
        }
        let looked = Set(idle.map(\.id)), present = Set(rows.map(\.id))
        commands = commands.filter { looked.contains($0.key) }
        shells = shells.filter { present.contains($0.key) }
    }

    private func refresh(_ rows: [AgentRow], on machine: Machine) async {
        for row in rows where shells[row.id] == nil {
            if let pid = try? await client.shellPID(paneID: row.agent.paneID, on: machine) { shells[row.id] = pid }
        }
        let watched = rows.compactMap { row in shells[row.id].map { (row.id, $0) } }
        // A machine that doesn't answer keeps what it last showed until it does.
        guard !watched.isEmpty, let processes = await read(watched.map(\.1), machine) else { return }
        let alive = Set(processes.map(\.pid))
        for (id, shell) in watched {
            // A pane that started over has a new shell: ask Herdr again next time.
            guard alive.contains(shell) else {
                shells[id] = nil
                commands[id] = nil
                continue
            }
            // Only a different set of processes changes what's shown, so views don't redraw for nothing.
            let found = BackgroundWork.commands(under: shell, in: processes)
            if (commands[id] ?? []).map(\.pid) != found.map(\.pid) { commands[id] = found.isEmpty ? nil : found }
        }
    }
}
