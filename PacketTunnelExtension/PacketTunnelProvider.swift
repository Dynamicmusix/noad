import Foundation
import NetworkExtension
import os.log

/// Exact replication of `MagicLassoiOSPacketTunnelProviderExtension.PacketTunnelProvider`.
/// Starts `ConnectProxyServer` (`NetworkBlockingHandler` + `ConnectHandler`) on `127.0.0.1:9090`,
/// configures `NEPacketTunnelNetworkSettings` with `NEProxySettings` (and Magic Lasso's exact
/// exceptionList `192.168.*`, `*.local`, `*.lan`, `*.apple.com`) plus `NEDNSOverHTTPSSettings` (`1.1.1.1`, `1.0.0.1`).
final class PacketTunnelProvider: NEPacketTunnelProvider {
    private let logger = Logger(subsystem: AppConstants.packetTunnelBundleIdentifier, category: "PacketTunnelProvider")

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        loadRulesIntoConnectProxy()

        do {
            try ConnectProxyServer.shared.start(enableAudioKeepAlive: false)
            logger.info("PacketTunnelProvider: Server started successfully")
        } catch {
            logger.error("PacketTunnelProvider: Unable to start server: \(error.localizedDescription, privacy: .public)")
            completionHandler(error)
            return
        }

        let proxyPort = Int(ConnectProxyServer.shared.port)
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = 1500

        // Configure IPv4 loopback settings for the virtual interface
        let ipv4 = NEIPv4Settings(addresses: ["10.254.254.1"], subnetMasks: ["255.255.255.252"])
        settings.ipv4Settings = ipv4

        // Exact NEProxySettings + exceptionList from Magic Lasso's binary (__oslogstring / __cstring [34]..[43])
        let proxySettings = NEProxySettings()
        let proxyServer = NEProxyServer(address: "127.0.0.1", port: proxyPort)
        proxySettings.httpEnabled = true
        proxySettings.httpServer = proxyServer
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = proxyServer
        proxySettings.excludeSimpleHostnames = true
        proxySettings.exceptionList = [
            "192.168.*",
            "*.local",
            "*.lan",
            "idmsa.apple.com",
            "gsa.apple.com",
            "ids.apple.com",
            "*.ids.apple.com",
            "ess.apple.com",
            "*.ess.apple.com",
            "gs.apple.com"
        ]
        settings.proxySettings = proxySettings

        // Exact NEDNSOverHTTPSSettings from Magic Lasso's binary (__cstring [44]..[45]: "1.1.1.1", "1.0.0.1")
        let dnsSettings = NEDNSOverHTTPSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dnsSettings.serverURL = URL(string: "https://cloudflare-dns.com/dns-query")
        settings.dnsSettings = dnsSettings

        setTunnelNetworkSettings(settings) { [weak self] error in
            if let error = error {
                self?.logger.error("PacketTunnelProvider: error occured while setTunnelNetworkSettings:\(error.localizedDescription, privacy: .public)")
                completionHandler(error)
                return
            }
            self?.logger.info("PacketTunnelProvider: Settings set successfully")
            completionHandler(nil)
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        ConnectProxyServer.shared.stop()
        logger.info("PacketTunnelProvider: closeAndCleanUpTunnel completed")
        completionHandler()
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // Reload rules when main app notifies rulesetBackedRepresentationDidChange
        loadRulesIntoConnectProxy()
        completionHandler?(Data("OK".utf8))
    }

    private func loadRulesIntoConnectProxy() {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
        let customBlocked = Set((defaults.stringArray(forKey: "customBlockedDomains") ?? []).map { $0.lowercased() })
        let customAllowed = Set((defaults.stringArray(forKey: "customAllowedDomains") ?? []).map { $0.lowercased() })

        var blocked = customBlocked
        var allowed = customAllowed

        if let groupBlockURL = AppConstants.sharedBlocklistFileURL,
           let text = try? String(contentsOf: groupBlockURL, encoding: .utf8) {
            blocked.formUnion(text.split(whereSeparator: \.isNewline).map { String($0).lowercased() })
        } else if let bundleBlockURL = Bundle.main.url(forResource: "core_block", withExtension: "txt"),
                  let text = try? String(contentsOf: bundleBlockURL, encoding: .utf8) {
            blocked.formUnion(text.split(whereSeparator: \.isNewline).map { String($0).lowercased() })
        }

        if let groupAllowURL = AppConstants.sharedAllowlistFileURL,
           let text = try? String(contentsOf: groupAllowURL, encoding: .utf8) {
            allowed.formUnion(text.split(whereSeparator: \.isNewline).map { String($0).lowercased() })
        } else if let bundleAllowURL = Bundle.main.url(forResource: "core_allow", withExtension: "txt"),
                  let text = try? String(contentsOf: bundleAllowURL, encoding: .utf8) {
            allowed.formUnion(text.split(whereSeparator: \.isNewline).map { String($0).lowercased() })
        }

        logger.info("NetworkBlockingHandler: set _allowRules to \(allowed.count) rules.")
        logger.info("NetworkBlockingHandler: set _blockRules to \(blocked.count) rules.")
        ConnectProxyServer.shared.updateRules(block: blocked, allow: allowed)
    }
}
