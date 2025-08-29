import Foundation
import Combine
import CoreBluetooth

struct SavedDevice: Codable, Identifiable {
    let id: Int
    let name: String
    let peripheralIdentifier: String?
    let dateAdded: Date
    
    var bleUniqueID: Int { id }
    var blePeripheralName: String { name }
}

class DeviceStorage: ObservableObject {
    static let shared = DeviceStorage()
    
    @Published var savedDevices: [SavedDevice] = []
    
    private let userDefaults = UserDefaults.standard
    private let savedDevicesKey = "SavedDevices"
    private let lastConnectedDeviceKey = "LastConnectedDevice"
    
    private init() {
        loadDevices()
    }
    
    func saveDevice(_ device: QorvoDevice) {
        let savedDevice = SavedDevice(
            id: device.bleUniqueID,
            name: device.blePeripheralName,
            peripheralIdentifier: device.blePeripheral?.identifier.uuidString,
            dateAdded: Date()
        )
        
        // 중복 제거
        if !savedDevices.contains(where: { $0.id == savedDevice.id }) {
            savedDevices.append(savedDevice)
            persistDevices()
        }
    }
    
    func removeDevice(_ device: SavedDevice) {
        savedDevices.removeAll { $0.id == device.id }
        persistDevices()
    }
    
    func isDeviceSaved(_ deviceID: Int) -> Bool {
        return savedDevices.contains { $0.id == deviceID }
    }
    
    func getSavedDevice(by id: Int) -> SavedDevice? {
        return savedDevices.first { $0.id == id }
    }
    
    private func loadDevices() {
        if let data = userDefaults.data(forKey: savedDevicesKey),
           let devices = try? JSONDecoder().decode([SavedDevice].self, from: data) {
            self.savedDevices = devices
        }
    }
    
    private func persistDevices() {
        if let data = try? JSONEncoder().encode(savedDevices) {
            userDefaults.set(data, forKey: savedDevicesKey)
        }
    }
    
    func setLastConnectedDevice(_ deviceID: Int) {
        userDefaults.set(deviceID, forKey: lastConnectedDeviceKey)
    }
    
    func getLastConnectedDevice() -> Int? {
        let deviceID = userDefaults.integer(forKey: lastConnectedDeviceKey)
        return deviceID == 0 ? nil : deviceID
    }
}
