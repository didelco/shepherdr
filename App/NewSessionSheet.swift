import AppKit
import SwiftUI
import ShepherdrCore

/// Where the user keeps projects on this Mac: New Session's folder picker always starts here,
/// and a bare folder name means a folder inside it.
enum ProjectsFolder {
    static let key = "projectsFolder"
    static let defaultPath = "~/projects"

    static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }
}

/// Creates a Herdr workspace in a folder with a shell in it. Starting an agent there is up to
/// the user; Shepherdr picks it up as soon as Herdr detects it.
struct NewSessionSheet: View {
    @Bindable var model: AppModel
    let draft: NewSessionDraft
    @AppStorage("newSessionMachine") private var lastMachineID = Machine.local.id
    @AppStorage(ProjectsFolder.key) private var projectsFolder = ProjectsFolder.defaultPath
    @ViewState<String?> private var machineID: String?
    @ViewState<String> private var directory: String
    @ViewState<String> private var name = ""
    @ViewState<HerdrFailure?> private var failure: HerdrFailure? = nil
    @FocusState private var focus: Field?

    private enum Field { case directory, name }

    init(model: AppModel, draft: NewSessionDraft) {
        self.model = model
        self.draft = draft
        _machineID = ViewState(initialValue: draft.machineID)
        _directory = ViewState(initialValue: draft.directory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "")
    }

    private var machine: MachineState? {
        let id = machineID ?? lastMachineID
        return model.onlineMachines.first { $0.id == id } ?? model.onlineMachines.first
    }
    private var isLocal: Bool { machine?.machine.isLocal ?? true }
    private var resolvedDirectory: String {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLocal else { return trimmed }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard !expanded.isEmpty, !expanded.hasPrefix("/") else { return expanded }
        return ProjectsFolder.url(projectsFolder).appendingPathComponent(expanded).path
    }
    private var resolvedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? URL(fileURLWithPath: resolvedDirectory).lastPathComponent
    }
    private var canCreate: Bool {
        machine != nil && !resolvedDirectory.isEmpty && !resolvedName.isEmpty && !model.isCreatingSession
    }
    private var subtitle: String {
        guard case .into(let groupID) = draft.placement,
              let group = model.groups.first(where: { $0.id == groupID }) else { return "a new herdr workspace with a shell in it" }
        return "a new herdr workspace with a shell, in \(group.name)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PixelFlock(pixel: 1.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEW SESSION").font(Theme.mono(15, .bold)).tracking(2).foregroundStyle(Theme.text)
                    Text(subtitle).font(Theme.mono(10.5)).foregroundStyle(Theme.dim).lineLimit(1)
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
                    consoleTextField(isLocal ? "\(projectsFolder)/my-app" : "/home/me/projects/my-app", text: $directory)
                        .focused($focus, equals: .directory)
                    if isLocal {
                        Button("CHOOSE…") { chooseFolder() }.buttonStyle(ConsoleButtonStyle(tint: Theme.dim))
                    }
                }
            }

            field("Name") {
                consoleTextField(resolvedDirectory.isEmpty ? "defaults to the folder name" : resolvedName, text: $name)
                    .focused($focus, equals: .name)
            }

            Text("Start an agent in its terminal when you need one; the session joins the queue as soon as Herdr detects it.")
                .font(Theme.mono(10)).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)

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
                    Text("creating workspace…").font(Theme.mono(10.5)).foregroundStyle(Theme.phosphor)
                    BlinkingCursor()
                }
                Spacer()
                Button("CANCEL") { model.newSession = nil }
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
        // A prefilled folder usually only needs a name.
        .onAppear { focus = directory.isEmpty ? .directory : .name }
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
        panel.directoryURL = ProjectsFolder.url(projectsFolder)
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
        lastMachineID = machine.id
        let request = NewSessionRequest(directory: resolvedDirectory, name: resolvedName, agentKind: nil)
        Task { failure = await model.createSession(request, onMachine: machine.id, placement: draft.placement) }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
