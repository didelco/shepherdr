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
    /// Changing this gives the terminal keyboard focus.
    let focusRequest: Int
    /// Opens a clicked link or file; `external` asks for the default browser or app instead of Shepherdr's own.
    let openLink: (_ url: URL, _ external: Bool) -> Void
    /// The existing local file a printed path names, if any.
    let resolveFile: (_ path: String) -> URL?
    /// Pull requests, issues and Claude artifacts seen on screen.
    let onResources: (_ found: [SessionResource]) -> Void

    public init(store: TerminalStore, palette: TerminalPalette, font: NSFont, focusRequest: Int = 0,
                resolveFile: @escaping (_ path: String) -> URL? = { _ in nil },
                onResources: @escaping (_ found: [SessionResource]) -> Void = { _ in },
                openLink: @escaping (_ url: URL, _ external: Bool) -> Void = { url, _ in NSWorkspace.shared.open(url) }) {
        self.store = store
        self.palette = palette
        self.font = font
        self.focusRequest = focusRequest
        self.resolveFile = resolveFile
        self.onResources = onResources
        self.openLink = openLink
    }

    public func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    public func makeNSView(context: Context) -> ConsoleTerminalView {
        let view = ConsoleTerminalView(frame: NSRect(x: 0, y: 0, width: 900, height: 520), font: font)
        apply(palette, to: view)
        context.coordinator.palette = palette
        view.allowMouseReporting = false // Selection and copy remain native; input uses the keyboard.
        // Option types what the keyboard layout gives it (@, #, €…), as in Terminal; the word-wise
        // keys that need Meta get it from installInteractions.
        view.optionAsMetaKey = false
        view.terminalDelegate = context.coordinator
        view.installInteractions()
        store.display = { [weak view] frame in view?.show(frame) }
        store.resetDisplay = { [weak view] in view?.resetScreen() }
        store.resize(columns: view.getTerminal().cols, rows: view.getTerminal().rows)
        store.open()
        return view
    }

    public func updateNSView(_ view: ConsoleTerminalView, context: Context) {
        view.openLink = openLink
        view.resolveFile = resolveFile
        view.onResources = onResources
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak view] in view?.window?.makeFirstResponder(view) }
        }
        if context.coordinator.palette != palette {
            context.coordinator.palette = palette
            apply(palette, to: view)
        }
        if view.font != font { view.font = font }
    }

    public static func dismantleNSView(_ view: ConsoleTerminalView, coordinator: Coordinator) {
        view.removeInteractions()
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
        var palette: TerminalPalette?
        var focusRequest: Int?
        init(store: TerminalStore) { self.store = store }
        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            if (source as? ConsoleTerminalView)?.applyingFrame != true { store.resize(columns: newCols, rows: newRows) }
        }
        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) { store.send(.bytes(Data(data))) }
        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        /// SwiftTerm calls this for ⌘-clicks on links agents mark up explicitly (OSC 8).
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased()) else { return }
            (source as? ConsoleTerminalView)?.openLink?(url, true)
        }
        public func bell(source: SwiftTerm.TerminalView) {}
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}

/// SwiftTerm's view with Shepherdr's interactions: clicking a link opens it (⌘-click: in the
/// default browser), Shift-Return inserts a new line in agent TUIs instead of submitting, and
/// selecting text copies it.
public final class ConsoleTerminalView: SwiftTerm.TerminalView {
    var openLink: ((_ url: URL, _ external: Bool) -> Void)?
    var resolveFile: ((_ path: String) -> URL?)?
    var onResources: ((_ found: [SessionResource]) -> Void)?
    private var scanPending = false
    /// Bumped by every frame, so the menu found under the pointer is reused until the screen changes.
    private var screenGeneration = 0
    private var menuCache: (generation: Int, row: Int, moves: Int?)?
    /// A click that chose a menu option is not a selection to copy.
    private var clickWasConsumed = false
    /// Set while a Herdr frame resizes the view, so that resize is not reported back as the user's.
    private(set) var applyingFrame = false
    private var linkTracker: LinkTracker?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    /// Frames that arrived while the mouse button is down in the terminal. SwiftTerm drops the
    /// selection whenever output arrives, so a busy agent would otherwise make text impossible to select.
    private var heldFrames: [TerminalFrame]?
    private var selectedWithMouse = false
    private var pressedCell: (row: Int, column: Int)?

    func show(_ frame: TerminalFrame) {
        if heldFrames != nil {
            // A press whose mouse up went elsewhere (another app took it) must not freeze the terminal.
            if NSEvent.pressedMouseButtons & 1 != 0 { heldFrames?.append(frame); return }
            pressedCell = nil
            endMousePress()
        }
        applyingFrame = true
        if getTerminal().cols != frame.columns || getTerminal().rows != frame.rows {
            resize(cols: frame.columns, rows: frame.rows)
        }
        feed(byteArray: Array(frame.bytes)[...])
        applyingFrame = false
        paintChangedRows()
    }

    func resetScreen() {
        heldFrames = heldFrames.map { _ in [] }
        feed(text: "\u{1b}c")
        paintChangedRows()
    }

    /// SwiftTerm paints new output a sixtieth of a second after it arrives. Painting the changed rows
    /// right away saves that wait on every keystroke's echo; SwiftTerm's own pass then finds nothing
    /// left to paint and only moves the caret.
    private func paintChangedRows() {
        let terminal = getTerminal()
        guard let (first, last) = terminal.getUpdateRange() else { return }
        terminal.clearUpdateRange()
        let height = cellSize.height
        var region = CGRect(x: 0, y: bounds.height - CGFloat(last + 1) * height,
                            width: bounds.width, height: CGFloat(last - first + 1) * height)
        // As SwiftTerm does: the last row also repaints the leftover strip below it.
        if last == terminal.rows - 1 { region = CGRect(x: 0, y: 0, width: bounds.width, height: region.maxY) }
        setNeedsDisplay(region)
        NSAccessibility.post(element: self, notification: .valueChanged)
        screenGeneration += 1
        scheduleResourceScan()
    }

    /// Looks for links worth keeping at most once a second while output flows.
    private func scheduleResourceScan() {
        guard !scanPending, onResources != nil else { return }
        scanPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.scanPending = false
            let terminal = self.getTerminal()
            var found = SessionResources.find(onScreen: self.screenRows())
            // Links agents mark up explicitly keep their whole URL in every cell, however they wrap.
            for row in 0..<terminal.rows {
                for column in 0..<terminal.cols {
                    guard let payload = terminal.getCharData(col: column, row: row)?.getPayload() as? String,
                          let separator = payload.firstIndex(of: ";"),
                          let url = URL(string: String(payload[payload.index(after: separator)...])),
                          let resource = SessionResource(url: url), !found.contains(resource) else { continue }
                    found.append(resource)
                }
            }
            if !found.isEmpty { self.onResources?(found) }
        }
    }

    /// The visible screen, one character per column.
    func screenRows(_ rows: ClosedRange<Int>? = nil) -> [[Character]] {
        let terminal = getTerminal()
        let range = rows ?? 0...max(0, terminal.rows - 1)
        return range.map { index -> [Character] in
            guard let line = terminal.getLine(row: index) else { return Array(repeating: " ", count: terminal.cols) }
            return (0..<terminal.cols).map { column in
                guard column < line.count else { return " " }
                let cell = line[column]
                // The second half of a wide character, and empty cells, read as blanks.
                let character = cell.getCharacter()
                return cell.width == 0 || character == "\u{0}" ? " " : character
            }
        }
    }

    /// Chooses the menu option at a point by moving the menu's highlight there with the arrow keys;
    /// a double click also confirms it. Returns whether the click was on a menu option.
    func chooseMenuOption(at point: NSPoint, clickCount: Int) -> Bool {
        guard let moves = menuMoves(at: point) else { return false }
        clickWasConsumed = true
        if clickCount >= 2 {
            send(data: [13][...])
        } else if moves != 0 {
            let applicationCursor = getTerminal().applicationCursor
            let key: [UInt8] = moves < 0 ? (applicationCursor ? [27, 79, 65] : [27, 91, 65])
                                         : (applicationCursor ? [27, 79, 66] : [27, 91, 66])
            send(data: Array(Array(repeating: key, count: abs(moves)).joined())[...])
        }
        return true
    }

    /// How far the highlight of the agent menu under a point must move to reach it, if there is one.
    func menuMoves(at point: NSPoint) -> Int? {
        guard let row = cell(at: point)?.row else { return nil }
        if let cache = menuCache, cache.generation == screenGeneration, cache.row == row { return cache.moves }
        let lines = screenRows().map { String($0).replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }
        let moves = TerminalMenus.moves(in: lines, clicked: row)
        menuCache = (screenGeneration, row, moves)
        return moves
    }

    private func cell(at point: NSPoint) -> (row: Int, column: Int)? {
        let terminal = getTerminal(), size = cellSize
        let column = Int(point.x / size.width), row = Int((bounds.height - point.y) / size.height)
        guard point.x >= 0, point.y <= bounds.height, (0..<terminal.cols).contains(column),
              (0..<terminal.rows).contains(row) else { return nil }
        return (row, column)
    }

    /// SwiftTerm's own cell metrics: the width of "W" and the font's line height.
    private var cellSize: CGSize {
        CGSize(width: max(1, font.advancement(forGlyph: font.glyph(withName: "W")).width),
               height: max(1, ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))))
    }

    public override func selectionChanged(source: Terminal) {
        super.selectionChanged(source: source)
        if heldFrames != nil { selectedWithMouse = true }
    }

    /// Mouse down in the terminal holds output; mouse up copies what the mouse selected, then lets output in.
    private func handleMouse(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.type == .leftMouseDown {
            guard event.window === window, !isHiddenOrHasHiddenAncestor, bounds.contains(point) else { return }
            // A double click's second press can come before the first one is wrapped up.
            if heldFrames == nil {
                heldFrames = []
                selectedWithMouse = false
            }
            pressedCell = cell(at: point)
        } else if let pressed = pressedCell {
            // Released in the cell it was pressed in: a click rather than a selection drag.
            let click = cell(at: point).map { $0 == pressed } == true
                ? (point: point, count: event.clickCount, command: event.modifierFlags.contains(.command)) : nil
            pressedCell = nil
            // After SwiftTerm has handled this mouse up.
            DispatchQueue.main.async { [weak self] in
                if let click { self?.clicked(at: click.point, count: click.count, command: click.command) }
                self?.endMousePress()
            }
        }
    }

    /// A click opens the link or file under it (⌘: in the default browser or app), or chooses the
    /// option of an agent's menu under it.
    private func clicked(at point: NSPoint, count: Int, command: Bool) {
        if let link = link(at: point) {
            // SwiftTerm already opens explicit links on ⌘-click, through requestOpenLink. A double click
            // opens a link once.
            guard count == 1, !(command && link.explicit) else { return }
            clickWasConsumed = true
            openLink?(link.url, command)
        } else if !command {
            _ = chooseMenuOption(at: point, clickCount: count)
        }
    }

    /// Copies what the mouse selected and lets the held output in, unless another press has begun;
    /// that one finishes the job.
    private func endMousePress() {
        guard pressedCell == nil, let frames = heldFrames else { return }
        defer { clickWasConsumed = false }
        if selectedWithMouse, !clickWasConsumed, let text = getSelection(), !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        heldFrames = nil
        frames.forEach(show)
    }

    /// SwiftTerm's mouse and key handlers are not overridable, so local event monitors add these
    /// around them; selection keeps working.
    func installInteractions() {
        guard linkTracker == nil else { return }
        let tracker = LinkTracker(view: self)
        linkTracker = tracker
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
                                       owner: tracker))
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window, self.window?.firstResponder === self,
                  let bytes = Self.metaSequence(for: event) else { return event }
            self.terminalDelegate?.send(source: self, data: bytes[...])
            return nil
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    func removeInteractions() {
        for monitor in [keyMonitor, mouseMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil
        mouseMonitor = nil
    }

    /// Keys that send Meta (Escape-prefixed) sequences although Option otherwise types characters.
    static func metaSequence(for event: NSEvent) -> [UInt8]? {
        let flags = event.modifierFlags.intersection([.shift, .control, .option, .command])
        switch (event.keyCode, flags) {
        // Claude Code, Codex and Gemini read ESC-Return (Alt-Return) as a new line; Return submits.
        case (36, .shift), (76, .shift), (36, .option), (76, .option): return [27, 13]
        case (123, .option): return EscapeSequences.emacsBack // a word back
        case (124, .option): return EscapeSequences.emacsForward // a word forward
        case (51, .option): return [27, 127] // delete the previous word
        default: return nil
        }
    }

    /// The link at a point in this view: one an agent marked up explicitly, a plain-text URL, or the
    /// path of an existing local file.
    func link(at point: NSPoint) -> (url: URL, explicit: Bool)? {
        let terminal = getTerminal()
        guard let (row, column) = cell(at: point) else { return nil }
        if let payload = terminal.getCharData(col: column, row: row)?.getPayload() as? String {
            // SwiftTerm keeps OSC 8 links as "parameters;url".
            guard let separator = payload.firstIndex(of: ";"),
                  let url = URL(string: String(payload[payload.index(after: separator)...])),
                  ["https", "http"].contains(url.scheme?.lowercased()) else { return nil }
            return (url, true)
        }
        let first = max(0, row - 8), last = min(terminal.rows - 1, row + 8)
        let rows = screenRows(first...last)
        if let url = TerminalLinks.url(in: rows, row: row - first, column: column) { return (url, false) }
        return TerminalPaths.path(in: rows, row: row - first, column: column).flatMap { resolveFile?($0) }.map { ($0, false) }
    }
}

/// Shows a pointing hand over links, files and menu options.
@MainActor private final class LinkTracker: NSResponder {
    weak var view: ConsoleTerminalView?

    init(view: ConsoleTerminalView) {
        self.view = view
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func mouseMoved(with event: NSEvent) {
        guard let view else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        guard view.link(at: point) != nil || view.menuMoves(at: point) != nil else { return }
        NSCursor.pointingHand.set()
    }
}
