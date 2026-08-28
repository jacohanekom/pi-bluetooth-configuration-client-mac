import SwiftUI

@main
struct PiBluetoothConfigurationClientApp: App {
    @StateObject private var ble = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
        }
        .windowResizability(.contentSize)
    }
}
