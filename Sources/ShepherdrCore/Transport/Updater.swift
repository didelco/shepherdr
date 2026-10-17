import Foundation
import Security

/// Looks for new releases on GitHub, and installs one with the updater script that ships in the
/// app: it checks the download, waits for this app to quit, swaps the apps and opens the new one.
public enum Updater {
    public static let latestRelease = URL(string: "https://api.github.com/repos/theam/shepherdr/releases/latest")!

    /// The latest published release; nil when GitHub doesn't answer.
    public static func latest(from url: URL = latestRelease) async -> AppRelease? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return AppRelease.parse(data)
    }

    /// The Apple team that signed the running app; nil for a local build, signed ad hoc or not at
    /// all. Updates must come from the same team.
    public static func signingTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// The updater script, as bundled.
    public static var script: URL? { Bundle.module.url(forResource: "update", withExtension: "sh", subdirectory: "Updater") }

    public enum Stage: String, Sendable {
        case downloading, verifying
    }

    public struct Failure: LocalizedError, Equatable, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// Runs the updater script for a release and returns once it has checked the new app and waits
    /// for this one to quit, which is the caller's to do next. `progress` hears what it is doing.
    /// - Parameter relaunch: whether the script opens the new app; tests leave it closed.
    public static func install(_ release: AppRelease, over app: URL, team: String, bundleID: String, status: URL,
                               pid: Int32, relaunch: Bool = true, progress: @escaping @Sendable (Stage) -> Void) async throws {
        guard let script else { throw Failure(message: "The updater is missing from this app.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "--app", app.path, "--version", release.version.description, "--team", team,
                             "--bundle-id", bundleID, "--zip", release.zip.absoluteString,
                             "--sums", release.checksums.absoluteString, "--status", status.path, "--pid", String(pid)]
            + (relaunch ? [] : ["--no-relaunch"])
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? FileManager.default.removeItem(at: status)
        try FileManager.default.createDirectory(at: status.deletingLastPathComponent(), withIntermediateDirectories: true)
        try process.run()
        // The script outlives this app: it only reports until it is ready.
        for try await line in output.fileHandleForReading.bytes.lines {
            guard line.hasPrefix("shepherdr-update ") else { continue }
            let word = line.dropFirst("shepherdr-update ".count)
            if word == "ready" { return }
            if word.hasPrefix("failed ") { throw Failure(message: String(word.dropFirst("failed ".count))) }
            if let stage = Stage(rawValue: String(word)) { progress(stage) }
        }
        throw Failure(message: "The updater stopped without saying why.")
    }
}
