import AppKit
// Notification settings and requests predate Sendable; they never leave the main actor here.
@preconcurrency import UserNotifications
import ShepherdrCore

/// Posts a macOS notification when an agent finishes or needs you: the session's name, its state
/// and what the agent last said. Clicking one opens the session.
@MainActor
final class SessionNotifier: NSObject {
    static let enabledKey = "notifySessions"
    weak var model: AppModel?
    private var tracker = AgentStateTracker()
    /// Notifications need an app bundle; a bare SwiftPM executable has none.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil

    override init() {
        super.init()
        // Set before launch finishes, so a click that launches the app still reaches us.
        center?.delegate = self
    }

    /// Called with every refresh of the sessions.
    func observe(_ rows: [AgentRow]) {
        for row in tracker.stoppedWorking(rows) {
            Task {
                // What the agent printed also feeds the session's resources.
                let output = await model?.cluster.recentOutput(paneID: row.agent.paneID, onMachine: row.id.machineID, lines: 200)
                if let output { model?.collectResources(SessionResources.find(in: output), for: row.id) }
                // A finished turn may have pushed: its pull requests' checks start over.
                model?.checksMonitor.refresh(row.id)
                // The session on screen needs no notification.
                guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true,
                      !(NSApp.isActive && model?.selectedID == row.id) else { return }
                await post(row, output: output)
            }
        }
    }

    private func post(_ row: AgentRow, output: String?) async {
        guard let center, await isAuthorized(center) else { return }
        let content = UNMutableNotificationContent()
        content.title = row.workspace
        let place = (model?.showsMachineNames ?? false) ? "@\(row.machineName)" : nil
        content.subtitle = [row.agent.state == .blocked ? "Needs you" : "Done", row.name, place]
            .compactMap { $0 }.joined(separator: " · ")
        content.body = output.flatMap { AgentReply.lastParagraph(in: $0) } ?? row.agent.summary ?? ""
        content.sound = .default
        content.threadIdentifier = "\(row.id.machineID)/\(row.id.terminalID)"
        // Routes the click to the existing window.
        content.targetContentIdentifier = "main"
        content.userInfo = ["machineID": row.id.machineID, "terminalID": row.id.terminalID]
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Tells you a pull request's checks finished: passed, or how many failed.
    func checksFinished(_ pull: SessionResource, _ checks: PullRequestChecks, in id: Agent.ID) {
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true,
              !(NSApp.isActive && model?.selectedID == id) else { return }
        Task {
            guard let center, await isAuthorized(center) else { return }
            let content = UNMutableNotificationContent()
            content.title = checks.state == .passed ? "✓ Checks passed" : "✗ \(checks.failed) check\(checks.failed == 1 ? "" : "s") failed"
            let session = model?.row(for: id)?.workspace
            content.subtitle = [pull.name, session].compactMap { $0 }.joined(separator: " · ")
            content.body = [pull.title, checks.summary].compactMap { $0 }.joined(separator: "\n")
            content.sound = .default
            content.threadIdentifier = pull.key
            content.targetContentIdentifier = "main"
            content.userInfo = ["machineID": id.machineID, "terminalID": id.terminalID, "link": pull.url.absoluteString]
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    /// Asks the first time a notification is due; later answers come from System Settings.
    private func isAuthorized(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false
        }
    }
}

extension SessionNotifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let machineID = info["machineID"] as? String, let terminalID = info["terminalID"] as? String {
            let id = Agent.ID(machineID: machineID, terminalID: terminalID)
            let link = (info["link"] as? String).flatMap(URL.init(string:))
            Task { @MainActor in
                // Into the one main window, reopened if it was closed: never a second window.
                NSApp.activate(ignoringOtherApps: true)
                self.model?.showMainWindow()
                // A pull request's checks open the pull request too.
                if let link { self.model?.openLink(link, in: id) } else { self.model?.open(id) }
            }
        }
        completionHandler()
    }
}
