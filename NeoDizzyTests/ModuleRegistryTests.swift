import Foundation
import SwiftUI
import Testing
@testable import NeoDizzy

@MainActor
struct ModuleRegistryTests {
    private enum TestRoute: Hashable { case item(Int) }

    private final class TestModule: AppModule {
        let descriptor: ModuleDescriptor
        var destinations: [AppRoute] = []
        var urlVisits = 0
        init(_ id: String) {
            descriptor = ModuleDescriptor(id: ModuleID(rawValue: id), title: id, systemImage: "music.note")
        }
        func rootView() -> AnyView { AnyView(Text(descriptor.title)) }
        func destination(for route: AppRoute) -> AnyView? {
            destinations.append(route)
            guard let payload = route.destination.base as? TestRoute else { return nil }
            return AnyView(Text(String(describing: payload)))
        }
        func handleURL(_ url: URL, host: ModuleHost) -> Bool {
            urlVisits += 1
            guard url.scheme == descriptor.id.rawValue else { return false }
            return host.select(descriptor.id)
        }
    }

    @Test func acceptsAnIndependentProviderAndDispatchesOnlyToItsOwner() throws {
        let first = TestModule("test-first")
        let second = TestModule("test-second")
        let registry = try ModuleRegistry([first, second])
        let route = AppRoute(moduleID: second.descriptor.id, destination: TestRoute.item(7), title: "Seven")
        _ = registry.destination(for: route)
        #expect(first.destinations.isEmpty)
        #expect(second.destinations == [route])
        #expect(registry.descriptors.map(\.id) == [first.descriptor.id, second.descriptor.id])
        _ = registry.destination(for: AppRoute(moduleID: ModuleID(rawValue: "absent"), destination: TestRoute.item(0), title: "Missing"))
        #expect(first.destinations.isEmpty)
        #expect(second.destinations.count == 1)
    }

    @Test func rejectsAmbiguousAndEmptyRegistrations() {
        #expect(throws: ModuleRegistry.RegistrationError.self) { try ModuleRegistry([]) }
        #expect(throws: ModuleRegistry.RegistrationError.self) {
            try ModuleRegistry([TestModule("duplicate"), TestModule("duplicate")])
        }
    }

    @Test func routesAreNamespacedAndKeepTypedPayloads() {
        let first = AppRoute(moduleID: ModuleID(rawValue: "a"), destination: TestRoute.item(1), title: "Item")
        let second = AppRoute(moduleID: ModuleID(rawValue: "b"), destination: TestRoute.item(1), title: "Item")
        #expect(first != second)
        #expect(first.destination.base as? TestRoute == .item(1))
        #expect(first.moduleID.rawValue == "a")
        #expect(AppRoute.localAlbum(id: "album").moduleID == .localLibrary)
    }

    @Test func zoomRoutesPreserveTheirTypedDestinationAndModuleOwner() throws {
        let first = TestModule("first")
        let second = TestModule("second")
        let registry = try ModuleRegistry([first, second])
        let route = AppRoute(moduleID: second.descriptor.id, destination: TestRoute.item(7), title: "Seven")
        let sourceID = UUID()
        let zoomRoute = route.zooming(from: sourceID)

        #expect(route.zoomSourceID == nil)
        #expect(zoomRoute.zoomSourceID == sourceID)
        #expect(zoomRoute.moduleID == route.moduleID)
        #expect(zoomRoute.destination.base as? TestRoute == .item(7))
        #expect(zoomRoute.title == route.title)
        _ = registry.destination(for: zoomRoute)
        #expect(first.destinations.isEmpty)
        #expect(second.destinations == [zoomRoute])
    }

    @Test func sameCollectionFromDifferentCardsKeepsIndependentReturnSources() throws {
        let suite = "ModuleRegistryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let module = TestModule("collection-provider")
        let registry = try ModuleRegistry([module])
        let settings = ModuleSettings(modules: registry.descriptors, defaults: defaults)
        let host = ModuleHost(settings: settings)
        let route = AppRoute(moduleID: module.descriptor.id, destination: TestRoute.item(7), title: "Seven")
        let firstSourceID = UUID()
        let firstVisit = route.zooming(from: firstSourceID)
        let nestedVisit = route.zooming(from: UUID())

        #expect(Set([firstVisit, nestedVisit]).count == 2)
        #expect(route.zooming(from: firstSourceID) == firstVisit)
        #expect(host.select(module.descriptor.id, path: [firstVisit]))
        host.paths[module.descriptor.id, default: []].append(nestedVisit)
        #expect(host.paths[module.descriptor.id] == [firstVisit, nestedVisit])

        let popped = host.paths[module.descriptor.id]?.popLast()
        #expect(popped == nestedVisit)
        #expect(host.paths[module.descriptor.id] == [firstVisit])
        #expect(host.paths[module.descriptor.id]?.last?.zoomSourceID == firstSourceID)
    }

    @Test func hostUsesRegisteredIDsAndKeepsIndependentStacks() throws {
        let suite = "ModuleRegistryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = TestModule("first")
        let second = TestModule("second")
        let third = TestModule("third")
        let registry = try ModuleRegistry([first, second, third])
        let settings = ModuleSettings(modules: registry.descriptors, defaults: defaults)
        let host = ModuleHost(settings: settings)
        let route = AppRoute(moduleID: first.descriptor.id, destination: TestRoute.item(1), title: "One")
        #expect(host.select(first.descriptor.id, path: [route]))
        #expect(registry.handleURL(URL(string: "second://open")!, host: host))
        #expect(host.selection == second.descriptor.id)
        #expect(host.paths[first.descriptor.id] == [route])
        #expect(host.paths[second.descriptor.id] == [])
        #expect(third.urlVisits == 0)
        settings.setVisible(false, for: second.descriptor.id)
        host.reconcileSelection()
        #expect(host.selection == first.descriptor.id)
        #expect(!host.select(second.descriptor.id))
        settings.reorder([third.descriptor.id, first.descriptor.id, second.descriptor.id])
        let restored = ModuleSettings(modules: registry.descriptors, defaults: defaults)
        #expect(restored.order == settings.order)
        #expect(restored.visibleModules == [third.descriptor.id, first.descriptor.id])
        settings.setVisible(false, for: first.descriptor.id)
        settings.setVisible(false, for: third.descriptor.id)
        #expect(settings.visibleModules == [third.descriptor.id])
    }

    @Test func replacingInstalledModulesRepairsPreferencesWithoutDizzyLab() throws {
        let suite = "ModuleRemovalTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = TestModule("old"), remaining = TestModule("remaining"), new = TestModule("new")
        let before = ModuleSettings(modules: [old.descriptor, remaining.descriptor], defaults: defaults)
        before.startupModule = old.descriptor.id
        before.setVisible(false, for: remaining.descriptor.id)
        let after = ModuleSettings(modules: [remaining.descriptor, new.descriptor], defaults: defaults)
        #expect(after.order == [remaining.descriptor.id, new.descriptor.id])
        #expect(after.initialModule == new.descriptor.id)
        #expect(!after.isVisible(old.descriptor.id))
        after.setVisible(true, for: old.descriptor.id)
        #expect(!after.visibleModules.contains(old.descriptor.id))
    }
}
