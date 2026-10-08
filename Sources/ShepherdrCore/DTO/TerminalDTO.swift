import Foundation

enum TerminalJSON {
    private struct Record: Decodable {
        let type: String
        let encoding: String?
        let bytes: String?
        let width: Int?
        let height: Int?
        let full: Bool?
        let reason: String?
    }

    static func event(_ data: Data) throws -> TerminalEvent? {
        let record = try JSONDecoder().decode(Record.self, from: data)
        switch record.type {
        case "terminal.frame":
            guard record.encoding == "ansi", let encoded = record.bytes,
                  let bytes = Data(base64Encoded: encoded),
                  let width = record.width, (1...1_000).contains(width),
                  let height = record.height, (1...1_000).contains(height), let full = record.full else {
                throw HerdrFailure(.incompatible, "Herdr sent an invalid terminal frame.")
            }
            return .frame(.init(bytes: bytes, columns: width, rows: height, isFull: full))
        case "terminal.closed": return .closed(record.reason ?? "Herdr closed the connection.")
        default: return nil // Ignore future record types; never interpret them as terminal bytes.
        }
    }

    static func command(_ input: TerminalInput) throws -> Data {
        let object: [String: Any]
        switch input {
        case .bytes(let bytes): object = ["type": "terminal.input", "bytes": bytes.base64EncodedString()]
        case .resize(let size): object = ["type": "terminal.resize", "cols": size.columns, "rows": size.rows]
        case .scroll(let up, let lines):
            object = ["type": "terminal.scroll", "direction": up ? "up" : "down", "lines": min(500, max(1, lines))]
        case .mouse(let pressed, let column, let row):
            object = ["type": "terminal.mouse", "action": pressed ? "down" : "up", "button": "left",
                      "column": max(0, column), "row": max(0, row)]
        case .release: object = ["type": "terminal.release"]
        case .pause: throw HerdrFailure(.incompatible, "A local pause is not a terminal command.")
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) + Data([10])
    }
}
