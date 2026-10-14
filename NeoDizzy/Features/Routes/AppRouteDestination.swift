import SwiftUI

struct AppRouteDestination: View {
    @Environment(ModuleRegistry.self) private var modules
    let route: AppRoute
    var body: some View { modules.destination(for: route) }
}
