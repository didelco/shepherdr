import SwiftUI
import ShepherdrCore
import ShepherdrTerminalUI

// Use the public State property wrapper explicitly. This also supports SDKs that
// export a same-named macro unavailable to standalone command-line toolchains.
typealias ViewState<Value> = SwiftUI.State<Value>

@main
struct ShepherdrApp: App {
    @ViewState<AppModel> private var model = AppModel()

    init() {
        ConsoleFonts.registerBundled()
        // One window, never merged into tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        Window("Shepherdr", id: "main") {
            MainView(model: model)
                .frame(minWidth: 820, minHeight: 520)
        }
        .defaultSize(width: 1_280, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session…") { model.startNewSession() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(model.onlineMachines.isEmpty)
                Button("New Session in Same Folder…") {
                    if let id = model.selectedID { model.startNewSession(besides: id) }
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(!(model.selectedID.map(model.canStartNewSession(besides:)) ?? false))
                Divider()
                Button("Refresh Sessions") { Task { await model.refreshNow() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.cluster.isRefreshing)
            }
            CommandGroup(after: .sidebar) {
                Toggle("Gather Sessions by Project", isOn: Binding { model.order.gathersProjects }
                                                               set: { model.order.gathersProjects = $0 })
            }
            CommandMenu("Compass") {
                Button("Agents") { model.mode = .agents }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Compass") { model.mode = .compass }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Divider()
                Button("Run Compass Now") {
                    model.mode = .compass
                    model.compass.runNow()
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(!model.compass.isSetUp || model.compass.openRun != nil)
                Button("Show Today's Page") {
                    model.mode = .compass
                    model.compass.show(.today)
                }
                .disabled(!model.compass.hasTodaysPage)
                Button("Open Compass Folder") { NSWorkspace.shared.open(model.compass.folder.root) }
                    .disabled(!model.compass.isSetUp)
            }
            CommandMenu("Session") {
                Button("Overview") {
                    model.mode = .agents
                    model.selection = .overview
                }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Next Session") { model.step(1) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Previous Session") { model.step(-1) }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button("Prompt Editor") { model.togglePromptEditor() }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(model.activeTerminal == nil)
                Button("Browser") { model.toggleBrowser() }
                    .keyboardShortcut("b", modifiers: .command)
                Button(model.dictation.isRecording ? "Stop Dictation" : "Dictate Prompt") { model.toggleDictation() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                    .disabled(model.selectedID == nil && !model.dictation.isRecording)
                Button(model.activeTerminal?.mode == .observe ? "Unlock Session" : "Lock Session (Read-Only)") { model.toggleLive() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!model.canToggleLive)
                Button("Send Escape") { model.activeTerminal?.press(.escape) }
                    .keyboardShortcut(.escape, modifiers: .command)
                    .disabled(model.activeTerminal?.status != .interactive)
                Divider()
                ForEach(0..<9, id: \.self) { position in
                    Button(sessionTitle(position)) { model.open(position: position) }
                        .keyboardShortcut(KeyEquivalent(Character("\(position + 1)")), modifiers: .command)
                        .disabled(!model.visibleRows.indices.contains(position))
                }
                Divider()
                Button("Raise Priority") { model.moveSelection(.up) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(!model.canMove(model.selectedID, .up))
                Button("Lower Priority") { model.moveSelection(.down) }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(!model.canMove(model.selectedID, .down))
                Button("Move to Top") { model.moveSelection(.first) }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option, .shift])
                    .disabled(!model.canMove(model.selectedID, .first))
                Divider()
                Button("Wait For…") { if let id = model.selectedID { model.pickWaits(for: id) } }
                    .disabled(model.selectedID.flatMap(model.row(for:)) == nil || model.rankedRows.count < 2)
                Button("New Group…") { model.promptNewGroup(with: model.selectedID) }
            }
            CommandGroup(replacing: .help) {
                Button("Shepherdr Guide") { if let guide = AppModel.guide { model.openHelp(guide) } }
                    .keyboardShortcut("?", modifiers: .command)
                Button("Herdr Documentation") { model.openHelp(AppModel.herdrDocumentation) }
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }

    private func sessionTitle(_ position: Int) -> String {
        guard model.visibleRows.indices.contains(position) else { return "Session \(position + 1)" }
        let row = model.visibleRows[position]
        return "\(row.workspace) — \(row.title)"
    }
}
