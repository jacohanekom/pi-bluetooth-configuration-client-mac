import Foundation
import Network

/// Plain JSON-over-TCP client for pi-bluetooth-configuration's handoff
/// interface (see that repo's README, "WiFi/Bluetooth coexistence and the
/// TCP handoff"). The Pi 3's onboard Bluetooth shares an antenna with its
/// WiFi radio, so BLE routinely drops once WiFi is actively passing
/// traffic -- once Status reports a non-empty ip, BLEManager switches to
/// this instead of continuing to rely on the BLE link.
final class NetworkControlClient {
    var onStatus: ((WifiStatus) -> Void)?
    var onScanResults: (([WifiScanResult]) -> Void)?
    var onError: ((String) -> Void)?

    private var connection: NWConnection?
    private var buffer = Data()

    func connect(host: String, port: UInt16) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.onError?("Network control connection failed: \(error.localizedDescription)")
            }
        }
        conn.start(queue: .main)
        receiveLoop()
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        buffer.removeAll()
    }

    func send(cmd: String, extra: [String: String] = [:]) {
        guard let connection else { return }
        var fields = ["\"cmd\":\"\(escape(cmd))\""]
        for (key, value) in extra {
            fields.append("\"\(escape(key))\":\"\(escape(value))\"")
        }
        let json = "{" + fields.joined(separator: ",") + "}\n"
        connection.send(content: Data(json.utf8), completion: .contentProcessed { _ in })
    }

    private func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }
            if let error {
                self.onError?("Network control connection error: \(error.localizedDescription)")
                return
            }
            if isComplete { return }
            self.receiveLoop()
        }
    }

    private func processBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            guard !lineData.isEmpty else { continue }

            // Every reply is either a status object, a scan-results array,
            // or a plain {"ok":...} ack -- try the two we act on and
            // silently ignore acks, since commands here are fire-and-poll.
            if let status = try? JSONDecoder().decode(WifiStatus.self, from: lineData) {
                onStatus?(status)
            } else if let results = try? JSONDecoder().decode([WifiScanResult].self, from: lineData) {
                onScanResults?(results)
            }
        }
    }
}
