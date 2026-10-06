import Foundation

/// Finds plain-text web links on a terminal screen, so they open like the explicit
/// hyperlinks some agents emit.
public enum TerminalLinks {
    /// Characters RFC 3986 allows in a URL. Box drawing and other decoration end a link.
    private static let urlCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
    private static let pattern = try! NSRegularExpression(
        pattern: #"https?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#, options: [.caseInsensitive])
    /// Lines a wrapped link may span in either direction from the clicked one.
    private static let wrapLimit = 8

    /// The web link at a cell, if any.
    /// - Parameter rows: the screen, one character per column. A row whose last column holds a
    ///   URL character continues on the next row when that one starts with a URL character too,
    ///   which is how long links wrap.
    public static func url(in rows: [[Character]], row: Int, column: Int) -> URL? {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return nil }
        func continues(_ upper: Int) -> Bool {
            guard let last = rows[upper].last, let first = rows[upper + 1].first else { return false }
            return isURLCharacter(last) && isURLCharacter(first)
        }
        var first = row, last = row
        while first > 0, row - first < wrapLimit, continues(first - 1) { first -= 1 }
        while last < rows.count - 1, last - row < wrapLimit, continues(last) { last += 1 }

        var text = ""
        var clicked = 0
        for index in first...last {
            if index == row { clicked = text.utf16.count + String(rows[index][..<column]).utf16.count }
            text += String(rows[index])
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.matches(in: text, range: range).first(where: { NSLocationInRange(clicked, $0.range) }),
              let matched = Range(match.range, in: text) else { return nil }
        let link = trimmed(String(text[matched]))
        // Clicking punctuation that follows a link, like a closing period, is not clicking the link.
        guard clicked < match.range.location + link.utf16.count,
              let url = URL(string: link), url.host?.isEmpty == false else { return nil }
        return url
    }

    private static func isURLCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.count == 1 && urlCharacters.contains(character.unicodeScalars.first!)
    }

    /// Drops sentence punctuation and unbalanced closing brackets that prose wraps around links.
    private static func trimmed(_ link: String) -> String {
        var link = link
        while let last = link.last {
            if ".,;:!?'\"*".contains(last) {
                link.removeLast()
            } else if last == ")", link.filter({ $0 == "(" }).count < link.filter({ $0 == ")" }).count {
                link.removeLast()
            } else if last == "]", link.filter({ $0 == "[" }).count < link.filter({ $0 == "]" }).count {
                link.removeLast()
            } else {
                break
            }
        }
        return link
    }
}
