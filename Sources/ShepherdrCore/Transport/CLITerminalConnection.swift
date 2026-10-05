import Foundation
import Darwin

/// One long-lived CLI stream. Mutable state and all writes are confined to ioQueue.
/// Pipes drain concurrently, writes are nonblocking, and a slow consumer fails rather than
/// silently losing ANSI deltas. This process never owns the Herdr server or its terminal.
final class CLITerminalConnection: HerdrTerminalConnection, @unchecked Sendable {
    let events: AsyncThrowingStream<TerminalEvent, Error>
    private let continuation: AsyncThrowingStream<TerminalEvent, Error>.Continuation
    private let ioQueue = DispatchQueue(label: "io.github.javiertoledo.shepherdr.terminal-stream")
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let mode: TerminalMode
    private var lineBuffer = Data()
    private var diagnostics = Data()
    private var pendingInput = Data()
    private var writeSource: DispatchSourceWrite?
    private var startupDeadline: DispatchWorkItem?
    private var outputEnded = false
    private var errorsEnded = false
    private var exitCode: Int32?
    private var finished = false
    private var receivedFrame = false
    private let lineLimit = 4 * 1_024 * 1_024

    private init(mode: TerminalMode) {
        self.mode = mode
        let stream = AsyncThrowingStream<TerminalEvent, Error>.makeStream(bufferingPolicy: .bufferingOldest(8))
        events = stream.stream
        continuation = stream.continuation
        continuation.onTermination = { [weak self] _ in
            self?.ioQueue.async { [weak self] in self?.finish() }
        }
    }

    static func start(command: TerminalCommand, mode: TerminalMode, startupTimeout: TimeInterval = 15) async throws -> CLITerminalConnection {
        let connection = CLITerminalConnection(mode: mode)
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
                connection.ioQueue.async {
                    do {
                        guard !connection.finished else { throw CancellationError() }
                        try connection.launch(command, startupTimeout: startupTimeout)
                        ready.resume()
                    } catch {
                        connection.finish(error)
                        ready.resume(throwing: error)
                    }
                }
            }
        } onCancel: { connection.close() }
        return connection
    }

    private func launch(_ command: TerminalCommand, startupTimeout: TimeInterval) throws {
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = command.environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        for (pipe, isError) in [(output, false), (errors, true)] {
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                // read(upToCount:) can wait to fill its request on macOS; a live stream
                // needs each currently available chunk without waiting for EOF.
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil }
                self?.ioQueue.async { [weak self] in self?.receive(bytes, isError: isError) }
            }
        }
        process.terminationHandler = { [weak self] child in
            let code = child.terminationStatus
            self?.ioQueue.async { [weak self] in
                self?.exitCode = code
                self?.finishIfDrained()
            }
        }
        let fd = input.fileHandleForWriting.fileDescriptor
        guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1,
              fcntl(fd, F_SETNOSIGPIPE, 1) != -1 else {
            throw HerdrFailure(.unreachable, "Could not configure terminal input.")
        }
        try process.run()
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, !self.receivedFrame else { return }
            self.finish(HerdrFailure(.unreachable, "Herdr did not provide a terminal frame in time.",
                                    detail: "Check the running server, SSH authentication, and terminal session support."))
        }
        startupDeadline = deadline
        ioQueue.asyncAfter(deadline: .now() + startupTimeout, execute: deadline)
    }

    func send(_ command: TerminalInput) async throws {
        let bytes = try TerminalJSON.command(command)
        try await withCheckedThrowingContinuation { (sent: CheckedContinuation<Void, Error>) in
            ioQueue.async { [self] in
                guard !finished, mode.acceptsInput else {
                    sent.resume(throwing: HerdrFailure(.unreachable, "This terminal is not accepting input."))
                    return
                }
                guard pendingInput.count + bytes.count <= 1_024 * 1_024 else {
                    sent.resume(throwing: HerdrFailure(.unreachable, "Terminal input is full. Wait before pasting more text."))
                    return
                }
                pendingInput.append(bytes)
                flushInput()
                sent.resume()
            }
        }
    }

    private func flushInput() {
        let fd = input.fileHandleForWriting.fileDescriptor
        while !pendingInput.isEmpty, !finished {
            let count = pendingInput.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if count > 0 { pendingInput.removeFirst(count); continue }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN {
                if writeSource == nil {
                    let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: ioQueue)
                    source.setEventHandler { [weak self] in self?.flushInput() }
                    writeSource = source
                    source.resume()
                }
                return
            }
            finish(HerdrFailure(.unreachable, "The terminal input connection closed."))
            return
        }
        writeSource?.cancel()
        writeSource = nil
    }

    private func receive(_ bytes: Data, isError: Bool) {
        guard !finished else { return }
        if isError {
            diagnostics.append(bytes.prefix(max(0, 16_384 - diagnostics.count)))
            if bytes.isEmpty { errorsEnded = true }
        } else {
            if bytes.isEmpty { outputEnded = true }
            lineBuffer.append(bytes)
            do {
                while let newline = lineBuffer.firstIndex(of: 10) {
                    let line = Data(lineBuffer[..<newline])
                    lineBuffer.removeSubrange(...newline)
                    guard line.count <= lineLimit else { throw oversizedFrame() }
                    if line.isEmpty { continue }
                    if let event = try TerminalJSON.event(line) {
                        if case .frame = event {
                            receivedFrame = true
                            startupDeadline?.cancel()
                        }
                        if case .dropped = continuation.yield(event) {
                            throw HerdrFailure(.unreachable, "Terminal rendering fell behind. Reconnect to obtain a complete screen.")
                        }
                        if case .closed = event { finish(); return }
                    }
                }
                guard lineBuffer.count <= lineLimit else { throw oversizedFrame() }
            } catch { finish(error); return }
        }
        finishIfDrained()
    }

    private func oversizedFrame() -> HerdrFailure { HerdrFailure(.incompatible, "Herdr sent a terminal record larger than 4 MB.") }

    private func finishIfDrained() {
        guard outputEnded, errorsEnded, let exitCode else { return }
        if exitCode != 0 || !receivedFrame || !lineBuffer.isEmpty {
            let detail = String(decoding: diagnostics, as: UTF8.self).nonempty
            finish(HerdrFailure(exitCode == 2 ? .incompatible : .unreachable,
                                "Could not keep the Herdr terminal connected (exit \(exitCode)).",
                                detail: detail ?? "Herdr must support terminal session observe/control and the existing terminal must still be available."))
        } else { finish() }
    }

    func close() { ioQueue.sync { finish() } }

    private func finish(_ error: Error? = nil) {
        guard !finished else { return }
        finished = true
        startupDeadline?.cancel()
        startupDeadline = nil
        writeSource?.cancel()
        writeSource = nil
        pendingInput.removeAll()
        // Closing stdin releases control; terminating this disposable CLI/SSH child also
        // closes its socket. Neither path addresses the server or pane process IDs.
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        for pipe in [output, errors] {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            try? pipe.fileHandleForWriting.close()
        }
        try? input.fileHandleForReading.close()
        process.terminationHandler = nil
        continuation.finish(throwing: error)
    }

    deinit {
        if process.isRunning { process.terminate() }
    }
}
