import AppKit
import SwiftUI

/// A growing multi-line prompt field. Return submits, Shift/Option-Return inserts a newline,
/// and Up/Down on an empty or recalled prompt walk through this session's history.
struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var isEnabled: Bool
    var font: NSFont
    var focusRequest: Int
    var history: [String]
    var onSubmit: () -> Void

    static let maxLines: CGFloat = 8

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let textView = scroll.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.font = font
        textView.textColor = NSColor(hex: 0xD9E7DE)
        textView.insertionPointColor = NSColor(hex: 0x4DFFA0)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(hex: 0x4DFFA0, alpha: 0.28)]
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 5)
        textView.textContainer?.lineFragmentPadding = 0
        for disable in [\NSTextView.isAutomaticQuoteSubstitutionEnabled, \.isAutomaticDashSubstitutionEnabled,
                        \.isAutomaticTextReplacementEnabled, \.isAutomaticSpellingCorrectionEnabled,
                        \.isContinuousSpellCheckingEnabled, \.isAutomaticLinkDetectionEnabled] {
            textView[keyPath: disable] = false
        }
        textView.setAccessibilityLabel("Prompt")
        context.coordinator.textView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        if textView.font != font { textView.font = font }
        textView.isEditable = isEnabled
        textView.isSelectable = true
        if focusRequest != context.coordinator.focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        }
        context.coordinator.measure()
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        weak var textView: NSTextView?
        var focusRequest = 0
        /// Position while browsing history; nil while editing a fresh draft.
        private var recall: Int?
        private var stash = ""

        init(_ parent: PromptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            recall = nil
            parent.text = textView.string
            measure()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) || flags.contains(.option) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                } else if parent.isEnabled {
                    recall = nil
                    parent.onSubmit()
                }
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            case #selector(NSResponder.moveUp(_:)):
                return browse(-1, in: textView)
            case #selector(NSResponder.moveDown(_:)):
                return browse(1, in: textView)
            default:
                return false
            }
        }

        private func browse(_ delta: Int, in textView: NSTextView) -> Bool {
            let history = parent.history
            guard !history.isEmpty, textView.string.isEmpty || recall != nil else { return false }
            let next: Int? = switch (recall, delta < 0) {
            case (nil, true): history.count - 1
            case (nil, false): nil
            case (let index?, true): max(0, index - 1)
            case (let index?, false): index + 1 < history.count ? index + 1 : nil
            }
            if recall == nil { stash = textView.string }
            if let next {
                set(history[next], in: textView)
                recall = next
            } else if recall != nil {
                set(stash, in: textView)
                recall = nil
            }
            return true
        }

        private func set(_ value: String, in textView: NSTextView) {
            textView.string = value
            textView.setSelectedRange(NSRange(location: (value as NSString).length, length: 0))
            parent.text = value
            measure()
        }

        func measure() {
            guard let textView, let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let line = layout.defaultLineHeight(for: parent.font)
            let used = max(line, layout.usedRect(for: container).height)
            let height = min(used, line * PromptEditor.maxLines) + textView.textContainerInset.height * 2
            if abs(height - parent.height) > 0.5 {
                let binding = parent.$height
                DispatchQueue.main.async { binding.wrappedValue = height }
            }
        }
    }
}
