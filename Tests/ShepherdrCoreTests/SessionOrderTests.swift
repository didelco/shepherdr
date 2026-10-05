import Foundation
import Testing
@testable import ShepherdrCore

@Suite @MainActor struct SessionOrderTests {
    private let a = Agent.ID(machineID: "local", terminalID: "a")
    private let b = Agent.ID(machineID: "local", terminalID: "b")
    private let c = Agent.ID(machineID: "remote:one", terminalID: "a")
    private let d = Agent.ID(machineID: "remote:one", terminalID: "b")

    private func withDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let suite = "ShepherdrTests.SessionOrder.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    @Test func prioritiesSurviveRelaunchAndDistinguishMachines() async throws {
        try await withDefaults { defaults in
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            order.move(c, .first, visibleIDs: [a, b, c, d])
            #expect(order.orderedIDs == [c, a, b, d])
            let reopened = SessionOrderStore(defaults: defaults)
            #expect(reopened.orderedIDs == [c, a, b, d])
            let data = try #require(defaults.data(forKey: SessionOrderStore.storageKey))
            let records = try #require(JSONSerialization.jsonObject(with: data) as? [[String: String]])
            #expect(records.allSatisfy { Set($0.keys) == ["machineID", "terminalID"] })
        }
    }

    @Test func discoveriesAppendWithoutLosingMissingSessionsOrFollowingRefreshOrder() async throws {
        try await withDefaults { defaults in
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c])
            order.move(c, .first, visibleIDs: [a, b, c])
            order.synchronize(with: []) // Refresh starts before any machine has replied.
            order.synchronize(with: [b, a]) // Missing remote, different state/name sorting.
            let reopened = SessionOrderStore(defaults: defaults)
            reopened.synchronize(with: [d, c, b, a, d])
            #expect(reopened.orderedIDs == [c, a, b, d])
        }
    }

    @Test func filteredMovesPreserveHiddenSlotsAndBoundaries() async throws {
        try await withDefaults { defaults in
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            // b is hidden by a search or machine filter. Its slot must not change.
            order.move(d, .first, visibleIDs: [a, c, d])
            #expect(order.orderedIDs == [d, b, a, c])
            order.move(d, .down, visibleIDs: [d, a, c])
            #expect(order.orderedIDs == [a, b, d, c])
            order.move(d, .up, visibleIDs: [a, d, c])
            order.move(d, .last, visibleIDs: [d, a, c])
            #expect(order.orderedIDs == [a, b, c, d])
            #expect(!order.canMove(a, .up, visibleIDs: [a, c, d]))
            #expect(!order.canMove(d, .down, visibleIDs: [a, c, d]))
            #expect(!order.canMove(b, .first, visibleIDs: [a, c, d]))
            #expect(!order.canMove(nil, .up, visibleIDs: []))
            order.move(b, .first, visibleIDs: [a, c, d])
            #expect(order.orderedIDs == [a, b, c, d])
        }
    }

    @Test func dragAndDropMovesWithinVisibleSessionsAndPersists() async throws {
        try await withDefaults { defaults in
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: [a, b, c, d])
            // List semantics: moving row 3 (d) before row 0 (a), with b hidden by a filter.
            order.move(fromOffsets: [2], toOffset: 0, visibleIDs: [a, c, d])
            #expect(order.orderedIDs == [d, b, a, c])
            // Dropping past the end moves to the last visible slot.
            order.move(fromOffsets: [0], toOffset: 3, visibleIDs: [d, a, c])
            #expect(order.orderedIDs == [a, b, c, d])
            order.move(fromOffsets: [0, 1], toOffset: 4, visibleIDs: [a, b, c, d])
            #expect(order.orderedIDs == [c, d, a, b])
            // No-op and out-of-range drops leave saved order untouched.
            order.move(fromOffsets: [1], toOffset: 1, visibleIDs: [c, d, a, b])
            order.move(fromOffsets: [9], toOffset: 0, visibleIDs: [c, d, a, b])
            #expect(SessionOrderStore(defaults: defaults).orderedIDs == [c, d, a, b])
        }
    }

    @Test func invalidPreferencesRecoverAndDuplicateIdentifiersAreNormalized() async throws {
        try await withDefaults { defaults in
            defaults.set(Data("not JSON".utf8), forKey: SessionOrderStore.storageKey)
            let recovered = SessionOrderStore(defaults: defaults)
            #expect(recovered.orderedIDs.isEmpty)
            recovered.synchronize(with: [a, a, b])
            #expect(SessionOrderStore(defaults: defaults).orderedIDs == [a, b])
            let malformed = [a, a, Agent.ID(machineID: "", terminalID: ""), b]
            defaults.set(try JSONEncoder().encode(malformed), forKey: SessionOrderStore.storageKey)
            #expect(SessionOrderStore(defaults: defaults).orderedIDs == [a, b])
        }
    }

    @Test func clusterRefreshFailureAndRecoveryKeepManualRanking() async throws {
        try await withDefaults { defaults in
            let client = MockHerdrClient()
            await client.setCatalog(.success([Fixture.remote]))
            await client.set(.local, .success(try Fixture.snapshot()))
            await client.set(Fixture.remote, .success(try Fixture.snapshot(machine: Fixture.remote)))
            let cluster = ClusterStore(client: client)
            await cluster.refresh()
            let order = SessionOrderStore(defaults: defaults)
            order.synchronize(with: cluster.agents.map(\.id))
            let promoted = try #require(cluster.agents.last { $0.id.machineID == Fixture.remote.id })
            order.move(promoted.id, .first, visibleIDs: cluster.agents.map(\.id))
            let expected = order.ranked(cluster.agents).map(\.id)

            await client.set(Fixture.remote, .failure(HerdrFailure(.unreachable, "Offline")))
            await cluster.refresh()
            order.synchronize(with: cluster.agents.map(\.id))
            #expect(order.ranked(cluster.agents).map(\.id) == expected)
            #expect(order.ranked(cluster.agents).first?.isStale == true)

            // A successful empty response removes rows, but not their saved positions.
            await client.set(Fixture.remote, .success(.init(version: "test", protocolVersion: 22, workspaces: [], agents: [])))
            await cluster.refresh()
            order.synchronize(with: cluster.agents.map(\.id))
            #expect(order.ranked(cluster.agents).map(\.manualPriority) == [1, 2, 3, 4])
            await client.set(Fixture.remote, .success(try Fixture.snapshot(machine: Fixture.remote)))
            await cluster.refresh()
            let reopened = SessionOrderStore(defaults: defaults)
            reopened.synchronize(with: cluster.agents.map(\.id))
            #expect(reopened.ranked(cluster.agents).map(\.id) == expected)
            #expect(reopened.ranked(cluster.agents).map(\.manualPriority) == Array(1...8))
        }
    }
}
