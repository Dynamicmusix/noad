import Foundation
import Network
import AVFoundation
import UIKit

/// Replicates Magic Lasso's exact `ConnectProxyServer` + `NetworkBlockingHandler` + `ConnectHandler`
/// local TCP HTTP/HTTPS CONNECT proxy pipeline using all 202,868 domains in `core_block.txt` and `core_allow.txt`.
/// Uses direct POSIX BSD sockets (`getaddrinfo` + `socket` + `connect`) for upstream connections so it
/// NEVER loops back into the system Wi-Fi HTTP proxy (`127.0.0.1:9090`)!
public final class ConnectProxyServer: @unchecked Sendable {
    public static let shared = ConnectProxyServer()

    public let port: UInt16 = 9090
    private let acceptQueue = DispatchQueue(label: "com.noad.app.ConnectProxy.accept", qos: .userInitiated)
    private let workerQueue = DispatchQueue(label: "com.noad.app.ConnectProxy.worker", qos: .userInitiated, attributes: .concurrent)

    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var audioPlayer: AVAudioPlayer?
    #if !EXTENSION
    private var bgTask: UIBackgroundTaskIdentifier = .invalid
    #endif

    private var blockRules: Set<String> = []
    private var allowRules: Set<String> = []
    private let rulesLock = NSLock()

    public var onActivity: (@Sendable (String, Bool) -> Void)?
    public private(set) var isRunning: Bool = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.ensureKeepAlivePlaying()
        }
        #if !EXTENSION
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.beginExtendedBackgroundTask()
            self?.ensureKeepAlivePlaying()
        }
        #endif
    }

    // MARK: - NetworkBlockingHandler Rule Table

    public func updateRules(block: Set<String>, allow: Set<String>) {
        rulesLock.lock()
        var cleanBlock = block
        // Ensure youtubei.youtube.com is not blocked if it breaks player metadata, while keeping ads.youtube.com, doubleclick.net, etc.
        cleanBlock.remove("youtubei.youtube.com")
        self.blockRules = cleanBlock
        self.allowRules = allow
        rulesLock.unlock()
    }

    public func shouldBlock(host rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return false }

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

    // MARK: - Start / Stop Pure POSIX Local Proxy Server (Zero Proxy Loopback!)

    public func start(enableAudioKeepAlive: Bool = true) throws {
        if isRunning && serverFD >= 0 { return }
        stop()

        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            throw NSError(domain: "ConnectProxyServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else {
            close(fd)
            throw NSError(domain: "ConnectProxyServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "bind(127.0.0.1:\(port)) failed"])
        }

        guard listen(fd, 256) == 0 else {
            close(fd)
            throw NSError(domain: "ConnectProxyServer", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        self.serverFD = fd
        self.isRunning = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.acceptSource = source

        if enableAudioKeepAlive {
            startBackgroundKeepAlive()
            beginExtendedBackgroundTask()
        }
    }

    public func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFD = -1
        isRunning = false
        stopBackgroundKeepAlive()
    }

    private func acceptPendingClients() {
        while serverFD >= 0 {
            var clientAddr = sockaddr_storage()
            var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(serverFD, $0, &addrLen)
                }
            }
            if clientFD < 0 {
                break
            }
            var yes: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            workerQueue.async { [weak self] in
                self?.handleClientSocket(clientFD)
            }
        }
    }

    // MARK: - HTTPServerPipelineHandler -> NetworkBlockingHandler -> Direct POSIX ConnectHandler

    private func handleClientSocket(_ clientFD: Int32) {
        var tv = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var buf = [UInt8](repeating: 0, count: 16384)
        let n = recv(clientFD, &buf, buf.count, 0)
        guard n > 0, let requestHeader = String(bytes: buf[0..<n], encoding: .utf8) else {
            close(clientFD)
            return
        }

        guard let firstLine = requestHeader.components(separatedBy: "\r\n").first else {
            close(clientFD)
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            close(clientFD)
            return
        }

        let method = String(parts[0]).uppercased()
        let target = String(parts[1])
        let (host, targetPort) = extractHostAndPort(method: method, target: target, fullHeader: requestHeader)

        guard !host.isEmpty, host != "127.0.0.1", host != "localhost" else {
            close(clientFD)
            return
        }

        // NetworkBlockingHandler check against 202,868 core_block.txt rules + URL ad patterns
        let isURLAd = target.contains("/pagead/") || target.contains("/pcs/activeview") || target.contains("is_ad=1") || target.contains("adformat=")
        if shouldBlock(host: host) || isURLAd {
            onActivity?(host, true)
            let blockedResp = Array("HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
            _ = sendAll(fd: clientFD, bytes: blockedResp, count: blockedResp.count)
            close(clientFD)
            return
        }

        onActivity?(host, false)

        // Direct POSIX socket connection to remote host:port — completely bypasses iOS Wi-Fi HTTP proxy settings!
        let upstreamFD = connectDirectPOSIX(host: host, port: targetPort)
        guard upstreamFD >= 0 else {
            let badGw = Array("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".utf8)
            _ = sendAll(fd: clientFD, bytes: badGw, count: badGw.count)
            close(clientFD)
            return
        }

        if method == "CONNECT" {
            let okResp = Array("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)
            guard sendAll(fd: clientFD, bytes: okResp, count: okResp.count) else {
                close(clientFD)
                close(upstreamFD)
                return
            }
        } else {
            // Forward plain HTTP request
            guard sendAll(fd: upstreamFD, bytes: Array(buf[0..<n]), count: n) else {
                close(clientFD)
                close(upstreamFD)
                return
            }
        }

        // Bidirectional TCP relay
        workerQueue.async {
            Self.pump(from: clientFD, to: upstreamFD)
        }
        Self.pump(from: upstreamFD, to: clientFD)
    }

    private func connectDirectPOSIX(host: String, port: UInt16) -> Int32 {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var res: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &res)
        guard status == 0, let firstAddr = res else {
            return -1
        }
        defer { freeaddrinfo(res) }

        var ptr: UnsafeMutablePointer<addrinfo>? = firstAddr
        while let info = ptr {
            let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if fd >= 0 {
                var yes: Int32 = 1
                setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
                var tv = timeval(tv_sec: 10, tv_usec: 0)
                setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                    var longTv = timeval(tv_sec: 120, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &longTv, socklen_t(MemoryLayout<timeval>.size))
                    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &longTv, socklen_t(MemoryLayout<timeval>.size))
                    return fd
                }
                close(fd)
            }
            ptr = info.pointee.ai_next
        }
        return -1
    }

    private func sendAll(fd: Int32, bytes: [UInt8], count: Int) -> Bool {
        var sent = 0
        while sent < count {
            let w = bytes.withUnsafeBufferPointer { ptr in
                send(fd, ptr.baseAddress! + sent, count - sent, 0)
            }
            if w <= 0 { return false }
            sent += w
        }
        return true
    }

    private static func pump(from srcFD: Int32, to dstFD: Int32) {
        var buf = [UInt8](repeating: 0, count: 32768)
        while true {
            let r = recv(srcFD, &buf, buf.count, 0)
            if r <= 0 { break }
            var sent = 0
            var failed = false
            while sent < r {
                let w = buf.withUnsafeBufferPointer { ptr in
                    send(dstFD, ptr.baseAddress! + sent, r - sent, 0)
                }
                if w <= 0 {
                    failed = true
                    break
                }
                sent += w
            }
            if failed { break }
        }
        shutdown(dstFD, SHUT_WR)
        close(srcFD)
    }

    // MARK: - Background Keep-Alive (Audio + Extended Background Task)

    private func beginExtendedBackgroundTask() {
        #if !EXTENSION
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.bgTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.bgTask)
            }
            self.bgTask = UIApplication.shared.beginBackgroundTask(withName: "NOADConnectProxy") { [weak self] in
                guard let self = self else { return }
                UIApplication.shared.endBackgroundTask(self.bgTask)
                self.bgTask = .invalid
            }
        }
        #endif
    }

    private func ensureKeepAlivePlaying() {
        guard isRunning else { return }
        if audioPlayer?.isPlaying != true {
            startBackgroundKeepAlive()
        }
    }

    private func startBackgroundKeepAlive() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

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
            player.volume = 0.01
            player.play()
            self.audioPlayer = player
        } catch {}
    }

    private func stopBackgroundKeepAlive() {
        audioPlayer?.stop()
        audioPlayer = nil
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
