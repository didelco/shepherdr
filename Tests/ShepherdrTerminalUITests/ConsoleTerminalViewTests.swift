import AppKit
import Testing
import SwiftTerm
@testable import ShepherdrCore
@testable import ShepherdrTerminalUI

@MainActor
struct ConsoleTerminalViewTests {
    private final class Recorder: TerminalViewDelegate {
        var sent: [UInt8] = []
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) { sent += data }
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }

    private func key(_ code: UInt16, _ characters: String, ignoring: String? = nil,
                     _ flags: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: characters, charactersIgnoringModifiers: ignoring ?? characters,
                         isARepeat: false, keyCode: code)!
    }

    @Test func wordKeysKeepMetaSequences() {
        let arrows: NSEvent.ModifierFlags = [.function, .numericPad]
        #expect(ConsoleTerminalView.metaSequence(for: key(123, "\u{F702}", arrows.union(.option))) == [27, 98])
        #expect(ConsoleTerminalView.metaSequence(for: key(124, "\u{F703}", arrows.union(.option))) == [27, 102])
        #expect(ConsoleTerminalView.metaSequence(for: key(51, "\u{7F}", .option)) == [27, 127])
        #expect(ConsoleTerminalView.metaSequence(for: key(36, "\r", .shift)) == [27, 13])
        #expect(ConsoleTerminalView.metaSequence(for: key(36, "\r", .option)) == [27, 13])
        #expect(ConsoleTerminalView.metaSequence(for: key(36, "\r", [])) == nil)
        #expect(ConsoleTerminalView.metaSequence(for: key(123, "\u{F702}", arrows.union([.option, .shift]))) == nil)
    }

    @Test func optionTypesWhatTheKeyboardLayoutGives() {
        // Spanish layout: Option-2 is "@" and Option-3 is "#".
        #expect(ConsoleTerminalView.metaSequence(for: key(19, "@", ignoring: "2", .option)) == nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: .titled,
                              backing: .buffered, defer: true)
        let view = ConsoleTerminalView(frame: window.contentLayoutRect)
        window.contentView = view
        view.optionAsMetaKey = false
        let recorder = Recorder()
        view.terminalDelegate = recorder
        view.keyDown(with: key(19, "@", ignoring: "2", .option))
        view.keyDown(with: key(20, "#", ignoring: "3", .option))
        #expect(recorder.sent == Array("@#".utf8))
    }

    @Test func droppedFilesAndImagesBecomeFiles() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShepherdrTests.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop test.txt")
        try Data("hi".utf8).write(to: file)
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        #expect(ConsoleTerminalView.canTakeFiles(from: pasteboard))
        #expect(ConsoleTerminalView.files(from: pasteboard) == [file])
        // An image without a file is saved as a PNG.
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus(); NSColor.green.setFill(); NSRect(x: 0, y: 0, width: 4, height: 4).fill(); image.unlockFocus()
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        #expect(ConsoleTerminalView.canTakeFiles(from: pasteboard))
        let saved = try #require(ConsoleTerminalView.files(from: pasteboard).first)
        #expect(saved.pathExtension == "png")
        #expect(NSImage(contentsOf: saved) != nil)
        try? FileManager.default.removeItem(at: saved)
        pasteboard.clearContents()
        pasteboard.setString("just text", forType: .string)
        #expect(!ConsoleTerminalView.canTakeFiles(from: pasteboard))
    }

    @Test func framesArePaintedWithoutWaitingForSwiftTerm() {
        let view = ConsoleTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.show(TerminalFrame(bytes: Data("hello".utf8), columns: 40, rows: 10, isFull: false))
        let terminal = view.getTerminal()
        #expect(terminal.cols == 40 && terminal.rows == 10)
        #expect(terminal.getLine(row: 0)?.translateToString(trimRight: true) == "hello")
        // Nothing is left for SwiftTerm's delayed pass to paint.
        #expect(terminal.getUpdateRange() == nil)
    }

    @Test func resizesLeaveNoStaleHistoryToScrollInto() {
        let view = ConsoleTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.getTerminal().changeHistorySize(0)
        // Herdr paints whole screens with the cursor at the bottom; a smaller one pushes rows out.
        let rows = (1...10).map { "\u{1b}[\($0);1Hrow \($0)" }.joined()
        view.show(TerminalFrame(bytes: Data(rows.utf8), columns: 40, rows: 10, isFull: true))
        view.show(TerminalFrame(bytes: Data("\u{1b}[6;1H\u{1b}[2Klive".utf8), columns: 40, rows: 6, isFull: false))
        #expect(!view.canScroll)
        // Scrolling must not leave live output out of sight behind rows from before the resize.
        view.scrollUp(lines: 3)
        #expect(view.getTerminal().getLine(row: 5)?.translateToString(trimRight: true) == "live")
    }

    @Test func theWheelScrollsWholeLinesAtMostOnceAFrame() async throws {
        let view = ConsoleTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        var sent: [String] = []
        view.onScroll = { up, lines in sent.append("\(up ? "up" : "down") \(lines)") }
        view.scroll(lines: 0.4, startsGesture: true)
        #expect(sent.isEmpty)
        // A whole line goes at once; what follows within the frame waits for it to end.
        view.scroll(lines: 0.7)
        view.scroll(lines: 2.5)
        view.scroll(lines: 0.5)
        #expect(sent == ["up 1"])
        try await Task.sleep(for: .milliseconds(60))
        #expect(sent == ["up 1", "up 3"])
        // Turning the other way drops what was left of the other direction.
        view.scroll(lines: -1.2)
        try await Task.sleep(for: .milliseconds(60))
        #expect(sent == ["up 1", "up 3", "down 1"])
    }

    @Test func framesSkipSynchronizedOutput() {
        let frame = Data("\u{1b}[?2026h\u{1b}[?25l\u{1b}[5;1Hspin\u{1b}[?2026l\u{1b}[?2026".utf8)
        #expect(ConsoleTerminalView.unsynchronized(frame) == Array("\u{1b}[?25l\u{1b}[5;1Hspin\u{1b}[?2026".utf8))
        // A frame that changes one row repaints that row only.
        let view = ConsoleTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        view.show(TerminalFrame(bytes: Data("\u{1b}[?2026h\u{1b}[2J\u{1b}[1;1Hfull\u{1b}[?2026l".utf8), columns: 40, rows: 10, isFull: true))
        view.getTerminal().clearUpdateRange()
        view.getTerminal().feed(text: "\u{1b}[?2026h\u{1b}[5;1Hspin\u{1b}[?2026l")
        #expect(view.getTerminal().getUpdateRange().map { [$0.0, $0.1] } == [0, 9])
        view.getTerminal().clearUpdateRange()
        view.getTerminal().feed(byteArray: ConsoleTerminalView.unsynchronized(Data("\u{1b}[?2026h\u{1b}[5;1Hspun\u{1b}[?2026l".utf8)))
        #expect(view.getTerminal().getUpdateRange().map { [$0.0, $0.1] } == [4, 4])
    }
}
