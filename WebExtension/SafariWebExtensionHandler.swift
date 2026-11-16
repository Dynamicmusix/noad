import SafariServices
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) ?? .standard
        let adBlockingEnabled = defaults.object(forKey: "adBlockingEnabled") as? Bool ?? true
        let youtubeAdsEnabled = defaults.object(forKey: "youtubeAdsEnabled") as? Bool ?? true

        let response = NSExtensionItem()
        response.userInfo = [
            SFExtensionMessageKey: [
                "adBlockingEnabled": adBlockingEnabled,
                "youtubeAdsEnabled": youtubeAdsEnabled
            ]
        ]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}

