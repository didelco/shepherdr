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
