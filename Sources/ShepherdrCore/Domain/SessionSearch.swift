import Foundation

/// Finds a session from a few letters of it, as you type: names that start with them first, then
/// names with a word that does, then names containing them, then sessions whose machine, folder
/// or task match. `@` narrows to a machine, as in `api@build`.
public enum SessionSearch {
    /// The sessions matching every word typed, best first; ties keep the order given.
    public static func ranked(_ rows: [AgentRow], matching query: String) -> [AgentRow] {
        let (text, machine) = split(query)
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty || machine != nil else { return rows }
        return rows.enumerated()
            .compactMap { index, row -> (score: Int, index: Int, row: AgentRow)? in
                if let machine, !row.machineName.localizedStandardContains(machine) { return nil }
                guard words.allSatisfy(row.matches) else { return nil }
                return (score(of: row, for: text), index, row)
            }
            .sorted { ($0.score, $0.index) < ($1.score, $1.index) }
            .map(\.row)
    }

    /// What was typed, as words that must each match somewhere and the machine after an `@`.
    public static func terms(of query: String) -> (words: [String], machine: String?) {
        let (text, machine) = split(query)
        return (text.split(whereSeparator: \.isWhitespace).map(String.init), machine)
    }

    /// Whether a word typed names one of a session's pull requests or issues. A number, as in
    /// `theam/shepherdr#12`, `shepherdr#12` or `#12`, names exactly that one, never `#123`; other words
    /// match any part of its name or title.
    public static func matches(_ resource: SessionResource, word: String) -> Bool {
        let name = resource.name.lowercased(), word = word.lowercased()
        if let mark = word.lastIndex(of: "#"), !word[word.index(after: mark)...].isEmpty,
           word[word.index(after: mark)...].allSatisfy(\.isNumber) {
            return name == word || name.hasSuffix("/" + word) || (word.hasPrefix("#") && name.hasSuffix(word))
        }
        return name.localizedStandardContains(word) || (resource.title?.localizedStandardContains(word) ?? false)
    }

    /// The text before the last `@`, and the machine after it when one is typed.
    private static func split(_ query: String) -> (text: String, machine: String?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = trimmed.lastIndex(of: "@") else { return (trimmed, nil) }
        let machine = trimmed[trimmed.index(after: at)...].trimmingCharacters(in: .whitespaces)
        return (String(trimmed[..<at]).trimmingCharacters(in: .whitespaces), machine.isEmpty ? nil : machine)
    }

    /// 0 for a name typed in full, 1 for its start, 2 for the start of a word in it, 3 for any part
    /// of it, 4 for a match elsewhere.
    private static func score(of row: AgentRow, for text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let names = [row.workspace, row.name]
        if names.contains(where: { $0.compare(text, options: options) == .orderedSame }) { return 0 }
        if names.contains(where: { $0.range(of: text, options: options.union(.anchored)) != nil }) { return 1 }
        let words = names.flatMap { $0.split { !$0.isLetter && !$0.isNumber } }
        if words.contains(where: { $0.range(of: text, options: options.union(.anchored)) != nil }) { return 2 }
        if names.contains(where: { $0.localizedStandardContains(text) }) { return 3 }
        return 4
    }
}
