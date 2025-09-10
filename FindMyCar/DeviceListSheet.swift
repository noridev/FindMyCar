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
                    nearbyInteractionManager: nearbyInteractionManager,
                    isSaved: DeviceStorage.shared.isDeviceSaved(device.bleUniqueID),
                    onVehicleSelected: { _ in }
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


struct DirectionIndicator: View {
    let direction: simd_float3
    
    var body: some View {
        // UWB 방향 벡터를 화면 좌표계에 맞게 변환
        // direction.x: 오른쪽이 양수, direction.z: 뒤쪽이 양수일 수 있음
        let angle = atan2(direction.x, -direction.z) * 180 / .pi
        
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