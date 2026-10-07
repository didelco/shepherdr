import AppKit
import SwiftUI
import ShepherdrCore

/// The links a session has produced, at hand: pull requests, issues and Claude artifacts, newest
/// first. Clicking one opens it in the session's browser.
struct ResourcesPanel: View {
    let workspace: SessionWorkspace

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConsoleHeader(title: "Resources", trailing: "\(workspace.resources.count)")
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(SessionResource.Kind.allCases, id: \.self) { kind in
                        let items = workspace.resources.filter { $0.kind == kind }
                        if !items.isEmpty {
                            Text(kind.title.uppercased()).font(Theme.mono(9, .semibold)).tracking(1)
                                .foregroundStyle(Theme.faint)
                                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 3)
                            ForEach(items) { resource in row(resource) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private func row(_ resource: SessionResource) -> some View {
        let isOpen = workspace.browser.isVisible && workspace.browser.selected?.url == resource.url
        return Button { workspace.browser.open(resource.url) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Self.glyph(resource.kind)).font(Theme.mono(10.5, .bold))
                    .foregroundStyle(Self.tint(resource.kind)).frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text(resource.name).font(Theme.mono(11, .medium)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(isOpen ? Theme.text : Theme.text.opacity(0.82))
                    Text(resource.url.host() ?? "").font(Theme.mono(9.5)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(isOpen ? Theme.raised : .clear)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.phosphor).frame(width: 2).opacity(isOpen ? 1 : 0) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(resource.url.absoluteString)
        .contextMenu {
            Button("Open") { workspace.browser.open(resource.url) }
            Button("Open in Default Browser") { NSWorkspace.shared.open(resource.url) }
            Button("Copy Link") { copyToPasteboard(resource.url.absoluteString) }
            Divider()
            Button("Remove") { workspace.remove(resource) }
        }
    }

    private static func glyph(_ kind: SessionResource.Kind) -> String {
        switch kind {
        case .pullRequest: "⇄"
        case .issue: "◎"
        case .artifact: "◆"
        }
    }

    private static func tint(_ kind: SessionResource.Kind) -> Color {
        switch kind {
        case .pullRequest: Theme.phosphor
        case .issue: Theme.amber
        case .artifact: Theme.cyan
        }
    }
}
