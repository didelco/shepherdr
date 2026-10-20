import Foundation
import Testing
@testable import ShepherdrCore

struct ReadinessTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let host = "api.anthropic.com"

    /// Awake, online, and `host` resolved at `start`.
    private func ready() -> Readiness {
        var readiness = Readiness()
        readiness.pathChanged(online: true, at: start - 10)
        readiness.looked(up: host, resolved: true, asked: start, at: start)
        return readiness
    }

    @Test func aMacFullyAwakeAndOnlineIsReady() {
        let readiness = ready()
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 1) == nil)
        #expect(!readiness.needsLookup(host, at: start + 1))
        // Where macOS doesn't say, sleep and wake alone decide.
        #expect(readiness.blocker(host: host, hasGraphics: nil, at: start + 1) == nil)
    }

    @Test func aDarkWakeIsNeverReady() {
        // 20/10, 10:14:54: Shepherdr started Claude Code a second into a two-second dark wake.
        let readiness = ready()
        #expect(readiness.blocker(host: host, hasGraphics: false, at: start + 1) == .darkWake)
        #expect(readiness.blocker(host: nil, hasGraphics: false, at: start + 1) == .darkWake)
    }

    @Test func goingToSleepWaitsForTheWake() {
        var readiness = ready()
        readiness.willSleep(at: start + 5)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 6) == .sleeping)
        #expect(readiness.blocker(host: nil, hasGraphics: true, at: start + 6) == .sleeping)
        // Without macOS's answer, only the wake ends it.
        #expect(readiness.blocker(host: nil, hasGraphics: nil, at: start + 3_600) == .sleeping)
        // With it, a Mac with graphics a minute later missed the wake.
        #expect(readiness.blocker(host: nil, hasGraphics: true, at: start + 66) == nil)
        // A clock set back doesn't end it.
        #expect(readiness.blocker(host: nil, hasGraphics: true, at: start) == .sleeping)
        readiness.didWake(at: start + 7)
        #expect(readiness.blocker(host: nil, hasGraphics: true, at: start + 8) == nil)
    }

    @Test func aWakeLooksTheHostUpAgain() {
        var readiness = ready()
        readiness.willSleep(at: start + 5)
        readiness.didWake(at: start + 3_600)
        // The answer from before the sleep doesn't count, and neither does one asked before the wake.
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 3_601) == .lookingUp(host))
        #expect(readiness.needsLookup(host, at: start + 3_601))
        readiness.looked(up: host, resolved: true, asked: start + 3_599, at: start + 3_602)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 3_602) == .lookingUp(host))
        readiness.looked(up: host, resolved: true, asked: start + 3_601, at: start + 3_602)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 3_603) == nil)
    }

    @Test func theNetworkMustHaveAPathAndTheHostMustResolve() {
        var readiness = Readiness()
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start) == .offline)
        readiness.pathChanged(online: false, at: start)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start) == .offline)
        // An agent whose service Shepherdr doesn't know doesn't wait for the network.
        #expect(readiness.blocker(host: nil, hasGraphics: true, at: start) == nil)
        readiness.pathChanged(online: true, at: start + 1)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 1) == .lookingUp(host))
        readiness.looked(up: host, resolved: false, asked: start + 1, at: start + 2)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 3) == .unresolved(host))
        // A failed lookup is tried again after a while, a good one after a minute.
        #expect(!readiness.needsLookup(host, at: start + 5))
        #expect(readiness.needsLookup(host, at: start + 12))
        readiness.looked(up: host, resolved: true, asked: start + 12, at: start + 12)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 13) == nil)
        #expect(!readiness.needsLookup(host, at: start + 70))
        #expect(readiness.needsLookup(host, at: start + 72))
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 72) == .lookingUp(host))
        // Another network, such as Ethernet after Wi-Fi, is looked up again.
        readiness.looked(up: host, resolved: true, asked: start + 72, at: start + 72)
        readiness.pathChanged(online: true, at: start + 80)
        #expect(readiness.blocker(host: host, hasGraphics: true, at: start + 80) == .lookingUp(host))
    }

    @Test func sleepingAndLosingTheNetworkAreDisruptions() {
        var readiness = ready()
        #expect(!readiness.disrupted(since: start - 100))
        readiness.pathChanged(online: true, at: start + 5)
        #expect(!readiness.disrupted(since: start - 100))
        readiness.pathChanged(online: false, at: start + 10)
        readiness.pathChanged(online: false, at: start + 20)
        #expect(readiness.disrupted(since: start + 10))
        // Still offline is the same disruption.
        #expect(!readiness.disrupted(since: start + 11))
        readiness.pathChanged(online: true, at: start + 30)
        readiness.willSleep(at: start + 40)
        readiness.didWake(at: start + 4_000)
        #expect(readiness.disrupted(since: start + 40))
        #expect(!readiness.disrupted(since: start + 41))
    }

    @Test func blockersSayWhatTheRunWaitsFor() {
        #expect(Readiness.Blocker.darkWake.summary == "this Mac to wake up")
        #expect(Readiness.Blocker.lookingUp(host).summary == "the network")
        #expect(Readiness.Blocker.unresolved(host).summary == "the network: api.anthropic.com doesn't resolve")
        #expect(Readiness.host(forAgent: "claude") == host)
        #expect(Readiness.host(forAgent: "opencode") == nil)
    }
}

struct AgentStartupTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func online(at date: Date) -> Readiness {
        var readiness = Readiness()
        readiness.pathChanged(online: true, at: date)
        return readiness
    }

    @Test func theFirstPromptWaitsForTheAgentToSettle() {
        let startup = AgentStartup(terminalID: "t1", began: start, ready: start + 8)
        let readiness = online(at: start - 60)
        #expect(startup.decision(disrupted: readiness.disrupted(since: startup.began), typed: false, at: start + 9) == .wait)
        #expect(startup.decision(disrupted: readiness.disrupted(since: startup.began), typed: false, at: start + 8 + AgentStartup.settling) == .prompt)
    }

    @Test func anAgentStartedAcrossASleepStartsAgain() {
        // 19/10: the agent started at 09:39:19, the Mac slept seconds later and woke at 10:07:43.
        let startup = AgentStartup(terminalID: "t1", began: start, ready: start + 20)
        var readiness = online(at: start - 60)
        readiness.willSleep(at: start + 2)
        readiness.didWake(at: start + 1_700)
        #expect(startup.decision(disrupted: readiness.disrupted(since: startup.began), typed: false, at: start + 1_710) == .restart)
        // Never once you typed to it: it may have your conversation.
        #expect(startup.decision(disrupted: readiness.disrupted(since: startup.began), typed: true, at: start + 1_710) == .prompt)
        // And only so many times.
        let again = AgentStartup(terminalID: "t2", began: start, ready: start + 20, restarts: AgentStartup.maxRestarts)
        #expect(again.decision(disrupted: readiness.disrupted(since: again.began), typed: false, at: start + 1_710) == .prompt)
    }

    @Test func aNetworkLostWhileItStartedCountsToo() {
        let startup = AgentStartup(terminalID: "t1", began: start, ready: start + 10)
        var readiness = online(at: start - 60)
        readiness.pathChanged(online: false, at: start + 12)
        readiness.pathChanged(online: true, at: start + 14)
        #expect(startup.decision(disrupted: readiness.disrupted(since: startup.began), typed: false, at: start + 40) == .restart)
        // A disruption before it began doesn't.
        let later = AgentStartup(terminalID: "t2", began: start + 20, ready: start + 30)
        #expect(later.decision(disrupted: readiness.disrupted(since: later.began), typed: false, at: start + 60) == .prompt)
    }
}
