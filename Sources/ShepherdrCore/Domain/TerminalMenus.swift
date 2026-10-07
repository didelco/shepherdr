import Foundation

/// The numbered menus agents draw in the terminal, such as Claude Code's permission prompts, so a
/// click can choose an option by moving the menu's highlight with the arrow keys.
public enum TerminalMenus {
    /// Marks of the highlighted option: Claude Code ❯, Codex ›, others ▶, ●, ➤ or >.
    private static let option = try! NSRegularExpression(pattern: #"^(?:([❯›>▶➤→●◉])\s*)?([0-9]{1,2})[.)]\s+\S"#)
    /// Box borders that frame some prompts.
    private static let frame = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "│┃║|"))

    private struct Option {
        let row: Int
        let number: Int
        let column: Int
        let isHighlighted: Bool
    }

    /// How many rows the highlight must move to reach the option clicked, negative upward, or nil
    /// when the click is not on an option of a menu with exactly one highlighted option.
    public static func moves(in rows: [String], clicked: Int) -> Int? {
        guard rows.indices.contains(clicked) else { return nil }
        let options = rows.indices.map { parse(rows[$0], row: $0) }
        // The clicked option, or the one whose wrapped text continues on the clicked row.
        var target = options[clicked]
        var row = clicked
        while target == nil, row > 0, clicked - row < 3, !isBlank(rows[row]) {
            row -= 1
            target = options[row]
        }
        guard let target, target.row == clicked || indentation(rows[clicked]) > target.column else { return nil }

        // Its menu: options numbered in sequence, aligned, with at most two wrapped rows between them.
        var menu = [target]
        func extend(from start: Option, step: Int) {
            var last = start, index = start.row + step, gap = 0
            while rows.indices.contains(index), gap <= 2 {
                if let next = options[index], next.number == last.number + step, next.column == last.column {
                    menu.append(next)
                    last = next
                    gap = 0
                } else if isBlank(rows[index]) || options[index] != nil {
                    break
                } else {
                    gap += 1
                }
                index += step
            }
        }
        extend(from: target, step: -1)
        extend(from: target, step: 1)
        menu.sort { $0.number < $1.number }
        let highlighted = menu.filter(\.isHighlighted)
        guard menu.count > 1, highlighted.count == 1, let current = highlighted.first else { return nil }
        return target.number - current.number
    }

    private static func parse(_ line: String, row: Int) -> Option? {
        let content = line.trimmingCharacters(in: frame)
        let range = NSRange(content.startIndex..., in: content)
        guard let match = option.firstMatch(in: content, range: range),
              let numberRange = Range(match.range(at: 2), in: content), let number = Int(content[numberRange]),
              let lineRange = line.range(of: content) else { return nil }
        let column = line.distance(from: line.startIndex, to: lineRange.lowerBound)
            + content.distance(from: content.startIndex, to: numberRange.lowerBound)
        return Option(row: row, number: number, column: column, isHighlighted: match.range(at: 1).location != NSNotFound)
    }

    private static func indentation(_ line: String) -> Int {
        line.prefix { $0 == " " || "│┃║|".contains($0) }.count
    }

    private static func isBlank(_ line: String) -> Bool { line.trimmingCharacters(in: frame).isEmpty }
}
