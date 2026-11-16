import Foundation
import SafariServices
import NetworkExtension
import Combine

@MainActor
public final class BlockerController: ObservableObject {
    public static let shared = BlockerController()

    private let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard

    @Published public var adBlockingEnabled: Bool {
        didSet { defaults.set(adBlockingEnabled, forKey: "adBlockingEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var appAdBlockingEnabled: Bool {
        didSet { defaults.set(appAdBlockingEnabled, forKey: "appAdBlockingEnabled") }
    }
    @Published public var annoyancesEnabled: Bool {
        didSet { defaults.set(annoyancesEnabled, forKey: "annoyancesEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var antiAdblockEnabled: Bool {
        didSet { defaults.set(antiAdblockEnabled, forKey: "antiAdblockEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var cryptominingEnabled: Bool {
        didSet { defaults.set(cryptominingEnabled, forKey: "cryptominingEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var youtubeAdsEnabled: Bool {
        didSet { defaults.set(youtubeAdsEnabled, forKey: "youtubeAdsEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var strictModeEnabled: Bool {
        didSet { defaults.set(strictModeEnabled, forKey: "strictModeEnabled"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var selectedRegionalRuleset: RegionalRuleset {
        didSet { defaults.set(selectedRegionalRuleset.rawValue, forKey: "selectedRegionalRuleset"); Task { await rebuildAndReloadSafariRules() } }
    }

    @Published public var customBlockedDomains: [String] {
        didSet { defaults.set(customBlockedDomains, forKey: "customBlockedDomains"); Task { await rebuildAndReloadSafariRules() } }
    }
    @Published public var customAllowedDomains: [String] {
        didSet { defaults.set(customAllowedDomains, forKey: "customAllowedDomains"); Task { await rebuildAndReloadSafariRules() } }
    }

    @Published public var selectedDNSProvider: EncryptedDNSProvider {
        didSet { defaults.set(selectedDNSProvider.rawValue, forKey: "selectedDNSProvider") }
    }
    @Published public var customDoHURL: String {
        didSet { defaults.set(customDoHURL, forKey: "customDoHURL") }
    }
    @Published public var excludedWiFiSSIDs: [String] {
        didSet { defaults.set(excludedWiFiSSIDs, forKey: "excludedWiFiSSIDs") }
    }

    @Published public var activeSafariRuleCount: Int = 0
    @Published public var coreBlockHostCount: Int = 202_868
    @Published public var coreAllowHostCount: Int = 4
    @Published public var safariExtensionEnabled: Bool = false
    @Published public var systemDNSEnabled: Bool = false
    @Published public var statusMessage: String = "Ready"
    @Published public var isBusy: Bool = false

    private var coreBlockedDomainsSet: Set<String> = []
    private var coreAllowedDomainsSet: Set<String> = []

    private init() {
        self.adBlockingEnabled = defaults.object(forKey: "adBlockingEnabled") as? Bool ?? true
        self.appAdBlockingEnabled = defaults.object(forKey: "appAdBlockingEnabled") as? Bool ?? true
        self.annoyancesEnabled = defaults.object(forKey: "annoyancesEnabled") as? Bool ?? true
        self.antiAdblockEnabled = defaults.object(forKey: "antiAdblockEnabled") as? Bool ?? true
        self.cryptominingEnabled = defaults.object(forKey: "cryptominingEnabled") as? Bool ?? true
        self.youtubeAdsEnabled = defaults.object(forKey: "youtubeAdsEnabled") as? Bool ?? true
        self.strictModeEnabled = defaults.object(forKey: "strictModeEnabled") as? Bool ?? false
        let rawRegion = defaults.string(forKey: "selectedRegionalRuleset") ?? RegionalRuleset.none.rawValue
        self.selectedRegionalRuleset = RegionalRuleset(rawValue: rawRegion) ?? .none
        self.customBlockedDomains = defaults.stringArray(forKey: "customBlockedDomains") ?? []
        self.customAllowedDomains = defaults.stringArray(forKey: "customAllowedDomains") ?? []
        let rawProvider = defaults.string(forKey: "selectedDNSProvider") ?? EncryptedDNSProvider.adguard.rawValue
        self.selectedDNSProvider = EncryptedDNSProvider(rawValue: rawProvider) ?? .adguard
        self.customDoHURL = defaults.string(forKey: "customDoHURL") ?? "https://dns.adguard-dns.com/dns-query"
        self.excludedWiFiSSIDs = defaults.stringArray(forKey: "excludedWiFiSSIDs") ?? []

        Task {
            await loadCoreNetworkBlockerLists()
            await refreshStatus()
            await rebuildAndReloadSafariRules()
        }
    }

    // MARK: - Core Network Blocker Lists (202,868 blocked domains + allowlist)

    public func loadCoreNetworkBlockerLists() async {
        if let blockURL = Bundle.main.url(forResource: "core_block", withExtension: "txt"),
           let text = try? String(contentsOf: blockURL, encoding: .utf8) {
            let lines = text.split(whereSeparator: \.isNewline).map { String($0).lowercased() }
            coreBlockedDomainsSet = Set(lines)
            coreBlockHostCount = coreBlockedDomainsSet.count
        }
        if let allowURL = Bundle.main.url(forResource: "core_allow", withExtension: "txt"),
           let text = try? String(contentsOf: allowURL, encoding: .utf8) {
            let lines = text.split(whereSeparator: \.isNewline).map { String($0).lowercased() }
            coreAllowedDomainsSet = Set(lines)
            coreAllowHostCount = coreAllowedDomainsSet.count
        }
    }

    public func isHostnameBlockedInApp(_ hostname: String) -> (blocked: Bool, reason: String) {
        let host = hostname.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !host.isEmpty else { return (false, "Enter a hostname") }
        if customAllowedDomains.contains(where: { host == $0.lowercased() || host.hasSuffix(".\($0.lowercased())") }) {
            return (false, "Allowed by Custom Allowlist")
        }
        if coreAllowedDomainsSet.contains(host) {
            return (false, "Allowed by Core Allowlist (core_allow.txt)")
        }
        if customBlockedDomains.contains(where: { host == $0.lowercased() || host.hasSuffix(".\($0.lowercased())") }) {
            return (true, "Blocked by Custom Blocklist")
        }
        let parts = host.split(separator: ".")
        for i in 0..<parts.count {
            let candidate = parts[i...].joined(separator: ".")
            if coreBlockedDomainsSet.contains(candidate) {
                return (true, "Blocked by Core In-App Blocklist (matches '\(candidate)' in 202,868-domain core_block.txt)")
            }
        }
        return (false, "Not in core_block.txt (Allowed)")
    }

    // MARK: - 1. Safari Content Blocker Rule Compiler & Reloader

    public func rebuildAndReloadSafariRules() async {
        isBusy = true
        defer { isBusy = false }

        var merged: [SafariContentRule] = []

        if adBlockingEnabled {
            merged.append(contentsOf: loadBundledOrCachedRules(named: "default"))
            if antiAdblockEnabled {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "anti-adblock"))
            }
            if annoyancesEnabled {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "annoyances"))
            }
            if cryptominingEnabled {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "cryptomining"))
            }
            if youtubeAdsEnabled {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "youtube"))
            }
            if let regionalFile = selectedRegionalRuleset.localFilename {
                merged.append(contentsOf: loadBundledOrCachedRules(named: regionalFile))
            }
            if strictModeEnabled {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "strictmode-active"))
            } else {
                merged.append(contentsOf: loadBundledOrCachedRules(named: "strictmode-inactive"))
            }
            for host in customBlockedDomains {
                let escaped = NSRegularExpression.escapedPattern(for: host.lowercased())
                merged.append(SafariContentRule(
                    trigger: .init(urlFilter: "^https?:\\/\\/(.*\\.)*\(escaped)[^a-zA-Z0-9_\\-\\.%].*"),
                    action: .init(type: "block", selector: nil)
                ))
            }
            for host in customAllowedDomains {
                let escaped = NSRegularExpression.escapedPattern(for: host.lowercased())
                merged.append(SafariContentRule(
                    trigger: .init(urlFilter: ".*", ifDomain: ["*\(escaped)"]),
                    action: .init(type: "ignore-previous-rules", selector: nil)
                ))
            }
        } else {
            merged.append(SafariContentRule(
                trigger: .init(urlFilter: "magiclasso\\.co"),
                action: .init(type: "css-display-none", selector: "#magic-lasso-disabled")
            ))
        }

        // Apple allows up to 150,000 rules per Content Blocker extension
        if merged.count > 149_500 {
            merged = Array(merged.prefix(149_500))
        }

        do {
            let data = try JSONEncoder().encode(merged)
            if let destURL = AppConstants.mergedRulesFileURL {
                try data.write(to: destURL, options: .atomic)
            }
            activeSafariRuleCount = merged.count
            try await SFContentBlockerManager.reloadContentBlocker(withIdentifier: AppConstants.contentBlockerBundleIdentifier)
            statusMessage = "NØAD loaded \(merged.count.formatted()) Safari rules"
        } catch {
            statusMessage = "NØAD Safari reload note: \(error.localizedDescription)"
        }
        await refreshStatus()
    }

    private func loadBundledOrCachedRules(named name: String) -> [SafariContentRule] {
        if let groupURL = AppConstants.sharedContainerURL?.appendingPathComponent("\(name).json"),
           let data = try? Data(contentsOf: groupURL),
           let rules = try? JSONDecoder().decode([SafariContentRule].self, from: data) {
            return rules
        }
        if let bundleURL = Bundle.main.url(forResource: name, withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let rules = try? JSONDecoder().decode([SafariContentRule].self, from: data) {
            return rules
        }
        return []
    }

    // MARK: - Live Over-the-Air Rule Updates

    public func updateRulesFromServer() async {
        isBusy = true
        statusMessage = "Updating NØAD rules from server..."
        defer { isBusy = false }

        var mapping: [(local: String, remote: String)] = [
            ("default", "index.json"),
            ("annoyances", "annoyances/index.json"),
            ("anti-adblock", "anti-adblock/index.json"),
            ("cryptomining", "cryptomining/index.json"),
            ("youtube", "youtube/index.json"),
            ("strictmode-inactive", "strictmode/inactive.json"),
            ("strictmode-active", "strictmode/active.json")
        ]
        if let regLocal = selectedRegionalRuleset.localFilename,
           let regRemote = selectedRegionalRuleset.remotePath {
            mapping.append((regLocal, regRemote))
        }

        var updatedCount = 0
        for item in mapping {
            guard let url = URL(string: AppConstants.rulesBaseURL + item.remote) else { continue }
            if let (data, response) = try? await URLSession.shared.data(from: url),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let dest = AppConstants.sharedContainerURL?.appendingPathComponent("\(item.local).json") {
                try? data.write(to: dest, options: .atomic)
                updatedCount += 1
            }
        }
        statusMessage = "NØAD updated \(updatedCount) rulesets; reloading Safari..."
        await rebuildAndReloadSafariRules()
    }

    // MARK: - 3. System-Wide In-App Blocking via iOS Encrypted DNS (.mobileconfig + NEDNSSettingsManager)

    public func generateEncryptedDNSProfileURL() -> URL? {
        let dohURL = selectedDNSProvider == .custom ? customDoHURL : selectedDNSProvider.serverURL
        let ips = selectedDNSProvider.serverAddresses

        var dnsSettings: [String: Any] = [
            "DNSProtocol": "HTTPS",
            "ServerURL": dohURL
        ]
        if !ips.isEmpty {
            dnsSettings["ServerAddresses"] = ips
        }

        var onDemandRules: [[String: Any]] = []
        if !excludedWiFiSSIDs.isEmpty {
            onDemandRules.append([
                "Action": "Disconnect",
                "InterfaceTypeMatch": "WiFi",
                "SSIDMatch": excludedWiFiSSIDs
            ])
        }
        let allAllowed = Array(coreAllowedDomainsSet.union(customAllowedDomains.map { $0.lowercased() })).sorted()
        if !allAllowed.isEmpty {
            onDemandRules.append([
                "Action": "EvaluateConnection",
                "ActionParameters": [[
                    "DomainAction": "NeverConnect",
                    "Domains": allAllowed
                ]]
            ])
        }
        onDemandRules.append(["Action": "Connect"])

        let payload: [String: Any] = [
            "PayloadDisplayName": "NØAD System-Wide AdBlock DNS (\(selectedDNSProvider.rawValue))",
            "PayloadIdentifier": "com.noad.app.dnssettings",
            "PayloadType": "com.apple.dnsSettings.managed",
            "PayloadUUID": "7A5E9E44-1122-4B6D-8F91-82C11D22E901",
            "PayloadVersion": 1,
            "DNSSettings": dnsSettings,
            "OnDemandRules": onDemandRules
        ]

        let rootProfile: [String: Any] = [
            "PayloadContent": [payload],
            "PayloadDescription": "NØAD blocks in-app ads and trackers across all iOS apps using Encrypted DNS-over-HTTPS (\(dohURL)).",
            "PayloadDisplayName": "NØAD In-App AdBlock DNS",
            "PayloadIdentifier": "com.noad.app.profile",
            "PayloadOrganization": "NØAD",
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": "9B6F8A55-3344-4E1C-9A02-71D22E33F812",
            "PayloadVersion": 1
        ]

        guard let plistData = try? PropertyListSerialization.data(fromPropertyList: rootProfile, format: .xml, options: 0) else {
            return nil
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("NOAD-AdBlock-DNS.mobileconfig")
        try? plistData.write(to: tempURL, options: .atomic)
        return tempURL
    }

    public func applyNativeNEDNSSettings() async {
        let manager = NEDNSSettingsManager.shared()
        do {
            try await manager.loadFromPreferences()
            let dohURL = selectedDNSProvider == .custom ? customDoHURL : selectedDNSProvider.serverURL
            guard let url = URL(string: dohURL) else { return }
            let settings = NEDNSOverHTTPSSettings(servers: selectedDNSProvider.serverAddresses)
            settings.serverURL = url
            manager.dnsSettings = settings
            manager.localizedDescription = "NØAD In-App AdBlock DNS"
            try await manager.saveToPreferences()
            statusMessage = "NØAD Encrypted DNS saved! Enable it in Settings → VPN & Device Management → DNS."
            await refreshStatus()
        } catch {
            statusMessage = "Tap 'Install NØAD Encrypted DNS Profile' on a Free Apple ID (\(error.localizedDescription))."
        }
    }

    public func refreshStatus() async {
        if let state = try? await SFContentBlockerManager.stateOfContentBlocker(withIdentifier: AppConstants.contentBlockerBundleIdentifier) {
            safariExtensionEnabled = state.isEnabled
        }
        try? await NEDNSSettingsManager.shared().loadFromPreferences()
        systemDNSEnabled = NEDNSSettingsManager.shared().isEnabled
    }
}
