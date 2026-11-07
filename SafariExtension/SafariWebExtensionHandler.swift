import Foundation
import SafariServices
import AppKit

@objc(SafariWebExtensionHandler)
public class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    public func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let userInfo = item?.userInfo as? [String: Any]
        var responsePayload: [String: Any] = ["success": false]

        if let message = userInfo?[SFExtensionMessageKey] as? [String: Any],
           let urlString = message["url"] as? String,
           !urlString.isEmpty {

            let time = (message["time"] as? Double) ?? (message["time"] as? Int).map { Double($0) } ?? 0.0

            var components = URLComponents(string: "serein://open")
            var queryItems = [URLQueryItem(name: "url", value: urlString)]
            if time > 0 {
                queryItems.append(URLQueryItem(name: "time", value: String(format: "%.1f", time)))
            }
            components?.queryItems = queryItems

            if let openURL = components?.url {
                let sema = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.serein.player") {
                        let config = NSWorkspace.OpenConfiguration()
                        config.activates = true
                        NSWorkspace.shared.open([openURL], withApplicationAt: appURL, configuration: config) { _, error in
                            if error != nil {
                                _ = NSWorkspace.shared.open(openURL)
                            }
                            sema.signal()
                        }
                    } else {
                        _ = NSWorkspace.shared.open(openURL)
                        sema.signal()
                    }
                }
                _ = sema.wait(timeout: .now() + 2.0)
                responsePayload["success"] = true
            }
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: responsePayload]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
