import SwiftUI
import UIKit

@main
struct NOADApp: App {
    @StateObject private var controller = BlockerController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(controller)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var controller: BlockerController
    @State private var newBlockedDomain = ""
    @State private var newAllowedDomain = ""
    @State private var testHostname = ""
    @State private var testResultMessage: String?
    @State private var exportedProfileURL: URL?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            List {
                // NØAD Hero Header with Logo Icon
                Section {
                    HStack(spacing: 14) {
                        Image("NOADLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .shadow(radius: 3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(controller.adBlockingEnabled || controller.appAdBlockingEnabled ? "NØAD Protection Active" : "NØAD Protection Paused")
                                .font(.headline)
                            Text("\(controller.activeSafariRuleCount.formatted()) Safari rules • \(controller.coreBlockHostCount.formatted()) In-App rules")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(controller.statusMessage)
                                .font(.caption2)
                                .foregroundStyle(.teal)
                        }
                        Spacer()
                        if controller.isBusy {
                            ProgressView()
                        }
                    }
                    .padding(.vertical, 6)

                    Toggle(isOn: $controller.adBlockingEnabled) {
                        Label("Safari Ad & Tracker Blocking", systemImage: "safari.fill")
                    }
                    .tint(.teal)

                    Toggle(isOn: $controller.appAdBlockingEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("In-App Ad & Tracker Blocking (ConnectProxy)", systemImage: "network.badge.shield.half.filled")
                            Text(controller.localProxyRunning
                                 ? "ConnectProxyServer running on 127.0.0.1:9090 • \(controller.blockedInAppRequestsCount) blocked"
                                 : "ConnectProxyServer stopped")
                                .font(.caption2)
                                .foregroundStyle(controller.localProxyRunning ? .green : .secondary)
                        }
                    }
                    .tint(.teal)
                }

                // Local ConnectProxyServer + Automatic PAC Sinkhole Section
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recommended (Never Disconnects in Background):")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.teal)
                        Text("Settings → Wi-Fi → (i) → Configure Proxy → Automatic")
                            .font(.caption)
                        HStack {
                            Text("https://raw.githubusercontent.com/Dynamicmusix/noad/main/noad.pac")
                                .font(.caption2.monospaced())
                                .lineLimit(1)
                            Spacer()
                            Button("Copy PAC URL") {
                                UIPasteboard.general.string = "https://raw.githubusercontent.com/Dynamicmusix/noad/main/noad.pac"
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.teal)
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Local Proxy Server: 127.0.0.1")
                                .font(.subheadline.weight(.medium))
                            Text("Port: 9090 (202,867 core_block.txt rules active)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Copy 127.0.0.1") {
                            UIPasteboard.general.string = "127.0.0.1"
                        }
                        .buttonStyle(.bordered)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Test Hostname Against NetworkBlockingHandler (core_block.txt):")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("e.g. youtubei.youtube.com or ads.youtube.com", text: $testHostname)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Test") {
                                let res = controller.isHostnameBlockedInApp(testHostname)
                                testResultMessage = (res.blocked ? "🛑 BLOCKED: " : "✅ ALLOWED: ") + res.reason
                            }
                            .buttonStyle(.bordered)
                        }
                        if let msg = testResultMessage {
                            Text(msg)
                                .font(.caption2)
                                .foregroundStyle(msg.hasPrefix("🛑") ? .red : .green)
                        }
                    }

                    if !controller.recentProxyActivity.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Live ConnectProxyServer Pipeline Activity:")
                                .font(.caption.weight(.semibold))
                            ForEach(controller.recentProxyActivity.prefix(8)) { entry in
                                HStack {
                                    Image(systemName: entry.blocked ? "xmark.octagon.fill" : "checkmark.circle.fill")
                                        .foregroundStyle(entry.blocked ? .red : .green)
                                        .font(.caption2)
                                    Text(entry.host)
                                        .font(.caption2.monospaced())
                                        .lineLimit(1)
                                    Spacer()
                                    Text(entry.blocked ? "BLOCKED" : "ALLOWED")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(entry.blocked ? .red : .secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Local ConnectProxyServer Pipeline (YouTube & All Apps)")
                } footer: {
                    Text("To route all iPhone app traffic (including the YouTube app) through NØAD's local 202,868-rule ConnectProxyServer pipeline on a Free Apple ID: go to Settings → Wi-Fi → tap (i) → Configure Proxy → Manual → Server: 127.0.0.1, Port: 9090 → Save.")
                }

                // Feature 1 & 2: Exact Magic Lasso Toggles
                Section("Safari & YouTube Ruleset Toggles") {
                    Toggle("Core Ads & Trackers (57,506 rules)", isOn: $controller.adBlockingEnabled)
                        .tint(.teal)
                    Toggle("Block Annoyances & Pop-ups (3,732 rules)", isOn: $controller.annoyancesEnabled)
                        .tint(.teal)
                    Toggle("Anti-Adblock Killer (2,773 rules)", isOn: $controller.antiAdblockEnabled)
                        .tint(.teal)
                    Toggle("Block YouTube Video Ads (17 rules + JS)", isOn: $controller.youtubeAdsEnabled)
                        .tint(.teal)
                    Toggle("Battery Boost / Cryptomining (308 rules)", isOn: $controller.cryptominingEnabled)
                        .tint(.teal)
                    Toggle("Strict Mode (Block Affiliate Redirects)", isOn: $controller.strictModeEnabled)
                        .tint(.teal)

                    Picker("Regional Ad Blocking (22 Languages)", selection: $controller.selectedRegionalRuleset) {
                        ForEach(RegionalRuleset.allCases) { region in
                            Text(region.displayName).tag(region)
                        }
                    }

                    Button {
                        Task { await controller.updateRulesFromServer() }
                    } label: {
                        Label("Update All Rules Over-the-Air", systemImage: "arrow.triangle.2.circlepath")
                    }
                }

                // Encrypted DNS Backup Option
                Section("Optional: Encrypted DNS Profile (.mobileconfig)") {
                    Picker("Encrypted DNS Provider", selection: $controller.selectedDNSProvider) {
                        ForEach(EncryptedDNSProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }

                    if controller.selectedDNSProvider == .custom {
                        TextField("https://your-doh-server/dns-query", text: $controller.customDoHURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button {
                        if let url = controller.generateEncryptedDNSProfileURL() {
                            exportedProfileURL = url
                            showShareSheet = true
                        }
                    } label: {
                        Label("Export NØAD Encrypted DNS Profile", systemImage: "arrow.up.doc")
                    }
                }

                // Custom Blocklist / Allowlist
                Section("NØAD Custom Rules (Blocklist & Allowlist)") {
                    HStack {
                        TextField("Block domain (e.g. ads.example.com)", text: $newBlockedDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Block") {
                            let d = newBlockedDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !d.isEmpty && !controller.customBlockedDomains.contains(d) {
                                controller.customBlockedDomains.append(d)
                                newBlockedDomain = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                    ForEach(controller.customBlockedDomains, id: \.self) { host in
                        HStack {
                            Image(systemName: "xmark.shield.fill").foregroundStyle(.red)
                            Text(host)
                        }
                    }
                    .onDelete { idx in controller.customBlockedDomains.remove(atOffsets: idx) }

                    HStack {
                        TextField("Allow domain (bypass Safari & Proxy)", text: $newAllowedDomain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Allow") {
                            let d = newAllowedDomain.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !d.isEmpty && !controller.customAllowedDomains.contains(d) {
                                controller.customAllowedDomains.append(d)
                                newAllowedDomain = ""
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    ForEach(controller.customAllowedDomains, id: \.self) { host in
                        HStack {
                            Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                            Text(host)
                        }
                    }
                    .onDelete { idx in controller.customAllowedDomains.remove(atOffsets: idx) }
                }
            }
            .navigationTitle("NØAD")
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedProfileURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
