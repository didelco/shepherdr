import AppKit
import SwiftUI
import SwiftTerm
import ShepherdrCore

/// Colors for the embedded renderer. Agents mostly paint in true color; the ANSI table covers
/// shells and older tools so they match the surrounding interface.
public struct TerminalPalette: Equatable, Sendable {
    public var background: NSColor
    public var foreground: NSColor
    public var caret: NSColor
    public var selection: NSColor
    /// Sixteen ANSI colors: normal 0–7, then bright 8–15.
    public var ansi: [NSColor]

    public init(background: NSColor, foreground: NSColor, caret: NSColor, selection: NSColor, ansi: [NSColor]) {
        precondition(ansi.count == 16, "A terminal palette needs 16 ANSI colors")
        self.background = background
        self.foreground = foreground
        self.caret = caret
        self.selection = selection
        self.ansi = ansi
    }
}

/// A live Herdr terminal embedded in the window's work area. Mounting it connects the store;
/// removing it detaches this client only, never the pane or its process.
@MainActor
public struct TerminalSurface: NSViewRepresentable {
    let store: TerminalStore
    let palette: TerminalPalette
    let font: NSFont

    public init(store: TerminalStore, palette: TerminalPalette, font: NSFont) {
        self.store = store
        self.palette = palette
        self.font = font
    }

    public func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    public func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let view = SwiftTerm.TerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 520),
                                          font: font)
        apply(palette, to: view)
        context.coordinator.palette = palette
        view.allowMouseReporting = false // Selection and copy remain native; input uses the keyboard.
        view.terminalDelegate = context.coordinator
        let coordinator = context.coordinator
        store.display = { [weak view, weak coordinator] frame in
            guard let view else { return }
            coordinator?.applyingFrame = true
            if view.getTerminal().cols != frame.columns || view.getTerminal().rows != frame.rows {
                view.resize(cols: frame.columns, rows: frame.rows)
            }
            view.feed(byteArray: Array(frame.bytes)[...])
            coordinator?.applyingFrame = false
        }
        store.resetDisplay = { [weak view] in view?.feed(text: "\u{1b}c") }
        store.resize(columns: view.getTerminal().cols, rows: view.getTerminal().rows)
        store.open()
        return view
    }

    public func updateNSView(_ view: SwiftTerm.TerminalView, context: Context) {
        if context.coordinator.palette != palette {
            context.coordinator.palette = palette
            apply(palette, to: view)
        }
        if view.font != font { view.font = font }
    }

    public static func dismantleNSView(_ view: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.store.disconnect()
        coordinator.store.display = nil
        coordinator.store.resetDisplay = nil
        view.terminalDelegate = nil
    }

    private func apply(_ palette: TerminalPalette, to view: SwiftTerm.TerminalView) {
        view.nativeBackgroundColor = palette.background
        view.nativeForegroundColor = palette.foreground
        view.caretColor = palette.caret
        view.selectedTextBackgroundColor = palette.selection
        view.installColors(palette.ansi.map(Self.terminalColor))
        view.layer?.backgroundColor = palette.background.cgColor
    }

    private static func terminalColor(_ color: NSColor) -> SwiftTerm.Color {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return SwiftTerm.Color(red: UInt16(rgb.redComponent * 65_535), green: UInt16(rgb.greenComponent * 65_535),
                               blue: UInt16(rgb.blueComponent * 65_535))
    }

    @MainActor public final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let store: TerminalStore
        var applyingFrame = false
        var palette: TerminalPalette?
        init(store: TerminalStore) { self.store = store }
        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            if !applyingFrame { store.resize(columns: newCols, rows: newRows) }
        }
        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) { store.send(.bytes(Data(data))) }
        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased()) else { return }
            NSWorkspace.shared.open(url)
        }
        public func bell(source: SwiftTerm.TerminalView) {}
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}
