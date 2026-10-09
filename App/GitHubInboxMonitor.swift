import Foundation
import ShepherdrCore

/// Asks GitHub, through its CLI, what the followed repositories ask of you: issues assigned to you,
/// pull requests awaiting your review and your own open pull requests, in one query. A failed sync
/// keeps the last answer on screen.
@MainActor @Observable
final class GitHubInboxMonitor {
    /// The last answer GitHub gave, kept through failed syncs.
    private(set) var inbox: GitHubInbox?
    private(set) var isSyncing = false
    /// Why the last sync failed; nil once one succeeds.
    private(set) var error: GitHubSyncError?
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private let gitHub = GitHubLookup()
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    /// How old an answer can be before showing the home screen asks again.
    static let freshness: TimeInterval = 300

    /// Syncs if it never did, or if the last answer is more than five minutes old. Called when the
    /// home screen appears.
    func syncIfNeeded() async {
        if let inbox, Date().timeIntervalSince(inbox.syncedAt) <= Self.freshness { return }
        await sync()
    }

    /// Syncs now, for the manual button. A sync already under way isn't repeated: this waits for it.
    func sync() async {
        if let syncTask {
            await syncTask.value
            return
        }
        let task = Task { await run() }
        syncTask = task
        await task.value
        syncTask = nil
    }

    private func run() async {
        isSyncing = true
        defer { isSyncing = false }
        let repositories = model?.githubInbox.activeRepositories ?? []
        switch await gitHub.inbox(repositories: repositories, includeMyPullRequests: true) {
        case .success(let found):
            inbox = found
            error = nil
        case .failure(let failure):
            error = failure
        }
    }
}

extension GitHubSyncError {
    /// A short headline and what to do about it, in the user's words.
    var notice: (title: String, message: String, detail: String?) {
        switch self {
        case .notInstalled:
            ("Instala GitHub CLI",
             "Esta sección pregunta a GitHub a través de su CLI, gh, y no está instalado en este Mac.",
             "Instálalo con `brew install gh` (o desde https://cli.github.com), inicia sesión con `gh auth login` y pulsa SYNC.")
        case .signedOut:
            ("Inicia sesión en GitHub CLI",
             "gh está instalado pero no tiene sesión iniciada.",
             "Ejecuta `gh auth login` en una terminal y pulsa SYNC.")
        case .rateLimited(let resetAt):
            ("Límite de peticiones de GitHub agotado",
             resetAt.map { "GitHub vuelve a responder a partir de las \($0.formatted(date: .omitted, time: .shortened))." }
                ?? "Inténtalo más tarde.",
             nil)
        case .failed(let message):
            ("No se pudo sincronizar con GitHub", "GitHub no devolvió la bandeja. Pulsa SYNC para reintentar.", message)
        }
    }
}
