//
//  LocationStorage.swift
//  FindMyCar
//
//  Created by NoriDev on 8/27/25.
//

import Foundation
import CoreLocation

class LocationStorage {
    static let shared = LocationStorage()
    
    private let userDefaults = UserDefaults.standard
    private let locationKey = "DeviceLocations"
    
    private init() {}
    
    func saveLocation(deviceID: Int, coordinate: CLLocationCoordinate2D) {
        var locations = getAllLocations()
        let locationData = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "timestamp": Date().timeIntervalSince1970
        ]
        locations[String(deviceID)] = locationData
        
        userDefaults.set(locations, forKey: locationKey)
        
        print("Saved location for device \(deviceID): \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    func getLastLocation(for deviceID: Int) -> CLLocationCoordinate2D? {
        let locations = getAllLocations()
        
        guard let locationData = locations[String(deviceID)] as? [String: Double],
              let latitude = locationData["latitude"],
              let longitude = locationData["longitude"] else {
            return nil
        }
        
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    func getLocationWithTimestamp(for deviceID: Int) -> (coordinate: CLLocationCoordinate2D, timestamp: Date)? {
        let locations = getAllLocations()
        
        guard let locationData = locations[String(deviceID)] as? [String: Double],
              let latitude = locationData["latitude"],
              let longitude = locationData["longitude"],
              let timestamp = locationData["timestamp"] else {
            return nil
        }
        
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let date = Date(timeIntervalSince1970: timestamp)
        
        return (coordinate: coordinate, timestamp: date)
    }
    
    func removeLocation(for deviceID: Int) {
        var locations = getAllLocations()
        locations.removeValue(forKey: String(deviceID))
        userDefaults.set(locations, forKey: locationKey)
    }
    
    func getAllStoredDeviceIDs() -> [Int] {
        let locations = getAllLocations()
        return locations.keys.compactMap { Int($0) }
    }
    
    private func getAllLocations() -> [String: Any] {
        return userDefaults.dictionary(forKey: locationKey) ?? [:]
    }
    
    func clearAllLocations() {
        userDefaults.removeObject(forKey: locationKey)
    }
}