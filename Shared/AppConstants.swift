import Foundation

public enum AppConstants {
    public static let appName = "NØAD"
    public static let appGroupIdentifier = "group.com.noad.app"
    public static let contentBlockerBundleIdentifier = "com.noad.app.ContentBlocker"
    public static let webExtensionBundleIdentifier = "com.noad.app.WebExtension"
    public static let mergedRulesFilename = "activeBlockerList.json"
    public static let rulesBaseURL = "https://rules.magiclasso.co/latest/v2/"

    public static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    public static var mergedRulesFileURL: URL? {
        sharedContainerURL?.appendingPathComponent(mergedRulesFilename)
    }
}
