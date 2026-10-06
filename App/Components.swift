import AppKit
import SwiftUI
import ShepherdrCore

struct NoticeView: View {
    let title: String
    let message: String
    let detail: String?
    @ViewState<Bool> private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("!").font(Theme.mono(12, .bold)).foregroundStyle(Theme.amber)
                Text(title).font(Theme.mono(12, .semibold)).foregroundStyle(Theme.amber)
            }
            Text(message).font(Theme.mono(11)).foregroundStyle(Theme.text.opacity(0.8)).textSelection(.enabled)
            if let detail {
                Button(expanded ? "▾ details" : "▸ details") { expanded.toggle() }
                    .buttonStyle(.plain).font(Theme.mono(10)).foregroundStyle(Theme.dim)
                if expanded {
                    Text(detail).font(Theme.mono(10)).foregroundStyle(Theme.dim).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.amber.opacity(0.3), lineWidth: 1))
    }
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// Copies how to address a session through Herdr: its pane ID, or a reference to paste into
/// another agent's prompt, such as "report your progress to the coordinator (…)".
struct CopyPaneMenu: View {
    let paneID: String
    let workspace: String
    let machine: Machine

    var body: some View {
        Button("Copy Pane ID (\(paneID))") { copyToPasteboard(paneID) }
        Button("Copy Reference for Agents") {
            copyToPasteboard(PaneReference.description(workspace: workspace, paneID: paneID, machine: machine))
        }
    }
}

/// The session's Herdr pane ID, which agents address it by: click to copy.
struct PaneIDButton: View {
    let paneID: String
    let workspace: String
    let machine: Machine
    @ViewState<Bool> private var copied = false

    var body: some View {
        Button {
            copyToPasteboard(paneID)
            copied = true
            Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
        } label: {
            HStack(spacing: 4) {
                Text("pane \(paneID)")
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 8.5, weight: .semibold))
            }
            .font(Theme.mono(10))
            .foregroundStyle(copied ? Theme.phosphor : Theme.dim)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy the Herdr pane ID. Agents prompt this session with: \(PaneReference.promptCommand(paneID: paneID)). Right-click for a reference to paste into a prompt.")
        .contextMenu { CopyPaneMenu(paneID: paneID, workspace: workspace, machine: machine) }
        .accessibilityLabel("Copy pane ID \(paneID)")
    }
}

