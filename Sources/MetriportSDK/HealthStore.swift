import Foundation
import HealthKit
import Combine
import CoreData
import WebKit

public class MetriportHealthStoreManager {
    public let healthStore = HKHealthStore()
    public let metriportClient: MetriportClient
    private let healthKitTypes = HealthKitTypes()
    private var metriportUserId = ""

    public init(clientApiKey: String,  sandbox: Bool, apiUrl: String? = nil) {
        var url = sandbox ? "https://api.sandbox.metriport.com" : "https://api.metriport.com"
        url = apiUrl ?? url
        self.metriportClient = MetriportClient(healthStore: healthStore, clientApiKey: clientApiKey, apiUrl: url)

        // If we've already authorized then start checking background updates on app load
        if UserDefaults.standard.object(forKey: "HealthKitAuth") != nil {
            // Get metriportUserId from local storage to send in webhook requests
            if let userid = UserDefaults.standard.object(forKey: "metriportUserId") as! Optional<Data> {
                do {
                    self.metriportUserId = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(userid) as! String
                } catch {
                    self.metriportClient.metriportApi.sendError(metriportUserId: self.metriportUserId, error: "Error retrieving metriportUserId from local storage")
                }
            }

            if self.metriportUserId == "" {
                self.metriportClient.metriportApi.sendError(metriportUserId: self.metriportUserId, error: "Error no metriportUserId present")
            }


            self.metriportClient.checkBackgroundUpdates(metriportUserId: self.metriportUserId, sampleTypes: self.healthKitTypes.typesToRead)
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
                self.metriportClient.metriportApi.sendError(metriportUserId: self.metriportUserId, error: "Error requesting authorization")
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
                    self.metriportClient.metriportApi.sendError(metriportUserId: self.metriportUserId, error: "Error setting authorization true in localstorage")
                }
            }
        }
    }
    // Handles messages send to webview
    private func sendMessageToWebView(js: String, webView: WKWebView?) {
        DispatchQueue.main.async {
            webView?.evaluateJavaScript(js, completionHandler: { (response, error) in
                if let error = error {
                    self.metriportClient.metriportApi.sendError(metriportUserId: self.metriportUserId, error: "Error sending message to webview")
                } else {
                    print("Successfully sent message to webview")
                }
            })
        }
    }
}
