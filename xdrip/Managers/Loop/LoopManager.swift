//
//  LoopManager.swift
//  xdrip
//
//  Created by Julian Groen on 05/04/2020.
//  Copyright © 2020 Johan Degraeve. All rights reserved.
//

import Foundation

public class LoopManager:NSObject {
    
    // MARK: - private properties
    
    /// reference to coreDataManager
    private var coreDataManager:CoreDataManager
    
    /// a BgReadingsAccessor
    private var bgReadingsAccessor:BgReadingsAccessor
    
    /// shared UserDefaults to publish data
    private let sharedUserDefaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName)
    
    // MARK: - initializer
    
    init(coreDataManager:CoreDataManager) {
        
        // initialize non optional private properties
        self.coreDataManager = coreDataManager
        self.bgReadingsAccessor = BgReadingsAccessor(coreDataManager: coreDataManager)
        
        // call super.init
        super.init()
        
    }
    
    // MARK: - public functions
    
    /// share latest readings with Loop
    public func share() {
        
        // unwrap sharedUserDefaults
        guard let sharedUserDefaults = sharedUserDefaults else {return}

        // get last readings with calculated value
        let lastReadings = bgReadingsAccessor.getLatestBgReadings(limit: ConstantsShareWithLoop.maxReadingsToShareWithLoop, fromDate: UserDefaults.standard.timeStampLatestLoopSharedBgReading, forSensor: nil, ignoreRawData: true, ignoreCalculatedValue: false)

        // if there's no readings, then no further processing
        if lastReadings.count == 0 {
            return
        }

        // convert to json Dexcom Share format
        var dictionary = [Dictionary<String, Any>]()
        for reading in lastReadings {
            dictionary.append(reading.dictionaryRepresentationForDexcomShareUpload)
        }

        // get Dictionary stored in UserDefaults from previous session
        // append readings already stored in this storedDictionary so that we get dictionary filled with maxReadingsToShareWithLoop readings, if possible
        if let storedDictionary = UserDefaults.standard.readingsStoredInSharedUserDefaultsAsDictionary, storedDictionary.count > 0 {
            
            let maxAmountsOfReadingsToAppend = ConstantsShareWithLoop.maxReadingsToShareWithLoop - dictionary.count
            
            if maxAmountsOfReadingsToAppend > 0 {
                
                let rangeToAppend = 0..<(min(storedDictionary.count, maxAmountsOfReadingsToAppend))
                
                for value in storedDictionary[rangeToAppend] {
                    
                    dictionary.append(value)
                    
                }
                
            }
            
        }
        
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary) else {
            return
        }
        
        sharedUserDefaults.set(data, forKey: "latestReadings")
        
        UserDefaults.standard.timeStampLatestLoopSharedBgReading = lastReadings.first!.timeStamp
        
        UserDefaults.standard.readingsStoredInSharedUserDefaultsAsDictionary = dictionary
        
        let decoded = try? JSONSerialization.jsonObject(with: data, options: [])
        guard let sgvs = decoded as? Array<AnyObject> else {
            debuglogging("Failed to decode SGVs as array from recieved data.")
            return
        }
        
        var transformed: Array<Glucose> = []
        for sgv in sgvs {
            // Collector might not be available
            var collector : String? = nil
            if let _col = sgv["Collector"] as? String {
                collector = _col
            }
            
            if let glucose = sgv["Value"] as? Int, let trend = sgv["Trend"] as? Int, let dt = sgv["DT"] as? String {
                transformed.append(Glucose(
                    glucose: UInt16(glucose),
                    trend: UInt8(trend),
                    timestamp: self.parseDate(dt),
                    collector: collector
                ))
            } else {
                debuglogging("Failed to decode an SGV record.")
            }
        }
        
        for element in transformed {
            debuglogging("element timestamp " + element.timestamp.toString(timeStyle: .medium, dateStyle: .none) + ",element value " + element.glucose.description)
            
        }
        
        
    }
    
    private func parseDate(_ wt: String) -> Date {
        // wt looks like "/Date(1462404576000)/"
        do {
            let re = try NSRegularExpression(pattern: "\\((.*)\\)")
            if let match = re.firstMatch(in: wt, range: NSMakeRange(0, wt.count)) {
                #if swift(>=4)
                let matchRange = match.range(at: 1)
                #else
                let matchRange = match.rangeAt(1)
                #endif
                let epoch = Double((wt as NSString).substring(with: matchRange))! / 1000
                return Date(timeIntervalSince1970: epoch)
            } else {
                debuglogging("parsedate error")
            }

        } catch _ {
            
            debuglogging("error")
            return Date()
            
        }
        
        return Date()
    }
    
}



 struct Glucose {
    public let glucose: UInt16
    public let trend: UInt8
    public let timestamp: Date
    public let collector: String?
}
