import Foundation
import NearbyInteraction
import Combine
import simd
import os.log
import CoreBluetooth
import CoreLocation

class NearbyInteractionManager: NSObject, ObservableObject, BluetoothManagerDelegate {
    private let logger = Logger(subsystem: "com.findmycar.app", category: "NearbyInteractionManager")
    
    @Published var isSessionActive = false
    @Published var distance: Float?
    @Published var direction: simd_float3?
    @Published var elevation: Float?
    @Published var sessionStatus: SessionStatus = .idle
    @Published var lastUpdate: Date?
    
    private var bluetoothManager: BluetoothManager
    private var niSessions: [Int: NISession] = [:]
    private var configurations: [Int: NINearbyAccessoryConfiguration] = [:]
    private var selectedDeviceID: Int = -1
    private let locationManager = CLLocationManager()
    
    enum SessionStatus: Equatable {
        case idle
        case starting
        case running
        case paused
        case failed(Error)
        
        static func == (lhs: SessionStatus, rhs: SessionStatus) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle),
                 (.starting, .starting),
                 (.running, .running),
                 (.paused, .paused):
                return true
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
        super.init()
        self.bluetoothManager.delegate = self
    }
    
    deinit {
        niSessions.values.forEach { $0.invalidate() }
        niSessions.removeAll()
    }
    
    func startSession() {
        // This will be called automatically when we receive configuration data
        // For now, just update the status
        if sessionStatus == .idle {
            sessionStatus = .starting
        }
    }
    
    func stopSession() {
        niSessions.values.forEach { $0.invalidate() }
        niSessions.removeAll()
        configurations.removeAll()
        
        isSessionActive = false
        sessionStatus = .idle
        distance = nil
        direction = nil
        elevation = nil
        
        logger.info("All NI sessions stopped")
    }
    
    private func setupAccessory(_ configData: Data, deviceID: Int) {
        logger.info("Setting up accessory with configuration data")
        
        do {
            let configuration = try NINearbyAccessoryConfiguration(data: configData)
            configuration.isCameraAssistanceEnabled = true
            configurations[deviceID] = configuration
            
            // Create NISession for this device
            let session = NISession()
            session.delegate = self
            niSessions[deviceID] = session
            
            // Run the session
            session.run(configuration)
            
            isSessionActive = true
            sessionStatus = .running
            selectedDeviceID = deviceID
            
            logger.info("NI session started successfully for device \(deviceID)")
            
        } catch {
            logger.error("Failed to create NINearbyAccessoryConfiguration: \(error)")
            sessionStatus = .failed(error)
        }
    }
}

// MARK: - BluetoothManagerDelegate
extension NearbyInteractionManager {
    func bluetoothManager(_ manager: BluetoothManager, didConnectDevice deviceID: Int) {
        logger.info("Device connected, sending initialize command")
        
        // Send initialize command like in Qorvo sample
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            manager.initializeUWB(deviceID: deviceID)
        }
    }
    
    func bluetoothManager(_ manager: BluetoothManager, didReceiveAccessoryConfigurationData data: Data, deviceID: Int) {
        logger.info("Received accessory configuration data, starting NI session")
        
        // Setup the accessory with configuration data (like Qorvo setupAccessory)
        setupAccessory(data, deviceID: deviceID)
        
        // configureAndStart will be sent automatically in didGenerateShareableConfigurationData
    }
    
    func bluetoothManager(_ manager: BluetoothManager, uwbDidStart: Bool, deviceID: Int) {
        logger.info("UWB status changed: \(uwbDidStart ? "Started" : "Stopped") for device \(deviceID)")
        
        if uwbDidStart {
            logger.info("UWB is now active on accessory")
        } else {
            logger.info("UWB stopped on accessory")
            // If UWB stops, invalidate the session for this device
            if let session = niSessions[deviceID] {
                session.invalidate()
                niSessions.removeValue(forKey: deviceID)
                configurations.removeValue(forKey: deviceID)
            }
            
            // If this was the selected device, update UI
            if deviceID == selectedDeviceID {
                isSessionActive = false
                sessionStatus = .idle
                distance = nil
                direction = nil
                elevation = nil
            }
        }
    }
}

// MARK: - NISessionDelegate
extension NearbyInteractionManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let nearbyObject = nearbyObjects.first else {
            return
        }
        
        // Update the UI with new measurements
        DispatchQueue.main.async {
            if let distance = nearbyObject.distance {
                self.distance = distance
            }
            
            if let direction = nearbyObject.direction {
                self.direction = direction
            }
            
            // Handle elevation if available
            switch nearbyObject.verticalDirectionEstimate {
            case .same:
                self.elevation = 0
            case .above:
                self.elevation = 1
            case .below:
                self.elevation = -1
            case .aboveOrBelow:
                self.elevation = 0
            case .unknown:
                self.elevation = nil
            @unknown default:
                self.elevation = nil
            }
            
            self.lastUpdate = Date()
        }
        
        // Update device location in bluetooth manager and save location
        if let deviceIndex = bluetoothManager.discoveredDevices.firstIndex(where: { 
            niSessions[$0.bleUniqueID] === session 
        }) {
            let device = bluetoothManager.discoveredDevices[deviceIndex]
            device.uwbLocation?.distance = nearbyObject.distance ?? 0
            device.uwbLocation?.direction = nearbyObject.direction ?? SIMD3<Float>(0, 0, 0)
            device.uwbLocation?.elevation = nearbyObject.verticalDirectionEstimate.rawValue
            device.uwbLocation?.noUpdate = false
            
            // Save current location when device is being tracked
            if let currentLocation = locationManager.location?.coordinate {
                LocationStorage.shared.saveLocation(deviceID: device.bleUniqueID, coordinate: currentLocation)
            }
        }
        
        logger.debug("Updated location - Distance: \(nearbyObject.distance?.description ?? "nil"), Direction: \(nearbyObject.direction?.debugDescription ?? "nil")")
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        logger.info("Lost nearby objects, reason: \(reason.rawValue)")
        
        DispatchQueue.main.async {
            // Reset measurements when objects are removed
            if reason == .timeout {
                self.distance = nil
                self.direction = nil
                self.elevation = nil
            }
        }
        
        // Update device to indicate no update
        if let deviceIndex = bluetoothManager.discoveredDevices.firstIndex(where: { 
            niSessions[$0.bleUniqueID] === session 
        }) {
            let device = bluetoothManager.discoveredDevices[deviceIndex]
            device.uwbLocation?.noUpdate = true
        }
    }
    
    func session(_ session: NISession, didInvalidateWith error: Error) {
        logger.error("NI Session invalidated with error: \(error.localizedDescription)")
        
        DispatchQueue.main.async {
            self.sessionStatus = .failed(error)
            self.isSessionActive = false
        }
        
        // Handle specific error types
        if let niError = error as? NIError {
            switch niError.code {
            case .unsupportedPlatform:
                logger.error("Nearby Interaction not supported")
            case .invalidConfiguration:
                logger.error("Invalid session configuration")
            case .sessionFailed:
                logger.error("Session failed")
            case .resourceUsageTimeout:
                logger.error("Session timed out due to resource usage")
            case .activeSessionsLimitExceeded:
                logger.error("Too many active sessions")
            case .userDidNotAllow:
                logger.error("User did not allow Nearby Interaction")
            case .invalidARConfiguration:
                logger.error("Invalid AR configuration")
            case .accessoryPeerDeviceUnavailable:
                logger.error("Accessory peer device unavailable")
            case .incompatiblePeerDevice:
                logger.error("Incompatible peer device")
            case .activeExtendedDistanceSessionsLimitExceeded:
                logger.error("Extended distance sessions limit exceeded")
            @unknown default:
                logger.error("Unknown NI error: \(niError.localizedDescription)")
            }
        }
        
        // Remove the session from our tracking
        for (deviceID, trackedSession) in niSessions {
            if trackedSession === session {
                niSessions.removeValue(forKey: deviceID)
                configurations.removeValue(forKey: deviceID)
                break
            }
        }
    }
    
    func sessionWasSuspended(_ session: NISession) {
        DispatchQueue.main.async {
            self.sessionStatus = .paused
        }
        logger.info("NI Session was suspended")
    }
    
    func sessionSuspensionEnded(_ session: NISession) {
        DispatchQueue.main.async {
            self.sessionStatus = .running
        }
        logger.info("NI Session suspension ended")
    }
    
    func session(_ session: NISession, didGenerateShareableConfigurationData shareableConfigurationData: Data, for object: NINearbyObject) {
        logger.info("Generated shareable configuration data")
        
        // Find the deviceID for this session
        guard let deviceID = niSessions.first(where: { $0.value === session })?.key else {
            logger.error("Could not find deviceID for session")
            return
        }
        
        // Send configureAndStart message with the shareable configuration data (like Qorvo)
        var msg = Data([MessageId.configureAndStart.rawValue])
        msg.append(shareableConfigurationData)
        
        let dataString = msg.map { String(format: "0x%02x", $0) }.joined(separator: ", ")
        logger.info("Sending shareable configuration bytes: \(dataString)")
        
        bluetoothManager.sendDataToAccessory(msg, deviceID: deviceID)
    }
}

// Helper extensions for error handling
extension NIError {
    static let unsupportedPlatform = NIError(_nsError: NSError(
        domain: "NearbyInteractionManager",
        code: 1001,
        userInfo: [NSLocalizedDescriptionKey: "Nearby Interaction not supported on this platform"]
    ))
    
    static let invalidConfiguration = NIError(_nsError: NSError(
        domain: "NearbyInteractionManager",
        code: 1002,
        userInfo: [NSLocalizedDescriptionKey: "Invalid Nearby Interaction configuration"]
    ))
}