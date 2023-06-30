import Foundation
import HealthKit
import Combine
import CoreData
import WebKit

@objc public class MetriportHealthStoreManager: NSObject {
    public let healthStore = HKHealthStore()
    public let metriportClient: MetriportClient
    private let healthKitTypes = HealthKitTypes()

    public init(clientApiKey: String, sandbox: Bool, apiUrl: String? = nil) {
        var url = sandbox ? "https://api.sandbox.metriport.com" : "https://api.metriport.com"
        url = apiUrl ?? url
        self.metriportClient = MetriportClient(healthStore: healthStore, clientApiKey: clientApiKey, apiUrl: url)

        do {
            let data : Data = try NSKeyedArchiver.archivedData(withRootObject: clientApiKey, requiringSecureCoding: false)
            UserDefaults.standard.set(data, forKey: "clientApiKey")

            let storedApiUrl : Data = try NSKeyedArchiver.archivedData(withRootObject: url, requiringSecureCoding: false)
            UserDefaults.standard.set(storedApiUrl, forKey: "apiUrl")

            let storedSandbox : Data = try NSKeyedArchiver.archivedData(withRootObject: sandbox, requiringSecureCoding: false)
            UserDefaults.standard.set(storedSandbox, forKey: "sandbox")
        } catch {
            MetriportClient.metriportApi?.sendError(metriportUserId: "unknown", error: "Error unable to store clientApiKey or apiurl")
        }
    }
    // Request authorization from user for the healthkit access
    public func requestAuthorization(webView: WKWebView?) {
        // Request authorization for those quantity types.
        healthStore.requestAuthorization(toShare: [], read: Set(self.healthKitTypes.typesToRead)) { (success, error) in
            // Handle error.
            if error != nil {
                let js = "var event = new CustomEvent('authorization', { detail: { success: false }}); window.dispatchEvent(event);"
                self.sendMessageToWebView(js: js, webView: webView)
                MetriportClient.metriportApi?.sendError(metriportUserId: "unknown", error: "Error requesting authorization")
            }

            if success {
                // On success dispatch message back to the webview that it's connected
                let js = "var event = new CustomEvent('authorization', { detail: { success: true }}); window.dispatchEvent(event);"
                self.sendMessageToWebView(js: js, webView: webView)
                // Set authorization to true in localstorage
                do {
                    let data : Data = try NSKeyedArchiver.archivedData(withRootObject: true, requiringSecureCoding: false)
                    UserDefaults.standard.set(data, forKey: "HealthKitAuth")
                } catch {
                    MetriportClient.metriportApi?.sendError(metriportUserId: "unknown", error: "Error setting authorization true in localstorage")
                }
            }
        }
    }
    // Handles messages send to webview
    private func sendMessageToWebView(js: String, webView: WKWebView?) {
        DispatchQueue.main.async {
            webView?.evaluateJavaScript(js, completionHandler: { (response, error) in
                if let error = error {
                    MetriportClient.metriportApi?.sendError(metriportUserId: "unknown", error: "Error sending message to webview")
                } else {
                    print("Successfully sent message to webview")
                }
            })
        }
    }
}
