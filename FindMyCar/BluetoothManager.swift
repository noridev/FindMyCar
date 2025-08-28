import Foundation
import CoreBluetooth
import Combine
import os.log
import NearbyInteraction
import simd

protocol BluetoothManagerDelegate: AnyObject {
    func bluetoothManager(_ manager: BluetoothManager, didReceiveAccessoryConfigurationData data: Data, deviceID: Int)
    func bluetoothManager(_ manager: BluetoothManager, uwbDidStart: Bool, deviceID: Int)
    func bluetoothManager(_ manager: BluetoothManager, didConnectDevice deviceID: Int)
}

// Qorvo transfer service UUIDs (Nordic UART Service compatible)
struct TransferService {
    static let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rxCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    static let txCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
}

// Qorvo NI service UUIDs
struct QorvoNIService {
    static let serviceUUID = CBUUID(string: "2E938FD0-6A61-11ED-A1EB-0242AC120002")
    static let scCharacteristicUUID = CBUUID(string: "2E93941C-6A61-11ED-A1EB-0242AC120002")
    static let rxCharacteristicUUID = CBUUID(string: "2E93998A-6A61-11ED-A1EB-0242AC120002")
    static let txCharacteristicUUID = CBUUID(string: "2E939AF2-6A61-11ED-A1EB-0242AC120002")
}

// Message protocol for UWB communication
enum MessageId: UInt8 {
    // Messages from the accessory
    case accessoryConfigurationData = 0x1
    case accessoryUwbDidStart = 0x2
    case accessoryUwbDidStop = 0x3
    
    // Messages to the accessory
    case initialize = 0xA
    case configureAndStart = 0xB
    case stop = 0xC
    
    // User defined/notification messages
    case getReserved = 0x20
    case setReserved = 0x21
    case iOSNotify = 0x2F
}

// Base struct to save the last location values
struct Location {
    var distance: Float
    var direction: simd_float3
    var elevation: Int
    var noUpdate: Bool
}

class QorvoDevice {
    var blePeripheral: CBPeripheral?
    var rxCharacteristic: CBCharacteristic?
    var txCharacteristic: CBCharacteristic?
    
    var bleUniqueID: Int
    var blePeripheralName: String
    var blePeripheralStatus: String?
    var bleTimestamp: Int64
    var uwbLocation: Location?
    
    init(peripheral: CBPeripheral, uniqueID: Int, peripheralName: String, timeStamp: Int64) {
        self.blePeripheral = peripheral
        self.bleUniqueID = uniqueID
        self.blePeripheralName = peripheralName
        self.blePeripheralStatus = statusDiscovered
        self.bleTimestamp = timeStamp
        self.uwbLocation = Location(
            distance: 0,
            direction: SIMD3<Float>(x: 0, y: 0, z: 0),
            elevation: NINearbyObject.VerticalDirectionEstimate.unknown.rawValue,
            noUpdate: false
        )
    }
    
    // For saved devices without actual peripheral
    init() {
        self.blePeripheral = nil
        self.bleUniqueID = 0
        self.blePeripheralName = ""
        self.blePeripheralStatus = "Saved"
        self.bleTimestamp = 0
        self.uwbLocation = Location(
            distance: 0,
            direction: SIMD3<Float>(x: 0, y: 0, z: 0),
            elevation: NINearbyObject.VerticalDirectionEstimate.unknown.rawValue,
            noUpdate: true
        )
    }
}

enum BluetoothLECentralError: Error {
    case noPeripheral
}

let statusDiscovered = "Discovered"
let statusConnected = "Connected"
let statusRanging = "Ranging"

class BluetoothManager: NSObject, ObservableObject {
    private let logger = Logger(subsystem: "com.findmycar.app", category: "BluetoothManager")
    
    @Published var isScanning = false
    @Published var connectedPeripheral: CBPeripheral?
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var discoveredDevices: [QorvoDevice] = []
    @Published var uwbActive = false
    
    weak var delegate: BluetoothManagerDelegate?
    
    private var centralManager: CBCentralManager!
    private var bluetoothReady = false
    private var shouldStartWhenReady = false
    
    // Timer for device cleanup
    private var cleanupTimer: Timer?
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case scanning
        case connecting
        case connected
        case failed(Error)
        
        static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.scanning, .scanning),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    enum BluetoothError: Error {
        case bluetoothOff
        case unauthorized
        case unsupported
        case connectionFailed
    }
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        
        // Start cleanup timer like in Qorvo sample
        cleanupTimer = Timer.scheduledTimer(timeInterval: 0.2, target: self, selector: #selector(timerHandler), userInfo: nil, repeats: true)
        
        // Load saved devices and attempt auto-connect
        loadSavedDevices()
    }
    
    deinit {
        centralManager.stopScan()
        cleanupTimer?.invalidate()
        logger.info("Scanning stopped.")
    }
    
    // Clear peripherals if not responding for more than 5 seconds (Qorvo logic)
    @objc private func timerHandler() {
        let currentTime = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        
        discoveredDevices.removeAll { device in
            // 저장된 디바이스는 제거하지 않음
            if DeviceStorage.shared.isDeviceSaved(device.bleUniqueID) {
                return false
            }
            
            // 연결된 디바이스나 연결 중인 디바이스는 제거하지 않음
            if device.blePeripheralStatus == statusConnected || 
               device.blePeripheralStatus == statusRanging {
                return false
            }
            
            // 발견된 디바이스만 타임아웃으로 제거
            if device.blePeripheralStatus == statusDiscovered {
                if currentTime > (device.bleTimestamp + 5000) {
                    logger.info("Device \(device.blePeripheralName) timed-out removed")
                    return true
                }
            }
            return false
        }
    }
    
    func getDeviceFromUniqueID(_ uniqueID: Int) -> QorvoDevice? {
        return discoveredDevices.first { $0.bleUniqueID == uniqueID }
    }
    
    func startScanning() {
        if bluetoothReady {
            isScanning = true
            connectionStatus = .scanning
            
            centralManager.scanForPeripherals(
                withServices: [TransferService.serviceUUID, QorvoNIService.serviceUUID],
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
            )
            
            logger.info("Scanning started.")
        } else {
            shouldStartWhenReady = true
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if connectionStatus == .scanning {
            connectionStatus = .disconnected
        }
        logger.info("Scanning stopped.")
    }
    
    func connect(to device: QorvoDevice) {
        connectPeripheral(device.bleUniqueID)
    }
    
    func connectPeripheral(_ uniqueID: Int) {
        guard let deviceToConnect = getDeviceFromUniqueID(uniqueID) else {
            logger.error("Device with uniqueID \(uniqueID) not found")
            return
        }
        
        logger.info("Connecting to peripheral: \(deviceToConnect.blePeripheralName)")
        connectionStatus = .connecting
        
        // 연결 시도 시 타임스탬프 업데이트하여 타임아웃으로 제거되지 않도록 함
        deviceToConnect.bleTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        
        guard let peripheral = deviceToConnect.blePeripheral else {
            logger.error("Cannot connect: peripheral is nil")
            return
        }
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        
        connectedPeripheral = nil
        connectionStatus = .disconnected
        uwbActive = false
    }
    
    public func sendDataToAccessory(_ data: Data, deviceID: Int) {
        guard let device = getDeviceFromUniqueID(deviceID),
              let characteristic = device.rxCharacteristic else {
            logger.error("Cannot send data - device or characteristic not available")
            return
        }
        
        device.blePeripheral?.writeValue(data, for: characteristic, type: .withResponse)
        logger.info("Sent data to accessory: \(data.map { String(format: "0x%02x", $0) }.joined(separator: ", "))")
    }
    
    // UWB control methods
    func initializeUWB(deviceID: Int) {
        let message = Data([MessageId.initialize.rawValue])
        sendDataToAccessory(message, deviceID: deviceID)
        logger.info("Sent UWB initialize command")
    }
    
    func configureAndStartUWB(deviceID: Int) {
        let message = Data([MessageId.configureAndStart.rawValue])
        sendDataToAccessory(message, deviceID: deviceID)
        logger.info("Sent UWB configure and start command")
    }
    
    func stopUWB(deviceID: Int) {
        let message = Data([MessageId.stop.rawValue])
        sendDataToAccessory(message, deviceID: deviceID)
        logger.info("Sent UWB stop command")
        uwbActive = false
    }
}

// MARK: - CBCentralManagerDelegate
extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.info("Central manager state changed to: \(central.state.rawValue)")
        
        switch central.state {
        case .poweredOn:
            logger.info("Bluetooth is powered on and ready")
            bluetoothReady = true
            connectionStatus = .disconnected
            
            // Start auto-connect if needed
            if shouldStartWhenReady {
                shouldStartWhenReady = false
                attemptAutoConnect()
            }
            
        case .poweredOff:
            connectionStatus = .failed(BluetoothError.bluetoothOff)
            bluetoothReady = false
            logger.error("Bluetooth is powered off")
        case .unauthorized:
            connectionStatus = .failed(BluetoothError.unauthorized)
            bluetoothReady = false
            logger.error("Bluetooth access unauthorized")
        case .unsupported:
            connectionStatus = .failed(BluetoothError.unsupported)
            bluetoothReady = false
            logger.error("Bluetooth not supported on this device")
        default:
            bluetoothReady = false
            logger.warning("Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let deviceName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "Unknown"
        let timeStamp = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let uniqueID = peripheral.hashValue
        
        logger.info("Discovered peripheral: \(deviceName) with RSSI: \(RSSI)")
        
        // Check if device already exists, if so update timestamp
        if let existingDeviceIndex = discoveredDevices.firstIndex(where: { $0.bleUniqueID == uniqueID }) {
            discoveredDevices[existingDeviceIndex].bleTimestamp = timeStamp
        } else {
            // Add new device
            let newDevice = QorvoDevice(
                peripheral: peripheral,
                uniqueID: uniqueID,
                peripheralName: deviceName,
                timeStamp: timeStamp
            )
            discoveredDevices.append(newDevice)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        logger.info("Successfully connected to peripheral: \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = peripheral
        connectionStatus = .connected
        peripheral.delegate = self
        
        // Update device status
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.blePeripheral === peripheral }) {
            discoveredDevices[deviceIndex].blePeripheralStatus = statusConnected
        }
        
        // Discover services
        peripheral.discoverServices([TransferService.serviceUUID, QorvoNIService.serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        logger.error("Failed to connect to peripheral: \(error?.localizedDescription ?? "Unknown error")")
        connectionStatus = .failed(error ?? BluetoothError.connectionFailed)
        
        // Reset device status
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.blePeripheral === peripheral }) {
            discoveredDevices[deviceIndex].blePeripheralStatus = statusDiscovered
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        logger.info("Disconnected from peripheral: \(peripheral.name ?? "Unknown")")
        
        connectedPeripheral = nil
        connectionStatus = .disconnected
        uwbActive = false
        
        // Reset device status
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.blePeripheral === peripheral }) {
            discoveredDevices[deviceIndex].blePeripheralStatus = statusDiscovered
            discoveredDevices[deviceIndex].rxCharacteristic = nil
            discoveredDevices[deviceIndex].txCharacteristic = nil
        }
        
        if let error = error {
            logger.error("Disconnection error: \(error.localizedDescription)")
        }
    }
}

// MARK: - CBPeripheralDelegate
extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            logger.error("Error discovering services: \(error!.localizedDescription)")
            return
        }
        
        guard let services = peripheral.services else { return }
        
        for service in services {
            logger.info("Discovered service: \(service.uuid)")
            
            if service.uuid == TransferService.serviceUUID {
                logger.info("Found Transfer service")
                peripheral.discoverCharacteristics([
                    TransferService.rxCharacteristicUUID,
                    TransferService.txCharacteristicUUID
                ], for: service)
            } else if service.uuid == QorvoNIService.serviceUUID {
                logger.info("Found Qorvo NI service")
                peripheral.discoverCharacteristics([
                    QorvoNIService.rxCharacteristicUUID,
                    QorvoNIService.txCharacteristicUUID,
                    QorvoNIService.scCharacteristicUUID
                ], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            logger.error("Error discovering characteristics: \(error!.localizedDescription)")
            return
        }
        
        guard let characteristics = service.characteristics,
              let deviceIndex = discoveredDevices.firstIndex(where: { $0.blePeripheral === peripheral }) else { return }
        
        for characteristic in characteristics {
            logger.info("Discovered characteristic: \(characteristic.uuid)")
            
            // Handle Transfer Service characteristics
            if characteristic.uuid == TransferService.rxCharacteristicUUID {
                logger.info("Found Transfer RX characteristic")
                discoveredDevices[deviceIndex].rxCharacteristic = characteristic
            } else if characteristic.uuid == TransferService.txCharacteristicUUID {
                logger.info("Found Transfer TX characteristic")
                discoveredDevices[deviceIndex].txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            // Handle Qorvo NI Service characteristics
            else if characteristic.uuid == QorvoNIService.rxCharacteristicUUID {
                logger.info("Found Qorvo NI RX characteristic")
                discoveredDevices[deviceIndex].rxCharacteristic = characteristic
            } else if characteristic.uuid == QorvoNIService.txCharacteristicUUID {
                logger.info("Found Qorvo NI TX characteristic")
                discoveredDevices[deviceIndex].txCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        // Check if we have both characteristics ready
        let device = discoveredDevices[deviceIndex]
        if device.rxCharacteristic != nil && device.txCharacteristic != nil {
            logger.info("All required characteristics found for device")
            
            // Call delegate to notify connection is complete
            delegate?.bluetoothManager(self, didConnectDevice: device.bleUniqueID)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            logger.error("Error reading characteristic: \(error!.localizedDescription)")
            return
        }
        
        guard let data = characteristic.value,
              let deviceIndex = discoveredDevices.firstIndex(where: { $0.blePeripheral === peripheral }) else { return }
        
        let dataString = data.map { String(format: "0x%02x", $0) }.joined(separator: ", ")
        logger.info("Received \(data.count) bytes: \(dataString)")
        
        let deviceID = discoveredDevices[deviceIndex].bleUniqueID
        
        // Handle message from accessory
        if data.count > 0 {
            let messageId = data[0]
            handleReceivedMessage(messageId: messageId, data: data, deviceID: deviceID)
        }
    }
    
    private func handleReceivedMessage(messageId: UInt8, data: Data, deviceID: Int) {
        guard let message = MessageId(rawValue: messageId) else {
            logger.warning("Unknown message ID: 0x\(String(format: "%02x", messageId))")
            return
        }
        
        switch message {
        case .accessoryConfigurationData:
            logger.info("Received accessory configuration data")
            if data.count > 1 {
                let configData = Data(data.dropFirst())
                logger.info("Stored \(configData.count) bytes of configuration data")
                
                // Notify delegate with configuration data
                DispatchQueue.main.async {
                    self.delegate?.bluetoothManager(self, didReceiveAccessoryConfigurationData: configData, deviceID: deviceID)
                }
            }
            
        case .accessoryUwbDidStart:
            logger.info("UWB started on accessory")
            DispatchQueue.main.async {
                self.uwbActive = true
                self.delegate?.bluetoothManager(self, uwbDidStart: true, deviceID: deviceID)
            }
            
            // Update device status to ranging
            if let deviceIndex = discoveredDevices.firstIndex(where: { $0.bleUniqueID == deviceID }) {
                discoveredDevices[deviceIndex].blePeripheralStatus = statusRanging
            }
            
        case .accessoryUwbDidStop:
            logger.info("UWB stopped on accessory")
            DispatchQueue.main.async {
                self.uwbActive = false
                self.delegate?.bluetoothManager(self, uwbDidStart: false, deviceID: deviceID)
            }
            
            // Update device status back to connected
            if let deviceIndex = discoveredDevices.firstIndex(where: { $0.bleUniqueID == deviceID }) {
                discoveredDevices[deviceIndex].blePeripheralStatus = statusConnected
            }
            
        default:
            logger.info("Received message: \(String(describing: message))")
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            logger.error("Error changing notification state: \(error.localizedDescription)")
            return
        }
        
        if characteristic.isNotifying {
            logger.info("Notification began on \(characteristic.uuid)")
        } else {
            logger.info("Notification stopped on \(characteristic.uuid)")
        }
    }
    
    // MARK: - Device Storage Integration
    
    private func loadSavedDevices() {
        let savedDevices = DeviceStorage.shared.savedDevices
        
        for savedDevice in savedDevices {
            let qorvoDevice = QorvoDevice()
            qorvoDevice.bleUniqueID = savedDevice.id
            qorvoDevice.blePeripheralName = savedDevice.name
            qorvoDevice.blePeripheralStatus = statusDiscovered // 저장된 디바이스도 발견된 상태로 시작
            qorvoDevice.bleTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
            
            if !discoveredDevices.contains(where: { $0.bleUniqueID == savedDevice.id }) {
                discoveredDevices.append(qorvoDevice)
            }
        }
        
        // Start auto-connect when Bluetooth is ready
        if bluetoothReady {
            attemptAutoConnect()
        } else {
            shouldStartWhenReady = true
        }
    }
    
    private func attemptAutoConnect() {
        guard bluetoothReady && !isScanning else { return }
        
        let savedDevices = DeviceStorage.shared.savedDevices
        guard !savedDevices.isEmpty else { return }
        
        logger.info("Attempting to auto-connect to \(savedDevices.count) saved devices")
        
        // Start scanning to find saved devices
        startScanning()
        
        // Stop auto-scan after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            if self?.isScanning == true {
                self?.stopScanning()
                self?.logger.info("Auto-connect scan timeout")
            }
        }
    }
    
    func saveCurrentDevice(_ device: QorvoDevice) {
        DeviceStorage.shared.saveDevice(device)
        
        // 디바이스를 저장하더라도 실제 연결 상태는 유지
        // (UI에서 저장 여부는 DeviceStorage.shared.isDeviceSaved()로 확인)
    }
    
    func removeSavedDevice(_ deviceID: Int) {
        if let savedDevice = DeviceStorage.shared.getSavedDevice(by: deviceID) {
            DeviceStorage.shared.removeDevice(savedDevice)
            
            // Update discovered devices list
            discoveredDevices.removeAll { $0.bleUniqueID == deviceID }
        }
    }
}