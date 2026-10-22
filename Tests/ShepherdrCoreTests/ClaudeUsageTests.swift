import Foundation
import Testing
@testable import ShepherdrCore

struct ClaudeUsageTests {
    private let answer = Data("""
    {"five_hour":{"utilization":3.0,"resets_at":"2026-10-22T22:10:00.436446+00:00"},
     "seven_day":{"utilization":59.6,"resets_at":"2026-10-24T12:00:00+00:00"},
     "extra_usage":{"is_enabled":false,"utilization":0.0}}
    """.utf8)

    @Test func readsBothLimitsAndTheirResets() throws {
        let usage = try #require(ClaudeUsage.parse(answer))
        #expect(usage.session?.percent == 3)
        #expect(usage.week?.percent == 60)
        #expect(usage.session?.resetsAt != nil)
        #expect(usage.week?.resetsAt == Date(timeIntervalSince1970: 1792843200))
    }

    @Test func anAnswerWithoutLimitsIsNoData() {
        #expect(ClaudeUsage.parse(Data("{}".utf8)) == nil)
        #expect(ClaudeUsage.parse(Data("nope".utf8)) == nil)
    }

    @Test func saysHowLongIsLeft() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(ClaudeUsage.untilReset(now.addingTimeInterval(130 * 60), now: now) == "in 2h 10m")
        #expect(ClaudeUsage.untilReset(now.addingTimeInterval(40 * 60), now: now) == "in 40m")
        #expect(ClaudeUsage.untilReset(now.addingTimeInterval(27 * 3600), now: now) == "in 1d 3h")
        #expect(ClaudeUsage.untilReset(now.addingTimeInterval(-5), now: now) == "in 1m")
    }
}
