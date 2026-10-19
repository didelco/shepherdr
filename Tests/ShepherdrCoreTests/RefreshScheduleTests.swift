import Foundation
import Testing
@testable import ShepherdrCore

struct RefreshScheduleTests {
    private let remote = Fixture.remote
    private let disabled = Machine(profileID: "off", name: "Off", target: "off", session: "default", isEnabled: false)
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func onScreenEveryMachineAnswersAtTheUsersInterval() {
        var schedule = RefreshSchedule()
        let machines = [Machine.local, remote, disabled]
        let first = schedule.due(machines, interval: 5, onScreen: true, now: start)
        #expect(first.machines == [Machine.local.id, remote.id])
        #expect(first.catalog)
        schedule.didAsk(first.machines, catalog: true, at: start)
        #expect(schedule.due(machines, interval: 5, onScreen: true, now: start + 3).machines.isEmpty)
        // A tick a hair early still counts.
        #expect(schedule.due(machines, interval: 5, onScreen: true, now: start + 4.95).machines == [Machine.local.id, remote.id])
        #expect(!schedule.due(machines, interval: 5, onScreen: true, now: start + 5).catalog)
    }

    @Test func offScreenOtherMachinesAnswerEveryThirtySeconds() {
        var schedule = RefreshSchedule()
        let machines = [Machine.local, remote]
        schedule.didAsk([Machine.local.id, remote.id], catalog: true, at: start)
        #expect(schedule.due(machines, interval: 5, onScreen: false, now: start + 5).machines == [Machine.local.id])
        schedule.didAsk([Machine.local.id], catalog: false, at: start + 5)
        #expect(schedule.due(machines, interval: 5, onScreen: false, now: start + 25).machines == [Machine.local.id])
        #expect(schedule.due(machines, interval: 5, onScreen: false, now: start + 30).machines == [Machine.local.id, remote.id])
        // An interval longer than that one applies off screen too.
        #expect(schedule.due(machines, interval: 60, onScreen: false, now: start + 30).machines.isEmpty)
        // Back on screen, it is due at the user's interval again.
        #expect(schedule.due(machines, interval: 5, onScreen: true, now: start + 10).machines == [Machine.local.id, remote.id])
    }

    @Test func theCatalogIsReadAboutOnceAMinuteAndAgainAfterAFailure() {
        var schedule = RefreshSchedule()
        schedule.didAsk([], catalog: true, at: start)
        #expect(!schedule.due([], interval: 5, onScreen: true, now: start + 30).catalog)
        #expect(schedule.due([], interval: 5, onScreen: true, now: start + 59.5).catalog)
        schedule.catalogFailed = true
        #expect(schedule.due([], interval: 5, onScreen: true, now: start + 5).catalog)
        // A clock set back counts as time gone by.
        schedule.catalogFailed = false
        #expect(schedule.due([Machine.local], interval: 5, onScreen: true, now: start - 60).catalog)
    }

    @MainActor @Test func offScreenTicksLeaveOtherMachinesAlone() async throws {
        let client = MockHerdrClient()
        await client.setCatalog(.success([remote]))
        await client.set(.local, .success(try Fixture.snapshot()))
        await client.set(remote, .success(try Fixture.snapshot(machine: remote)))
        let store = ClusterStore(client: client)
        await store.refresh()
        #expect(await client.snapshotCalls().sorted() == [Machine.local.id, remote.id].sorted())
        #expect(await client.catalogReadCount() == 1)

        store.isOnScreen = false
        let now = Date()
        await store.tick(now: now + 5)
        await store.tick(now: now + 10)
        #expect(await client.snapshotCalls().filter { $0 == remote.id }.count == 1)
        #expect(await client.snapshotCalls().filter { $0 == Machine.local.id }.count == 3)
        #expect(await client.catalogReadCount() == 1)
        await store.tick(now: now + 31)
        #expect(await client.snapshotCalls().filter { $0 == remote.id }.count == 2)

        // On screen again, every machine answers at the user's interval; the catalog once a minute.
        store.isOnScreen = true
        await store.tick(now: now + 36)
        #expect(await client.snapshotCalls().filter { $0 == remote.id }.count == 3)
        await store.tick(now: now + 61)
        #expect(await client.catalogReadCount() == 2)
    }

    @MainActor @Test func aMachineThatJoinsIsAskedRightAway() async throws {
        let client = MockHerdrClient()
        await client.set(.local, .success(try Fixture.snapshot()))
        await client.set(remote, .success(try Fixture.snapshot(machine: remote)))
        let store = ClusterStore(client: client)
        await store.refresh()
        #expect(store.machines.count == 1)
        // Saved in Herdr meanwhile: the next catalog read brings it, and it is asked at once.
        await client.setCatalog(.success([remote]))
        store.isOnScreen = false
        await store.tick(now: Date() + 61)
        #expect(store.machines.count == 2)
        #expect(await client.snapshotCalls().contains(remote.id))
        #expect(store.machines.last?.connection == .online)
    }
}
