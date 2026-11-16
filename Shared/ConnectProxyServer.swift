import Foundation
import Network
import AVFoundation

/// Replicates Magic Lasso's exact `ConnectProxyServer` + `NetworkBlockingHandler` + `ConnectHandler`
/// local TCP HTTP/HTTPS CONNECT proxy pipeline using all 202,868 domains in `core_block.txt` and `core_allow.txt`.
/// Runs directly on `127.0.0.1:9090` so it works on a Free Apple ID without needing paid VPN entitlements!
public final class ConnectProxyServer: @unchecked Sendable {
    public static let shared = ConnectProxyServer()

    public let port: UInt16 = 9090
    private let queue = DispatchQueue(label: "com.noad.app.ConnectProxyServer", qos: .userInitiated, attributes: .concurrent)
    private var listener: NWListener?
    private var audioPlayer: AVAudioPlayer?

    private var blockRules: Set<String> = []
    private var allowRules: Set<String> = []
    private let rulesLock = NSLock()

    public var onActivity: (@Sendable (String, Bool) -> Void)?
    public private(set) var isRunning: Bool = false

    private init() {}

    // MARK: - NetworkBlockingHandler Rule Table

    public func updateRules(block: Set<String>, allow: Set<String>) {
        rulesLock.lock()
        self.blockRules = block
        self.allowRules = allow
        rulesLock.unlock()
    }

    public func shouldBlock(host rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return false }

        // Bypass local and Apple auth hosts (from Magic Lasso binary strings [34]..[43])
        if host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasPrefix("192.168.") {
            return false
        }
        let appleBypass = ["idmsa.apple.com", "gsa.apple.com", "ids.apple.com", "ess.apple.com", "gs.apple.com"]
        for bypass in appleBypass {
            if host == bypass || host.hasSuffix(".\(bypass)") {
                return false
            }
        }

        rulesLock.lock()
        let allowed = allowRules
        let blocked = blockRules
        rulesLock.unlock()

        let parts = host.split(separator: ".")
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            if allowed.contains(candidate) {
                return false
            }
        }
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            if blocked.contains(candidate) {
                return true
            }
        }
        return false
    }

    // MARK: - Start / Stop Local Proxy Pipeline + Background Keep-Alive

    public func start(enableAudioKeepAlive: Bool = true) throws {
        if isRunning { return }

        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }

        let newListener = try NWListener(using: params, on: nwPort)
        newListener.newConnectionHandler = { [weak self] clientConn in
            self?.handleClientConnection(clientConn)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isRunning = true
            case .failed, .cancelled:
                self?.isRunning = false
            default:
                break
            }
        }
        newListener.start(queue: queue)
        self.listener = newListener
        self.isRunning = true
        if enableAudioKeepAlive {
            startBackgroundKeepAlive()
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        stopBackgroundKeepAlive()
    }

    // Keeps the local proxy alive in the background on iOS when the user switches to YouTube or other apps
    private func startBackgroundKeepAlive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)

            // Generate a tiny in-memory silent WAV buffer so iOS never suspends the proxy socket
            let sampleRate: UInt32 = 8000
            let numSamples: UInt32 = 8000
            var wav = Data()
            wav.append("RIFF".data(using: .ascii)!)
            var chunkSize: UInt32 = 36 + numSamples
            wav.append(Data(bytes: &chunkSize, count: 4))
            wav.append("WAVEfmt ".data(using: .ascii)!)
            var subchunk1Size: UInt32 = 16
            var audioFormat: UInt16 = 1
            var numChannels: UInt16 = 1
            var byteRate: UInt32 = sampleRate
            var blockAlign: UInt16 = 1
            var bitsPerSample: UInt16 = 8
            wav.append(Data(bytes: &subchunk1Size, count: 4))
            wav.append(Data(bytes: &audioFormat, count: 2))
            wav.append(Data(bytes: &numChannels, count: 2))
            var sr = sampleRate
            wav.append(Data(bytes: &sr, count: 4))
            wav.append(Data(bytes: &byteRate, count: 4))
            wav.append(Data(bytes: &blockAlign, count: 2))
            wav.append(Data(bytes: &bitsPerSample, count: 2))
            wav.append("data".data(using: .ascii)!)
            var subchunk2Size: UInt32 = numSamples
            wav.append(Data(bytes: &subchunk2Size, count: 4))
            wav.append(Data(repeating: 128, count: Int(numSamples)))

            let player = try AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
            player.numberOfLoops = -1
            player.volume = 0.0
            player.play()
            self.audioPlayer = player
        } catch {
            // Ignore audio session errors
        }
    }

    private func stopBackgroundKeepAlive() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    // MARK: - HTTPServerPipelineHandler -> NetworkBlockingHandler -> ConnectHandler

    private func handleClientConnection(_ client: NWConnection) {
        client.start(queue: queue)
        client.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self = self, let data = data, !data.isEmpty, error == nil,
                  let requestHeader = String(data: data, encoding: .utf8) else {
                client.cancel()
                return
            }

            guard let firstLine = requestHeader.components(separatedBy: "\r\n").first else {
                client.cancel()
                return
            }
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                client.cancel()
                return
            }

            let method = String(parts[0]).uppercased()
            let target = String(parts[1])

            let (host, targetPort) = self.extractHostAndPort(method: method, target: target, fullHeader: requestHeader)
            guard !host.isEmpty else {
                client.cancel()
                return
            }

            // NetworkBlockingHandler check against 202,868 core_block.txt rules
            if self.shouldBlock(host: host) {
                self.onActivity?(host, true)
                let blockedResp = "HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"
                client.send(content: blockedResp.data(using: .utf8), completion: .contentProcessed { _ in
                    client.cancel()
                })
                return
            }

            self.onActivity?(host, false)

            // ConnectHandler: establish upstream TCP tunnel
            guard let nwPort = NWEndpoint.Port(rawValue: targetPort) else {
                client.cancel()
                return
            }
            let upstream = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            upstream.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if method == "CONNECT" {
                        let okResp = "HTTP/1.1 200 Connection Established\r\n\r\n"
                        client.send(content: okResp.data(using: .utf8), completion: .contentProcessed { err in
                            if err != nil {
                                client.cancel()
                                upstream.cancel()
                                return
                            }
                            self.pipe(from: client, to: upstream)
                            self.pipe(from: upstream, to: client)
                        })
                    } else {
                        upstream.send(content: data, completion: .contentProcessed { err in
                            if err != nil {
                                client.cancel()
                                upstream.cancel()
                                return
                            }
                            self.pipe(from: client, to: upstream)
                            self.pipe(from: upstream, to: client)
                        })
                    }
                case .failed, .cancelled:
                    client.cancel()
                default:
                    break
                }
            }
            upstream.start(queue: self.queue)
        }
    }

    private func pipe(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                destination.send(content: data, completion: .contentProcessed { sendErr in
                    if sendErr != nil || isComplete || error != nil {
                        source.cancel()
                        destination.cancel()
                    } else {
                        self?.pipe(from: source, to: destination)
                    }
                })
            } else {
                source.cancel()
                destination.cancel()
            }
        }
    }

    private func extractHostAndPort(method: String, target: String, fullHeader: String) -> (String, UInt16) {
        if method == "CONNECT" {
            let hp = target.split(separator: ":")
            let h = String(hp[0])
            let p = hp.count > 1 ? (UInt16(hp[1]) ?? 443) : 443
            return (h, p)
        }
        if let url = URL(string: target), let h = url.host {
            let p = UInt16(url.port ?? (url.scheme == "https" ? 443 : 80))
            return (h, p)
        }
        for line in fullHeader.components(separatedBy: "\r\n") {
            if line.lowercased().hasPrefix("host:") {
                let value = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                let hp = value.split(separator: ":")
                let h = String(hp[0])
                let p = hp.count > 1 ? (UInt16(hp[1]) ?? 80) : 80
                return (h, p)
            }
        }
        return ("", 80)
    }
}

