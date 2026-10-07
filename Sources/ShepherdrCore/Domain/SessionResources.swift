import Foundation

/// A link worth keeping at hand while a session works: a pull request, an issue or a Claude artifact.
public struct SessionResource: Identifiable, Hashable, Codable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case pullRequest, issue, artifact

        public var title: String {
            switch self {
            case .pullRequest: "Pull requests"
            case .issue: "Issues"
            case .artifact: "Claude artifacts"
            }
        }
    }

    /// The canonical link: a pull request's own page rather than its files tab, without anchors.
    public let url: URL
    public let kind: Kind
    /// A short name such as `theam/shepherdr#12`, `ENG-42` or `artifact 3f450b55`.
    public let name: String
    public var id: URL { url }

    public init(url: URL, kind: Kind, name: String) {
        self.url = url
        self.kind = kind
        self.name = name
    }

    /// Recognizes the links worth keeping: GitHub, GitLab and Bitbucket pull requests and issues,
    /// Linear and Jira issues, and Claude artifacts. Any other link is nil.
    public init?(url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host()?.lowercased() else { return nil }
        let path = url.path().split(separator: "/").map(String.init)
        func canonical(_ components: ArraySlice<String>) -> URL? {
            URL(string: "\(scheme)://\(host)/\(components.joined(separator: "/"))")
        }
        func isNumber(_ text: String) -> Bool { !text.isEmpty && text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber) }
        func isIssueKey(_ text: String) -> Bool { text.range(of: #"^[A-Za-z][A-Za-z0-9]*-[0-9]+$"#, options: .regularExpression) != nil }

        if host == "claude.ai" {
            let prefix: [String]? = path.starts(with: ["code", "artifact"]) ? ["code", "artifact"]
                : path.starts(with: ["public", "artifacts"]) ? ["public", "artifacts"]
                : path.starts(with: ["artifact"]) ? ["artifact"] : nil
            guard let prefix, path.count > prefix.count, let link = canonical(path[...prefix.count]) else { return nil }
            self.init(url: link, kind: .artifact, name: "artifact \(path[prefix.count].prefix(8))")
        } else if host == "github.com" || host == "bitbucket.org", path.count >= 4, isNumber(path[3]),
                  let kind: Kind = ["pull", "pull-requests"].contains(path[2]) ? .pullRequest : path[2] == "issues" ? .issue : nil,
                  let link = canonical(path[...3]) {
            self.init(url: link, kind: kind, name: "\(path[0])/\(path[1])#\(path[3])")
        } else if host == "linear.app", path.count >= 3, path[1] == "issue", isIssueKey(path[2]), let link = canonical(path[...2]) {
            self.init(url: link, kind: .issue, name: path[2].uppercased())
        } else if host.hasSuffix(".atlassian.net"), path.count >= 2, path[0] == "browse", isIssueKey(path[1]),
                  let link = canonical(path[...1]) {
            self.init(url: link, kind: .issue, name: path[1].uppercased())
        } else if let dash = path.firstIndex(of: "-"), dash > 0, path.count > dash + 2, isNumber(path[dash + 2]),
                  let kind: Kind = path[dash + 1] == "merge_requests" ? .pullRequest : path[dash + 1] == "issues" ? .issue : nil,
                  let link = canonical(path[...(dash + 2)]) {
            // GitLab, on gitlab.com or a company's own host.
            let project = path[..<dash].joined(separator: "/")
            self.init(url: link, kind: kind, name: "\(project)\(kind == .pullRequest ? "!" : "#")\(path[dash + 2])")
        } else {
            return nil
        }
    }
}

public enum SessionResources {
    /// The resources linked in plain text, in order of appearance, each once.
    public static func find(in text: String) -> [SessionResource] {
        let range = NSRange(text.startIndex..., in: text)
        let urls = TerminalLinks.pattern.matches(in: text, range: range).compactMap { match in
            Range(match.range, in: text).flatMap { URL(string: TerminalLinks.trimmed(String(text[$0]))) }
        }
        return unique(urls.compactMap(SessionResource.init(url:)))
    }

    /// The resources linked on a terminal screen, including links that wrap across rows.
    public static func find(onScreen rows: [[Character]]) -> [SessionResource] {
        unique(TerminalLinks.urls(in: rows).compactMap(SessionResource.init(url:)))
    }

    /// Adds newly found resources in front of the known ones, newest first; known ones keep their place.
    public static func merge(_ found: [SessionResource], into known: [SessionResource], limit: Int = 100) -> [SessionResource] {
        let fresh = found.filter { new in !known.contains { $0.url == new.url } }
        return Array((fresh.reversed() + known).prefix(limit))
    }

    private static func unique(_ resources: [SessionResource]) -> [SessionResource] {
        var seen = Set<URL>()
        return resources.filter { seen.insert($0.url).inserted }
    }
}
