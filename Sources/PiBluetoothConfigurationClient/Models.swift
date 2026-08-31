import CoreBluetooth
import Foundation

/// UUIDs and layout match pi-bluetooth-configuration-alpine's GATT service
/// exactly -- see that repo's README for the protocol these characteristics
/// implement.
enum GATT {
    static let serviceUUID     = CBUUID(string: "7b1e0000-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let ssidUUID        = CBUUID(string: "7b1e0001-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let passwordUUID    = CBUUID(string: "7b1e0002-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let commandUUID     = CBUUID(string: "7b1e0003-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let statusUUID      = CBUUID(string: "7b1e0004-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let scanResultsUUID = CBUUID(string: "7b1e0005-6a45-4d1f-9b0a-3c2f8e4d5a10")
    static let ethernetIPUUID  = CBUUID(string: "7b1e0006-6a45-4d1f-9b0a-3c2f8e4d5a10")

    static let allCharacteristicUUIDs = [
        ssidUUID, passwordUUID, commandUUID, statusUUID, scanResultsUUID, ethernetIPUUID
    ]
}

struct WifiStatus: Decodable, Equatable {
    var state: String
    var ssid: String
    var ip: String
    var error: String

    static let idle = WifiStatus(state: "idle", ssid: "", ip: "", error: "")
}

struct WifiScanResult: Decodable, Equatable, Identifiable {
    var ssid: String
    var rssi: Int
    var security: String

    var id: String { ssid }
}
