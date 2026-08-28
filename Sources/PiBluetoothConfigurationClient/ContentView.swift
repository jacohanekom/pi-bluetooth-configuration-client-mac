import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var ssid: String = ""
    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !ble.isBluetoothReady {
                Text("Turn on Bluetooth to continue.")
                    .foregroundStyle(.secondary)
            } else if !ble.isConnected {
                deviceListSection
            } else {
                connectedSection
            }

            if let error = ble.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(minWidth: 440, minHeight: 520)
    }

    private var header: some View {
        HStack {
            Text("pi-bluetooth-configuration")
                .font(.title2).bold()
            Spacer()
            if ble.isConnected {
                Button("Disconnect") { ble.disconnect() }
            }
        }
    }

    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby devices").font(.headline)
                Spacer()
                Button {
                    ble.startScan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan")
            }

            if ble.discoveredDevices.isEmpty {
                Text("Scanning for pi-bluetooth-configuration devices…")
                    .foregroundStyle(.secondary)
            }

            List(ble.discoveredDevices) { device in
                Button {
                    ble.connect(to: device)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("RSSI \(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if ble.isConnecting {
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 180)
        }
    }

    private var connectedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected to \(ble.connectedName ?? "device")")
                .font(.headline)

            transportBadge
            statusBadge

            GroupBox("WiFi network") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("SSID", text: $ssid)
                    SecureField("Password (leave blank for an open network)", text: $password)
                    HStack {
                        Button("Scan Networks") {
                            ble.sendCommand("scan")
                        }
                        Spacer()
                        Button("Forget") {
                            ble.sendCommand("forget")
                        }
                        Button("Connect") {
                            ble.writeSSID(ssid)
                            ble.writePassword(password)
                            ble.sendCommand("connect")
                        }
                        .disabled(ssid.isEmpty)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 4)
            }

            if !ble.scanResults.isEmpty {
                GroupBox("Scan results (tap to fill in SSID)") {
                    List(ble.scanResults) { result in
                        Button {
                            ssid = result.ssid
                        } label: {
                            HStack {
                                Text(result.ssid)
                                Spacer()
                                Text(result.security).foregroundStyle(.secondary)
                                Text("\(result.rssi) dBm").foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(minHeight: 140)
                }
            }
        }
    }

    private var transportBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: ble.usingNetwork ? "wifi" : "dot.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Text(ble.usingNetwork
                 ? "Managing over WiFi (\(ble.networkHost ?? ""))"
                 : "Managing over Bluetooth")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(statusText)
            Spacer()
        }
        .font(.subheadline)
    }

    private var statusColor: Color {
        switch ble.status.state {
        case "connected":  return .green
        case "connecting", "scanning": return .yellow
        case "failed":     return .red
        default:           return .gray
        }
    }

    private var statusText: String {
        switch ble.status.state {
        case "connected":
            return "Connected to \(ble.status.ssid) — \(ble.status.ip)"
        case "connecting":
            return "Connecting to \(ble.status.ssid)…"
        case "scanning":
            return "Scanning for networks…"
        case "failed":
            return "Failed: \(ble.status.error)"
        default:
            return "Idle"
        }
    }
}
