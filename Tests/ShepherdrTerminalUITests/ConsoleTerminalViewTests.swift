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
}
