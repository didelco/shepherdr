import Foundation

/// Finds file paths agents print, such as `docs/GUIDE.md` or `App/Theme.swift:23`, so a click can open them.
public enum TerminalPaths {
    /// Letters, digits and the punctuation paths use; quotes, brackets and box drawing end a path.
    private static let pathCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-/~+@%=:"))

    /// The path written at a cell: a word with a slash or a file extension, without the punctuation
    /// around it or a trailing `:line:column`. Whether that file exists is the caller's question.
    /// The path at a cell of a screen. A row whose last column holds a path character continues on
    /// the next row when that one starts with one, which is how long paths wrap.
    public static func path(in rows: [[Character]], row: Int, column: Int) -> String? {
        guard rows.indices.contains(row) else { return nil }
        func continues(_ upper: Int) -> Bool {
            guard let last = rows[upper].last, let first = rows[upper + 1].first else { return false }
            return isPathCharacter(last) && isPathCharacter(first)
        }
        var first = row, last = row
        while first > 0, row - first < 4, continues(first - 1) { first -= 1 }
        while last < rows.count - 1, last - row < 4, continues(last) { last += 1 }
        let offset = rows[first..<row].reduce(0) { $0 + $1.count }
        return path(in: Array(rows[first...last].joined()), column: offset + column)
    }

    public static func path(in row: [Character], column: Int) -> String? {
        guard row.indices.contains(column), isPathCharacter(row[column]) else { return nil }
        var start = column, end = column
        while start > 0, isPathCharacter(row[start - 1]) { start -= 1 }
        while end < row.count - 1, isPathCharacter(row[end + 1]) { end += 1 }
        var word = String(row[start...end])
        guard !word.contains("://") else { return nil }
        // A trailing `:12` or `:12:5` names a line in the file.
        if let suffix = word.range(of: #"(:[0-9]+){1,2}:?$"#, options: .regularExpression) { word.removeSubrange(suffix) }
        while let last = word.last, ".:".contains(last), word != "." { word.removeLast() }
        while let first = word.first, first == ":" { word.removeFirst() }
        guard word.contains("/") || hasExtension(word), word.contains(where: \.isLetter) else { return nil }
        return word
    }

    private static func hasExtension(_ word: String) -> Bool {
        // A version such as 0.9.3 has a number where a file has an extension.
        word.range(of: #"[^./]\.[A-Za-z0-9]*[A-Za-z][A-Za-z0-9]*$"#, options: .regularExpression) != nil
    }

    private static func isPathCharacter(_ character: Character) -> Bool {
        String(character).rangeOfCharacter(from: pathCharacters.inverted) == nil
    }
}
