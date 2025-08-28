//
//  ContentView.swift
//  FindMyCar
//
//  Created by NoriDev on 8/25/25.
//

import SwiftUI
import CoreBluetooth
import NearbyInteraction

struct ContentView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var nearbyInteractionManager: NearbyInteractionManager
    
    init() {
        let bluetoothManager = BluetoothManager()
        self._bluetoothManager = StateObject(wrappedValue: bluetoothManager)
        self._nearbyInteractionManager = StateObject(wrappedValue: NearbyInteractionManager(bluetoothManager: bluetoothManager))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "car.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Find My Car")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                // Connection Status Card
                ConnectionStatusCard(
                    bluetoothManager: bluetoothManager,
                    nearbyInteractionManager: nearbyInteractionManager
                )
                
                // Device List
                if bluetoothManager.isScanning || !bluetoothManager.discoveredDevices.isEmpty {
                    DeviceListView(bluetoothManager: bluetoothManager)
                }
                
                // Measurement Display
                if nearbyInteractionManager.isSessionActive {
                    MeasurementDisplayView(nearbyInteractionManager: nearbyInteractionManager)
                    
                    // Detailed Measurements (expandable)
                    DisclosureGroup("Detailed Measurements") {
                        DetailedMeasurementsView(nearbyInteractionManager: nearbyInteractionManager)
                    }
                    .padding(.horizontal)
                }
                
                // Action Buttons
                ActionButtonsView(
                    bluetoothManager: bluetoothManager,
                    nearbyInteractionManager: nearbyInteractionManager
                )
                }
                .padding()
            }
            .navigationTitle("Find My Car")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ConnectionStatusCard: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connection Status")
                    .font(.headline)
                Spacer()
                StatusIndicator(
                    isConnected: bluetoothManager.connectedPeripheral != nil,
                    isActive: nearbyInteractionManager.isSessionActive
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    title: "Bluetooth",
                    status: bluetoothStatusText,
                    color: bluetoothStatusColor
                )
                
                StatusRow(
                    title: "UWB Session",
                    status: uwbStatusText,
                    color: uwbStatusColor
                )
                
                if bluetoothManager.connectedPeripheral != nil {
                    StatusRow(
                        title: "UWB Module",
                        status: bluetoothManager.uwbActive ? "Active" : "Inactive",
                        color: bluetoothManager.uwbActive ? .green : .secondary
                    )
                }
                
                
                if let connectedDevice = bluetoothManager.connectedPeripheral {
                    StatusRow(
                        title: "Device",
                        status: connectedDevice.name ?? "DWM3001CDK",
                        color: .primary
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var bluetoothStatusText: String {
        switch bluetoothManager.connectionStatus {
        case .disconnected:
            return "Disconnected"
        case .scanning:
            return "Scanning..."
        case .connecting:
            return "Connecting..."
        case .connected:
            return "Connected"
        case .failed(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
    
    private var bluetoothStatusColor: Color {
        switch bluetoothManager.connectionStatus {
        case .disconnected:
            return .secondary
        case .scanning, .connecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var uwbStatusText: String {
        switch nearbyInteractionManager.sessionStatus {
        case .idle:
            return "Idle"
        case .starting:
            return "Starting..."
        case .running:
            return "Active"
        case .paused:
            return "Paused"
        case .failed(let error):
            return "Error: \(error.localizedDescription)"
        }
    }
    
    private var uwbStatusColor: Color {
        switch nearbyInteractionManager.sessionStatus {
        case .idle, .paused:
            return .secondary
        case .starting:
            return .orange
        case .running:
            return .green
        case .failed:
            return .red
        }
    }
    
}

struct StatusIndicator: View {
    let isConnected: Bool
    let isActive: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isConnected ? Color.green : Color.red)
                .frame(width: 12, height: 12)
            
            if isActive {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

struct StatusRow: View {
    let title: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(status)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

struct DeviceListView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Discovered Devices")
                    .font(.headline)
                Spacer()
                if bluetoothManager.isScanning {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if bluetoothManager.discoveredDevices.isEmpty && !bluetoothManager.isScanning {
                Text("No devices found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(bluetoothManager.discoveredDevices, id: \.bleUniqueID) { device in
                    DeviceRow(device: device, bluetoothManager: bluetoothManager)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct DeviceRow: View {
    let device: QorvoDevice
    @ObservedObject var bluetoothManager: BluetoothManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.blePeripheralName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Text("ID: \(String(device.bleUniqueID).prefix(8))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("• \(device.blePeripheralStatus ?? "Unknown")")
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                if let location = device.uwbLocation, !location.noUpdate && location.distance > 0 {
                    Text("\(String(format: "%.2f", location.distance))m away")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            
            Spacer()
            
            if device.blePeripheralStatus == statusDiscovered {
                if bluetoothManager.connectionStatus == .connecting {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button("Connect") {
                        bluetoothManager.connect(to: device)
                    }
                    .buttonStyle(.bordered)
                }
            } else if device.blePeripheralStatus == statusConnected {
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            } else if device.blePeripheralStatus == statusRanging {
                Text("Ranging")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .fontWeight(.medium)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch device.blePeripheralStatus {
        case statusDiscovered:
            return .blue
        case statusConnected:
            return .green
        case statusRanging:
            return .purple
        default:
            return .secondary
        }
    }
}

struct ActionButtonsView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: {
                    if bluetoothManager.isScanning {
                        bluetoothManager.stopScanning()
                    } else {
                        bluetoothManager.startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: bluetoothManager.isScanning ? "stop.circle" : "magnifyingglass")
                        Text(bluetoothManager.isScanning ? "Stop Scan" : "Scan Devices")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Button(action: {
                    if nearbyInteractionManager.isSessionActive {
                        nearbyInteractionManager.stopSession()
                    } else {
                        nearbyInteractionManager.startSession()
                    }
                }) {
                    HStack {
                        Image(systemName: nearbyInteractionManager.isSessionActive ? "stop.circle" : "play.circle")
                        Text(nearbyInteractionManager.isSessionActive ? "Stop UWB" : "Start UWB")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(bluetoothManager.connectedPeripheral == nil)
            }
            
            // Show UWB controls for connected and ranging devices
            let connectedDevices = bluetoothManager.discoveredDevices.filter { 
                $0.blePeripheralStatus == statusConnected || $0.blePeripheralStatus == statusRanging 
            }
            
            if !connectedDevices.isEmpty {
                VStack(spacing: 8) {
                    ForEach(connectedDevices, id: \.bleUniqueID) { device in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.blePeripheralName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text(device.blePeripheralStatus ?? "Unknown")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if device.blePeripheralStatus == statusConnected {
                                Button("Initialize UWB") {
                                    bluetoothManager.initializeUWB(deviceID: device.bleUniqueID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.blue)
                            } else if device.blePeripheralStatus == statusRanging {
                                Button("Stop UWB") {
                                    bluetoothManager.stopUWB(deviceID: device.bleUniqueID)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.orange)
                            }
                            
                            Button("Disconnect") {
                                bluetoothManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .foregroundColor(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Show permission help if UWB session failed
            if case .failed(let error) = nearbyInteractionManager.sessionStatus,
               error.localizedDescription.contains("did not allow") {
                VStack(spacing: 8) {
                    Text("Nearby Interaction permission is required for UWB functionality.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Open Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(.systemYellow).opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
}

#Preview {
    ContentView()
}
