import CoreBluetooth
import Foundation

/// Central-role BLE client for pi-bluetooth-configuration's GATT service.
/// Pairing itself isn't driven from here -- the peripheral marks every
/// characteristic "encrypt-read"/"encrypt-write", so macOS's Bluetooth
/// stack triggers pairing automatically the first time we touch one, the
/// same way it would for any other encrypted GATT characteristic.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral
    }

    @Published private(set) var isBluetoothReady = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedName: String?
    @Published private(set) var status: WifiStatus = .idle
    @Published private(set) var scanResults: [WifiScanResult] = []
    @Published var lastError: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]

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
        isConnecting = true
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func writeSSID(_ ssid: String) {
        write(ssid, to: GATT.ssidUUID)
    }

    func writePassword(_ password: String) {
        write(password, to: GATT.passwordUUID)
    }

    func sendCommand(_ command: String) {
        write(command, to: GATT.commandUUID)
    }

    func refreshScanResults() {
        readValue(GATT.scanResultsUUID)
    }

    private func write(_ string: String, to uuid: CBUUID) {
        guard let peripheral, let characteristic = characteristics[uuid] else {
            lastError = "Not connected"
            return
        }
        peripheral.writeValue(Data(string.utf8), for: characteristic, type: .withResponse)
    }

    private func readValue(_ uuid: CBUUID) {
        guard let peripheral, let characteristic = characteristics[uuid] else { return }
        peripheral.readValue(for: characteristic)
    }

    private func resetConnectionState() {
        isConnected = false
        isConnecting = false
        connectedName = nil
        characteristics.removeAll()
        status = .idle
        scanResults = []
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
        if let error {
            lastError = error.localizedDescription
        }
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
            lastError = "pi-bluetooth-configuration service not found"
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
            // Reading/subscribing to these triggers macOS's pairing prompt
            // on first access, since the peripheral requires an encrypted
            // link for every characteristic in this service.
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
            }
        case GATT.scanResultsUUID:
            if let decoded = try? JSONDecoder().decode([WifiScanResult].self, from: data) {
                scanResults = decoded.sorted { $0.rssi > $1.rssi }
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
