import SwiftUI
import ShepherdrCore
import ShepherdrTerminalUI

/// One session in the work area: its live terminal and a composer for the next prompt.
/// The view is identified by its terminal target, so refreshes never reconnect it.
struct SessionView: View {
    let context: SessionContext
    @Bindable var model: AppModel
    @ViewState<TerminalStore> private var terminal: TerminalStore
    @ViewState<Bool> private var showDetails = false
    @ViewState<CGFloat> private var editorHeight: CGFloat = 28
    @AppStorage("terminalFontSize") private var fontSize = 13.0
    @AppStorage("terminalFontFamily") private var fontFamily = ConsoleFonts.defaultFamily

    init(context: SessionContext, model: AppModel, mode: TerminalMode) {
        self.context = context
        self.model = model
        _terminal = ViewState(initialValue: TerminalStore(target: context.target, mode: mode))
    }

    private var id: Agent.ID { .init(machineID: context.machine.id, terminalID: context.target.terminalID) }
    private var isLive: Bool { terminal.status == .interactive }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            if let notice = model.sessionNotices[id] {
                banner(notice, dismiss: { model.sessionNotices[id] = nil })
            }
            if let message = terminal.message {
                banner(message)
            } else if terminal.isControlledElsewhere {
                banner("Another client is typing in this terminal. Watching only — Take Over to send prompts from here.")
            }
            if context.canConnect {
                TerminalSurface(store: terminal, palette: Theme.terminal,
                                font: ConsoleFonts.font(family: fontFamily, size: fontSize))
                    .padding(.leading, 10).padding(.top, 6)
                    .background(Theme.background)
                    .overlay { if terminal.status == .connecting { connecting } }
            } else {
                offline
            }
            composer
        }
        .background(Theme.background)
        .onAppear { model.activeTerminal = terminal }
        .onDisappear { if model.activeTerminal === terminal { model.activeTerminal = nil } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            terminal.disconnect()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let agent = context.agent {
                StateGlyph(state: agent.agent.state, stale: agent.isStale)
            } else {
                Text("$").font(Theme.mono(13, .bold)).foregroundStyle(Theme.phosphor)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(context.target.workspace).font(Theme.mono(14, .bold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text("›").font(Theme.mono(13)).foregroundStyle(Theme.faint)
                    Text(context.title).font(Theme.mono(13)).foregroundStyle(Theme.text.opacity(0.75)).lineLimit(1)
                }
                Text(locationLine).font(Theme.mono(10)).foregroundStyle(Theme.faint).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if let agent = context.agent { StateTag(state: agent.agent.state, stale: agent.isStale) }
            modeSwitch
            Button { terminal.open() } label: { Text("↻") }
                .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                .disabled(terminal.status == .connecting || !context.canConnect)
                .help("Reconnect to this terminal")
            Button { model.requestClose(id) } label: { Text("✕") }
                .buttonStyle(ConsoleButtonStyle(tint: Theme.red))
                .disabled(context.isStale)
                .help("Close this session in Herdr… (⇧⌘W)")
            Button { showDetails.toggle() } label: { Text("i") }
                .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                .help("Session details")
                .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                    SessionDetails(context: context).frame(width: 320)
                }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
        .background(Theme.panel)
    }

    private var locationLine: String {
        let machine = context.machine.machine
        let place = machine.isLocal ? "local" : "\(machine.name) (\(machine.target ?? "ssh"))"
        let directory = context.agent?.project ?? ""
        return [place, "session \(machine.session)", directory].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// LIVE sends keyboard, paste and prompts to the session; WATCH is read-only.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            segment("LIVE", active: terminal.mode != .observe, tint: Theme.phosphor) {
                if terminal.mode == .observe { terminal.open(mode: .control) }
            }
            segment("WATCH", active: terminal.mode == .observe, tint: Theme.dim) {
                if terminal.mode != .observe { terminal.open(mode: .observe) }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
        .disabled(terminal.status == .connecting || !context.canConnect)
        .help("LIVE: type and send prompts. WATCH: observe without input (⌘E)")
    }

    private func segment(_ title: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if active && title == "LIVE" && isLive {
                    Circle().fill(Theme.phosphor).frame(width: 5, height: 5).shadow(color: Theme.phosphor, radius: 3)
                }
                Text(title)
            }
            .font(Theme.mono(10, .bold)).tracking(1)
            .foregroundStyle(active ? (title == "LIVE" ? Theme.background : Theme.text) : Theme.faint)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(active ? tint.opacity(title == "LIVE" ? 1 : 0.25) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Banners and states

    private func banner(_ message: String, dismiss: (() -> Void)? = nil) -> some View {
        let failed = terminal.status == .failed
        return HStack(alignment: .top, spacing: 10) {
            Text(failed ? "✗" : "!").font(Theme.mono(12, .bold))
            VStack(alignment: .leading, spacing: 3) {
                Text(message).font(Theme.mono(11.5)).textSelection(.enabled)
                if let detail = terminal.detail {
                    Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(4).textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if let dismiss {
                Button("OK", action: dismiss).buttonStyle(ConsoleButtonStyle(tint: Theme.amber))
            } else if terminal.status == .failed || terminal.status == .ended {
                Button("RECONNECT") { terminal.open() }.buttonStyle(ConsoleButtonStyle(tint: Theme.amber))
            }
        }
        .foregroundStyle(failed ? Theme.red : Theme.amber)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background((failed ? Theme.red : Theme.amber).opacity(0.08))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var connecting: some View {
        Text("connecting to \(context.target.workspace)…")
            .font(Theme.mono(12)).foregroundStyle(Theme.phosphor)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 4))
    }

    private var offline: some View {
        VStack(spacing: 10) {
            Text("[ \(context.machine.connection.title.uppercased()) ]").font(Theme.mono(13, .bold)).foregroundStyle(Theme.amber)
            Text(context.machine.failure?.message ?? "This machine is not reachable right now.")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
            if context.isStale { Text("showing last known state").font(Theme.mono(10)).foregroundStyle(Theme.faint) }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Composer

    private var draft: Binding<String> {
        Binding { model.drafts[id] ?? "" } set: { model.drafts[id] = $0 }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Text("›").font(Theme.mono(15, .bold))
                    .foregroundStyle(isLive ? Theme.phosphor : Theme.faint)
                    .shadow(color: isLive ? Theme.phosphor.opacity(0.7) : .clear, radius: 4)
                    .padding(.top, 3)
                ZStack(alignment: .topLeading) {
                    if draft.wrappedValue.isEmpty {
                        Text(placeholder).font(Font(ConsoleFonts.font(family: fontFamily, size: 13))).foregroundStyle(Theme.faint)
                            .padding(.top, 5).allowsHitTesting(false)
                    }
                    PromptEditor(text: draft, height: $editorHeight, isEnabled: isLive,
                                 font: ConsoleFonts.font(family: fontFamily, size: 13),
                                 focusRequest: model.promptFocusRequest, history: model.prompts(for: id),
                                 onSubmit: submit)
                        .frame(height: editorHeight)
                }
                if isLive {
                    Button(action: submit) { Text("SEND ⏎") }
                        .buttonStyle(ConsoleButtonStyle(prominent: true))
                        .disabled(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else if terminal.isControlledElsewhere {
                    Button("TAKE OVER") { terminal.takeOver() }
                        .buttonStyle(ConsoleButtonStyle(tint: Theme.amber))
                        .disabled(terminal.status == .connecting)
                        .help("Detach the other client's input and control this terminal from Shepherdr")
                } else if terminal.mode == .observe, context.canConnect {
                    Button("GO LIVE") { terminal.open(mode: .control) }.buttonStyle(ConsoleButtonStyle())
                        .disabled(terminal.status == .connecting)
                }
            }
            HStack(spacing: 6) {
                key("esc", .escape, help: "Escape — interrupts most agents (⌘⎋)")
                key("^C", .interrupt, help: "Control-C")
                key("tab", .tab, help: "Tab")
                key("↑", .up, help: "Up arrow")
                key("↓", .down, help: "Down arrow")
                key("⏎", .enter, help: "Return")
                Spacer(minLength: 8)
                Text(isLive ? "⏎ send · ⇧⏎ newline · ↑ history · ⌘L focus" : "read-only · ⌘E to go live")
                    .font(Theme.mono(9.5)).foregroundStyle(Theme.faint).lineLimit(1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 10)
        .background(Theme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(isLive ? Theme.phosphor.opacity(0.35) : Theme.line).frame(height: 1)
        }
    }

    private var placeholder: String {
        switch terminal.status {
        case .interactive: "next prompt for \(context.target.workspace)…"
        case .connecting: "connecting…"
        default: terminal.isControlledElsewhere ? "another client has input — take over to type" : "watching — go live to type"
        }
    }

    private func key(_ label: String, _ key: TerminalKey, help: String) -> some View {
        Button { terminal.press(key) } label: { Text(label) }
            .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
            .disabled(!isLive)
            .help(help)
    }

    private func submit() {
        let text = draft.wrappedValue
        guard terminal.submit(prompt: text) else { return }
        model.remember(text, for: id)
        draft.wrappedValue = ""
    }
}

/// Herdr metadata for the selected session.
private struct SessionDetails: View {
    let context: SessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ConsoleHeader(title: "Session")
            if let row = context.agent {
                field("Agent", row.agent.kind)
                field("State", row.agent.state == .unknown ? "Unknown (\(row.agent.reportedState))" : row.agent.state.title)
                field("Tab", "\(row.agent.tabName) · \(row.agent.tabID)")
                field("Pane", row.agent.paneID)
                field("Directory", row.agent.directory ?? "Not reported")
                if row.agent.isLaunchPending { field("Launch", "Pending in Herdr") }
            } else {
                field("Pane", context.target.title)
            }
            field("Machine", context.machine.machine.isLocal ? "Local" : "\(context.machine.machine.name) · \(context.machine.machine.target ?? "")")
            field("Herdr session", context.machine.machine.session)
            field("Terminal ID", context.target.terminalID)
            if let date = context.machine.lastSuccess {
                field("Last received", date.formatted(date: .abbreviated, time: .standard))
            }
            Text("Leaving a session detaches this client only. The pane keeps running in Herdr.")
                .font(Theme.mono(9.5)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .textSelection(.enabled)
        .background(Theme.panel)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(Theme.mono(9, .semibold)).tracking(1).foregroundStyle(Theme.faint)
            Text(value).font(Theme.mono(11.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
