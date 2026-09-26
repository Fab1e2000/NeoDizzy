import Foundation
import Testing
@testable import NeoDizzy

struct BrowsingHistoryTests {
    @Test func visitsPersistDeduplicateAndEnrichmentDoesNotReorder() throws {
        let suite = "BrowsingHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = BrowsingHistoryStore(defaults: defaults)
        let a = DiscSummary(id: "a", title: "专辑 A", coverURL: nil, labelName: "社团")
        store.visit(id: "a", summary: nil, at: Date(timeIntervalSince1970: 1))
        store.visit(id: "b", summary: nil, at: Date(timeIntervalSince1970: 2))
        store.update(a)
        #expect(store.entries.map(\.id) == ["b", "a"])
        #expect(store.entries[1].title == "专辑 A")
        #expect(store.entries[1].visitedAt == Date(timeIntervalSince1970: 1))
        store.visit(id: "a", summary: nil, at: Date(timeIntervalSince1970: 3))
        #expect(store.entries.map(\.id) == ["a", "b"])
        #expect(BrowsingHistoryStore(defaults: defaults).entries == store.entries)
        store.remove(ids: ["a"])
        store.update(a)
        #expect(store.entries.map(\.id) == ["b"])
        store.clear()
        #expect(BrowsingHistoryStore(defaults: defaults).entries.isEmpty)
    }

    @Test func capsHistoryAndSurvivesCorruptStorage() throws {
        let suite = "BrowsingHistoryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "browsedDiscs.v1")
        let store = BrowsingHistoryStore(defaults: defaults)
        #expect(store.entries.isEmpty)
        for index in 0..<205 { store.visit(id: String(index), summary: nil, at: Date(timeIntervalSince1970: Double(index))) }
        #expect(store.entries.count == 200)
        #expect(store.entries.first?.id == "204")
        #expect(store.entries.last?.id == "5")
    }
}
