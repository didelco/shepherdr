import Testing
import Foundation
@testable import ShepherdrCore

@Suite @MainActor struct TransportTests {
    private let executable = URL(fileURLWithPath: "/test/herdr")

    @Test func testCLIUsesStructuredCatalogAndOpaqueRemoteSelector() async throws {
        let runner = RecordingRunner([
            CommandOutput(stdout: try Fixture.data("machines"), stderr: Data(), exitCode: 0),
            CommandOutput(stdout: try Fixture.data(), stderr: Data(), exitCode: 0)
        ])
        let client = CLIHerdrClient(runner: runner, executable: executable)
        let catalog = try await client.machines()
        _ = try await client.snapshot(for: catalog[0])
        let args = await runner.recordedArguments()
        #expect(args == [["machine", "list", "--json"], ["--machine", "opaque-remote-a", "api", "snapshot"]])
    }

    @Test func testLocalSnapshotCommand() async throws {
        let runner = RecordingRunner([CommandOutput(stdout: try Fixture.data(), stderr: Data(), exitCode: 0)])
        let client = CLIHerdrClient(runner: runner, executable: executable)
        _ = try await client.snapshot(for: .local)
        let args = await runner.recordedArguments()
        #expect(args == [["api", "snapshot"]])
    }

    @Test func testAPIErrorOnStderrIsReadBeforeExitStatus() async {
        for (code, state) in [("server_not_running", ConnectionState.notRunning),
                              ("protocol_mismatch", .incompatible), ("method_not_found", .incompatible),
                              ("herdr_not_installed", .notInstalled)] {
            let runner = RecordingRunner([output("", stderr: "{\"error\":{\"code\":\"\(code)\",\"message\":\"Action required\"}}", code: 1)])
            do {
                _ = try await CLIHerdrClient(runner: runner, executable: executable).snapshot(for: .local)
                Issue.record("Expected \(state)")
            } catch {
                #expect((error as? HerdrFailure)?.state == state)
            }
        }
    }

    @Test func testUnsupportedMachineForwardingIsActionableAndNeverFallsBackToLocal() async {
        let runner = RecordingRunner([output("", stderr: "unknown option: --machine", code: 2)])
        do {
            _ = try await CLIHerdrClient(runner: runner, executable: executable).snapshot(for: Fixture.remote)
            Issue.record("Expected incompatibility")
        } catch {
            #expect((error as? HerdrFailure)?.state == .incompatible)
            #expect((error as? HerdrFailure)?.message.contains("--machine") == true)
        }
        let args = await runner.recordedArguments()
        #expect(args.count == 1)
    }

    @Test func testLegacyConnectionFailureUsesStructuredServerStatus() async {
        let runner = RecordingRunner([output("", stderr: "OS connection error", code: 1), output(#"{"running":false,"compatible":null}"#)])
        do {
            _ = try await CLIHerdrClient(runner: runner, executable: executable).snapshot(for: .local)
            Issue.record("Expected stopped state")
        } catch { #expect((error as? HerdrFailure)?.state == .notRunning) }
        let args = await runner.recordedArguments()
        #expect(args.last == ["status", "server", "--json"])
    }

    @Test func testMalformedJSONAndMissingRequiredFieldsAreIncompatible() async {
        for response in ["invalid", "{}", #"{"result":{"type":"session_snapshot","snapshot":{}}}"#] {
            let runner = RecordingRunner([output(response)])
            do {
                _ = try await CLIHerdrClient(runner: runner, executable: executable).snapshot(for: .local)
                Issue.record("Expected incompatible response")
            } catch { #expect((error as? HerdrFailure)?.state == .incompatible) }
        }
    }

    @Test func testExecutableOverrideAndMissingInstallation() throws {
        #expect(try ExecutableLocator().locate(environment: ["SHEPHERDR_HERDR_PATH": "/bin/echo"]).path == "/bin/echo")
        #expect(throws: HerdrFailure.self) {
            try ExecutableLocator().locate(environment: ["SHEPHERDR_HERDR_PATH": "/missing/shepherdr-herdr"])
        }
    }

    @Test func testRealProcessPassesArgumentsLiterally() async throws {
        let literal = "$(touch /tmp/do-not-create) ; ' quoted value"
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/echo"), arguments: [literal], timeout: 3)
        #expect(String(decoding: result.stdout, as: UTF8.self) == literal + "\n")
        #expect(result.exitCode == 0)
    }

    @Test func testRealProcessDrainsBothPipesBeyondPipeCapacity() async throws {
        let script = "i=0; while [ $i -lt 2000 ]; do echo 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz0123456789'; echo 'stderr-abcdefghijklmnopqrstuvwxyz0123456789' >&2; i=$((i+1)); done"
        let result = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], timeout: 5)
        #expect(result.stdout.count > 100_000)
        #expect(result.stderr.count > 65_536)
        #expect(result.exitCode == 0)
    }

    @Test func testRealProcessTimeoutIsBounded() async {
        let start = Date()
        do {
            _ = try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.1)
            Issue.record("Expected timeout")
        } catch CommandError.timedOut { }
        catch { Issue.record("Unexpected \(error)") }
        #expect(Date().timeIntervalSince(start) < 2)
    }

    @Test func testRealProcessCancellationIsBounded() async throws {
        let task = Task {
            try await ProcessRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 15)
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
    }

    private let created = #"{"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9","label":"api"},"root_pane":{"pane_id":"w9:p1","terminal_id":"term-new","workspace_id":"w9"},"tab":{"tab_id":"w9:t1"}}}"#

    @Test func testCreateSessionMakesWorkspaceThenStartsAgentOnRemote() async throws {
        let runner = RecordingRunner([output(created), output(#"{"id":"cli:agent:start","result":{"type":"ok"}}"#)])
        let client = CLIHerdrClient(runner: runner, executable: executable)
        let session = try await client.createSession(.init(directory: "/srv/api", name: "api", agentKind: "claude"), on: Fixture.remote)
        #expect(session == CreatedSession(workspaceID: "w9", paneID: "w9:p1", terminalID: "term-new"))
        #expect(await runner.recordedArguments() == [
            ["--machine", "remote-1", "workspace", "create", "--cwd", "/srv/api", "--label", "api", "--no-focus"],
            ["--machine", "remote-1", "agent", "start", "api", "--kind", "claude", "--pane", "w9:p1", "--timeout", "60000"],
        ])
    }

    @Test func testAgentWaitingAtStartupStillOpensTheSession() async throws {
        let waiting = #"{"error":{"code":"agent_not_ready","message":"agent api is blocked during startup"},"id":"cli:agent:start"}"#
        let runner = RecordingRunner([output(created), output(waiting, code: 1)])
        let session = try await CLIHerdrClient(runner: runner, executable: executable)
            .createSession(.init(directory: "/tmp/api", name: "api", agentKind: "codex"), on: .local)
        #expect(session.terminalID == "term-new")
        #expect(session.notice?.contains("waiting for you") == true)

        let shell = RecordingRunner([output(created)])
        let plain = try await CLIHerdrClient(runner: shell, executable: executable)
            .createSession(.init(directory: "/tmp/api", name: "api", agentKind: nil), on: .local)
        #expect(plain.notice == nil)
        #expect(await shell.recordedArguments().count == 1)
    }

    @Test func testCloseAndMachineChangesUseLiteralArguments() async throws {
        let ok = output(#"{"result":{"type":"ok"}}"#)
        let runner = RecordingRunner([ok, ok, ok, ok, ok])
        let client = CLIHerdrClient(runner: runner, executable: executable)
        try await client.closeSession(paneID: "w2:p1", on: Fixture.remote)
        try await client.addMachine(.init(sshTarget: " me@box ", label: "Build box", remoteSession: "agents"))
        try await client.addMachine(.init(sshTarget: "box", label: " ", remoteSession: nil))
        try await client.setMachine(profileID: "remote-1", enabled: false)
        try await client.removeMachine(profileID: "remote-1")
        #expect(await runner.recordedArguments() == [
            ["--machine", "remote-1", "pane", "close", "w2:p1"],
            ["machine", "add", "me@box", "--label", "Build box", "--remote-session", "agents"],
            ["machine", "add", "box"],
            ["machine", "disable", "remote-1"],
            ["machine", "remove", "remote-1"],
        ])
    }

    @Test func testChangesRejectOptionLikeValuesWithoutRunningHerdr() async {
        let runner = RecordingRunner([])
        let client = CLIHerdrClient(runner: runner, executable: executable)
        await #expect(throws: HerdrFailure.self) {
            _ = try await client.createSession(.init(directory: "/tmp", name: "--takeover", agentKind: nil), on: .local)
        }
        await #expect(throws: HerdrFailure.self) {
            _ = try await client.createSession(.init(directory: "/tmp", name: "ok", agentKind: "-x"), on: .local)
        }
        await #expect(throws: HerdrFailure.self) { try await client.addMachine(.init(sshTarget: "-oProxyCommand=x", label: nil, remoteSession: nil)) }
        await #expect(throws: HerdrFailure.self) { try await client.addMachine(.init(sshTarget: "a b", label: nil, remoteSession: nil)) }
        await #expect(throws: HerdrFailure.self) { try await client.closeSession(paneID: "", on: .local) }
        #expect(await runner.recordedArguments().isEmpty)
    }

    @Test func testFailedMachineAddKeepsHerdrDiagnostics() async {
        let runner = RecordingRunner([output("", stderr: "Permission denied (publickey).", code: 1)])
        do {
            try await CLIHerdrClient(runner: runner, executable: executable)
                .addMachine(.init(sshTarget: "box", label: nil, remoteSession: nil))
            Issue.record("Expected failure")
        } catch let failure as HerdrFailure {
            #expect(failure.message == "Herdr could not add box.")
            #expect(failure.detail == "Permission denied (publickey).")
        } catch { Issue.record("Unexpected \(error)") }
    }
}
