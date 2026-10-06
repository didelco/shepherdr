import SwiftUI
import ShepherdrCore

/// The home screen: cluster pulse at a glance, then every session as a card in priority order.
struct OverviewView: View {
    @Bindable var model: AppModel
    private var cluster: ClusterStore { model.cluster }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                counters
                if let failure = cluster.discoveryFailure, failure.state != .notInstalled {
                    NoticeView(title: "Saved machines could not be refreshed", message: failure.message, detail: failure.detail)
                }
                ForEach(cluster.machines.filter { $0.failure != nil }) { state in
                    NoticeView(title: "\(state.machine.name): \(state.connection.title)" + (state.isStale ? " · showing last known data" : ""),
                               message: state.failure?.message ?? "", detail: state.failure?.detail)
                }
                sessions
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 28)
            .frame(maxWidth: 1_100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 18) {
            PixelFlock(pixel: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text("SHEPHERDR").font(Theme.mono(28, .heavy)).tracking(6).foregroundStyle(Theme.text)
                    .shadow(color: Theme.phosphor.opacity(0.35), radius: 8)
                HStack(spacing: 0) {
                    Text("do androids dream of electric sheep?")
                    BlinkingCursor()
                }
                .font(Theme.mono(12)).foregroundStyle(Theme.phosphor.opacity(0.8))
            }
        }
    }

    private var counters: some View {
        let live = cluster.agents.filter { !$0.isStale }
        return HStack(spacing: 10) {
            ForEach([AgentState.blocked, .working, .done, .idle], id: \.self) { state in
                let count = live.filter { $0.agent.state == state }.count
                let color = count > 0 ? Theme.color(for: state) : Theme.faint
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%02d", count)).font(Theme.mono(26, .bold)).foregroundStyle(color)
                        .shadow(color: count > 0 ? color.opacity(0.5) : .clear, radius: 6)
                    Text(state == .blocked ? "NEED YOU" : state.title.uppercased())
                        .font(Theme.mono(10, .semibold)).tracking(1.5).foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(count > 0 && state == .blocked ? Theme.amber.opacity(0.5) : Theme.line, lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var sessions: some View {
        let rows = model.matchingRows
        ConsoleHeader(title: "Sessions by priority", trailing: rows.isEmpty ? nil : "⌘1–⌘9 to jump")
        if rows.isEmpty {
            Text(emptyMessage).font(Theme.mono(12)).foregroundStyle(Theme.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 10)], spacing: 10) {
                ForEach(rows) { row in
                    SessionCard(row: row, showsMachine: model.showsMachineNames) { model.open(row.id) }
                }
            }
        }
    }

    private var emptyMessage: String {
        if !model.search.isEmpty { return "No sessions match \"\(model.search)\"." }
        if cluster.isRefreshing && cluster.lastRefresh == nil { return "Connecting to Herdr…" }
        if cluster.onlineCount == 0 { return "Herdr is not reachable. Open Settings (⌘,) → Machines for details, then refresh (⌘R)." }
        return "Connected. Agents appear here when Herdr detects them in a workspace."
    }
}

private struct SessionCard: View {
    let row: AgentRow
    let showsMachine: Bool
    let open: () -> Void
    @ViewState<Bool> private var hovering = false

    var body: some View {
        let color = Theme.color(for: row.agent.state, stale: row.isStale)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(String(format: "%02d", row.manualPriority)).font(Theme.mono(10, .semibold)).foregroundStyle(Theme.faint)
                    StateGlyph(state: row.agent.state, stale: row.isStale)
                    Text(row.workspace).font(Theme.mono(13, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 4)
                    StateTag(state: row.agent.state, stale: row.isStale)
                }
                Text(row.title).font(Theme.mono(11)).foregroundStyle(Theme.text.opacity(0.7)).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(showsMachine ? "\(row.agent.kind) @\(row.machineName)" : row.agent.kind)
                    .font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(hovering ? Theme.raised : Theme.panel, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(hovering ? color.opacity(0.6) : Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(row.isStale ? 0.6 : 1)
        .help("Open \(row.workspace)")
    }
}

struct BlinkingCursor: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { timeline in
            let on = Int(timeline.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0
            Rectangle().fill(Theme.phosphor).frame(width: 7, height: 13).opacity(on ? 0.9 : 0).padding(.leading, 3)
        }
        .accessibilityHidden(true)
    }
}
