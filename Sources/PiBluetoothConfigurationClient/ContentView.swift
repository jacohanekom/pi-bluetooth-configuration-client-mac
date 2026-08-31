import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var manualSSID: String = ""
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
                wizardSection
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
            Spacer()
            if ble.isConnected {
                Button("Disconnect") { ble.disconnect() }
            }
        }
    }

    // MARK: - Device list

    private var deviceListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Nearby Devices").font(.headline)
                Spacer()
                Button {
                    ble.startScan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan")
            }

            if ble.discoveredDevices.isEmpty {
                Text("Scanning for aipicam devices…")
                    .foregroundStyle(.secondary)
            }

            List(ble.discoveredDevices) { device in
                Button {
                    ble.connect(to: device)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                                .font(.system(.body, design: .monospaced))
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

    // MARK: - WiFi already configured

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

            Button("Reset") {
                ble.resetNetwork()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Wizard (WiFi not yet configured)

    private var wizardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected to \(ble.connectedName ?? "device")")
                .font(.headline)

            switch ble.wizardStep {
            case .scanning:
                scanningStep
            case .pickNetwork:
                pickNetworkStep
            case .enterPassword(let ssid):
                enterPasswordStep(ssid: ssid)
            }
        }
    }

    private var scanningStep: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Scanning for networks…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private var pickNetworkStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Choose a Network").font(.headline)
                Spacer()
                Button {
                    ble.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Rescan")
            }

            if ble.scanResults.isEmpty {
                Text("No networks found.")
                    .foregroundStyle(.secondary)
            }

            List(ble.scanResults) { result in
                Button {
                    password = ""
                    ble.selectNetwork(ssid: result.ssid)
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
            .frame(minHeight: 180)

            Button("Enter Network Manually") {
                manualSSID = ""
                password = ""
                ble.selectNetwork(ssid: "")
            }
        }
    }

    private func enterPasswordStep(ssid: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button {
                    ble.backToNetworkList()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                Text(ssid.isEmpty ? "Enter Network" : ssid)
                    .font(.headline)
            }

            if ssid.isEmpty {
                TextField("SSID", text: $manualSSID)
            }
            SecureField("Password (leave blank for an open network)", text: $password)

            if ble.status.state == "connecting" || ble.status.state == "failed" {
                statusBadge
            }

            Button("Connect") {
                ble.connectToNetwork(ssid: ssid.isEmpty ? manualSSID : ssid, password: password)
            }
            .disabled((ssid.isEmpty ? manualSSID : ssid).isEmpty || ble.status.state == "connecting")
            .buttonStyle(.borderedProminent)
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
        case "connecting": return .yellow
        case "failed":     return .red
        default:           return .gray
        }
    }

    private var statusText: String {
        switch ble.status.state {
        case "connecting":
            return "Connecting to \(ble.status.ssid)…"
        case "failed":
            return "Failed: \(ble.status.error)"
        default:
            return ""
        }
    }
}
