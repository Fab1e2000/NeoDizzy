import SwiftUI

struct AppRouteDestination: View {
    @Environment(ModuleRegistry.self) private var modules
    let route: AppRoute
    var body: some View {
        if let page = route.destination.base as? InlinePageRoute { page.make() } else { modules.destination(for: route) }
    }
}
