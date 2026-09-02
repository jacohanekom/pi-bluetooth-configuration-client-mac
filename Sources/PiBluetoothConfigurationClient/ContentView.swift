import SwiftUI

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager
    @State private var manualSSID: String = ""
    @State private var password: String = ""
    @State private var localIPField: String = ""
    @State private var rangeStartField: String = ""
    @State private var rangeEndField: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if !ble.isBluetoothReady {
                Text("Turn on Bluetooth to continue.")
                    .foregroundStyle(.secondary)
            } else if !ble.isConnected {
                deviceListSection
            } else if ble.status.finished {
                connectedDetailsSection
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

    // MARK: - Setup finished: WiFi + Local Network details

    private var connectedDetailsSection: some View {
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

            GroupBox("Local Network") {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent("Gateway IP", value: ble.ethernetConfig.ip)
                    LabeledContent("DHCP range", value: "\(rangeAddress(ble.ethernetConfig.rangeStart)) – \(rangeAddress(ble.ethernetConfig.rangeEnd))")
                    if ble.dhcpLeases.isEmpty {
                        Text("No devices connected")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(ble.dhcpLeases) { lease in
                            LabeledContent(lease.hostname.isEmpty ? lease.mac : lease.hostname, value: lease.ip)
                        }
                    }
                }
                .padding(.top, 4)
            }

            if !ble.relays.isEmpty {
                relaysSection
            }

            Button("Reset") {
                ble.resetNetwork()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Relays (pi-relay-control-alpine, via pi-bluetooth-configuration)

    private var relaysSection: some View {
        GroupBox("Relays") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ble.relays) { relay in
                    Toggle(isOn: Binding(
                        get: { relay.isOn },
                        set: { ble.setRelay(port: relay.port, on: $0) }
                    )) {
                        Text(relay.label)
                    }
                    .toggleStyle(.switch)
                    .disabled(relay.state == "unknown")
                }
            }
            .padding(.top, 4)
        }
    }

    private func rangeAddress(_ lastOctet: Int) -> String {
        let ip = ble.ethernetConfig.ip
        guard let dot = ip.lastIndex(of: ".") else { return "\(lastOctet)" }
        return "\(ip[ip.startIndex..<dot]).\(lastOctet)"
    }

    // MARK: - Wizard (WiFi not yet configured, or configured but not finished)

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
            case .localNetworkConfig:
                localNetworkConfigStep
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

    // MARK: - Local network configuration (last wizard step, after WiFi joins)

    private var localNetworkConfigStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local Network Configuration").font(.headline)
            Text("eth0 already has a working gateway IP and DHCP server. Adjust it here if you'd like, or just continue.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Text("IP address").frame(width: 90, alignment: .leading)
                TextField("192.168.4.1", text: $localIPField)
                    .frame(maxWidth: 160)
            }
            HStack {
                Text("DHCP range").frame(width: 90, alignment: .leading)
                TextField("2", text: $rangeStartField)
                    .frame(maxWidth: 50)
                Text("–")
                TextField("200", text: $rangeEndField)
                    .frame(maxWidth: 50)
            }

            Button("Finish") {
                let start = Int(rangeStartField) ?? ble.ethernetConfig.rangeStart
                let end = Int(rangeEndField) ?? ble.ethernetConfig.rangeEnd
                ble.setLocalNetworkConfig(ip: localIPField, rangeStart: start, rangeEnd: end)
                ble.finishSetup()
            }
            .disabled(!isValidIPv4(localIPField) || Int(rangeStartField) == nil || Int(rangeEndField) == nil)
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            if localIPField.isEmpty { localIPField = ble.ethernetConfig.ip }
            if rangeStartField.isEmpty { rangeStartField = String(ble.ethernetConfig.rangeStart) }
            if rangeEndField.isEmpty { rangeEndField = String(ble.ethernetConfig.rangeEnd) }
        }
    }

    // Mirrors the daemon's own is_valid_ipv4 (eth_control.hpp): 4
    // dot-separated all-digit octets, each 0-255. Just a client-side
    // sanity gate on the Finish button -- the daemon is the actual
    // validation boundary.
    private func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, part.allSatisfy(\.isNumber),
                  let value = Int(part) else { return false }
            return value >= 0 && value <= 255
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
