import Foundation
import JavaScriptCore

/// Renders Markdown files as pages for the session browser: GitHub-flavored, with the bundled
/// marked running in JavaScriptCore, in the console's colors. The page itself needs no script.
@MainActor
public enum MarkdownRenderer {
    private static let parse: JSValue? = {
        guard let url = Bundle.module.url(forResource: "marked.umd", withExtension: "js", subdirectory: "Markdown"),
              let source = try? String(contentsOf: url, encoding: .utf8), let context = JSContext() else { return nil }
        context.evaluateScript(source)
        return context.evaluateScript("(function (text) { return marked.parse(text, { gfm: true }); })")
    }()

    nonisolated public static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    /// A complete HTML page for `markdown`, titled with the file's name and showing its path.
    public static func page(markdown: String, file: URL) -> String {
        let rendered = parse?.call(withArguments: [markdown])?.toString() ?? "<pre>\(escaped(markdown))</pre>"
        let body = embeddingImages(in: rendered, relativeTo: file.deletingLastPathComponent())
        let path = (file.path as NSString).abbreviatingWithTildeInPath
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <title>\(escaped(file.lastPathComponent))</title><style>\(style)</style></head>
        <body><div class="path">\(escaped(path))</div><article>\(body)</article></body></html>
        """
    }

    private static let image = try! NSRegularExpression(pattern: #"(<img\b[^>]*?\bsrc=")([^"]+)(")"#, options: [.caseInsensitive])
    private static let imageTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                                     "svg": "image/svg+xml", "webp": "image/webp"]

    /// Local images go into the page itself: the browser may not read files next to the Markdown.
    static func embeddingImages(in html: String, relativeTo folder: URL) -> String {
        var result = html
        for match in image.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed() {
            guard let range = Range(match.range(at: 2), in: html) else { continue }
            let source = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            guard !source.contains("://") || source.hasPrefix("file://"), !source.hasPrefix("data:") else { continue }
            let file = source.hasPrefix("file://") ? URL(string: source)
                : URL(string: source.removingPercentEncoding.map { $0.hasPrefix("/") ? $0 : folder.appendingPathComponent($0).path } ?? "",
                      relativeTo: nil).map { URL(fileURLWithPath: $0.path) }
            guard let file, let type = imageTypes[file.pathExtension.lowercased()],
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000,
                  let data = try? Data(contentsOf: file),
                  let target = Range(match.range(at: 2), in: result) else { continue }
            result.replaceSubrange(target, with: "data:\(type);base64,\(data.base64EncodedString())")
        }
        return result
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let style = """
    :root { color-scheme: dark; }
    body { background: #090C0A; color: #D9E7DE; margin: 0 auto; max-width: 880px; padding: 20px 40px 64px;
           font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    .path { font: 11px "SF Mono", Menlo, monospace; color: #4B5E53; padding-bottom: 10px;
            border-bottom: 1px solid #1F2B25; margin-bottom: 8px; word-break: break-all; }
    h1, h2, h3, h4, h5, h6 { color: #F2FFF7; line-height: 1.25; margin: 1.5em 0 0.6em; }
    h1 { font-size: 1.9em; padding-bottom: 0.3em; border-bottom: 1px solid #1F2B25; }
    h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid #1F2B25; }
    a { color: #4DFFA0; text-decoration: none; } a:hover { text-decoration: underline; }
    code, pre, kbd { font-family: "SF Mono", Menlo, monospace; font-size: 0.86em; }
    code { background: #141B17; padding: 0.15em 0.4em; border-radius: 4px; }
    pre { background: #0E1310; border: 1px solid #1F2B25; border-radius: 6px; padding: 14px 16px; overflow: auto; line-height: 1.45; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 0; padding: 0 1em; color: #7E9488; border-left: 3px solid #4B5E53; }
    table { border-collapse: collapse; display: block; overflow: auto; }
    th, td { border: 1px solid #1F2B25; padding: 6px 12px; } th { background: #0E1310; }
    hr { border: 0; border-top: 1px solid #1F2B25; margin: 24px 0; }
    img { max-width: 100%; } ul, ol { padding-left: 2em; } li + li { margin-top: 0.25em; }
    input[type=checkbox] { margin: 0 0.5em 0 -1.4em; accent-color: #4DFFA0; }
    """
}
