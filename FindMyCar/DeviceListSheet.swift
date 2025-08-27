import SwiftUI
import CoreLocation
import simd

struct DeviceListSheet: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    @Binding var height: CGFloat
    
    let minHeight: CGFloat
    let maxHeight: CGFloat
    
    @State private var dragOffset: CGFloat = 0
    @State private var startHeight: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            handle
                .padding(.top, 8)
                .padding(.bottom, 12)
            
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    
                    if bluetoothManager.discoveredDevices.isEmpty {
                        noDevicesView
                    } else {
                        deviceListSection
                    }
                    
                    controlsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .frame(height: height + dragOffset)
        .background(
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -2)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    if startHeight == 0 {
                        startHeight = height
                    }
                    dragOffset = -value.translation.height
                }
                .onEnded { value in
                    withAnimation(.spring()) {
                        let newHeight = startHeight - value.translation.height
                        
                        if newHeight < minHeight {
                            height = minHeight
                        } else if newHeight > maxHeight {
                            height = maxHeight
                        } else {
                            height = newHeight
                        }
                        
                        dragOffset = 0
                        startHeight = 0
                    }
                }
        )
    }
    
    private var handle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(.systemGray3))
            .frame(width: 36, height: 4)
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find My Car")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("UWB 디바이스")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                connectionStatusIndicator
            }
            
            if nearbyInteractionManager.isSessionActive {
                activeSessionCard
            }
        }
    }
    
    private var connectionStatusIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(bluetoothStatusColor)
                .frame(width: 12, height: 12)
            
            if nearbyInteractionManager.isSessionActive {
                Circle()
                    .fill(Color.purple)
                    .frame(width: 12, height: 12)
            }
        }
    }
    
    private var bluetoothStatusColor: Color {
        switch bluetoothManager.connectionStatus {
        case .connected:
            return .green
        case .connecting, .scanning:
            return .orange
        case .failed:
            return .red
        default:
            return .gray
        }
    }
    
    private var activeSessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "location.circle.fill")
                    .foregroundColor(.purple)
                Text("Active Tracking")
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            if let distance = nearbyInteractionManager.distance {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("거리")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.2f", distance))m")
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                    
                    if let direction = nearbyInteractionManager.direction {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("방향")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            DirectionIndicator(direction: direction)
                        }
                    }
                }
            } else {
                Text("위치 정보를 받고 있습니다...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var noDevicesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("디바이스가 발견되지 않았습니다")
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text("Bluetooth를 켜고 스캔을 시작해주세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    private var deviceListSection: some View {
        LazyVStack(spacing: 12) {
            ForEach(bluetoothManager.discoveredDevices, id: \.bleUniqueID) { device in
                DeviceCard(
                    device: device,
                    bluetoothManager: bluetoothManager,
                    nearbyInteractionManager: nearbyInteractionManager
                )
            }
        }
    }
    
    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: {
                    if bluetoothManager.isScanning {
                        bluetoothManager.stopScanning()
                    } else {
                        bluetoothManager.startScanning()
                    }
                }) {
                    HStack {
                        if bluetoothManager.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "magnifyingglass")
                        }
                        Text(bluetoothManager.isScanning ? "스캔 중지" : "디바이스 스캔")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }
}

struct DeviceCard: View {
    let device: QorvoDevice
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "car.fill")
                            .foregroundColor(statusColor)
                            .font(.system(size: 16))
                        
                        Text(device.blePeripheralName)
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    
                    Text(device.blePeripheralStatus ?? "알 수 없음")
                        .font(.subheadline)
                        .foregroundColor(statusColor)
                    
                    if let locationInfo = LocationStorage.shared.getLocationWithTimestamp(for: device.bleUniqueID) {
                        Text("마지막 위치: \(formatTimestamp(locationInfo.timestamp))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    if let location = device.uwbLocation, !location.noUpdate, location.distance > 0 {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(String(format: "%.2f", location.distance))m")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                            
                            DirectionIndicator(direction: location.direction)
                        }
                    }
                    
                    deviceActionButton
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    @ViewBuilder
    private var deviceActionButton: some View {
        switch device.blePeripheralStatus {
        case statusDiscovered:
            Button("연결") {
                bluetoothManager.connect(to: device)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(bluetoothManager.connectionStatus == .connecting)
            
        case statusConnected:
            Button("UWB 시작") {
                bluetoothManager.initializeUWB(deviceID: device.bleUniqueID)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.green)
            
        case statusRanging:
            VStack(spacing: 4) {
                Button("UWB 중지") {
                    bluetoothManager.stopUWB(deviceID: device.bleUniqueID)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                
                Button("위치 저장") {
                    saveCurrentLocation()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.purple)
            }
            
        default:
            EmptyView()
        }
    }
    
    private var statusColor: Color {
        switch device.blePeripheralStatus {
        case statusConnected:
            return .green
        case statusRanging:
            return .purple
        case statusDiscovered:
            return .blue
        default:
            return .secondary
        }
    }
    
    private func saveCurrentLocation() {
        guard let userLocation = CLLocationManager().location?.coordinate else { return }
        LocationStorage.shared.saveLocation(deviceID: device.bleUniqueID, coordinate: userLocation)
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct DirectionIndicator: View {
    let direction: simd_float3
    
    var body: some View {
        // 방향을 180도 회전시켜 올바른 방향을 표시
        let angle = atan2(-direction.x, -direction.z) * 180 / .pi
        
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 16))
            .foregroundColor(.purple)
            .rotationEffect(.degrees(Double(angle)))
    }
}

#Preview {
    VStack {
        Spacer()
        DeviceListSheet(
            bluetoothManager: BluetoothManager(),
            nearbyInteractionManager: NearbyInteractionManager(bluetoothManager: BluetoothManager()),
            height: .constant(300),
            minHeight: 120,
            maxHeight: 600
        )
    }
}