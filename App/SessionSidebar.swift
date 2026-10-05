import SwiftUI
import ShepherdrCore

/// The priority queue: every agent session in the user's order, with reordering controls.
struct SessionSidebar: View {
    @Bindable var model: AppModel
    @AppStorage("refreshSeconds") private var refreshSeconds = 5
    @ViewState<Bool> private var showShells = true
    @FocusState private var searchFocused: Bool

    private var cluster: ClusterStore { model.cluster }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField.padding(.horizontal, 12).padding(.bottom, 10)
            Rectangle().fill(Theme.line).frame(height: 1)
            queue
            Rectangle().fill(Theme.line).frame(height: 1)
            footer
        }
        .background(Theme.panel)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { model.selection = .overview } label: {
                HStack(alignment: .center, spacing: 10) {
                    PixelFlock(pixel: 1.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHEPHERDR").font(Theme.mono(13, .heavy)).tracking(2.5).foregroundStyle(Theme.text)
                        Text(summaryLine).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Overview (⌘0)")
            Button { model.showsNewSession = true } label: { Text("+").font(Theme.mono(14, .bold)) }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(model.onlineMachines.isEmpty)
                .help("New session (⌘N)")
        }
        .padding(.horizontal, 14).padding(.top, 34).padding(.bottom, 12)
    }

    private var summaryLine: String {
        let live = cluster.agents.filter { !$0.isStale }
        let working = live.filter { $0.agent.state == .working }.count
        let blocked = live.filter { $0.agent.state == .blocked }.count
        return blocked > 0 ? "\(blocked) need you · \(working) working" : "\(live.count) agents · \(working) working"
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Text("/").font(Theme.mono(12, .bold)).foregroundStyle(Theme.phosphor)
            TextField("filter sessions", text: $model.search)
                .textFieldStyle(.plain).font(Theme.mono(12)).foregroundStyle(Theme.text)
                .focused($searchFocused)
                .onExitCommand { model.search = ""; searchFocused = false }
            if !model.search.isEmpty {
                Button { model.search = "" } label: { Text("×").font(Theme.mono(13)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.dim).help("Clear filter")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4)
            .strokeBorder(searchFocused ? Theme.phosphor.opacity(0.6) : Theme.line, lineWidth: 1))
        .background { Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0) }
    }

    private var queue: some View {
        List {
            // Headers are plain rows: plain-style section headers float over rows with a system material.
            ConsoleHeader(title: "Queue", trailing: model.search.isEmpty ? "\(model.visibleRows.count)" : "\(model.visibleRows.count) match")
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
                .plainRow()
            ForEach(model.visibleRows) { row in
                SessionRowView(row: row, isSelected: model.selectedID == row.id,
                               showsMachine: model.showsMachineNames, model: model)
                    .plainRow()
            }
            .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            if model.visibleRows.isEmpty { emptyQueue.plainRow() }
            if !model.shells.isEmpty {
                Button { showShells.toggle() } label: {
                    ConsoleHeader(title: "\(showShells ? "▾" : "▸") Shells", trailing: "\(model.shells.count)")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
                .help("Panes without a detected agent")
                .plainRow()
                if showShells {
                    ForEach(model.shells) { shell in
                        ShellRowView(shell: shell, isSelected: model.selectedID == shell.id,
                                     showsMachine: model.showsMachineNames) { model.open(shell.id) }
                            .contextMenu {
                                Button("Open") { model.open(shell.id) }
                                Button("Close Shell…") { model.requestClose(shell.id) }.disabled(shell.isStale)
                            }
                            .plainRow()
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    @ViewBuilder private var emptyQueue: some View {
        let text: String = if !model.search.isEmpty { "no match for \"\(model.search)\"" }
            else if cluster.isRefreshing && cluster.lastRefresh == nil { "connecting to herdr…" }
            else if cluster.onlineCount == 0 { "herdr is not reachable.\nopen settings (⌘,) for details." }
            else { "no agents running.\nstart one in herdr." }
        Text(text).font(Theme.mono(11)).foregroundStyle(Theme.faint)
            .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            let enabled = cluster.machines.filter(\.machine.isEnabled)
            ConnectionDot(state: cluster.onlineCount == enabled.count && !enabled.isEmpty ? .online
                          : cluster.onlineCount == 0 ? .unreachable : .loading)
            Text(enabled.count == 1 ? (cluster.onlineCount == 1 ? "local online" : "local offline")
                                    : "\(cluster.onlineCount)/\(enabled.count) online")
            Spacer(minLength: 4)
            if cluster.isRefreshing {
                Text("sync…").foregroundStyle(Theme.phosphor.opacity(0.7))
            } else {
                Text(refreshSeconds == 0 ? "paused" : "↻ \(refreshSeconds)s")
                    .help(cluster.lastRefresh.map { "Checked \($0.formatted(date: .omitted, time: .standard))" } ?? "")
            }
            SettingsLink { Text("⚙").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(Theme.dim)
                .help("Machines and preferences (⌘,)")
        }
        .font(Theme.mono(10))
        .foregroundStyle(Theme.dim)
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct SessionRowView: View {
    let row: AgentRow
    let isSelected: Bool
    let showsMachine: Bool
    let model: AppModel
    @ViewState<Bool> private var hovering = false

    var body: some View {
        let accent = row.agent.state == .blocked && !row.isStale ? Theme.amber : Theme.phosphor
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%02d", row.manualPriority))
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(isSelected ? accent : Theme.faint)
                .padding(.top, 1)
            StateGlyph(state: row.agent.state, stale: row.isStale)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.workspace).font(Theme.mono(12, .semibold)).lineLimit(1)
                        .foregroundStyle(isSelected ? Theme.text : Theme.text.opacity(0.85))
                    if showsMachine {
                        Text("@\(row.machineName)").font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
                Text(row.title).font(Theme.mono(10.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            Spacer(minLength: 0)
            if hovering || isSelected { reorderControls }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 7)
        .background(isSelected ? Theme.raised : hovering ? Theme.raised.opacity(0.5) : .clear)
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2).opacity(isSelected ? 1 : row.agent.state == .blocked && !row.isStale ? 0.6 : 0)
                .shadow(color: accent, radius: isSelected ? 4 : 0)
        }
        .opacity(row.isStale ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.open(row.id) }
        .onHover { hovering = $0 }
        .help("\(row.agent.kind) · \(row.project)")
        .contextMenu {
            Button("Open") { model.open(row.id) }
            Divider()
            Button("Move to Top") { model.move(row.id, .first) }.disabled(!model.canMove(row.id, .first))
            Button("Raise Priority") { model.move(row.id, .up) }.disabled(!model.canMove(row.id, .up))
            Button("Lower Priority") { model.move(row.id, .down) }.disabled(!model.canMove(row.id, .down))
            Button("Move to Bottom") { model.move(row.id, .last) }.disabled(!model.canMove(row.id, .last))
            Divider()
            Button("Close Session…") { model.requestClose(row.id) }.disabled(row.isStale)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority \(row.manualPriority), \(row.workspace), \(row.title), \(row.agent.state.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var reorderControls: some View {
        VStack(spacing: 0) {
            arrow("▲", .up, help: "Raise priority (⌥⌘↑)")
            arrow("▼", .down, help: "Lower priority (⌥⌘↓)")
        }
    }

    private func arrow(_ glyph: String, _ direction: SessionOrderStore.Move, help: String) -> some View {
        Button { model.move(row.id, direction) } label: {
            Text(glyph).font(.system(size: 7)).frame(width: 18, height: 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canMove(row.id, direction) ? Theme.phosphor : Theme.faint.opacity(0.5))
        .disabled(!model.canMove(row.id, direction))
        .help(help)
    }
}

private struct ShellRowView: View {
    let shell: ShellRow
    let isSelected: Bool
    let showsMachine: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("$").font(Theme.mono(11, .bold)).foregroundStyle(isSelected ? Theme.phosphor : Theme.faint)
                .frame(width: 30, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(shell.pane.workspaceName).font(Theme.mono(11.5, .medium)).foregroundStyle(Theme.text.opacity(0.8)).lineLimit(1)
                Text(showsMachine ? "shell @\(shell.machine.name)" : "shell")
                    .font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 5)
        .background(isSelected ? Theme.raised : .clear)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.phosphor).frame(width: 2).opacity(isSelected ? 1 : 0) }
        .opacity(shell.isStale ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private extension View {
    func plainRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
}
