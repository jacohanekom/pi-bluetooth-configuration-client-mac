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
    static let relaysUUID      = CBUUID(string: "7b1e0008-6a45-4d1f-9b0a-3c2f8e4d5a10")

    static let allCharacteristicUUIDs = [
        ssidUUID, passwordUUID, commandUUID, statusUUID, scanResultsUUID, ethernetIPUUID, leasesUUID, relaysUUID
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
    //
    // Decoded leniently (defaulting to false): a Pi still running a
    // daemon build from before this field existed would otherwise fail
    // this whole decode and silently stall the wizard (no "finished"
    // key -> decode throws -> the app never processes the status update
    // at all, e.g. never triggers the first automatic network scan).
    var finished: Bool

    static let idle = WifiStatus(state: "idle", ssid: "", ip: "", error: "", finished: false)

    init(state: String, ssid: String, ip: String, error: String, finished: Bool) {
        self.state = state
        self.ssid = ssid
        self.ip = ip
        self.error = error
        self.finished = finished
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        ssid = try c.decode(String.self, forKey: .ssid)
        ip = try c.decode(String.self, forKey: .ip)
        error = try c.decode(String.self, forKey: .error)
        finished = try c.decodeIfPresent(Bool.self, forKey: .finished) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case state, ssid, ip, error, finished
    }
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

/// One relay pi-bluetooth-configuration forwards on/off/status to on
/// pi-relay-control-alpine's behalf -- see that repo's README, "Relay
/// control". `state` is "on", "off", or "unknown" (pi-relay-control-alpine
/// unreachable on that port).
struct RelayState: Decodable, Equatable, Identifiable {
    var port: Int
    var label: String
    var state: String

    var id: Int { port }
    var isOn: Bool { state == "on" }
}
