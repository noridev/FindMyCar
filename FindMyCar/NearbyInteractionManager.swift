//
//  NearbyInteractionManager.swift
//  FindMyCar
//
//  Created by NoriDev on 8/27/25.
//

import Foundation
import NearbyInteraction
import Combine
import simd
import os.log
import CoreBluetooth
import CoreLocation
import SwiftUI

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
    
    // 위치 업데이트 최적화를 위한 속성들
    private let backgroundQueue = DispatchQueue(label: "location-update-queue", qos: .utility)
    private var lastSavedLocations: [Int: CLLocationCoordinate2D] = [:]
    private let minimumDistanceForSave: Double = 5.0 // 5미터 이상 이동했을 때만 저장
    
    // UI 업데이트 디바운싱을 위한 속성들
    private var lastUIUpdateTime: Date = Date()
    private let uiUpdateInterval: TimeInterval = 0.2 // 초당 5회로 제한 (200ms)

    // UWB 데이터 감시를 위한 속성들
    private var lastDataReceiveTime: Date?
    private var dataMonitorTimer: Timer?
    private let maxDataInterval: TimeInterval = 5.0 // 5초간 데이터가 없으면 재시작
    
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
        stopDataMonitoring()
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
        stopDataMonitoring()

        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
            isSessionActive = false
        }
        sessionStatus = .idle
        distance = nil
        direction = nil
        elevation = nil

        logger.info("All NI sessions stopped")
    }

    func forceRestartSession() {
        logger.info("Force restarting UWB session")

        // 기존 세션들을 정리
        niSessions.values.forEach { $0.invalidate() }
        niSessions.removeAll()

        // 저장된 configuration을 사용해서 새 세션 시작
        for (deviceID, configuration) in configurations {
            let session = NISession()
            session.delegate = self
            niSessions[deviceID] = session

            session.run(configuration)
            logger.info("Restarted NI session for device \(deviceID)")

            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isSessionActive = true
            }
            sessionStatus = .running
            selectedDeviceID = deviceID
            startDataMonitoring() // 데이터 모니터링 시작
        }

        if configurations.isEmpty {
            logger.warning("No configurations available for restart - requesting new UWB initialization")
            // 설정이 없으면 블루투스 매니저에게 UWB 재초기화 요청
            if let connectedDeviceID = bluetoothManager.discoveredDevices.first(where: {
                $0.blePeripheralStatus == statusRanging || $0.blePeripheralStatus == statusConnected
            })?.bleUniqueID {
                bluetoothManager.initializeUWB(deviceID: connectedDeviceID)
            }
        }
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
            
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isSessionActive = true
            }
            sessionStatus = .running
            selectedDeviceID = deviceID
            startDataMonitoring() // 데이터 모니터링 시작

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
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    isSessionActive = false
                }
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
            logger.warning("NISession didUpdate called but no nearby objects")
            return
        }

        logger.info("NISession didUpdate - Distance: \(nearbyObject.distance?.description ?? "nil"), Direction: \(nearbyObject.direction?.debugDescription ?? "nil")")

        // 데이터 수신 시간 업데이트
        updateLastDataReceiveTime()

        // UI 업데이트 디바운싱 적용
        let now = Date()
        let shouldUpdateUI = now.timeIntervalSince(lastUIUpdateTime) >= uiUpdateInterval
        
        if shouldUpdateUI {
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
            
            lastUIUpdateTime = now
        }
        
        // Update device location in bluetooth manager (always update, not throttled)
        if let deviceIndex = bluetoothManager.discoveredDevices.firstIndex(where: { 
            niSessions[$0.bleUniqueID] === session 
        }) {
            let device = bluetoothManager.discoveredDevices[deviceIndex]
            device.uwbLocation?.distance = nearbyObject.distance ?? 0
            device.uwbLocation?.direction = nearbyObject.direction ?? SIMD3<Float>(0, 0, 0)
            device.uwbLocation?.elevation = nearbyObject.verticalDirectionEstimate.rawValue
            device.uwbLocation?.noUpdate = false
            
            // Save current location when device is being tracked (optimized)
            if let currentLocation = locationManager.location?.coordinate {
                saveLocationOptimized(deviceID: device.bleUniqueID, coordinate: currentLocation)
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
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                self.isSessionActive = false
            }
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

        // 세션이 일시정지에서 재개된 후 2초 후에도 데이터가 없으면 강제 재시작
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.distance == nil && self.direction == nil && self.sessionStatus == .running {
                self.logger.info("Session resumed but no data received - force restarting")
                self.forceRestartSession()
            }
        }
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
    
    // MARK: - 위치 저장 최적화
    private func saveLocationOptimized(deviceID: Int, coordinate: CLLocationCoordinate2D) {
        backgroundQueue.async { [weak self] in
            guard let self = self else { return }
            
            // 이전 위치와 비교하여 최소 거리 이상 이동했을 때만 저장
            if let lastLocation = self.lastSavedLocations[deviceID] {
                let lastCLLocation = CLLocation(latitude: lastLocation.latitude, longitude: lastLocation.longitude)
                let currentCLLocation = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                let distance = lastCLLocation.distance(from: currentCLLocation)
                
                if distance < self.minimumDistanceForSave {
                    return // 최소 거리 이하이면 저장하지 않음
                }
            }
            
            // 위치 저장
            LocationStorage.shared.saveLocation(deviceID: deviceID, coordinate: coordinate)
            self.lastSavedLocations[deviceID] = coordinate
            
            self.logger.debug("Location saved for device \(deviceID) - optimized")
        }
    }

    // MARK: - UWB 데이터 모니터링
    private func startDataMonitoring() {
        stopDataMonitoring() // 기존 타이머 정리

        dataMonitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkDataHealth()
        }

        logger.info("Started UWB data monitoring")
    }

    private func stopDataMonitoring() {
        dataMonitorTimer?.invalidate()
        dataMonitorTimer = nil
        logger.info("Stopped UWB data monitoring")
    }

    private func checkDataHealth() {
        guard isSessionActive && sessionStatus == .running else { return }

        if let lastReceive = lastDataReceiveTime {
            let timeSinceLastData = Date().timeIntervalSince(lastReceive)
            if timeSinceLastData > maxDataInterval {
                logger.warning("No UWB data received for \(timeSinceLastData) seconds - force restarting")
                forceRestartSession()
            }
        } else if isSessionActive {
            // 세션은 활성화되었지만 한 번도 데이터를 받지 못한 경우
            logger.warning("UWB session active but no data ever received - force restarting")
            forceRestartSession()
        }
    }

    private func updateLastDataReceiveTime() {
        lastDataReceiveTime = Date()
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
