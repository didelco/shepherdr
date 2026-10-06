import AppKit
import SwiftUI
import ShepherdrCore
import ShepherdrDictation

/// Sidebar queue on the left, the selected session's live terminal in the work area.
struct MainView: View {
    @Bindable var model: AppModel
    @AppStorage("refreshSeconds") private var refreshSeconds = 5
    @AppStorage("openMode") private var openMode = TerminalMode.control.rawValue

    private var cluster: ClusterStore { model.cluster }

    var body: some View {
        HSplitView {
            SessionSidebar(model: model)
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)
            workArea
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .ignoresSafeArea(.container, edges: .top)
        .preferredColorScheme(.dark)
        .tint(Theme.phosphor)
        .task {
            configureRefresh()
            await cluster.monitor()
        }
        .onChange(of: refreshSeconds) { configureRefresh() }
        .onChange(of: cluster.agents.map(\.id), initial: true) {
            model.order.synchronize(with: cluster.agents.map(\.id))
        }
        .sheet(item: $model.newSession) { draft in NewSessionSheet(model: model, draft: draft) }
        .alert("Download the speech model?", isPresented: $model.asksToDownloadSpeechModel) {
            Button("Download") { model.acceptSpeechModelDownload() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Dictation transcribes on this Mac with NVIDIA Parakeet v3, the model scribe uses. It needs a one-time download of \(Dictation.modelDownloadSize) from Hugging Face. Your voice never leaves this Mac.")
        }
        .confirmationDialog(closeTitle, isPresented: Binding { model.closingSession != nil } set: { if !$0 { model.closingSession = nil } },
                            titleVisibility: .visible, presenting: model.closingSession) { id in
            Button("Close Session", role: .destructive) { Task { await model.closeSession(id) } }
            Button("Cancel", role: .cancel) { model.closingSession = nil }
        } message: { id in
            Text(closeMessage(id))
        }
        .alert(model.actionFailure?.message ?? "", isPresented: Binding { model.actionFailure != nil } set: { if !$0 { model.actionFailure = nil } }) {
            Button("OK") { model.actionFailure = nil }
        } message: {
            Text(model.actionFailure?.detail ?? "")
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            if cluster.automaticRefresh { Task { await cluster.refresh() } }
        }
    }

    @ViewBuilder private var workArea: some View {
        switch model.selection {
        case .overview:
            OverviewView(model: model)
        case .session(let id):
            if let context = model.context(for: id) {
                SessionView(context: context, model: model, mode: TerminalMode(rawValue: openMode) ?? .control)
                    .id(context.target)
            } else {
                ended
            }
        }
    }

    private var ended: some View {
        VStack(spacing: 12) {
            Text("[ SESSION ENDED ]").font(Theme.mono(14, .bold)).foregroundStyle(Theme.dim)
            Text("Herdr no longer reports this terminal.").font(Theme.mono(11)).foregroundStyle(Theme.faint)
            Button("BACK TO OVERVIEW") { model.selection = .overview }.buttonStyle(ConsoleButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private var closeTitle: String {
        guard let id = model.closingSession, let context = model.context(for: id) else { return "Close session?" }
        return "Close \(context.target.workspace)?"
    }

    private func closeMessage(_ id: Agent.ID) -> String {
        guard let context = model.context(for: id) else { return "" }
        let what = context.agent.map { "ends \($0.agent.kind) and closes" } ?? "closes"
        return "This \(what) pane \(context.paneID) in Herdr\(context.machine.machine.isLocal ? "" : " on \(context.machine.machine.name)"). "
            + "If it is the workspace's last pane, the workspace closes too. This cannot be undone."
    }

    private func configureRefresh() {
        cluster.automaticRefresh = refreshSeconds > 0
        cluster.refreshInterval = TimeInterval(max(5, refreshSeconds))
    }
}
