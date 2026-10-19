import Foundation
import Testing
@testable import ShepherdrCore

@MainActor
struct VisitStoreTests {
    private func defaults() -> UserDefaults {
        let name = "visits-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let api = Agent.ID(machineID: "local", terminalID: "term_api")
    private let web = Agent.ID(machineID: "local", terminalID: "term_web")
    private let docs = Agent.ID(machineID: "remote:box", terminalID: "term_docs")
    private let fresh = Agent.ID(machineID: "local", terminalID: "term_fresh")

    @Test func theLastPlaceVisitedComesFirstButNeverTheOneYoureOn() {
        let store = VisitStore(defaults: defaults())
        let start = Date(timeIntervalSince1970: 1_000)
        store.record(.session(api), at: start)
        store.record(.compass, at: start + 10)
        store.record(.session(docs), at: start + 20)
        store.record(.session(web), at: start + 30)
        let places: [VisitStore.Place] = [.compass, .session(api), .session(fresh), .session(web), .session(docs)]
        // On web: docs was last, then Compass, then api; places never visited keep their order.
        #expect(store.recentFirst(places, place: { $0 }, excluding: .session(web))
                == [.session(docs), .compass, .session(api), .session(fresh)])
        #expect(store.recentFirst(places, place: { $0 }, excluding: .compass).first == .session(web))
        #expect(store.recentFirst(places, place: { $0 }, excluding: nil).count == 5)
    }

    @Test func visitsAreSavedAndOldOnesForgotten() {
        let saved = defaults()
        let store = VisitStore(defaults: saved)
        store.record(.session(api), at: Date(timeIntervalSince1970: 100))
        store.record(.compass, at: Date(timeIntervalSince1970: 200))
        let again = VisitStore(defaults: saved)
        #expect(again.visits == [.session(api): Date(timeIntervalSince1970: 100), .compass: Date(timeIntervalSince1970: 200)])

        for index in 0..<(VisitStore.limit + 5) {
            again.record(.session(.init(machineID: "local", terminalID: "term_\(index)")), at: Date(timeIntervalSince1970: 1_000 + Double(index)))
        }
        #expect(again.visits.count == VisitStore.limit)
        #expect(again.visits[.compass] == nil)
    }

    @Test func searchTermsSplitWordsAndTheMachine() {
        #expect(SessionSearch.terms(of: " fix login@build ") == (["fix", "login"], "build") as ([String], String?))
        #expect(SessionSearch.terms(of: "api").words == ["api"])
        #expect(SessionSearch.terms(of: "api").machine == nil)
    }
}
