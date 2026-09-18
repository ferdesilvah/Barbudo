import SwiftUI
import BarbudoUI

@main
struct BarbudoApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light) // the table is always warm wood, day or night
        }
    }
}
