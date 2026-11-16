import Foundation

public enum AppConstants {
    public static let appName = "NØAD"
    public static let appGroupIdentifier = "group.com.noad.app"
    public static let contentBlockerBundleIdentifier = "com.noad.app.ContentBlocker"
    public static let webExtensionBundleIdentifier = "com.noad.app.WebExtension"
    public static let packetTunnelBundleIdentifier = "com.noad.app.PacketTunnel"
    public static let mergedRulesFilename = "activeBlockerList.json"
    public static let sharedBlocklistFilename = "core_block.txt"
    public static let sharedAllowlistFilename = "core_allow.txt"
    public static let rulesBaseURL = "https://rules.magiclasso.co/latest/v2/"

    public static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public static var mergedRulesFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(mergedRulesFilename)
    }

    public static var sharedBlocklistFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(sharedBlocklistFilename)
    }

    public static var sharedAllowlistFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(sharedAllowlistFilename)
    }
}
