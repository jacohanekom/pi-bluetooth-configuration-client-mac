// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pi-bluetooth-configuration-client-mac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "pi-bluetooth-configuration-client-mac",
            path: "Sources/PiBluetoothConfigurationClient",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // Embeds Info.plist directly into the Mach-O binary so a
                // plain SPM executable (no .app bundle) still gets a real
                // NSBluetoothAlwaysUsageDescription -- CoreBluetooth
                // refuses to run without one, bundle or not.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ])
            ]
        )
    ]
)
