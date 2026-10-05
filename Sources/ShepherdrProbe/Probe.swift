import Foundation
import ShepherdrCore

@main struct Probe {
    @MainActor static func main() async {
        let store = ClusterStore()
        await store.refresh()
        for state in store.machines {
            print("\(state.machine.name): \(state.connection.title)")
            if let snapshot = state.snapshot {
                print("  Herdr \(snapshot.version), protocol \(snapshot.protocolVersion), \(snapshot.workspaces.count) workspaces, \(snapshot.agents.count) agents")
                for workspace in snapshot.workspaces { print("  Workspace: \(workspace.name)") }
                for agent in snapshot.agents {
                    print("  \(agent.name) · \(agent.state.title) · \(agent.workspaceName) · \(agent.paneID)")
                }
            }
            if let failure = state.failure { print("  \(failure.message)") }
        }
        if let failure = store.discoveryFailure { print("Machine discovery: \(failure.message)") }
        if store.onlineCount == 0 { exit(1) }
    }
}
