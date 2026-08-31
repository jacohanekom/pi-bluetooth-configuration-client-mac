import CoreBluetooth
import Foundation

/// Which step of the connect-a-new-network wizard is showing. Only
/// relevant while status.state isn't "connected" yet -- once it is,
/// ContentView shows the connected-details view instead, regardless of
/// this value.
enum WizardStep: Equatable {
    case scanning
    case pickNetwork
    case enterPassword(ssid: String)
}

/// Central-role BLE client for aipicam's WiFi-provisioning GATT service.
///
/// No pairing/bonding: the peripheral's characteristics are plain
/// read/write, not encrypted, so connecting is all that's needed -- see
/// pi-bluetooth-configuration-alpine's README ("Security model") for why
/// pairing was deliberately removed and what that trades away (WiFi
/// credentials cross BLE in the clear).
///
/// This is a one-shot provisioning flow, not a managed session: the Pi
/// reboots a few seconds after a successful "connect" or after "reset"
/// (see that repo's README, "One-shot provisioning and reboot
/// behavior"), so this client doesn't try to keep managing anything once
/// either happens -- it just shows the result and treats the BLE
/// disconnect that follows as expected, not an error.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral
    }

    static let maxReconnectAttempts = 3
    static let reconnectDelay: TimeInterval = 1

    @Published private(set) var isBluetoothReady = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedName: String?
    @Published private(set) var status: WifiStatus = .idle
    @Published private(set) var scanResults: [WifiScanResult] = []
    @Published private(set) var wizardStep: WizardStep = .scanning
    @Published var lastError: String?
    @Published var lastInfo: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    private var userInitiatedDisconnect = false
    // Set once we know the daemon is about to reboot (a successful
    // connect, or a reset we just sent) -- the BLE disconnect that
    // follows is expected, not a failure to retry against.
    private var expectRebootDisconnect = false
    private var reconnectAttempts = 0
    // Kicks off exactly one automatic scan per connection, the moment we
    // learn the Pi isn't already configured -- avoids re-scanning every
    // time a Status notification happens to repeat the same "not
    // connected yet" state.
    private var hasAutoScanned = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        central.scanForPeripherals(withServices: [GATT.serviceUUID],
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
    }

    func connect(to device: DiscoveredDevice) {
        stopScan()
        lastError = nil
        lastInfo = nil
        isConnecting = true
        userInitiatedDisconnect = false
        expectRebootDisconnect = false
        reconnectAttempts = 0
        hasAutoScanned = false
        wizardStep = .scanning
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        userInitiatedDisconnect = true
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
    }

    /// Rescans -- used both for the automatic first scan and a manual
    /// "Rescan" action from the network-picker step.
    func rescan() {
        lastError = nil
        wizardStep = .scanning
        write("scan", to: GATT.commandUUID)
    }

    /// User tapped a network in the picker (or chose to enter one
    /// manually, with an empty ssid) -- advance to the password step.
    func selectNetwork(ssid: String) {
        lastError = nil
        wizardStep = .enterPassword(ssid: ssid)
    }

    func backToNetworkList() {
        lastError = nil
        wizardStep = .pickNetwork
    }

    func connectToNetwork(ssid: String, password: String) {
        write(ssid, to: GATT.ssidUUID)
        write(password, to: GATT.passwordUUID)
        write("connect", to: GATT.commandUUID)
    }

    // Labeled "Reset" in the UI; the wire command is still "forget" --
    // that's the daemon's protocol (see pi-bluetooth-configuration-alpine's
    // README), this is just how the Mac app presents it.
    func resetNetwork() {
        expectRebootDisconnect = true
        lastInfo = "Resetting -- the Pi will reboot shortly."
        write("forget", to: GATT.commandUUID)
    }

    private func write(_ string: String, to uuid: CBUUID) {
        guard let peripheral, let characteristic = characteristics[uuid] else {
            lastError = "Not connected"
            return
        }
        peripheral.writeValue(Data(string.utf8), for: characteristic, type: .withResponse)
    }

    private func resetConnectionState() {
        isConnected = false
        isConnecting = false
        connectedName = nil
        characteristics.removeAll()
        status = .idle
        scanResults = []
        wizardStep = .scanning
    }
}

extension BLEManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isBluetoothReady = (central.state == .poweredOn)
        if central.state == .poweredOn {
            startScan()
        } else {
            discoveredDevices.removeAll()
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                         advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
            ?? "Unknown device"
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue, peripheral: peripheral)
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectAttempts = 0
        isConnecting = false
        isConnected = true
        connectedName = peripheral.name
        peripheral.discoverServices([GATT.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnecting = false
        lastError = error?.localizedDescription ?? "Failed to connect"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if userInitiatedDisconnect {
            userInitiatedDisconnect = false
            if let error { lastError = error.localizedDescription }
            resetConnectionState()
            return
        }

        if expectRebootDisconnect {
            expectRebootDisconnect = false
            lastInfo = "The Pi is rebooting to apply the change. Reconnect once it's back up."
            resetConnectionState()
            return
        }

        // Unexpected disconnect (e.g. the BCM43438's Hardware Failure
        // instability, or a transient RF issue) -- retry a few times
        // before treating it as an actual failure.
        if reconnectAttempts < Self.maxReconnectAttempts {
            reconnectAttempts += 1
            isConnecting = true
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reconnectDelay) { [weak self] in
                guard let self else { return }
                self.central.connect(peripheral, options: nil)
            }
            return
        }

        lastError = error?.localizedDescription ?? "Disconnected unexpectedly and could not reconnect"
        resetConnectionState()
    }
}

extension BLEManager: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let service = peripheral.services?.first(where: { $0.uuid == GATT.serviceUUID }) else {
            lastError = "aipicam WiFi-configuration service not found"
            return
        }
        peripheral.discoverCharacteristics(GATT.allCharacteristicUUIDs, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid] = characteristic
            if characteristic.uuid == GATT.statusUUID || characteristic.uuid == GATT.scanResultsUUID {
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            return
        }
        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        case GATT.statusUUID:
            if let decoded = try? JSONDecoder().decode(WifiStatus.self, from: data) {
                status = decoded
                if decoded.state == "connected" {
                    // The daemon reboots a few seconds after reporting
                    // this -- the BLE drop that follows is expected.
                    expectRebootDisconnect = true
                } else if !hasAutoScanned {
                    hasAutoScanned = true
                    rescan()
                }
            }
        case GATT.scanResultsUUID:
            if let decoded = try? JSONDecoder().decode([WifiScanResult].self, from: data) {
                scanResults = decoded.sorted { $0.rssi > $1.rssi }
                if wizardStep == .scanning {
                    wizardStep = .pickNetwork
                }
            }
        default:
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastError = error.localizedDescription
        }
    }
}
