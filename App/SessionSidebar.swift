import SwiftUI
import ShepherdrCore

/// The priority queue: every agent session in the user's order, with reordering controls.
struct SessionSidebar: View {
    @Bindable var model: AppModel
    @AppStorage("refreshSeconds") private var refreshSeconds = 5
    @ViewState<Bool> private var showShells = true
    /// Where a drag in progress would land, drawn as a line or a highlighted group.
    @ViewState<QueueDrop?> private var dropHint: QueueDrop?
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
        .alert(groupPromptTitle, isPresented: Binding { model.groupPrompt != nil } set: { if !$0 { model.groupPrompt = nil } }) {
            TextField("Group name", text: Binding { model.groupPrompt?.name ?? "" } set: { model.groupPrompt?.name = $0 })
            Button(isRenaming ? "Rename" : "Create") { model.commitGroupPrompt() }
            Button("Cancel", role: .cancel) { model.groupPrompt = nil }
        } message: {
            Text("Group sessions however you like: a project, a client, personal work… Groups move like a session, and their sessions keep their own order.")
        }
    }

    private var isRenaming: Bool {
        if case .rename = model.groupPrompt?.kind { true } else { false }
    }

    private var groupPromptTitle: String { isRenaming ? "Rename Group" : "New Group" }

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
            Button { model.startNewSession() } label: { Text("+").font(Theme.mono(14, .bold)) }
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
        let filtering = !model.search.isEmpty
        return ScrollView {
            // A plain stack: the queue is short, and a lazy stack whose rows measure themselves
            // could loop on layout and freeze the window.
            VStack(alignment: .leading, spacing: 0) {
                queueHeader
                ForEach(model.queue) { item in
                    switch item {
                    case .session(let row):
                        sessionRow(row, in: nil)
                    case .group(let group):
                        let expanded = !group.group.isCollapsed || filtering
                        GroupHeaderView(group: group, isExpanded: expanded,
                                        containsSelection: model.selectedID.map(group.group.members.contains) == true,
                                        model: model, hint: $dropHint)
                        if expanded {
                            let members = model.members(of: group)
                            ForEach(members) { member in
                                switch member {
                                case .session(let row): sessionRow(row, in: group)
                                case .shell(let shell): shellRow(shell, grouped: true)
                                }
                            }
                            if members.isEmpty {
                                EmptyGroupView(group: group.group, model: model, hint: $dropHint)
                            }
                        }
                    }
                }
                if model.queue.isEmpty { emptyQueue }
                QueueEndView(model: model, hint: $dropHint)
                shellsSection
            }
        }
    }

    private var queueHeader: some View {
        HStack(spacing: 10) {
            ConsoleHeader(title: "Queue", trailing: model.search.isEmpty ? "\(model.matchingRows.count)"
                                                                          : "\(model.matchingRows.count) match")
            Button { model.promptNewGroup() } label: { Text("+ group").font(Theme.mono(9.5, .semibold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.phosphor.opacity(0.8))
                .help("New group. Drag sessions into it, or use a session's context menu.")
        }
        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
    }

    private func sessionRow(_ row: AgentRow, in group: QueueGroupRow?) -> some View {
        SessionRowView(row: row, group: group?.group,
                       isFirst: group?.rows.first?.id == row.id, isLast: group?.rows.last?.id == row.id,
                       isSelected: model.selectedID == row.id, showsMachine: model.showsMachineNames,
                       model: model, hint: $dropHint)
    }

    @ViewBuilder private var shellsSection: some View {
        let shells = model.ungroupedShells
        if !shells.isEmpty {
            Button { showShells.toggle() } label: {
                ConsoleHeader(title: "\(showShells ? "▾" : "▸") Shells", trailing: "\(shells.count)")
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
            .help("Panes without a detected agent")
            if showShells {
                ForEach(shells, id: \.listID) { shell in shellRow(shell, grouped: false) }
            }
        }
    }

    private func shellRow(_ shell: ShellRow, grouped: Bool) -> some View {
        ShellRowView(shell: shell, isGrouped: grouped, isSelected: model.selectedID == shell.id,
                     showsMachine: model.showsMachineNames) { model.open(shell.id) }
            .contextMenu {
                Button("Open") { model.open(shell.id) }
                Button("New Session in Same Folder…") { model.startNewSession(besides: shell.id) }
                    .disabled(!model.canStartNewSession(besides: shell.id))
                if grouped {
                    Divider()
                    Button("Remove from Group") { model.moveToGroup(shell.id, nil) }
                }
                Divider()
                Button("Close Shell…") { model.requestClose(shell.id) }.disabled(shell.isStale)
            }
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
    /// The group holding this session, if any; grouped rows are indented under its header.
    let group: SessionGroup?
    let isFirst: Bool
    let isLast: Bool
    let isSelected: Bool
    let showsMachine: Bool
    let model: AppModel
    @Binding var hint: QueueDrop?
    @ViewState<Bool> private var hovering = false
    @ViewState private var height = RowHeight(44)

    private var item: QueueItemID { .session(row.id) }

    var body: some View {
        let accent = row.agent.state == .blocked && !row.isStale ? Theme.amber : Theme.phosphor
        HStack(alignment: .top, spacing: 8) {
            Text(String(format: "%02d", row.manualPriority))
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(isSelected ? accent : Theme.faint)
                .padding(.top, 1)
            if let wait = model.waitState(for: row.id) {
                // On hold: an hourglass replaces the agent's state until the session resumes.
                Image(systemName: wait == .ready ? "hourglass.bottomhalf.filled" : "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(wait == .ready ? Theme.phosphor : Theme.cyan)
                    .frame(width: 14)
                    .help(wait == .ready ? "On hold; the sessions it waits for have finished"
                                         : "On hold, waiting for other sessions")
            } else {
                StateGlyph(state: row.agent.state, stale: row.isStale)
            }
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
            if hovering || isSelected { ReorderArrows(item: item, model: model, shortcuts: true) }
        }
        .padding(.leading, group == nil ? 12 : 26).padding(.trailing, 8).padding(.vertical, 7)
        .background(isSelected ? Theme.raised : hovering ? Theme.raised.opacity(0.5) : .clear)
        .overlay(alignment: .leading) {
            if group != nil { Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 18) }
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(accent).frame(width: 2).opacity(isSelected ? 1 : row.agent.state == .blocked && !row.isStale ? 0.6 : 0)
                .shadow(color: accent, radius: isSelected ? 4 : 0)
        }
        .dropLine(.top, hint == .before(item))
        .dropLine(.bottom, hint == .after(item) || (isLast && group.map { hint == .after(.group($0.id)) } == true))
        .opacity(row.isStale ? 0.6 : 1)
        .measuringHeight(height)
        .contentShape(Rectangle())
        .onTapGesture { model.open(row.id) }
        .onHover { hovering = $0 }
        .help("\(row.agent.kind) · \(row.project)")
        .queueDraggable(item, model: model)
        .onDrop(of: [.plainText], delegate: QueueDropDelegate(model: model, hint: $hint) { dragged, y in
            let upper = y < height.value / 2
            switch dragged {
            case .session(let id):
                guard id != row.id else { return nil }
                return upper ? .before(item) : .after(item)
            case .group(let draggedGroup):
                // Groups never nest: over a grouped session, a group lands next to that group.
                guard let group else { return upper ? .before(item) : .after(item) }
                guard group.id != draggedGroup else { return nil }
                return upper && isFirst ? .before(.group(group.id)) : .after(.group(group.id))
            }
        })
        .contextMenu {
            Button("Open") { model.open(row.id) }
            Button("New Session in Same Folder…") { model.startNewSession(besides: row.id) }
                .disabled(!model.canStartNewSession(besides: row.id))
            Divider()
            PriorityMenu(item: item, model: model)
            Divider()
            Menu("Move to Group") {
                let others = model.groups.filter { $0.id != row.groupID }
                ForEach(others) { other in
                    Button(other.name) { model.moveToGroup(row.id, other.id) }
                }
                if !others.isEmpty { Divider() }
                Button("New Group…") { model.promptNewGroup(with: row.id) }
            }
            if row.groupID != nil {
                Button("Remove from Group") { model.moveToGroup(row.id, nil) }
            }
            Divider()
            Menu("Wait For") {
                ForEach(model.rankedRows.filter { $0.id != row.id }) { other in
                    Toggle(showsMachine ? "\(other.workspace) @\(other.machineName)" : other.workspace,
                           isOn: Binding { model.relations.isWaiting(row.id, for: other.id) }
                                     set: { model.relations.setWaiting(row.id, for: other.id, $0) })
                }
            }
            if !model.relations.waitingFor(row.id).isEmpty {
                Button("Resume (Stop Waiting)") { model.relations.stopWaiting(row.id) }
            }
            Divider()
            Button("Close Session…") { model.requestClose(row.id) }.disabled(row.isStale)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Priority \(row.manualPriority), \(row.workspace), \(row.title), \(row.agent.state.title)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A group's header: click to collapse or expand, drag to reorder, drop sessions on it to add them.
private struct GroupHeaderView: View {
    /// Fixed, so the controls shown on hover never change the row's height.
    private static let contentHeight: CGFloat = 26

    let group: QueueGroupRow
    let isExpanded: Bool
    let containsSelection: Bool
    let model: AppModel
    @Binding var hint: QueueDrop?
    @ViewState<Bool> private var hovering = false
    @ViewState private var height = RowHeight(32)

    private var item: QueueItemID { .group(group.id) }

    var body: some View {
        let live = group.rows.filter { !$0.isStale }
        let blocked = live.filter { $0.agent.state == .blocked }.count
        let working = live.filter { $0.agent.state == .working }.count
        let receiving = hint == .into(group: group.id)
        let count = group.rows.count + model.shells(in: group.group).count
        HStack(spacing: 7) {
            Text(isExpanded ? "▾" : "▸").font(Theme.mono(11, .bold))
                .foregroundStyle(Theme.phosphor.opacity(0.8)).frame(width: 14)
            Text(group.group.name.uppercased()).font(Theme.mono(10.5, .bold)).tracking(1.2).lineLimit(1)
                .foregroundStyle(containsSelection && !isExpanded ? Theme.phosphor : Theme.text.opacity(0.85))
            Text("\(count)").font(Theme.mono(10)).foregroundStyle(Theme.faint)
            Spacer(minLength: 4)
            if blocked > 0 {
                Text("\(blocked) need you").font(Theme.mono(9.5, .semibold)).foregroundStyle(Theme.amber).lineLimit(1)
            } else if working > 0 {
                Text("\(working) working").font(Theme.mono(9.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            if hovering {
                Button { model.startNewSession(in: group.group) } label: {
                    Text("+").font(Theme.mono(13, .bold)).frame(width: 18, height: Self.contentHeight).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.onlineMachines.isEmpty ? Theme.faint.opacity(0.5) : Theme.phosphor)
                .disabled(model.onlineMachines.isEmpty)
                .help("New session in \(group.group.name)")
                ReorderArrows(item: item, model: model, shortcuts: false)
            }
        }
        .frame(height: Self.contentHeight)
        .padding(.leading, 12).padding(.trailing, 8).padding(.top, 5).padding(.bottom, 1)
        .background(receiving ? Theme.phosphor.opacity(0.12) : hovering ? Theme.raised.opacity(0.5) : .clear)
        .overlay { if receiving { Rectangle().strokeBorder(Theme.phosphor.opacity(0.6), lineWidth: 1) } }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.amber).frame(width: 2).opacity(blocked > 0 ? 0.6 : 0) }
        .dropLine(.top, hint == .before(item))
        .dropLine(.bottom, hint == .after(item) && !isExpanded)
        .measuringHeight(height)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.18)) { model.toggleCollapsed(group.group) } }
        .onHover { hovering = $0 }
        .help("\(isExpanded ? "Collapse" : "Expand") \(group.group.name). Drag to reorder; drop sessions here to add them.")
        .queueDraggable(item, model: model)
        .onDrop(of: [.plainText], delegate: QueueDropDelegate(model: model, hint: $hint) { dragged, y in
            if dragged == item { return nil }
            if y < height.value * 0.4 { return .before(item) }
            if case .session = dragged { return .into(group: group.id) }
            return .after(item)
        })
        .contextMenu {
            Button("New Session in Group…") { model.startNewSession(in: group.group) }
                .disabled(model.onlineMachines.isEmpty)
            Divider()
            Button("Rename…") { model.promptRename(group.group) }
            Button(group.group.isCollapsed ? "Expand" : "Collapse") { model.toggleCollapsed(group.group) }
            Divider()
            PriorityMenu(item: item, model: model)
            Divider()
            Button("Ungroup") { model.ungroup(group.group) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group \(group.group.name), \(count) sessions\(blocked > 0 ? ", \(blocked) need you" : "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Stands in for an expanded group's sessions until the first one is dropped in.
private struct EmptyGroupView: View {
    let group: SessionGroup
    let model: AppModel
    @Binding var hint: QueueDrop?

    var body: some View {
        Text("drop sessions here").font(Theme.mono(10)).foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 30).padding(.vertical, 8)
            .background(hint == .into(group: group.id) ? Theme.phosphor.opacity(0.12) : .clear)
            .dropLine(.bottom, hint == .after(.group(group.id)))
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], delegate: QueueDropDelegate(model: model, hint: $hint) { dragged, _ in
                if case .session = dragged { return .into(group: group.id) }
                return dragged == .group(group.id) ? nil : .after(.group(group.id))
            })
    }
}

/// The space after the last row: dropping here moves a session or group to the end of the queue.
private struct QueueEndView: View {
    let model: AppModel
    @Binding var hint: QueueDrop?

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 28)
            .dropLine(.top, hint == .end)
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], delegate: QueueDropDelegate(model: model, hint: $hint) { _, _ in .end })
    }
}

private struct ReorderArrows: View {
    let item: QueueItemID
    let model: AppModel
    /// Whether to mention ⌥⌘↑/↓, which act on the selected session.
    let shortcuts: Bool

    var body: some View {
        VStack(spacing: 0) {
            arrow("▲", .up, help: shortcuts ? "Raise priority (⌥⌘↑)" : "Raise priority")
            arrow("▼", .down, help: shortcuts ? "Lower priority (⌥⌘↓)" : "Lower priority")
        }
    }

    private func arrow(_ glyph: String, _ direction: SessionOrderStore.Move, help: String) -> some View {
        Button { withAnimation(.snappy(duration: 0.18)) { model.move(item, direction) } } label: {
            Text(glyph).font(.system(size: 7)).frame(width: 18, height: 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(model.canMove(item, direction) ? Theme.phosphor : Theme.faint.opacity(0.5))
        .disabled(!model.canMove(item, direction))
        .help(help)
    }
}

/// Priority commands shared by session and group context menus.
private struct PriorityMenu: View {
    let item: QueueItemID
    let model: AppModel

    var body: some View {
        Button("Move to Top") { model.move(item, .first) }.disabled(!model.canMove(item, .first))
        Button("Raise Priority") { model.move(item, .up) }.disabled(!model.canMove(item, .up))
        Button("Lower Priority") { model.move(item, .down) }.disabled(!model.canMove(item, .down))
        Button("Move to Bottom") { model.move(item, .last) }.disabled(!model.canMove(item, .last))
    }
}

/// Drop handling for one queue row: where the pointer sits within the row picks the landing spot.
private struct QueueDropDelegate: DropDelegate {
    let model: AppModel
    @Binding var hint: QueueDrop?
    /// The landing spot for the dragged item at a height within the row, or nil to refuse it.
    let resolve: (QueueItemID, CGFloat) -> QueueDrop?

    func validateDrop(info: DropInfo) -> Bool { model.dragging != nil }

    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: hint == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        // Rows overlap at their edges: only clear the hint this row set.
        if let item = model.dragging, hint == resolve(item, info.location.y) { hint = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { hint = nil }
        guard let item = model.dragging, let drop = resolve(item, info.location.y),
              let provider = info.itemProviders(for: [.plainText]).first else {
            model.dragging = nil
            return false
        }
        let model = model
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            let token = (text as? NSString).map(String.init)
            Task { @MainActor in
                // Only the queue drag that set `dragging` carries its token. Any other text
                // dropped here finds it left over from a drag that ended outside the queue.
                let isQueueDrag = token == model.dragToken && model.dragging == item
                model.dragging = nil
                if isQueueDrag { withAnimation(.snappy(duration: 0.2)) { model.place(item, drop) } }
            }
        }
        return true
    }

    private func update(_ info: DropInfo) {
        guard let item = model.dragging else { return }
        hint = resolve(item, info.location.y)
    }
}

private struct ShellRowView: View {
    let shell: ShellRow
    /// Grouped shells are indented under their group's header, like its sessions.
    let isGrouped: Bool
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
        .padding(.leading, isGrouped ? 26 : 12).padding(.trailing, 8).padding(.vertical, 5)
        .background(isSelected ? Theme.raised : .clear)
        .overlay(alignment: .leading) {
            if isGrouped { Rectangle().fill(Theme.line).frame(width: 1).padding(.leading, 18) }
        }
        .overlay(alignment: .leading) { Rectangle().fill(Theme.phosphor).frame(width: 2).opacity(isSelected ? 1 : 0) }
        .opacity(shell.isStale ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Lazy stacks need identities unique across the whole list. A shell and the agent Herdr later
/// detects in it share an `Agent.ID`, and reusing it let the agent's row keep drawing the shell.
private struct ShellListID: Hashable {
    let id: Agent.ID
}

private extension ShellRow {
    var listID: ShellListID { ShellListID(id: id) }
}

private extension View {
    /// Starts an in-app drag of a queue item. The model carries what moves; the pasteboard
    /// carries a token for this drag, so drops can tell it from any other text.
    func queueDraggable(_ item: QueueItemID, model: AppModel) -> some View {
        onDrag {
            let token = "shepherdr-queue-item:\(UUID().uuidString)"
            model.dragging = item
            model.dragToken = token
            return NSItemProvider(object: token as NSString)
        }
    }

    /// The phosphor line that marks where a dragged item will land.
    func dropLine(_ edge: VerticalEdge, _ shown: Bool) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            if shown {
                Rectangle().fill(Theme.phosphor).frame(height: 2).shadow(color: Theme.phosphor, radius: 3)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Keeps `height` equal to the view's height, so drop targets can split rows into halves.
    func measuringHeight(_ height: RowHeight) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { height.value = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, new in height.value = new }
            }
        }
    }
}

/// A row's measured height, read only when something is dropped on it. A plain reference rather
/// than view state, so measuring never invalidates the view and can never feed a layout loop.
@MainActor final class RowHeight {
    var value: CGFloat
    init(_ value: CGFloat) { self.value = value }
}
