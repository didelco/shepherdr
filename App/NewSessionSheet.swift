import AppKit
import SwiftUI
import ShepherdrCore

/// Creates a Herdr workspace in a folder and starts an agent in it.
struct NewSessionSheet: View {
    @Bindable var model: AppModel
    @AppStorage("newSessionAgent") private var agentKind = "claude"
    @AppStorage("newSessionMachine") private var machineID = Machine.local.id
    @ViewState<String> private var directory = ""
    @ViewState<String> private var name = ""
    @ViewState<HerdrFailure?> private var failure: HerdrFailure? = nil
    @FocusState private var directoryFocused: Bool

    private static let shell = "shell"

    private var machine: MachineState? {
        model.onlineMachines.first { $0.id == machineID } ?? model.onlineMachines.first
    }
    private var isLocal: Bool { machine?.machine.isLocal ?? true }
    private var resolvedDirectory: String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        return isLocal ? (trimmed as NSString).expandingTildeInPath : trimmed
    }
    private var resolvedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? URL(fileURLWithPath: resolvedDirectory).lastPathComponent
    }
    private var canCreate: Bool {
        machine != nil && !resolvedDirectory.isEmpty && !resolvedName.isEmpty && !model.isCreatingSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PixelFlock(pixel: 1.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEW SESSION").font(Theme.mono(15, .bold)).tracking(2).foregroundStyle(Theme.text)
                    Text("a new herdr workspace with an agent in it").font(Theme.mono(10.5)).foregroundStyle(Theme.dim)
                }
            }

            if model.onlineMachines.count > 1 {
                field("Machine") {
                    Picker("", selection: Binding { machine?.id ?? Machine.local.id } set: { machineID = $0 }) {
                        ForEach(model.onlineMachines) { state in
                            Text(state.machine.isLocal ? "Local" : "\(state.machine.name) · \(state.machine.target ?? "")").tag(state.id)
                        }
                    }
                    .labelsHidden()
                }
            }

            field(isLocal ? "Folder" : "Folder on \(machine?.machine.name ?? "machine")") {
                HStack(spacing: 8) {
                    consoleTextField(isLocal ? "~/projects/my-app" : "/home/me/projects/my-app", text: $directory)
                        .focused($directoryFocused)
                    if isLocal {
                        Button("CHOOSE…") { chooseFolder() }.buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                    }
                }
            }

            field("Name") {
                consoleTextField(resolvedDirectory.isEmpty ? "defaults to the folder name" : resolvedName, text: $name)
            }

            field("Agent") {
                Picker("", selection: $agentKind) {
                    ForEach(NewSessionRequest.agentKinds, id: \.self) { Text($0).tag($0) }
                    Divider()
                    Text("shell only").tag(Self.shell)
                }
                .labelsHidden()
                .frame(width: 180)
            }

            if let failure {
                VStack(alignment: .leading, spacing: 3) {
                    Text("✗ \(failure.message)").font(Theme.mono(11)).foregroundStyle(Theme.red)
                    if let detail = failure.detail {
                        Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(4).textSelection(.enabled)
                    }
                }
            }

            HStack {
                if model.isCreatingSession {
                    Text(agentKind == Self.shell ? "creating workspace…" : "starting \(agentKind)… this can take a few seconds")
                        .font(Theme.mono(10.5)).foregroundStyle(Theme.phosphor)
                    BlinkingCursor()
                }
                Spacer()
                Button("CANCEL") { model.showsNewSession = false }
                    .buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isCreatingSession)
                Button("CREATE ⏎") { create() }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.panel)
        .onAppear { directoryFocused = true }
    }

    private func field(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(Theme.mono(9.5, .semibold)).tracking(1.2).foregroundStyle(Theme.faint)
            content()
        }
    }

    private func consoleTextField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain).font(Theme.mono(12)).foregroundStyle(Theme.text)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        if !resolvedDirectory.isEmpty { panel.directoryURL = URL(fileURLWithPath: resolvedDirectory) }
        if panel.runModal() == .OK, let url = panel.url {
            directory = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func create() {
        guard canCreate, let machine else { return }
        var isDirectory: ObjCBool = false
        if isLocal, !FileManager.default.fileExists(atPath: resolvedDirectory, isDirectory: &isDirectory) || !isDirectory.boolValue {
            failure = HerdrFailure(.unreachable, "That folder does not exist on this Mac.")
            return
        }
        failure = nil
        let request = NewSessionRequest(directory: resolvedDirectory, name: resolvedName,
                                        agentKind: agentKind == Self.shell ? nil : agentKind)
        Task { failure = await model.createSession(request, onMachine: machine.id) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
