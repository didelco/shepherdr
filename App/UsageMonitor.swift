import Observation
import ShepherdrCore

/// The Claude subscription's usage, asked again every five minutes while Shepherdr runs. Without
/// Claude Code's login on this Mac, or without a connection, it has nothing to show.
@MainActor @Observable
final class UsageMonitor {
    private(set) var usage: ClaudeUsage?
    @ObservationIgnored private var loop: Task<Void, Never>?

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                // Keeps the last answer when one fails: a figure a few minutes old beats none.
                if let usage = await ClaudeUsageClient().fetch() { self?.usage = usage }
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }
}
