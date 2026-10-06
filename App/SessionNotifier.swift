import AppKit
import UserNotifications
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
        let stopped = tracker.stoppedWorking(rows)
        guard UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true else { return }
        // The session on screen needs no notification.
        for row in stopped where !(NSApp.isActive && model?.selectedID == row.id) {
            Task { await post(row) }
        }
    }

    private func post(_ row: AgentRow) async {
        guard let center, await isAuthorized(center) else { return }
        let output = await model?.cluster.recentOutput(of: row)
        let content = UNMutableNotificationContent()
        content.title = row.workspace
        let place = (model?.showsMachineNames ?? false) ? "@\(row.machineName)" : nil
        content.subtitle = [row.agent.state == .blocked ? "Needs you" : "Done", row.name, place]
            .compactMap { $0 }.joined(separator: " · ")
        content.body = output.flatMap { AgentReply.lastParagraph(in: $0) } ?? row.agent.summary ?? ""
        content.sound = .default
        content.threadIdentifier = "\(row.id.machineID)/\(row.id.terminalID)"
        content.userInfo = ["machineID": row.id.machineID, "terminalID": row.id.terminalID]
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
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
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)
                self.model?.open(id)
            }
        }
        completionHandler()
    }
}
