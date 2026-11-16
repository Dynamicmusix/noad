import Foundation

final class ContentBlockerRequestHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        if let mergedURL = AppConstants.mergedRulesFileURL,
           FileManager.default.fileExists(atPath: mergedURL.path),
           let attachment = NSItemProvider(contentsOf: mergedURL) {
            let item = NSExtensionItem()
            item.attachments = [attachment]
            context.completeRequest(returningItems: [item], completionHandler: nil)
            return
        }

        if let fallbackURL = Bundle.main.url(forResource: "emptyBlockerList", withExtension: "json"),
           let attachment = NSItemProvider(contentsOf: fallbackURL) {
            let item = NSExtensionItem()
            item.attachments = [attachment]
            context.completeRequest(returningItems: [item], completionHandler: nil)
            return
        }

        context.cancelRequest(withError: NSError(domain: "NOADContentBlocker", code: 1))
    }
}
