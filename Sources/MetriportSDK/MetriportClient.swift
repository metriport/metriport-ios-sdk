import Foundation
import HealthKit
import Combine
import CoreData
import WebKit

class MyWorkoutData: ObservableObject {
    var workoutData: [WorkoutSample] = []

    public func addWorkout(startTime: Date, endTime: Date, type: Int, duration: Int, sourceId: String, sourceName: String, kcal: Int?, distance: Int?) {
        let sample = WorkoutSample(
            startTime: startTime,
            endTime: endTime,
            type: type,
            duration: duration,
            sourceId: sourceId,
            sourceName: sourceName,
            kcal: kcal,
            distance: distance
        )
        self.workoutData.append(sample)
    }
}

struct WorkoutSample: Codable {
    var startTime: Date
    var endTime: Date
    var type: Int
    var duration: Int
    var sourceId: String
    var sourceName: String
    var kcal: Int?
    var distance: Int?
}

class MySleepData: ObservableObject {
    var sleepData: [Sample] = []

    public func addSample(startTime: Date, endTime: Date, type: String, value: Int, sourceId: String, sourceName: String) {
        let sample = Sample(date: startTime,value: value, type: type, endDate: endTime, sourceId: sourceId, sourceName: sourceName)
        self.sleepData.append(sample)
    }
}

class MyDailyData: ObservableObject {
    var dailyData: [Sample] = []

    public func addDay(date: Date, value: Int) {
        let day = Sample(date: date, value: value)
        self.dailyData.append(day)
    }
}

struct Sample: Codable {
    var date: Date
    var value: Int
    var type: String?
    var endDate: Date?
    var sourceId: String?
    var sourceName: String?
}

enum SampleOrWorkout {
    case sample([Sample])
    case workout([WorkoutSample])
}

extension SampleOrWorkout: Codable {
    private enum CodingKeys: String, CodingKey {
        case type = "type"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let singleContainer = try decoder.singleValueContainer()

        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "sample":
            let sample = try singleContainer.decode(Sample.self)
            self = .sample([sample])
        case "workout":
            let workout = try singleContainer.decode(WorkoutSample.self)
            self = .workout([workout])
        default:
            fatalError("Unknown type of content.")
        }
    }

    func encode(to encoder: Encoder) throws {
        var singleContainer = encoder.singleValueContainer()

        switch self {
        case .sample(let sample):
            try singleContainer.encode(sample)
        case .workout(let workout):
            try singleContainer.encode(workout)
        }
    }
}

@objc public class MetriportClient: NSObject {
    public static var healthStore: HKHealthStore?
    static var metriportApi: MetriportApi?
    private static let healthKitTypes = HealthKitTypes()
    private static var thirtyDaySamples: [ String: SampleOrWorkout ] = [:]

    init (healthStore: HKHealthStore, clientApiKey: String, apiUrl: String?) {
        MetriportClient.metriportApi = MetriportApi(clientApiKey: clientApiKey, apiUrl: apiUrl)
        MetriportClient.healthStore = healthStore
    }

    @objc(checkBackgroundUpdates)
    public static func checkBackgroundUpdates() {
        print("METRIPORT-LOG: Check background updates")
        if healthStore ~= nil && UserDefaults.standard.object(forKey: "HealthKitAuth") != nil {
            if let userid = UserDefaults.standard.object(forKey: "metriportUserId") as! Optional<Data> {
                do {
                    let metriportUserId = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(userid) as! String

                    if let localClientApiKey = UserDefaults.standard.object(forKey: "clientApiKey") as! Optional<Data> {
                        if let localApiUrl = UserDefaults.standard.object(forKey: "apiUrl") as! Optional<Data> {
                            if let localSandbox = UserDefaults.standard.object(forKey: "sandbox") as! Optional<Data> {
                                do {
                                    let clientApiKey = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(localClientApiKey) as! String
                                    let apiUrl = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(localApiUrl) as! String
                                    let sandbox = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(localSandbox) as! Bool

                                    print("METRIPORT-LOG: retrieved local items", metriportUserId, clientApiKey, apiUrl, sandbox)

                                    let metriportHealth = MetriportHealthStoreManager(clientApiKey: clientApiKey, sandbox: sandbox, apiUrl: apiUrl)
                                    MetriportClient.healthStore = metriportHealth.healthStore
                                    MetriportClient.metriportApi = MetriportApi(clientApiKey: clientApiKey, apiUrl: apiUrl)
                                    enableBackgroundDelivery(for: healthKitTypes.typesToRead, metriportUserId: metriportUserId)
                                    fetchDataForAllTypes(metriportUserId: metriportUserId)
                                } catch {
                                    metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error retrieving clientApiKey or apiUrl from local storage")
                                }
                            } else {
                                metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error retrieving localHealthStore is undefined")
                            }
                        } else {
                            metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error retrieving localSandbox is undefined")
                        }
                    } else {
                        metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error retrieving localClientApiKey is undefined")
                    }
                } catch {
                    metriportApi?.sendError(metriportUserId: "unknown", error: "Error retrieving metriportUserId from local storage")
                }
            } else {
                metriportApi?.sendError(metriportUserId: "unknown", error: "Error no metriportUserId present")
            }
        } else if healthStore != nil {
            if let userid = UserDefaults.standard.object(forKey: "metriportUserId") as! Optional<Data> {
                do {
                    print("METRIPORT-LOG: retrieved local items", userid)
                    let metriportUserId = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(userid) as! String
                    enableBackgroundDelivery(for: healthKitTypes.typesToRead, metriportUserId: metriportUserId)
                    fetchDataForAllTypes(metriportUserId: metriportUserId)
                } catch {
                    metriportApi?.sendError(metriportUserId: "unknown", error: "Error retrieving metriportUserId from local storage")
                }
            } else {
                metriportApi?.sendError(metriportUserId: "unknown", error: "Error no metriportUserId present")
            }
        }
    }


    // Enable all specified data types to send data in the background
    private static func enableBackgroundDelivery(for sampleTypes: [HKSampleType], metriportUserId: String) {
        print("METRIPORT-LOG: enableBackgroundDelivery")
      for sampleType in sampleTypes {
          healthStore?.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { (success, failure) in
          guard failure == nil && success else {

            metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error enabling background delivery")
            return
          }
        }
      }
    }

    private static func fetchDataForAllTypes(metriportUserId: String) {
        print("METRIPORT-LOG: fetchDataForAllTypes")
        // There are 2 types of data aggregations
        let cumalativeTypes = self.healthKitTypes.cumalativeTypes
        let discreteTypes = self.healthKitTypes.discreteTypes

        // This allows us to await until all the queries for the last 30 days are done
        // So that in group.notifiy we make a request
        let group = DispatchGroup()

        // Aggregate data for a day
        let interval = DateComponents(day: 1)

        for sampleType in cumalativeTypes {
            group.enter()

           if UserDefaults.standard.object(forKey: "date \(sampleType)") == nil {
               fetchHistoricalData(type: sampleType, queryOption: .cumulativeSum, interval: interval, group: group, metriportUserId: metriportUserId)
           }

            fetchHourly(type: sampleType, queryOption: .cumulativeSum, metriportUserId: metriportUserId)
        }

        for sampleType in discreteTypes {
            group.enter()

            if UserDefaults.standard.object(forKey: "date \(sampleType)") == nil {
                fetchHistoricalData(type: sampleType, queryOption: .discreteAverage, interval: interval, group: group, metriportUserId: metriportUserId)
            }

            fetchHourly(type: sampleType, queryOption: .discreteAverage, metriportUserId: metriportUserId)
        }

        group.enter()
        fetchAnchorQuery(
            type: HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)!,
            samplesKey: "HKCategoryValueSleepAnalysis",
            metriportUserId: metriportUserId,
            transformData: { samples in
                let sleepData = self.getSleepData(samples: samples)
                return SampleOrWorkout.sample(sleepData.sleepData)
            },
            group: group)

        group.enter()
        fetchAnchorQuery(
            type: .workoutType(),
            samplesKey: "HKWorkout",
            metriportUserId: metriportUserId,
            transformData: { samples in
                let workoutData = self.getWorkoutData(samples: samples)
                return SampleOrWorkout.workout(workoutData.workoutData)
            },
            group: group)

        group.notify(queue: .main) {
            if self.thirtyDaySamples.count != 0 {
                metriportApi?.sendData(metriportUserId: metriportUserId, samples: self.thirtyDaySamples, hourly: false)
            }
        }
    }

    // Retrieve daily values for the last 30 days for all types
    private static func fetchHistoricalData(type: HKQuantityType, queryOption: HKStatisticsOptions, interval: DateComponents, group: DispatchGroup, metriportUserId: String) {
        print("METRIPORT-LOG: fetchHistoricalData", type, metriportUserId)

        let query = createStatisticsQuery(interval: interval, quantityType: type, options: queryOption)

        query.initialResultsHandler = {
            query, results, error in

            // Set time for a month ago (last 30 days)
            let calendar = Calendar.current
            let endDate = Date()
            let oneMonthAgo = DateComponents(month: -1)
            guard let startDate = calendar.date(byAdding: oneMonthAgo, to: endDate) else {
                metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error unable to calculate the historical start date")
                fatalError("*** Unable to calculate the start date ***")
            }

            // Each type has its own unit of measurement
            let unit = self.healthKitTypes.getUnit(quantityType: type)

            guard let data = self.handleStatistics(results: results,
                                                   unit: unit,
                                                   startDate: startDate,
                                                   endDate: endDate,
                                                   queryOption: queryOption) else {
                metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error unable to handle historical statistics")
                return
            }

            // Get the last date and set it in local storage
            // This will be used as the starting point for hourly queries
            let lastDate = data.last?.date ?? Date()

            self.setLocalKeyValue(key: "date \(type)", val: lastDate)

            if data.count != 0 {
                self.thirtyDaySamples["\(type)"] = SampleOrWorkout.sample(data)
            }

            group.leave()
        }

        healthStore?.execute(query)
    }

    private static func fetchHourly(type: HKQuantityType, queryOption: HKStatisticsOptions, metriportUserId: String) {
        print("METRIPORT-LOG: fetchHourly", type, metriportUserId)
        // Aggregate data for an hour
        let interval = DateComponents(hour: 1)

        let query = createStatisticsQuery(interval: interval, quantityType: type, options: queryOption)

        // We dont initially fetch data for the hours
        query.initialResultsHandler = {
            query, results, error in
        }

        // This listens for data that is added for the type
        query.statisticsUpdateHandler = {
            query, statistics, statisticsCollection, error in

            let calendar = Calendar.current
            var startDate = Date()
            let tomorrow = DateComponents(day: 1)

            // Get the last datetime specified after the 30 day fetch
            if let date = UserDefaults.standard.object(forKey: "date \(type)") as! Optional<Data> {
                do {
                    startDate = try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(date) as! Date
                } catch {
                    metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error unable to read hourly last datetime")
                }
            }

            guard let endDate = calendar.date(byAdding: tomorrow, to: Date()) else {
                metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error unable to calculate the hourly start date")
                fatalError("*** Unable to calculate the start date ***")
            }

            // Each type has its own unit of measurement
            let unit = self.healthKitTypes.getUnit(quantityType: type)

            print("METRIPORT-LOG: statisticsUpdateHandler", startDate, endDate, unit)

            guard let data = self.handleStatistics(results: statisticsCollection,
                                                   unit: unit,
                                                   startDate: startDate,
                                                   endDate: endDate,
                                                   queryOption: queryOption) else {
                metriportApi?.sendError(metriportUserId: metriportUserId, error: "Error unable to handle hourly statistics")
                return
            }

            print("METRIPORT-LOG: send data", data)

            self.setLocalKeyValue(key: "date \(type)", val: startDate)

            metriportApi?.sendData(metriportUserId: metriportUserId, samples: ["\(type)" : SampleOrWorkout.sample(data)], hourly: true)
        }

        healthStore?.execute(query)
    }

    // This sets up the query to gather statitics
    private static func createStatisticsQuery(interval: DateComponents, quantityType: Optional<HKQuantityType>, options: HKStatisticsOptions) -> HKStatisticsCollectionQuery {
        let calendar = Calendar.current


        let components = DateComponents(calendar: calendar,
                                        timeZone: calendar.timeZone,
                                        hour: 12,
                                        minute: 0,
                                        second: 0,
                                        weekday: 1)

        // This creates the anchor point to fetch data in intervals from
        // We are setting it to monnday at midnight above
        guard let anchorDate = calendar.nextDate(after: Date(),
                                                 matching: components,
                                                 matchingPolicy: .nextTime,
                                                 repeatedTimePolicy: .first,
                                                 direction: .backward) else {
            fatalError("*** unable to find the previous Monday. ***")
        }

        guard let statsQuantityType = quantityType else {
            fatalError("*** Unable to create a step count type ***")
        }

        // Create the query. It gathers the quantity type we would like to receive
        // It uses the anchor point to set the initial date and time
        // Then with the interval we set we will aggregate data within the timeframe
        let query = HKStatisticsCollectionQuery(quantityType: statsQuantityType,
                                                quantitySamplePredicate: nil,
                                                options: options,
                                                anchorDate: anchorDate,
                                                intervalComponents: interval)

        return query
    }

    // This handles the results of the query
    private static func handleStatistics(results: Optional<HKStatisticsCollection>,
                                  unit: HKUnit,
                                  startDate: Date,
                                  endDate: Date,
                                  queryOption: HKStatisticsOptions
    ) -> [Sample]? {

        print("METRIPORT-LOG: handleStatistics")

        guard let statsCollection = results else {
            print("error with stats collection")
            return nil
        }



        let dailyData = self.getCollectionsData(statsCollection: statsCollection,
                                            startDate: startDate,
                                            endDate: endDate,
                                            unit: unit,
                                            queryOption: queryOption)

        return dailyData
    }

    // Grabs the results and picks out the data for specified days and then formats it
    private static func getCollectionsData(statsCollection: HKStatisticsCollection,
                                    startDate: Date,
                                    endDate: Date,
                                    unit: HKUnit,
                                    queryOption: HKStatisticsOptions
    ) -> [Sample] {

        let dailyData = MyDailyData()

        statsCollection.enumerateStatistics(from: startDate, to: endDate)
        { (statistics, stop) in
            if let quantity = self.getSumOrAvgQuantity(statistics: statistics, queryOption: queryOption) {
                let date = statistics.startDate
                let compatible = quantity.is(compatibleWith: unit)

                if compatible {
                    let value = quantity.doubleValue(for: unit)

                    // Extract each day's data.
                    dailyData.addDay(date: date, value: Int(value))
                } else {
                    print(quantity)
                    print(unit)
                }
            }
        }

        print("METRIPORT-LOG: getCollectionsData", dailyData)

        return dailyData.dailyData
    }

    private static func getSumOrAvgQuantity(statistics: HKStatistics, queryOption: HKStatisticsOptions) -> Optional<HKQuantity> {
        if queryOption == .cumulativeSum {
            return statistics.sumQuantity()
        }

        return statistics.averageQuantity()
    }

    private static func setLocalKeyValue(key: String, val: Any) {
        do {
            let data : Data = try NSKeyedArchiver.archivedData(withRootObject: val, requiringSecureCoding: false)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            print("Couldnt write files")
        }
    }

    static func fetchAnchorQuery(
        type: HKSampleType,
        samplesKey: String,
        metriportUserId: String,
        transformData: @escaping ([HKSample]) -> SampleOrWorkout,
        group: DispatchGroup
    ) {
        let calendar = Calendar.current
        let endDate = Date()
        let oneMonthAgo = DateComponents(day: -30)
        guard let startDate = calendar.date(byAdding: oneMonthAgo, to: endDate) else {
            fatalError("*** Unable to calculate the start date ***")
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])

        var anchor = HKQueryAnchor.init(fromValue: 0)
        let anchorKey = "\(type) anchor"

        if UserDefaults.standard.object(forKey: anchorKey) != nil {
            let data = UserDefaults.standard.object(forKey: anchorKey) as! Data
            do {
                anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) as! HKQueryAnchor
            } catch {
                print("Unable to retrieve an anchor")
            }
        }

        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor, limit: HKObjectQueryNoLimit) { (query, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil) -> Void in
            guard let samples = samplesOrNil else {
                return
            }

            let data = transformData(samples)

            self.setLocalKeyValue(key: anchorKey, val: newAnchor!)
            self.thirtyDaySamples[samplesKey] = data
            group.leave()
        }

        query.updateHandler = { (query, samplesOrNil, deletedObjectsOrNil, newAnchor, errorOrNil) in
            guard let samples = samplesOrNil else {
                return
            }
            print(samples)

            let data = transformData(samples)

            print(data)

            self.setLocalKeyValue(key: anchorKey, val: newAnchor!)
            metriportApi?.sendData(metriportUserId: metriportUserId, samples: [samplesKey : data], hourly: true)
        }

        healthStore?.execute(query)
    }

    static func getSleepData(samples: [HKSample]) -> MySleepData {
        let sleepData = MySleepData()

        for item in samples {
            if let sample = item as? HKCategorySample {
                print(sample)
                print(sample.value)
                switch sample.value {
                    case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    sleepData.addSample(startTime: sample.startDate, endTime: sample.endDate, type: "inBed", value: Int(sample.endDate - sample.startDate), sourceId: sample.sourceRevision.source.bundleIdentifier, sourceName: sample.sourceRevision.productType?.description ?? "")
                    case HKCategoryValueSleepAnalysis.awake.rawValue:
                        sleepData.addSample(startTime: sample.startDate, endTime: sample.endDate, type: "awake", value: Int(sample.endDate - sample.startDate), sourceId: sample.sourceRevision.source.bundleIdentifier, sourceName: sample.sourceRevision.productType?.description ?? "")
                    default:
                    break
                }

                if #available(iOS 16.0, *) {
                    switch sample.value {
                        case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                            sleepData.addSample(startTime: sample.startDate, endTime: sample.endDate, type: "rem", value: Int(sample.endDate - sample.startDate), sourceId: sample.sourceRevision.source.bundleIdentifier, sourceName: sample.sourceRevision.productType?.description ?? "")
                        case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                            sleepData.addSample(startTime: sample.startDate, endTime: sample.endDate, type: "core", value: Int(sample.endDate - sample.startDate), sourceId: sample.sourceRevision.source.bundleIdentifier, sourceName: sample.sourceRevision.productType?.description ?? "")
                        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                            sleepData.addSample(startTime: sample.startDate, endTime: sample.endDate, type: "deep", value: Int(sample.endDate - sample.startDate), sourceId: sample.sourceRevision.source.bundleIdentifier, sourceName: sample.sourceRevision.productType?.description ?? "")
                        default:
                        break
                    }
                }
            }
        }


        return sleepData
    }

     static func getWorkoutData(samples: [HKSample]) -> MyWorkoutData {
        let workoutData = MyWorkoutData()

         for result in samples {
             if let workout = result as? HKWorkout {
                 let startTime = workout.startDate
                 let endTime = workout.endDate
                 let duration = Int(workout.duration)
                 let type = Int(workout.workoutActivityType.rawValue)
                 var kcal: Int? = nil
                 var distance: Int? = nil

               if #available(iOS 16.0, *) {
                   for (key, stat) in workout.allStatistics {
                       if key == HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)! && stat.sumQuantity() != nil {
                           kcal = Int((stat.sumQuantity()?.doubleValue(for: .kilocalorie()))!)
                       }

                       if key == HKObjectType.quantityType(forIdentifier:  .distanceWalkingRunning)! && stat.sumQuantity() != nil {
                           distance = Int((stat.sumQuantity()?.doubleValue(for: .meter()))!)
                       }
                   }
               }

                 workoutData.addWorkout(startTime: startTime, endTime: endTime, type: type, duration: duration, sourceId: workout.sourceRevision.source.bundleIdentifier, sourceName: workout.sourceRevision.productType?.description ?? "", kcal: kcal, distance: distance)
             }
         }

        return workoutData
    }
}

extension Date {
    static func - (lhs: Date, rhs: Date) -> TimeInterval {
        return lhs.timeIntervalSinceReferenceDate - rhs.timeIntervalSinceReferenceDate
    }
}
