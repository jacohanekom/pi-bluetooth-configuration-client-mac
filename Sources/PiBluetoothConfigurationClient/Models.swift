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
    static let leasesUUID      = CBUUID(string: "7b1e0007-6a45-4d1f-9b0a-3c2f8e4d5a10")

    static let allCharacteristicUUIDs = [
        ssidUUID, passwordUUID, commandUUID, statusUUID, scanResultsUUID, ethernetIPUUID, leasesUUID
    ]
}

struct WifiStatus: Decodable, Equatable {
    var state: String
    var ssid: String
    var ip: String
    var error: String
    // Whether the daemon's one-shot setup wizard has already completed
    // (its "finish" command ran) -- a Pi that just joined WiFi but
    // hasn't been finished yet also reports state == "connected", so
    // this (not just state) is what decides wizard vs. final details.
    var finished: Bool

    static let idle = WifiStatus(state: "idle", ssid: "", ip: "", error: "", finished: false)
}

struct WifiScanResult: Decodable, Equatable, Identifiable {
    var ssid: String
    var rssi: Int
    var security: String

    var id: String { ssid }
}

/// EthernetIP's wire format is plain CSV, "<ip>,<rangeStart>,<rangeEnd>"
/// -- matches eth_control.hpp/main.cpp on the daemon side, which has no
/// JSON parser for the write side.
struct EthernetConfig: Equatable {
    var ip: String
    var rangeStart: Int
    var rangeEnd: Int

    static let unknown = EthernetConfig(ip: "", rangeStart: 2, rangeEnd: 200)

    var wireValue: String { "\(ip),\(rangeStart),\(rangeEnd)" }

    init(ip: String, rangeStart: Int, rangeEnd: Int) {
        self.ip = ip
        self.rangeStart = rangeStart
        self.rangeEnd = rangeEnd
    }

    init?(wireValue: String) {
        let parts = wireValue.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3, let start = Int(parts[1]), let end = Int(parts[2]) else { return nil }
        ip = String(parts[0])
        rangeStart = start
        rangeEnd = end
    }
}

struct DhcpLease: Decodable, Equatable, Identifiable {
    var ip: String
    var mac: String
    var hostname: String

    var id: String { ip }
}
