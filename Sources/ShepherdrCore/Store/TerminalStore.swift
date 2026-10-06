import Foundation
import Observation

@MainActor @Observable
public final class TerminalStore {
    public enum Status: Equatable { case disconnected, connecting, observing, interactive, ended, failed }
    public let target: TerminalTarget
    public private(set) var status: Status = .disconnected
    public private(set) var mode: TerminalMode = .observe
    public private(set) var message: String?
    public private(set) var detail: String?
    public private(set) var size = TerminalSize()
    @ObservationIgnored public var display: ((TerminalFrame) -> Void)?
    @ObservationIgnored public var resetDisplay: (() -> Void)?
    @ObservationIgnored private let client: any HerdrTerminalClient
    @ObservationIgnored private var connection: (any HerdrTerminalConnection)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var resizeTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var inputTask: Task<Void, Never>?

    /// Another client already controls this terminal; Shepherdr fell back to observing it.
    public private(set) var isControlledElsewhere = false

    public init(target: TerminalTarget, mode: TerminalMode = .observe,
                client: any HerdrTerminalClient = CLIHerdrClient()) {
        self.target = target
        self.mode = mode == .takeover ? .control : mode
        self.client = client
    }

    public func open(mode: TerminalMode? = nil) {
        let mode = mode ?? self.mode
        disconnect()
        self.mode = mode
        status = .connecting
        message = nil
        detail = nil
        if mode != .observe { isControlledElsewhere = false }
        resetDisplay?()
        let attempt = generation
        task = Task { [weak self, client, target, size] in
            do {
                let stream = try await client.connect(to: target, mode: mode, size: size)
                guard let self, attempt == self.generation, !Task.isCancelled else { stream.close(); return }
                self.connection = stream
                defer { stream.close() }
                for try await event in stream.events {
                    guard attempt == self.generation, !Task.isCancelled else { return }
                    switch event {
                    case .frame(let frame):
                        // Written only on change: every write invalidates the views that read it.
                        let status: Status = mode.acceptsInput ? .interactive : .observing
                        if self.status != status { self.status = status }
                        // A takeover happens once; later reconnects ask politely again.
                        if mode == .takeover, self.mode != .control { self.mode = .control }
                        self.display?(frame)
                    case .closed(let reason):
                        let rejected = self.status == .connecting && Self.isControlConflict(reason)
                        if mode.acceptsInput, rejected || Self.wasTakenOver(reason) {
                            // Never steal input implicitly: keep watching and let the user decide.
                            self.isControlledElsewhere = true
                            self.open(mode: .observe)
                            return
                        }
                        self.message = reason
                        self.status = .ended
                    }
                }
                if attempt == self.generation, self.status != .failed {
                    self.status = .ended
                    self.message = self.message ?? "Detached. The terminal continues in Herdr."
                    self.connection = nil
                }
            } catch {
                guard let self, attempt == self.generation, !Task.isCancelled else { return }
                self.status = .failed
                self.message = error.localizedDescription
                self.detail = (error as? HerdrFailure)?.detail
                self.connection = nil
            }
        }
    }

    public func disconnect() {
        generation += 1
        resizeTask?.cancel()
        resizeTask = nil
        inputTask?.cancel()
        inputTask = nil
        task?.cancel()
        task = nil
        connection?.close()
        connection = nil
        status = .disconnected
    }

    /// Explicit, user-initiated replacement of another controlling client.
    public func takeOver() { open(mode: .takeover) }

    /// Types a composed prompt and submits it with a separate Return keystroke.
    @discardableResult
    public func submit(prompt text: String) -> Bool {
        guard status == .interactive, let body = TerminalPrompt.body(text) else { return false }
        send(.bytes(body))
        send(.pause(.milliseconds(body.first == 27 ? 120 : 40)))
        send(.bytes(TerminalPrompt.submit))
        return true
    }

    public func press(_ key: TerminalKey) { send(.bytes(key.bytes)) }

    public func send(_ input: TerminalInput) {
        guard status == .interactive, let connection else { return }
        let previous = inputTask
        let attempt = generation
        // Keep keyboard/paste/resize order even though the transport API is asynchronous.
        inputTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, self?.generation == attempt else { return }
            do {
                if case .pause(let duration) = input { try await Task.sleep(for: duration) }
                else { try await connection.send(input) }
            }
            catch {
                guard let self, self.generation == attempt else { return }
                self.message = error.localizedDescription
                self.detail = (error as? HerdrFailure)?.detail
            }
        }
    }

    public func resize(columns: Int, rows: Int) {
        let next = TerminalSize(columns: columns, rows: rows)
        guard next != size else { return }
        size = next
        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            guard let self else { return }
            if self.status == .interactive { self.send(.resize(self.size)) }
            // Observe has no stdin resize authority. Reopen just this observer at its new viewport.
            else if self.status == .observing || self.status == .connecting { self.open(mode: self.mode) }
        }
    }

    nonisolated static func wasTakenOver(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("taken over")
    }

    nonisolated static func isControlConflict(_ reason: String) -> Bool {
        reason.localizedCaseInsensitiveContains("already has an attached client")
            || reason.localizedCaseInsensitiveContains("--takeover")
    }
}
