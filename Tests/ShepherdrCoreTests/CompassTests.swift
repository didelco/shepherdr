import CryptoKit
import Foundation
import Testing
@testable import ShepherdrCore

/// Calendar dates in a fixed time zone, so the tests read like the schedule.
private struct Clock {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Atlantic/Canary")!
        return calendar
    }()

    /// `2026-10-15 14:40`. The 15th of October 2026 is a Thursday.
    func at(_ text: String) -> Date {
        let parts = text.split(whereSeparator: { "- :".contains($0) }).map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2],
                                                  hour: parts[3], minute: parts[4]))!
    }
}

@Suite struct CompassScheduleTests {
    private let clock = Clock()
    private let hourly = CompassSchedule(kind: .interval, every: 60, from: ClockTime(hour: 8), to: ClockTime(hour: 18))

    @Test func timesOfDayReadBothWays() {
        #expect(ClockTime("9:30")?.minutes == 570)
        #expect(ClockTime("09:30")?.description == "09:30")
        for bad in ["24:00", "9:3", "930", "a:bc", "", "-1:00"] { #expect(ClockTime(bad) == nil, "\(bad)") }
    }

    @Test func weekdaysFollowTheCalendar() {
        #expect(Weekday(calendarWeekday: 1) == .sun)
        #expect(Weekday(calendarWeekday: 2) == .mon)
        #expect(Weekday(calendarWeekday: 7) == .sat)
        #expect(clock.calendar.component(.weekday, from: clock.at("2026-10-15 12:00")) == 5)
    }

    @Test func anIntervalRunsFromItsFirstToItsLastHour() {
        let slots = hourly.slots(onDayOf: clock.at("2026-10-15 12:00"), calendar: clock.calendar)
        #expect(slots.count == 11)
        #expect(slots.first == clock.at("2026-10-15 08:00"))
        #expect(slots.last == clock.at("2026-10-15 18:00"))
        #expect(hourly.slots(onDayOf: clock.at("2026-10-17 12:00"), calendar: clock.calendar).isEmpty)
    }

    /// The Mac slept from 10:20 to 14:40: one run when it wakes, then the schedule goes on.
    @Test func missedRunsHappenOnceOnWaking() {
        let lastRun = clock.at("2026-10-15 10:00")
        #expect(hourly.dueSlot(at: clock.at("2026-10-15 14:40"), lastRun: lastRun, calendar: clock.calendar) == clock.at("2026-10-15 14:00"))
        // Having run at 14:40, nothing is due until 15:00.
        let woke = clock.at("2026-10-15 14:40")
        #expect(hourly.dueSlot(at: clock.at("2026-10-15 14:59"), lastRun: woke, calendar: clock.calendar) == nil)
        #expect(hourly.dueSlot(at: clock.at("2026-10-15 15:00"), lastRun: woke, calendar: clock.calendar) == clock.at("2026-10-15 15:00"))
        #expect(hourly.nextSlot(after: woke, calendar: clock.calendar) == clock.at("2026-10-15 15:00"))
    }

    @Test func aDailyRunMissedInTheMorningHappensWhenTheMacOpens() {
        let daily = CompassSchedule(kind: .daily, at: ClockTime(hour: 8, minute: 30))
        let yesterday = clock.at("2026-10-14 08:30")
        #expect(daily.dueSlot(at: clock.at("2026-10-15 10:15"), lastRun: yesterday, calendar: clock.calendar) == clock.at("2026-10-15 08:30"))
        #expect(daily.dueSlot(at: clock.at("2026-10-15 08:00"), lastRun: yesterday, calendar: clock.calendar) == nil)
    }

    @Test func aRunMissedOnAnotherDayIsNotMadeUp() {
        // Friday's 18:00 never ran; on Saturday nothing is due, and the next run is Monday's.
        let lastRun = clock.at("2026-10-16 17:00")
        #expect(hourly.dueSlot(at: clock.at("2026-10-17 10:00"), lastRun: lastRun, calendar: clock.calendar) == nil)
        #expect(hourly.nextSlot(after: clock.at("2026-10-17 10:00"), calendar: clock.calendar) == clock.at("2026-10-19 08:00"))
    }

    @Test func aRunMissedLateInTheDayHappensTheSameEvening() {
        let lastRun = clock.at("2026-10-15 17:00")
        #expect(hourly.dueSlot(at: clock.at("2026-10-15 21:00"), lastRun: lastRun, calendar: clock.calendar) == clock.at("2026-10-15 18:00"))
        #expect(hourly.isLastSlot(clock.at("2026-10-15 18:00"), calendar: clock.calendar))
        #expect(!hourly.isLastSlot(clock.at("2026-10-15 17:00"), calendar: clock.calendar))
    }

    @Test func aManualScheduleNeverComesDue() {
        let manual = CompassSchedule(kind: .manual)
        #expect(manual.dueSlot(at: clock.at("2026-10-15 12:00"), lastRun: nil, calendar: clock.calendar) == nil)
        #expect(manual.nextSlot(after: clock.at("2026-10-15 12:00"), calendar: clock.calendar) == nil)
        #expect(manual.summary == "only when you run it")
    }

    @Test func summariesReadLikeTheSettings() {
        #expect(hourly.summary == "every hour · 08:00–18:00 · mon–fri")
        #expect(CompassSchedule(kind: .daily, at: ClockTime(hour: 9), days: Weekday.allCases).summary == "daily at 09:00 · every day")
        #expect(CompassSchedule(kind: .interval, every: 30, days: [.mon, .wed]).summary == "every 30 min · 09:00–18:00 · mon, wed")
    }

    @Test func theFirstRunOfTheDayStartsItAndTheLastClosesIt() {
        let calendar = clock.calendar
        var run = CompassRun(kind: .update, trigger: .scheduled, slot: clock.at("2026-10-15 09:00"),
                             created: clock.at("2026-10-15 09:00"), day: "2026-10-15")
        run.outcome = .updated
        #expect(Compass.kind(for: clock.at("2026-10-16 08:00"), at: clock.at("2026-10-16 08:00"), runs: [run],
                             schedule: hourly, calendar: calendar) == .first)
        #expect(Compass.kind(for: clock.at("2026-10-15 12:00"), at: clock.at("2026-10-15 12:00"), runs: [run],
                             schedule: hourly, calendar: calendar) == .update)
        #expect(Compass.kind(for: clock.at("2026-10-15 18:00"), at: clock.at("2026-10-15 18:05"), runs: [run],
                             schedule: hourly, calendar: calendar) == .last)
        // A failed run didn't start the day.
        run.outcome = .failed
        #expect(Compass.kind(for: nil, at: clock.at("2026-10-15 12:00"), runs: [run], schedule: hourly, calendar: calendar) == .first)
    }

    @Test func theRunPromptSaysWhatKindOfRunItIsAndWhereToLook() {
        let run = CompassRun(kind: .update, trigger: .scheduled, slot: clock.at("2026-10-15 14:00"),
                             created: clock.at("2026-10-15 14:00"), day: "2026-10-15")
        let prompt = run.prompt(since: clock.at("2026-10-15 13:02"), calendar: clock.calendar, page: "days/2026-10-15.html")
        #expect(prompt == """
        Compass run · update · Thu 2026-10-15 14:00
        Since 13:02, when the last run finished.
        Follow prompt.md. Today's page is days/2026-10-15.html; context/run.json has the details of this run.
        """)
        let first = CompassRun(kind: .first, trigger: .manual, slot: nil, created: clock.at("2026-10-15 07:12"), day: "2026-10-15")
        #expect(first.prompt(since: clock.at("2026-10-14 18:03"), calendar: clock.calendar, page: "days/2026-10-15.html")
            .hasPrefix("Compass run · first of the day · Thu 2026-10-15 07:12 · asked for now\nFollow"))
    }
}

@Suite struct CompassConfigTests {
    @Test func theSettingsFileReadsWhatAnAgentWrites() throws {
        let json = #"{"agent":"codex","schedule":{"kind":"daily","at":"8:30","days":["mon","fri","xyz"]},"backup":"git@github.com:me/compass.git"}"#
        let config = try JSONDecoder().decode(CompassConfig.self, from: Data(json.utf8))
        #expect(config.enabled)
        #expect(config.agent == "codex")
        #expect(config.schedule.kind == .daily)
        #expect(config.schedule.at == ClockTime(hour: 8, minute: 30))
        #expect(config.schedule.days == [.mon, .fri])
        #expect(config.strip == CompassConfig.Strip())
        #expect(config.backup == "git@github.com:me/compass.git")
    }

    @Test func unreadableValuesFallBackInsteadOfStoppingCompass() throws {
        let json = #"{"enabled":"yes","agent":"rm -rf","schedule":{"kind":"sometimes","every":2,"from":"25:00"},"backup":"  "}"#
        let config = try JSONDecoder().decode(CompassConfig.self, from: Data(json.utf8))
        #expect(config.enabled)
        #expect(config.agent == "claude")
        #expect(config.schedule.kind == .interval)
        #expect(config.schedule.every == 10)
        #expect(config.schedule.from == ClockTime(hour: 9))
        #expect(config.backup == nil)
    }

    @Test func settingsWriteAndReadBack() throws {
        var config = CompassConfig()
        config.schedule = CompassSchedule(kind: .interval, every: 30, from: ClockTime(hour: 7), to: ClockTime(hour: 14), days: [.tue])
        config.strip = .init(from: ClockTime(hour: 7), to: ClockTime(hour: 15))
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(CompassConfig.self, from: data) == config)
        #expect(String(decoding: data, as: UTF8.self).contains(#""from":"07:00""#))
    }
}

@Suite struct CompassActionTests {
    @Test func aSessionToStartComesWithWhatItNeeds() {
        let action = CompassAction(["shepherdr": "spawn", "machine": "buildbox", "cwd": "~/src/api", "kind": "codex",
                                    "name": "fix-flaky", "prompt": "Fix the flaky test.\nThen hand back.", "item": "pr-41"])
        #expect(action == .spawn(.init(machine: "buildbox", directory: "~/src/api", agent: "codex", name: "fix-flaky",
                                       prompt: "Fix the flaky test.\nThen hand back."), item: "pr-41"))
        #expect(CompassAction(["shepherdr": "spawn"]) == .spawn(.init(machine: nil, directory: nil, agent: nil, name: nil, prompt: nil), item: nil))
    }

    @Test func valuesThatDontHoldUpAreRefused() {
        #expect(CompassAction(["shepherdr": "spawn", "name": "Bad Name"]) == nil)
        #expect(CompassAction(["shepherdr": "spawn", "kind": "bash"]) == nil)
        #expect(CompassAction(["shepherdr": "spawn", "cwd": "~/src\n/etc"]) == nil)
        #expect(CompassAction(["shepherdr": "spawn", "prompt": String(repeating: "x", count: CompassAction.promptLimit + 1)]) == nil)
        #expect(CompassAction(["shepherdr": "ask"]) == nil)
        #expect(CompassAction(["shepherdr": "ask", "prompt": "  "]) == nil)
        #expect(CompassAction(["shepherdr": "done"]) == nil)
        #expect(CompassAction(["shepherdr": "done", "item": "a b"]) == nil)
        #expect(CompassAction(["shepherdr": "run", "prompt": "x"]) == nil)
        #expect(CompassAction(["prompt": "x"]) == nil)
    }

    @Test func theOtherActionsReadTheirFields() {
        #expect(CompassAction(["shepherdr": "ask", "prompt": "Apply P1"]) == .ask("Apply P1"))
        #expect(CompassAction(["shepherdr": "session", "session": "api@buildbox"]) == .session("api@buildbox"))
        #expect(CompassAction(["shepherdr": "prompt", "session": "api", "prompt": "Rebase"]) == .prompt(session: "api", text: "Rebase"))
        #expect(CompassAction(["shepherdr": "done", "item": "pr-41"]) == .done(item: "pr-41"))
        // A shell needs no agent.
        #expect(CompassAction(["shepherdr": "spawn", "kind": "shell"]) == .spawn(.init(machine: nil, directory: nil, agent: "shell", name: nil, prompt: nil), item: nil))
    }
}

/// A scratch home with an empty Compass folder in it.
private struct ScratchCompass {
    let home: URL
    let folder: CompassFolder

    init() {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("compass-\(UUID().uuidString)").resolvingSymlinksInPath()
        folder = CompassFolder.standard(home: home)
    }

    func remove() { try? FileManager.default.removeItem(at: home) }

    func read(_ path: String) -> String? { try? String(contentsOf: folder.root.appendingPathComponent(path), encoding: .utf8) }

    func write(_ text: String, to path: String) throws {
        let url = folder.root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}

@Suite struct CompassFolderTests {
    private let kit = CompassFolder.Kit(version: 3, files: [
        "VERSION": "3\n", "AGENTS.md": "contract v3\n", "CLAUDE.md": "@AGENTS.md\n", "template.html": "<html>v3</html>\n",
        "prompt.md": "# Starter\n", "settings.json": #"{"allow":["Bash({{HOME}}/.shepherdr/bin/shepherdr status)"]}"#, "gitignore": "state.json\n",
    ])

    @Test func shepherdrCarriesTheCompassKit() throws {
        let kit = try CompassFolder.bundledKit()
        #expect(kit.version >= 1)
        #expect(kit.files["AGENTS.md"]?.contains("data-shepherdr") == true)
        #expect(kit.files["template.html"]?.contains("data-date=") == true)
        #expect(kit.files["CLAUDE.md"] == "@AGENTS.md\n")
    }

    /// Agents keep every Compass folder their contract describes, so the kit takes a new
    /// version whenever it changes. After bumping it, add the fingerprint this test prints.
    @Test func changingTheKitTakesANewVersion() throws {
        let fingerprints = [1: "68b639e11f263fa8"]
        let kit = try CompassFolder.bundledKit()
        var hash = SHA256()
        for name in kit.files.keys.sorted() where name != "VERSION" {
            hash.update(data: Data(name.utf8))
            hash.update(data: Data(kit.files[name]!.utf8))
        }
        let fingerprint = hash.finalize().map { String(format: "%02x", $0) }.joined().prefix(16)
        #expect(fingerprints[kit.version] == String(fingerprint),
                "The Compass kit doesn't match version \(kit.version)'s fingerprint. If you changed it, bump Compass/VERSION, then add the new version with \"\(fingerprint)\".")
    }

    @Test func preparingPutsEveryFileInItsPlace() throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        let written = try scratch.folder.prepare(kit, written: [:])
        #expect(scratch.read("AGENTS.md") == "contract v3\n")
        #expect(scratch.read("prompt.md") == "# Starter\n")
        #expect(scratch.read(".gitignore") == "state.json\n")
        #expect(scratch.read(".claude/settings.json")?.contains("Bash(\(scratch.home.path)/.shepherdr/bin/shepherdr status)") == true)
        #expect(scratch.read("compass.json").flatMap { try? JSONDecoder().decode(CompassConfig.self, from: Data($0.utf8)) } == CompassConfig())
        #expect(Set(written.keys) == ["AGENTS.md", "CLAUDE.md", "template.html", "prompt.md", ".claude/settings.json", ".gitignore"])
        let mode = try FileManager.default.attributesOfItem(atPath: scratch.folder.root.path)[.posixPermissions] as? Int
        #expect(mode == 0o700)
    }

    @Test func anUpdateRewritesShepherdrsFilesAndLeavesYoursAlone() throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        var written = try scratch.folder.prepare(kit, written: [:])
        try scratch.write("# Mine\n", to: "prompt.md")
        try scratch.write("<html>mine</html>\n", to: "template.html")
        try scratch.write("contract edited\n", to: "AGENTS.md")
        var config = CompassConfig()
        config.agent = "codex"
        try scratch.folder.writeConfig(config)
        #expect(scratch.folder.isCustomized("template.html", written: written))
        #expect(!scratch.folder.isCustomized(".gitignore", written: written))

        let next = CompassFolder.Kit(version: 4, files: kit.files.merging(["AGENTS.md": "contract v4\n", "template.html": "<html>v4</html>\n",
                                                                         "gitignore": "state.json\ncontext/\n", "prompt.md": "# Starter v4\n"]) { _, new in new })
        written = try scratch.folder.prepare(next, written: written)
        #expect(scratch.read("AGENTS.md") == "contract v4\n")
        #expect(scratch.read(".gitignore") == "state.json\ncontext/\n")
        #expect(scratch.read("prompt.md") == "# Mine\n")
        #expect(scratch.read("template.html") == "<html>mine</html>\n")
        #expect(scratch.folder.readConfig() == .read(config))

        // Putting the template back makes it Shepherdr's again.
        written["template.html"] = try scratch.folder.restore("template.html", from: next)
        #expect(scratch.read("template.html") == "<html>v4</html>\n")
        #expect(!scratch.folder.isCustomized("template.html", written: written))
    }

    @Test func aSettingsFileThatIsntJSONIsReportedNotReplaced() throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        try scratch.folder.prepare(kit, written: [:])
        try scratch.write("{ not json", to: "compass.json")
        guard case .unreadable = scratch.folder.readConfig() else { Issue.record("expected unreadable"); return }
        try scratch.folder.prepare(kit, written: [:])
        #expect(scratch.read("compass.json") == "{ not json")
    }

    @Test func pagesCopiesAndMarksLiveByDay() throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        try scratch.folder.prepare(kit, written: [:])
        #expect(try scratch.folder.snapshot("2026-10-15", at: "09-00") == nil)
        try scratch.write("<p>14th</p>", to: "days/2026-10-14.html")
        try scratch.write("<p>15th</p>", to: "days/2026-10-15.html")
        try scratch.write("notes", to: "days/notes.html")
        #expect(scratch.folder.days() == ["2026-10-15", "2026-10-14"])
        #expect(try scratch.folder.snapshot("2026-10-15", at: "09-00") == "days/2026-10-15/09-00.html")
        #expect(try scratch.folder.snapshot("2026-10-15", at: "09-00") == "days/2026-10-15/09-00-2.html")
        #expect(try scratch.folder.snapshot("2026-10-14", at: "18-00") == "days/2026-10-14/18-00.html")
        #expect(scratch.folder.snapshots("2026-10-15").map(\.time) == ["09-00", "09-00-2"])

        scratch.folder.pruneSnapshots(before: "2026-10-15")
        #expect(scratch.folder.snapshots("2026-10-14").isEmpty)
        #expect(scratch.folder.snapshots("2026-10-15").count == 2)
        #expect(scratch.folder.days() == ["2026-10-15", "2026-10-14"])

        var marks = CompassMarks()
        marks.done["pr-41"] = Date(timeIntervalSince1970: 1_792_000_000)
        marks.started["flaky"] = .init(session: "fix-flaky@buildbox", at: Date(timeIntervalSince1970: 1_792_000_100))
        try scratch.folder.writeMarks(marks, for: "2026-10-15")
        #expect(scratch.folder.readMarks("2026-10-15") == marks)
        #expect(scratch.read("days/2026-10-15.marks.json")?.contains("\"session\" : \"fix-flaky@buildbox\"") == true)
        #expect(scratch.folder.readMarks("2026-10-14") == CompassMarks())
    }

    @Test func notesSurviveARelaunch() throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        try scratch.folder.prepare(kit, written: [:])
        var state = CompassState()
        state.terminalID = "term_1"
        state.agentDay = "2026-10-15"
        var run = CompassRun(kind: .first, trigger: .scheduled, slot: Date(timeIntervalSince1970: 1_792_000_000),
                             created: Date(timeIntervalSince1970: 1_792_000_000), day: "2026-10-15")
        run.outcome = .updated
        state.runs = [run]
        try scratch.folder.writeState(state)
        #expect(scratch.folder.readState() == state)
        try scratch.write("garbage", to: "state.json")
        #expect(scratch.folder.readState() == CompassState())
    }
}

@Suite struct CompassRepositoryTests {
    @Test func gitHubRemotesNameTheirRepository() {
        #expect(CompassRepository.gitHubRepository("git@github.com:me/compass.git")! == ("me", "compass"))
        #expect(CompassRepository.gitHubRepository("https://github.com/me/my.compass")! == ("me", "my.compass"))
        #expect(CompassRepository.gitHubRepository("https://gitlab.com/me/compass.git") == nil)
        #expect(CompassRepository.gitHubRepository("git@github.com:me/compass/extra.git") == nil)
    }

    @Test func remotesAreURLsNotOptions() {
        #expect(throws: HerdrFailure.self) { try CompassRepository.requireRemote("--upload-pack=evil") }
        #expect(throws: HerdrFailure.self) { try CompassRepository.requireRemote("git@github.com:me/a b.git") }
        #expect(throws: Never.self) { try CompassRepository.requireRemote("git@github.com:me/compass.git") }
    }

    /// With Git on this Mac: runs commit the folder, a remote takes the history, and a new
    /// folder comes back from it.
    @Test(.enabled(if: CompassRepository.locateGit() != nil))
    func theFolderIsBackedUpAndRestored() async throws {
        let scratch = ScratchCompass()
        defer { scratch.remove() }
        try FileManager.default.createDirectory(at: scratch.folder.root, withIntermediateDirectories: true)
        try scratch.write("# Mine\n", to: "prompt.md")
        try scratch.write("state", to: "state.json")
        try scratch.write("state.json\n", to: ".gitignore")
        let repository = CompassRepository(root: scratch.folder.root)
        #expect(try await repository.commit("First run"))
        #expect(try await !repository.commit("Nothing changed"))

        let remote = scratch.home.appendingPathComponent("remote.git")
        let git = CompassRepository.locateGit()!
        let created = Process()
        created.executableURL = git
        // A bare repository whose HEAD names `master`, as Git makes them without init.defaultBranch:
        // Compass pushes `main`, so a clone checks out nothing unless restore picks the branch.
        created.arguments = ["init", "-q", "--bare", "-b", "master", remote.path]
        try created.run()
        created.waitUntilExit()
        try await repository.setRemote(remote.path)
        #expect(await repository.remote() == remote.path)
        try await repository.push()

        let restored = CompassRepository(root: scratch.home.appendingPathComponent("elsewhere/compass"))
        try await restored.restore(from: remote.path)
        #expect(try String(contentsOf: restored.root.appendingPathComponent("prompt.md"), encoding: .utf8) == "# Mine\n")
        #expect(!FileManager.default.fileExists(atPath: restored.root.appendingPathComponent("state.json").path))
        await #expect(throws: HerdrFailure.self) { try await restored.restore(from: remote.path) }

        try await repository.setRemote(nil)
        #expect(await repository.remote() == nil)
    }
}
