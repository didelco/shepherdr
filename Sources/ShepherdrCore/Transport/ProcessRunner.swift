import Foundation
import Darwin

struct CommandOutput: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

protocol CommandRunning: Sendable {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandOutput
}

enum CommandError: Error, Sendable { case timedOut, outputTooLarge, launch(String) }

struct ProcessRunner: CommandRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> CommandOutput {
        let operation = ProcessOperation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.start(executable: executable, arguments: arguments,
                                timeout: timeout, continuation: continuation)
            }
        } onCancel: {
            operation.cancel()
        }
    }
}

/// Foundation callbacks are bridged into one serial queue. All mutable state is queue-confined.
/// Both pipes are drained concurrently; neither waitUntilExit nor blocking reads run on an actor.
private final class ProcessOperation: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.javiertoledo.shepherdr.process")
    private let process = Process()
    private let stdout = Pipe()
    private let stderr = Pipe()
    private var output = Data()
    private var diagnostics = Data()
    private var stdoutEnded = false
    private var stderrEnded = false
    private var exitCode: Int32?
    private var cancelled = false
    private var finished = false
    private var continuation: CheckedContinuation<CommandOutput, Error>?
    private var deadline: DispatchWorkItem?
    private let outputLimit = 8 * 1_024 * 1_024

    func start(executable: URL, arguments: [String], timeout: TimeInterval,
               continuation: CheckedContinuation<CommandOutput, Error>) {
        queue.async { [self] in
            self.continuation = continuation
            guard !self.cancelled else { self.finish(.failure(CancellationError())); return }
            self.process.executableURL = executable
            self.process.arguments = arguments
            self.process.standardInput = FileHandle.nullDevice
            self.process.standardOutput = self.stdout
            self.process.standardError = self.stderr
            var environment = ProcessInfo.processInfo.environment
            // A GUI launched from an agent pane must not inherit that pane/session routing.
            for key in ["HERDR_PANE_ID", "HERDR_WORKSPACE_ID", "HERDR_TAB_ID", "HERDR_SOCKET_PATH", "HERDR_SESSION"] {
                environment.removeValue(forKey: key)
            }
            environment["NO_COLOR"] = "1"
            environment["SSH_ASKPASS_REQUIRE"] = "never"
            self.process.environment = environment
            self.stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = (try? handle.read(upToCount: 64 * 1_024)) ?? Data()
                if data.isEmpty { handle.readabilityHandler = nil }
                self?.receive(data, isError: false)
            }
            self.stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = (try? handle.read(upToCount: 64 * 1_024)) ?? Data()
                if data.isEmpty { handle.readabilityHandler = nil }
                self?.receive(data, isError: true)
            }
            self.process.terminationHandler = { [weak self] process in
                let code = process.terminationStatus
                self?.queue.async { [weak self] in
                    self?.exitCode = code
                    self?.completeIfDrained()
                }
            }
            do {
                try self.process.run()
                let deadline = DispatchWorkItem { [weak self] in
                    self?.finish(.failure(CommandError.timedOut))
                }
                self.deadline = deadline
                self.queue.asyncAfter(deadline: .now() + timeout, execute: deadline)
            } catch {
                self.finish(.failure(CommandError.launch(error.localizedDescription)))
            }
        }
    }

    func cancel() {
        queue.async {
            self.cancelled = true
            if self.continuation != nil { self.finish(.failure(CancellationError())) }
        }
    }

    private func receive(_ data: Data, isError: Bool) {
        queue.async {
            guard !self.finished else { return }
            if isError {
                self.diagnostics.append(data)
                if data.isEmpty { self.stderrEnded = true }
            } else {
                self.output.append(data)
                if data.isEmpty { self.stdoutEnded = true }
            }
            if self.output.count + self.diagnostics.count > self.outputLimit {
                self.finish(.failure(CommandError.outputTooLarge))
            } else {
                self.completeIfDrained()
            }
        }
    }

    private func completeIfDrained() {
        guard stdoutEnded, stderrEnded, let exitCode else { return }
        finish(.success(CommandOutput(stdout: output, stderr: diagnostics, exitCode: exitCode)))
    }

    private func finish(_ result: Result<CommandOutput, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel()
        deadline = nil
        if process.isRunning {
            let pid = process.processIdentifier
            // Only signal a child-owned process group, never the host app's process group.
            if getpgid(pid) == pid { kill(-pid, SIGKILL) }
            else { kill(pid, SIGKILL) }
        }
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        try? stdout.fileHandleForReading.close()
        try? stderr.fileHandleForReading.close()
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
        process.terminationHandler = nil
        continuation?.resume(with: result)
        continuation = nil
    }
}
