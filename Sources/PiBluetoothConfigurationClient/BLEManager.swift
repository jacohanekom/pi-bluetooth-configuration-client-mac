import CoreBluetooth
import Foundation

/// Central-role BLE client for pi-bluetooth-configuration's GATT service,
/// with a handoff to NetworkControlClient once the Pi has an IP.
///
/// No pairing/bonding: the peripheral's characteristics are plain
/// read/write, not encrypted, so connecting is all that's needed -- see
/// pi-bluetooth-configuration-alpine's README ("Security model") for why
/// pairing was deliberately removed (bonding on the Pi 3's BCM43438 kept
/// desyncing between BlueZ and the Mac in practice) and what that trades
/// away (WiFi credentials cross BLE in the clear).
///
/// The Pi 3's onboard Bluetooth shares an antenna with its WiFi radio, so
/// BLE routinely drops once WiFi is actively passing traffic -- a
/// hardware limitation, not a bug (see pi-bluetooth-configuration-alpine's
/// README). Once Status reports a non-empty ip, this switches to polling
/// the Pi's TCP control interface instead of continuing to rely on BLE,
/// and treats a subsequent BLE disconnect as expected rather than an error.
@MainActor
final class BLEManager: NSObject, ObservableObject {
    struct DiscoveredDevice: Identifiable {
        let id: UUID
        let name: String
        let rssi: Int
        let peripheral: CBPeripheral
    }

    static let networkControlPort: UInt16 = 8567
    static let networkPollInterval: TimeInterval = 2
    static let scanResultsFetchDelay: TimeInterval = 5
    static let maxReconnectAttempts = 3
    static let reconnectDelay: TimeInterval = 1

    @Published private(set) var isBluetoothReady = false
    @Published private(set) var discoveredDevices: [DiscoveredDevice] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isConnected = false
    @Published private(set) var connectedName: String?
    @Published private(set) var status: WifiStatus = .idle
    @Published private(set) var scanResults: [WifiScanResult] = []
    @Published private(set) var usingNetwork = false
    @Published private(set) var networkHost: String?
    @Published var lastError: String?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristics: [CBUUID: CBCharacteristic] = [:]

    private var networkClient: NetworkControlClient?
    private var statusPollTimer: Timer?
    private var stagedSSID = ""
    private var stagedPassword = ""

    // Transient link-level disconnects happen on this hardware even
    // without pairing involved -- e.g. the Pi 3's BCM43438 occasionally
    // drops the connection with HCI "Hardware Failure" (reason 0x03), a
    // known instability in that chip. An unexpected disconnect gets a
    // few silent reconnect attempts (reusing the connection, no bonding
    // to redo) before it's surfaced as an actual error.
    private var userInitiatedDisconnect = false
    private var reconnectAttempts = 0

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
        tearDownNetworkClient()
        stopScan()
        lastError = nil
        isConnecting = true
        userInitiatedDisconnect = false
        reconnectAttempts = 0
        peripheral = device.peripheral
        peripheral?.delegate = self
        central.connect(device.peripheral, options: nil)
    }

    func disconnect() {
        tearDownNetworkClient()
        userInitiatedDisconnect = true
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        resetConnectionState()
    }

    func writeSSID(_ ssid: String) {
        stagedSSID = ssid
        guard !usingNetwork else { return } // sent inline with "connect" over the network protocol
        write(ssid, to: GATT.ssidUUID)
    }

    func writePassword(_ password: String) {
        stagedPassword = password
        guard !usingNetwork else { return }
        write(password, to: GATT.passwordUUID)
    }

    func sendCommand(_ command: String) {
        guard !usingNetwork else {
            sendNetworkCommand(command)
            return
        }
        write(command, to: GATT.commandUUID)
    }

    func refreshScanResults() {
        guard !usingNetwork else {
            networkClient?.send(cmd: "scanresults")
            return
        }
        readValue(GATT.scanResultsUUID)
    }

    private func sendNetworkCommand(_ command: String) {
        switch command {
        case "scan":
            networkClient?.send(cmd: "scan")
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.scanResultsFetchDelay) { [weak self] in
                self?.networkClient?.send(cmd: "scanresults")
            }
        case "connect":
            networkClient?.send(cmd: "connect", extra: ["ssid": stagedSSID, "psk": stagedPassword])
        case "forget":
            networkClient?.send(cmd: "forget")
        default:
            break
        }
    }

    // Called once Status (over BLE) reports a connected state with an IP
    // -- from then on, the TCP interface is authoritative, and a BLE drop
    // is expected rather than treated as an error.
    private func switchToNetworkControl(host: String) {
        guard !usingNetwork else { return }
        usingNetwork = true
        networkHost = host

        let client = NetworkControlClient()
        client.onStatus = { [weak self] s in self?.status = s }
        client.onScanResults = { [weak self] r in self?.scanResults = r.sorted { $0.rssi > $1.rssi } }
        client.onError = { [weak self] e in self?.lastError = e }
        client.connect(host: host, port: Self.networkControlPort)
        networkClient = client

        statusPollTimer = Timer.scheduledTimer(withTimeInterval: Self.networkPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.networkClient?.send(cmd: "status") }
        }
    }

    private func tearDownNetworkClient() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
        networkClient?.disconnect()
        networkClient = nil
        usingNetwork = false
        networkHost = nil
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
        if usingNetwork {
            // Expected: the Pi 3's combo WiFi/BT chip often drops BLE once
            // WiFi is actively passing traffic, and we've already handed
            // off to the network control channel -- not an error.
            self.peripheral = nil
            characteristics.removeAll()
            return
        }

        if userInitiatedDisconnect {
            userInitiatedDisconnect = false
            if let error { lastError = error.localizedDescription }
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
                if decoded.state == "connected", !decoded.ip.isEmpty {
                    switchToNetworkControl(host: decoded.ip)
                }
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
