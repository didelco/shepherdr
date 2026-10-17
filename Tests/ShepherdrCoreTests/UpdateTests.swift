import Foundation
import Testing
@testable import ShepherdrCore

struct UpdateTests {
    @Test func versionsCompareNumberByNumber() throws {
        let v = { (text: String) in try #require(AppVersion(text)) }
        #expect(try v("v0.8.6") == v("0.8.6"))
        #expect(try v("0.8.6") < v("0.8.10"))
        #expect(try v("0.8.6") < v("0.9"))
        #expect(try v("0.9") == v("0.9.0"))
        #expect(try v("1.0.0") > v("0.99.99"))
        #expect(try v("0.8.6").description == "0.8.6")
        for text in ["", "v", "0.8.x", "0..1", "-1.0", "0.8.6-beta", "1.2.3.4.5"] { #expect(AppVersion(text) == nil, "\(text)") }
    }

    private func release(tag: String = "v0.8.7", draft: Bool = false, prerelease: Bool = false,
                         zip: String = "Shepherdr-0.8.7-macos-arm64.zip", scheme: String = "https") -> Data {
        let base = "\(scheme)://github.com/theam/shepherdr/releases/download/\(tag)"
        return Data("""
        {"tag_name":"\(tag)","html_url":"https://github.com/theam/shepherdr/releases/tag/\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "assets":[{"name":"\(zip)","browser_download_url":"\(base)/\(zip)"},
                   {"name":"Shepherdr-0.8.7-macos-arm64.dmg","browser_download_url":"\(base)/Shepherdr-0.8.7-macos-arm64.dmg"},
                   {"name":"SHA256SUMS","browser_download_url":"\(base)/SHA256SUMS"}]}
        """.utf8)
    }

    @Test func aReleaseNeedsItsZipAndChecksums() throws {
        let found = try #require(AppRelease.parse(release()))
        #expect(found.version.description == "0.8.7")
        #expect(found.zip.lastPathComponent == "Shepherdr-0.8.7-macos-arm64.zip")
        #expect(found.checksums.lastPathComponent == "SHA256SUMS")
        #expect(found.page.absoluteString == "https://github.com/theam/shepherdr/releases/tag/v0.8.7")
        #expect(AppRelease.parse(release(draft: true)) == nil)
        #expect(AppRelease.parse(release(prerelease: true)) == nil)
        #expect(AppRelease.parse(release(zip: "Shepherdr-0.8.6-macos-arm64.zip")) == nil)
        #expect(AppRelease.parse(release(scheme: "http")) == nil)
        #expect(AppRelease.parse(release(tag: "nightly")) == nil)
        #expect(AppRelease.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    }

    @Test func shepherdrLooksOnceADay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(UpdateSchedule.isDue(lastCheck: nil, now: now))
        #expect(!UpdateSchedule.isDue(lastCheck: now - 23 * 3_600, now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now - 24 * 3_600, now: now))
        #expect(UpdateSchedule.isDue(lastCheck: now + 60, now: now))
    }

    @Test func theStatusFileSaysHowTheUpdateWent() {
        #expect(UpdateOutcome(status: "updated 0.8.7\n") == .updated(AppVersion("0.8.7")!))
        #expect(UpdateOutcome(status: "failed Couldn't move the old app aside.\n") == .failed("Couldn't move the old app aside."))
        #expect(UpdateOutcome(status: "failed ") == nil)
        #expect(UpdateOutcome(status: "") == nil)
        #expect(UpdateOutcome(status: "updated soon") == nil)
    }

    @Test func theUpdaterShipsWithTheApp() {
        #expect(Updater.script.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }
}

/// Runs the updater script against a release made here: a ZIP of a small app signed ad hoc, and
/// its checksums, served from file URLs. The happy path needs a Developer ID release; see
/// docs/DEVELOPMENT.md for checking against a real one.
struct UpdaterScriptTests {
    private struct Release {
        let folder: URL
        let app: URL
        let zip: URL
        let sums: URL
    }

    private func makeRelease(version: String = "0.8.7", sumsFor listed: String? = nil, corrupt: Bool = false) throws -> Release {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-updater-\(UUID().uuidString)")
        let built = folder.appendingPathComponent("build/Shepherdr.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>com.theagilemonkeys.Shepherdr</string>
        <key>CFBundleShortVersionString</key><string>\(version)</string>
        <key>CFBundleExecutable</key><string>Shepherdr</string>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: built.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: built.appendingPathComponent("Shepherdr"))
        let app = folder.appendingPathComponent("build/Shepherdr.app")
        try run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        let name = "Shepherdr-\(version)-macos-arm64.zip"
        let zip = folder.appendingPathComponent(name)
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
        var digest = try run("/usr/bin/shasum", ["-a", "256", zip.path]).split(separator: " ").first.map(String.init) ?? ""
        if corrupt { digest = String(repeating: "0", count: 64) }
        let sums = folder.appendingPathComponent("SHA256SUMS")
        try Data("\(digest)  \(listed ?? name)\n".utf8).write(to: sums)
        let installed = folder.appendingPathComponent("Applications/Shepherdr.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        return Release(folder: folder, app: installed, zip: zip, sums: sums)
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// The script's last progress line.
    private func update(_ release: Release, team: String = "ABCDE12345", zip: String? = nil) throws -> String {
        let script = try #require(Updater.script)
        let output = try run("/bin/sh", [script.path, "--app", release.app.path, "--version", "0.8.7", "--team", team,
                                         "--bundle-id", "com.theagilemonkeys.Shepherdr", "--zip", zip ?? release.zip.absoluteString,
                                         "--sums", release.sums.absoluteString, "--check-only"])
        return output.split(separator: "\n").last.map(String.init) ?? ""
    }

    @Test func anAppSignedAdHocIsNeverInstalled() throws {
        let release = try makeRelease()
        defer { try? FileManager.default.removeItem(at: release.folder) }
        #expect(try update(release) == "shepherdr-update failed The new app isn't signed by the same team as this one.")
    }

    @Test func aDownloadThatDoesntMatchItsChecksumIsRefused() throws {
        let corrupt = try makeRelease(corrupt: true)
        defer { try? FileManager.default.removeItem(at: corrupt.folder) }
        #expect(try update(corrupt) == "shepherdr-update failed Shepherdr-0.8.7-macos-arm64.zip doesn't match the release's checksum.")
        let unlisted = try makeRelease(sumsFor: "Shepherdr-0.8.7-macos-arm64.dmg")
        defer { try? FileManager.default.removeItem(at: unlisted.folder) }
        #expect(try update(unlisted) == "shepherdr-update failed The release's checksums don't list Shepherdr-0.8.7-macos-arm64.zip.")
    }

    @Test func onlyDeveloperIDAppsOverHTTPSAreUpdated() throws {
        let release = try makeRelease()
        defer { try? FileManager.default.removeItem(at: release.folder) }
        #expect(try update(release, team: "") == "shepherdr-update failed Only an app signed with a Developer ID can update itself.")
        #expect(try update(release, zip: "http://example.com/Shepherdr-0.8.7-macos-arm64.zip")
                == "shepherdr-update failed The download must come over HTTPS.")
        #expect(FileManager.default.fileExists(atPath: release.app.path))
    }
}

/// Installs the published 0.8.6 over a downloaded 0.8.5 in a scratch folder, the way Shepherdr
/// does, except that nothing opens. It needs the network and GitHub, so it only runs when asked:
///   SHEPHERDR_LIVE_UPDATE_TEST=1 swift test --filter LiveUpdateTests
struct LiveUpdateTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SHEPHERDR_LIVE_UPDATE_TEST"] != nil))
    func aReleaseReplacesTheAppOnceItQuits() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shepherdr-live-update-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let applications = folder.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let base = "https://github.com/theam/shepherdr/releases/download"
        let (old, _) = try await URLSession.shared.download(from: URL(string: "\(base)/v0.8.5/Shepherdr-0.8.5-macos-arm64.zip")!)
        try shell("/usr/bin/ditto", "-x", "-k", old.path, applications.path)
        let app = applications.appendingPathComponent("Shepherdr.app")
        // The team that signed the old app, as Shepherdr reads its own.
        let team = try #require(shell("/usr/bin/codesign", "-dv", app.path).split(separator: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }.map { String($0.dropFirst("TeamIdentifier=".count)) })

        let release = AppRelease(version: AppVersion("0.8.6")!, page: URL(string: "https://github.com/theam/shepherdr/releases/tag/v0.8.6")!,
                                 zip: URL(string: "\(base)/v0.8.6/Shepherdr-0.8.6-macos-arm64.zip")!,
                                 checksums: URL(string: "\(base)/v0.8.6/SHA256SUMS")!)
        // Stands in for the running app: the script waits for it to quit.
        let running = Process()
        running.executableURL = URL(fileURLWithPath: "/bin/sleep")
        running.arguments = ["120"]
        try running.run()
        let status = folder.appendingPathComponent("status")
        let stages = Stages()
        try await Updater.install(release, over: app, team: team, bundleID: "com.theagilemonkeys.Shepherdr", status: status,
                                  pid: running.processIdentifier, relaunch: false) { stages.append($0) }
        #expect(stages.all == [.downloading, .verifying])
        // Not replaced while it runs.
        try await Task.sleep(for: .seconds(1))
        #expect(!FileManager.default.fileExists(atPath: status.path))
        running.terminate()
        for _ in 0..<40 where !FileManager.default.fileExists(atPath: status.path) { try await Task.sleep(for: .milliseconds(250)) }
        #expect(try String(contentsOf: status, encoding: .utf8) == "updated 0.8.6\n")
        let info = try #require(NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")))
        #expect(info["CFBundleShortVersionString"] as? String == "0.8.6")
    }

    @discardableResult
    private func shell(_ executable: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private final class Stages: @unchecked Sendable {
        private let lock = NSLock()
        private var stages: [Updater.Stage] = []
        var all: [Updater.Stage] { lock.withLock { stages } }
        func append(_ stage: Updater.Stage) { lock.withLock { stages.append(stage) } }
    }
}
