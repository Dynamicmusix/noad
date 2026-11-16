import SwiftUI

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
                            Text(controller.adBlockingEnabled ? "NØAD Protection Active" : "NØAD Protection Paused")
                                .font(.headline)
                            Text("\(controller.activeSafariRuleCount.formatted()) Safari rules • \(controller.coreBlockHostCount.formatted()) In-App domains")
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

                    Toggle(isOn: Binding(
                        get: { controller.appAdBlockingEnabled },
                        set: { newValue in
                            controller.appAdBlockingEnabled = newValue
                            if newValue, let url = controller.generateEncryptedDNSProfileURL() {
                                exportedProfileURL = url
                                showShareSheet = true
                            }
                        }
                    )) {
                        Label("In-App Ad & Tracker Blocking", systemImage: "app.badge.checkmark.fill")
                    }
                    .tint(.teal)
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

                // Feature 3: System-Wide In-App Ad Blocking (Encrypted DNS + 202,868 Core Blocklist)
                Section {
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
                        Label("Install NØAD In-App Encrypted DNS Profile", systemImage: "network.badge.shield.half.filled")
                            .fontWeight(.semibold)
                    }

                    Button {
                        Task { await controller.applyNativeNEDNSSettings() }
                    } label: {
                        Label("Apply via Native NEDNSSettingsManager", systemImage: "gearshape.2")
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Check Hostname Against Bundled 202,868 In-App Blocklist:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("e.g. doubleclick.net or ads.tiktok.com", text: $testHostname)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button("Check") {
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
                    .padding(.vertical, 4)
                } header: {
                    Text("In-App Ad Blocking (Encrypted DNS + 202,868 Core Domains)")
                } footer: {
                    Text("Toggling 'In-App Ad & Tracker Blocking' or tapping 'Install NØAD In-App Encrypted DNS Profile' exports a signed-ready iOS Encrypted DNS (.mobileconfig) profile with your Custom Allowlist & Core Allowlist built in. Works on any Free Apple ID!")
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
                        TextField("Allow domain (bypass Safari & DNS)", text: $newAllowedDomain)
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

                // Setup Instructions
                Section("One-Time iPhone Setup for NØAD") {
                    Label("1. Settings → Apps → Safari → Extensions → Enable 'NØAD Block' & 'NØAD Web'", systemImage: "safari")
                        .font(.footnote)
                    Label("2. Install the NØAD Encrypted DNS Profile above, then enable it under Settings → General → VPN & Device Management → DNS", systemImage: "lock.shield")
                        .font(.footnote)
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
