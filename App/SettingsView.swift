import AppKit
import SwiftUI
import ShepherdrCore
import ShepherdrTerminalUI

/// Machines change rarely, so they live here rather than in the main window.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "slider.horizontal.3") }
            MachineSettings(model: model)
                .tabItem { Label("Machines", systemImage: "server.rack") }
        }
        .frame(width: 580, height: 480)
        .preferredColorScheme(.dark)
        .tint(Theme.phosphor)
    }
}

private struct GeneralSettings: View {
    @AppStorage("refreshSeconds") private var refreshSeconds = 5
    @AppStorage("openMode") private var openMode = TerminalMode.control.rawValue
    @AppStorage("terminalFontSize") private var fontSize = 13.0
    @AppStorage("terminalFontFamily") private var fontFamily = ConsoleFonts.defaultFamily
    @AppStorage(ConsoleFonts.ligaturesKey) private var ligatures = false
    @AppStorage(ProjectsFolder.key) private var projectsFolder = ProjectsFolder.defaultPath
    @AppStorage(SessionNotifier.enabledKey) private var notifies = true
    @ViewState<[String]> private var families: [String] = [ConsoleFonts.defaultFamily]

    var body: some View {
        Form {
            Section("Sessions") {
                Picker("Open sessions", selection: $openMode) {
                    Text("Unlocked — type and send prompts").tag(TerminalMode.control.rawValue)
                    Text("Locked — read-only").tag(TerminalMode.observe.rawValue)
                }
                Text("Live never takes input from another client. When one is attached, Shepherdr watches and offers Take Over.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Refresh sessions", selection: $refreshSeconds) {
                    Text("Every 5 seconds").tag(5)
                    Text("Every 15 seconds").tag(15)
                    Text("Every 30 seconds").tag(30)
                    Text("Every minute").tag(60)
                    Text("Paused").tag(0)
                }
                LabeledContent("Projects folder") {
                    HStack(spacing: 8) {
                        Text(projectsFolder).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Choose…") { chooseProjectsFolder() }
                    }
                }
                Text("New Session's folder picker starts here, and a folder name alone means a folder inside it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Notifications") {
                Toggle("Notify when an agent finishes or needs you", isOn: $notifies)
                Text("Shows the session, its state and what the agent last said. Click one to open the session. The session you are looking at never notifies.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Terminal font") {
                Picker("Font", selection: $fontFamily) {
                    ForEach(families, id: \.self) { family in
                        Text(family == ConsoleFonts.defaultFamily ? "\(family) (default)" : family).tag(family)
                    }
                }
                Stepper(value: $fontSize, in: 10...22, step: 1) {
                    Text("Size: \(Int(fontSize)) pt")
                }
                Toggle("Ligatures", isOn: $ligatures)
                    .help("Join characters such as -> and != into single symbols, in fonts that have them")
                Text("❯ claude --resume  # -> != === 0x1F")
                    .font(Font(ConsoleFonts.font(family: fontFamily, size: fontSize, ligatures: ligatures)))
                    .foregroundStyle(Theme.phosphor)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
                Text("Used by the terminal and the prompt composer. Only monospaced fonts are listed. Ligatures make busy terminals redraw more slowly.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            families = ConsoleFonts.monospacedFamilies()
            if !families.contains(fontFamily) { fontFamily = ConsoleFonts.defaultFamily }
        }
    }

    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = ProjectsFolder.url(projectsFolder)
        if panel.runModal() == .OK, let url = panel.url {
            projectsFolder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }
}

private struct MachineSettings: View {
    @Bindable var model: AppModel
    @ViewState<Bool> private var addingMachine = false
    @ViewState<MachineState?> private var removing: MachineState? = nil
    @ViewState<HerdrFailure?> private var failure: HerdrFailure? = nil
    @ViewState<String?> private var busyMachine: String? = nil

    private var cluster: ClusterStore { model.cluster }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let failure = cluster.discoveryFailure, failure.state != .notInstalled {
                NoticeView(title: "Saved machines could not be refreshed", message: failure.message, detail: failure.detail)
                    .padding([.horizontal, .top], 16)
            }
            if let failure {
                NoticeView(title: failure.message, message: failure.detail ?? "", detail: nil)
                    .padding([.horizontal, .top], 16)
            }
            List(cluster.machines) { state in
                MachineRow(state: state, isBusy: busyMachine == state.id) {
                    change(state) { try await cluster.setMachine(state.id, enabled: !state.machine.isEnabled) }
                } remove: {
                    removing = state
                }
            }
            .listStyle(.inset)
            HStack(alignment: .center, spacing: 12) {
                Button {
                    addingMachine = true
                } label: {
                    Label("Add Machine…", systemImage: "plus")
                }
                Text("Saved in Herdr's machine catalog. Disable to stop polling without forgetting it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await cluster.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
                .disabled(cluster.isRefreshing)
            }
            .padding(16)
        }
        .sheet(isPresented: $addingMachine) { AddMachineSheet(model: model, isPresented: $addingMachine) }
        .confirmationDialog("Remove \(removing?.machine.name ?? "machine")?",
                            isPresented: Binding { removing != nil } set: { if !$0 { removing = nil } },
                            titleVisibility: .visible, presenting: removing) { state in
            Button("Remove Machine", role: .destructive) {
                change(state) { try await cluster.removeMachine(state.id) }
            }
        } message: { _ in
            Text("Herdr forgets this saved SSH profile. Its remote server and sessions keep running; add it again to return.")
        }
    }

    private func change(_ state: MachineState, _ action: @escaping () async throws -> Void) {
        busyMachine = state.id
        failure = nil
        Task {
            failure = await model.perform(action)
            busyMachine = nil
        }
    }
}

private struct MachineRow: View {
    let state: MachineState
    let isBusy: Bool
    let toggle: () -> Void
    let remove: () -> Void
    @ViewState<Bool> private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: state.machine.isLocal ? "laptopcomputer" : "server.rack").frame(width: 18)
                        .foregroundStyle(.secondary)
                    Text(state.machine.name).fontWeight(.medium)
                    ConnectionDot(state: state.connection)
                    Text(state.connection.title).foregroundStyle(.secondary).font(.callout)
                }
                HStack(spacing: 6) {
                    Text(state.machine.target ?? "This Mac")
                    Text("· session \(state.machine.session)")
                    if let snapshot = state.snapshot {
                        Text("· Herdr \(snapshot.version) · \(snapshot.workspaces.count) workspaces · \(snapshot.agents.count) agents")
                    }
                }
                .font(.caption).foregroundStyle(.secondary).padding(.leading, 26)
                if let failure = state.failure {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(failure.message)
                        if let detail = failure.detail {
                            Text(detail).foregroundStyle(.secondary).lineLimit(expanded ? nil : 2)
                                .onTapGesture { expanded.toggle() }
                        }
                        if state.isStale, let date = state.lastSuccess {
                            Text("Last received \(date.formatted(date: .abbreviated, time: .standard))").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption).foregroundStyle(.orange).padding(.leading, 26).textSelection(.enabled)
                }
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small)
            } else if !state.machine.isLocal {
                Button(state.machine.isEnabled ? "Disable" : "Enable", action: toggle)
                    .help(state.machine.isEnabled ? "Stop polling this machine; keep its profile" : "Resume polling this machine")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .help("Remove this machine from Herdr…")
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AddMachineSheet: View {
    @Bindable var model: AppModel
    @Binding var isPresented: Bool
    @ViewState<String> private var target = ""
    @ViewState<String> private var label = ""
    @ViewState<String> private var session = ""
    @ViewState<Bool> private var working = false
    @ViewState<HerdrFailure?> private var failure: HerdrFailure? = nil

    private var command: String {
        var parts = ["herdr machine add", target.isEmpty ? "user@host" : target]
        if !label.isEmpty { parts.append("--label \(Self.quote(label))") }
        if !session.isEmpty { parts.append("--remote-session \(Self.quote(session))") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Machine").font(.title3).fontWeight(.semibold)
            Form {
                TextField("SSH target", text: $target, prompt: Text("user@host or an ~/.ssh/config alias"))
                TextField("Label", text: $label, prompt: Text("optional"))
                TextField("Remote session", text: $session, prompt: Text("default"))
            }
            .formStyle(.grouped)
            Text("Herdr connects over SSH and prepares its server on that machine, which may install or start Herdr there. SSH must work without a password prompt — load your key into ssh-agent first. If it needs interaction, run this in Terminal instead:")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
            if let failure {
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.message).foregroundStyle(.orange)
                    if let detail = failure.detail { Text(detail).foregroundStyle(.secondary).lineLimit(5).textSelection(.enabled) }
                }
                .font(.caption)
            }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Preparing \(target)… this can take a minute.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { isPresented = false }.keyboardShortcut(.cancelAction).disabled(working)
                Button("Add Machine") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || target.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 500)
        .preferredColorScheme(.dark)
    }

    private func add() {
        working = true
        failure = nil
        let request = NewMachineRequest(sshTarget: target, label: label, remoteSession: session)
        Task {
            failure = await model.perform { try await model.cluster.addMachine(request) }
            working = false
            if failure == nil { isPresented = false }
        }
    }

    /// Shell quoting for the copyable command shown to the user.
    private static func quote(_ value: String) -> String {
        value.allSatisfy { $0.isLetter || $0.isNumber || "-_.@".contains($0) } ? value
            : "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
