import Foundation
import HealthKit
import Combine
import CoreData
import WebKit

class MetriportApi {
    let apiUrl: String
    let clientApiKey: String

    init(clientApiKey: String, apiUrl: String?) {
        self.apiUrl = apiUrl ?? "https://api.metriport.com"
        self.clientApiKey = clientApiKey
    }

    // Encode the data and strigify payload to be able to send as JSON
    // Data is structured as [ "TYPE ie HeartRate": [ARRAY OF SAMPLES]]
    public func sendData(metriportUserId: String, samples: [ String: SampleOrWorkout ], hourly: Bool? = nil) {
        var stringifyPayload: String = ""

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)

            stringifyPayload = String(data: data, encoding: .utf8)!
        } catch {
            print("Couldnt write files")
        }

        var bodyData = try? JSONSerialization.data(
            withJSONObject: ["metriportUserId": metriportUserId, "data": stringifyPayload]
        )

        if hourly != nil {
            bodyData = try? JSONSerialization.data(
                withJSONObject: ["metriportUserId": metriportUserId, "data": stringifyPayload, "hourly": hourly ?? false]
            )
        }

        makeRequest(payload: bodyData, hourly: hourly)
    }

    public func sendError(metriportUserId: String, error: String, extra: [String: String]? = nil) {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encodedExtra = try encoder.encode(extra)
            let data = try encoder.encode([
                "error": error,
                "extra": String(data: encodedExtra, encoding: .utf8)!
            ])

            var payload = try? JSONSerialization.data(
                withJSONObject: ["metriportUserId": metriportUserId, "data": String(data: data, encoding: .utf8)!]
            )

            makeRequest(payload: payload)
        } catch {
            print("Couldnt make request")

        }

    }

    // Send data to the api
    private func makeRequest(payload: Data? = nil, hourly: Bool? = nil) {
        var request = URLRequest(url: URL(string: "\(self.apiUrl)/webhook/apple")!)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(self.clientApiKey, forHTTPHeaderField: "x-api-key")
        let failedPayloadsKey = "failedPayloads"

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let response = response as? HTTPURLResponse, error == nil else {
                print("error", error ?? URLError(.badServerResponse))
                return
            }

            if (200 ... 299) ~= response.statusCode {
                if let failedPayloads = UserDefaults.standard.object(forKey: failedPayloadsKey) as! Optional<Data> {
                    do {
                        let payloads = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(failedPayloads) as! [Data]
                        for failedPayload in payloads {
                            self.makeRequest(payload: failedPayload)
                        }
                        UserDefaults.standard.removeObject(forKey: failedPayloadsKey)
                    } catch {
                        print("Couldnt read object")
                    }
                }
            } else {
                var payloads: [Data?] = []

                if let failedPayloads = UserDefaults.standard.object(forKey: failedPayloadsKey) as! Optional<Data> {
                    do {
                        payloads = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(failedPayloads) as! [Data]
                    } catch {
                        print("Couldnt read object")
                    }
                }

                do {
                    payloads.append(payload)
                    let data : Data = try NSKeyedArchiver.archivedData(withRootObject: payloads, requiringSecureCoding: false)
                    UserDefaults.standard.set(data, forKey: failedPayloadsKey)
                } catch {
                    print("Couldnt write files")
                }

                return
            }
        }

        task.resume()
    }
}
