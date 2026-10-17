import Foundation

/// A version as releases are tagged, `v0.8.6` or `0.8.6`, compared number by number.
public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let parts: [Int]

    public init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...4).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

/// A published release of Shepherdr, with the ZIP the updater installs and the checksums it checks.
public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    /// Its page on GitHub, with the release notes.
    public let page: URL
    public let zip: URL
    public let checksums: URL

    public init(version: AppVersion, page: URL, zip: URL, checksums: URL) {
        self.version = version
        self.page = page
        self.zip = zip
        self.checksums = checksums
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.version == rhs.version && lhs.zip == rhs.zip }

    /// Reads GitHub's answer for a release. Nil for a draft, a prerelease, or one without the
    /// Apple Silicon ZIP and its checksums, as the release workflow names them.
    public static func parse(_ data: Data) -> AppRelease? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]
        }
        guard let release = try? JSONDecoder().decode(Release.self, from: data), release.draft != true, release.prerelease != true,
              let version = AppVersion(release.tag_name),
              let zip = release.assets.first(where: { $0.name == "Shepherdr-\(version)-macos-arm64.zip" }),
              let checksums = release.assets.first(where: { $0.name == "SHA256SUMS" }),
              [zip.browser_download_url, checksums.browser_download_url].allSatisfy({ $0.scheme == "https" }) else { return nil }
        return AppRelease(version: version, page: release.html_url, zip: zip.browser_download_url,
                          checksums: checksums.browser_download_url)
    }
}

/// When Shepherdr looks for a new release: once a day.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        // A clock set back counts as a day gone by.
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }
}

/// How an update the updater script installed went, as it left it in its status file:
/// `updated 0.8.7` or `failed <why>`.
public enum UpdateOutcome: Equatable, Sendable {
    case updated(AppVersion)
    case failed(String)

    public init?(status: String) {
        let line = status.split(separator: "\n").first.map(String.init) ?? ""
        if line.hasPrefix("updated "), let version = AppVersion(String(line.dropFirst("updated ".count))) {
            self = .updated(version)
        } else if line.hasPrefix("failed "), line.count > 7 {
            self = .failed(String(line.dropFirst("failed ".count)))
        } else {
            return nil
        }
    }
}
