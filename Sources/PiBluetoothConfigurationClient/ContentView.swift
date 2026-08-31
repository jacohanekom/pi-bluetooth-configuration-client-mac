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
            } else if ble.status.state == "connected" {
                wifiConnectedSection
            } else {
                configureSection
            }

            if let info = ble.lastInfo {
                Text(info)
                    .foregroundStyle(.green)
                    .font(.footnote)
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

    // Shown once the Pi reports its WiFi is actually connected -- the
    // provisioning job is done at this point, so there's nothing left to
    // configure, just the result and a way to undo it.
    private var wifiConnectedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected to \(ble.connectedName ?? "device")")
                .font(.headline)

            GroupBox("WiFi") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Network", value: ble.status.ssid)
                    LabeledContent("IP address", value: ble.status.ip)
                }
                .padding(.top, 4)
            }

            Text("The Pi will reboot shortly to finish applying this. The Bluetooth connection will drop when it does -- that's expected.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Forget This Network") {
                ble.sendCommand("forget")
            }
            .buttonStyle(.bordered)
        }
    }

    // Shown before WiFi is connected: staging SSID/password, scanning,
    // and live connect progress/failure feedback.
    private var configureSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected to \(ble.connectedName ?? "device")")
                .font(.headline)

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
