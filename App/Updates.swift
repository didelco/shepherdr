import AppKit
import SwiftUI
import ShepherdrCore

/// Once a day, asks GitHub for Shepherdr's latest release and offers it when it is newer than this
/// app. Updating runs the updater script, which checks the download and the new app's signature,
/// then quits Shepherdr for the script to swap the apps and open the new one. Only builds signed
/// with a Developer ID update themselves: the new app must come from the same team.
@MainActor @Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        /// A newer release, offered until you update or put it off.
        case available(AppRelease)
        /// After a check you asked for found nothing newer.
        case upToDate
        case installing(Updater.Stage?)
        case failed(String)
    }

    static let automaticKey = "checksForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"

    private(set) var state: State = .idle
    /// The offer was put off: it comes back with the next day's check.
    private(set) var isPutOff = false
    /// How the last update went, shown once when Shepherdr opens after it.
    var outcome: UpdateOutcome?
    private(set) var lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    @ObservationIgnored private var ticker: Task<Void, Never>?

    let version = AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    @ObservationIgnored private let team = Updater.signingTeam()
    private var bundleID: String { Bundle.main.bundleIdentifier ?? "com.theagilemonkeys.Shepherdr" }

    /// Where the updater script says how an update went, read on the next launch.
    private var statusFile: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(bundleID, isDirectory: true).appendingPathComponent("update-status")
    }

    /// Release builds look for updates; a local build has nothing to compare a release with.
    var canUpdate: Bool { team != nil && version != nil }

    /// Why this copy can't replace itself, when it can't: then the offer opens the release page.
    var whyNoInstall: String? {
        guard canUpdate else { return "This build isn't a signed release, so it doesn't update itself." }
        let app = Bundle.main.bundleURL
        if app.path.contains("/AppTranslocation/") {
            return "macOS runs this copy from a temporary place. Move Shepherdr to Applications to update it from here."
        }
        let folder = app.deletingLastPathComponent().path
        return FileManager.default.isWritableFile(atPath: folder) ? nil : "Shepherdr can't write to \(folder)."
    }

    /// Reads how the last update went, then checks once a day while Shepherdr is open.
    func start() {
        guard ticker == nil else { return }
        if let text = try? String(contentsOf: statusFile, encoding: .utf8) {
            outcome = UpdateOutcome(status: text)
            try? FileManager.default.removeItem(at: statusFile)
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if canUpdate, UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true,
                   UpdateSchedule.isDue(lastCheck: lastCheck) {
                    await check(asked: false)
                }
                try? await Task.sleep(for: .seconds(3_600))
            }
        }
    }

    /// Asks GitHub for the latest release. A check you asked for also says when there's nothing newer.
    func check(asked: Bool) async {
        if case .installing = state { return }
        guard canUpdate, let version else {
            if asked { state = .failed("This build isn't a signed release, so it doesn't update itself.") }
            return
        }
        state = .checking
        let release = await Updater.latest()
        guard let release else {
            state = asked ? .failed("GitHub didn't answer. Try again in a while.") : .idle
            return
        }
        lastCheck = Date()
        UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey)
        if release.version > version {
            if state != .available(release) || asked { isPutOff = false }
            state = .available(release)
        } else {
            state = asked ? .upToDate : .idle
        }
    }

    /// Downloads and checks the release with the updater script, then quits for it to swap the apps.
    func install() {
        guard case .available(let release) = state else { return }
        guard whyNoInstall == nil, let team else {
            NSWorkspace.shared.open(release.page)
            return
        }
        state = .installing(nil)
        let app = Bundle.main.bundleURL, bundleID = bundleID, status = statusFile
        let pid = ProcessInfo.processInfo.processIdentifier
        Task {
            do {
                try await Updater.install(release, over: app, team: team, bundleID: bundleID, status: status, pid: pid) { stage in
                    Task { @MainActor [weak self] in self?.state = .installing(stage) }
                }
                NSApp.terminate(nil)
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }

    func putOff() { isPutOff = true }

    func dismiss() {
        outcome = nil
        if case .available = state { return }
        state = .idle
    }
}

/// Where the sidebar offers a new release and shows how updating goes.
struct UpdateBanner: View {
    let updates: UpdateController

    var body: some View {
        if let outcome = updates.outcome {
            switch outcome {
            case .updated(let version):
                line("✓ Updated to Shepherdr \(version)", color: Theme.phosphor) { closeButton }
            case .failed(let why):
                line("✗ The update didn't finish: \(why)", color: Theme.red) { closeButton }
            }
        } else {
            switch updates.state {
            case .available(let release) where !updates.isPutOff:
                offer(release)
            case .installing(let stage):
                line(stage == .verifying ? "checking the new version…" : "downloading the new version…", color: Theme.phosphor) {
                    BlinkingCursor()
                }
            case .upToDate:
                line("✓ Shepherdr \(updates.version?.description ?? "") is the latest version", color: Theme.phosphor) { closeButton }
            case .failed(let why):
                line("✗ \(why)", color: Theme.red) { closeButton }
            default:
                EmptyView()
            }
        }
    }

    private func offer(_ release: AppRelease) -> some View {
        let reason = updates.whyNoInstall
        return VStack(alignment: .leading, spacing: 7) {
            Text("↑ SHEPHERDR \(release.version) IS OUT").font(Theme.mono(10.5, .bold)).tracking(1).foregroundStyle(Theme.cyan)
            Text("You have \(updates.version?.description ?? "an older version").")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
            HStack(spacing: 6) {
                Button(reason == nil ? "UPDATE" : "DOWNLOAD") { updates.install() }
                    .buttonStyle(ConsoleButtonStyle(tint: Theme.cyan, prominent: true))
                    .help(reason ?? "Download it, check its signature, and restart Shepherdr in the new version")
                Button("NOTES") { NSWorkspace.shared.open(release.page) }
                    .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                    .help("What's new, on GitHub")
                Button("LATER") { updates.putOff() }
                    .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                    .help("Ask again tomorrow")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.cyan.opacity(0.07))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func line(_ text: String, color: Color, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(text).font(Theme.mono(10)).foregroundStyle(color).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var closeButton: some View {
        Button { updates.dismiss() } label: { Text("×").font(Theme.mono(12)) }
            .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Dismiss")
    }
}
