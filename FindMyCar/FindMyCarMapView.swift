import SwiftUI
import MapKit
import CoreLocation

struct FindMyCarMapView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var nearbyInteractionManager: NearbyInteractionManager
    @StateObject private var locationManager = LocationManager()
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingDeviceList = false
    @State private var mapStyle: MapStyle = .standard(elevation: .realistic)
    
    init() {
        let bluetoothManager = BluetoothManager()
        self._bluetoothManager = StateObject(wrappedValue: bluetoothManager)
        self._nearbyInteractionManager = StateObject(wrappedValue: NearbyInteractionManager(bluetoothManager: bluetoothManager))
    }
    
    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    if let userLocation = locationManager.userLocation {
                        Marker("You", systemImage: "person.circle.fill", coordinate: userLocation)
                            .tint(.blue)
                    }
                    
                    ForEach(Array(deviceAnnotations.enumerated()), id: \.offset) { index, annotation in
                        Annotation(annotation.title, coordinate: annotation.coordinate, anchor: .bottom) {
                            CarAnnotationView(device: annotation.device)
                        }
                    }
                }
                .mapStyle(mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                }
                .onAppear {
                    locationManager.requestLocationPermission()
                    if let userLocation = locationManager.userLocation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
                .onReceive(locationManager.$userLocation) { userLocation in
                    if let userLocation = userLocation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
            }
            
            VStack {
                HStack {
                    Spacer()
                    MapControlsGroup(
                        selectedStyle: $mapStyle,
                        cameraPosition: $cameraPosition,
                        locationManager: locationManager
                    )
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
            }
            .sheet(isPresented: $showingDeviceList) {
                DeviceListSheetView(
                    bluetoothManager: bluetoothManager,
                    nearbyInteractionManager: nearbyInteractionManager
                )
                .presentationDetents([.height(300), .height(500), .large])
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
            }
            .onAppear {
                showingDeviceList = true
            }
        }
        .ignoresSafeArea(.all, edges: .bottom)
    }
    
    private var deviceAnnotations: [DeviceAnnotation] {
        bluetoothManager.discoveredDevices.compactMap { device in
            guard let savedLocation = LocationStorage.shared.getLastLocation(for: device.bleUniqueID) else {
                return nil
            }
            
            return DeviceAnnotation(
                id: device.bleUniqueID,
                title: device.blePeripheralName,
                coordinate: savedLocation,
                device: device
            )
        }
    }
}

struct DeviceListSheetView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
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
                .padding()
            }
            .navigationTitle("Find My Car")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UWB 디바이스")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("디바이스 연결 및 추적")
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
                Text("활성 추적")
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

struct DeviceAnnotation {
    let id: Int
    let title: String
    let coordinate: CLLocationCoordinate2D
    let device: QorvoDevice
}

struct CarAnnotationView: View {
    let device: QorvoDevice
    
    var body: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 60, height: 60)
            
            Circle()
                .fill(statusColor)
                .frame(width: 40, height: 40)
            
            Image(systemName: "car.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
    
    private var statusColor: Color {
        switch device.blePeripheralStatus {
        case statusConnected:
            return .green
        case statusRanging:
            return .purple
        default:
            return .gray
        }
    }
}

enum MapStyleType: String, CaseIterable {
    case standard = "표준"
    case imagery = "위성"
    case hybrid = "하이브리드"
    
    var mapStyle: MapStyle {
        switch self {
        case .standard:
            return .standard(elevation: .realistic)
        case .imagery:
            return .imagery(elevation: .realistic)
        case .hybrid:
            return .hybrid(elevation: .realistic)
        }
    }
    
    var icon: String {
        switch self {
        case .standard:
            return "map"
        case .imagery:
            return "globe.americas"
        case .hybrid:
            return "square.stack.3d.up"
        }
    }
}

struct MapControlsGroup: View {
    @Binding var selectedStyle: MapStyle
    @Binding var cameraPosition: MapCameraPosition
    let locationManager: LocationManager
    
    @State private var selectedType: MapStyleType = .standard
    @State private var showingStylePicker = false
    
    var body: some View {
        VStack(spacing: 1) {
            // 지도 스타일 버튼
            Button(action: {
                showingStylePicker = true
            }) {
                Image(systemName: selectedType.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // 현재 위치 버튼
            Button(action: {
                if let userLocation = locationManager.userLocation {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                } else {
                    locationManager.requestLocationPermission()
                }
            }) {
                Image(systemName: "location")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingStylePicker) {
            MapStyleSheet(
                selectedType: $selectedType,
                selectedStyle: $selectedStyle
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }
}

struct MapStyleSheet: View {
    @Binding var selectedType: MapStyleType
    @Binding var selectedStyle: MapStyle
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                VStack(spacing: 24) {
                    ForEach(MapStyleType.allCases, id: \.self) { styleType in
                        Button(action: {
                            selectedType = styleType
                            selectedStyle = styleType.mapStyle
                            dismiss()
                        }) {
                            HStack(spacing: 16) {
                                Image(systemName: styleType.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(.primary)
                                    .frame(width: 40, height: 40)
                                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 8))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(styleType.rawValue)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(styleDescription(for: styleType))
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedType == styleType {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(selectedType == styleType ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                Spacer()
            }
            .navigationTitle("지도 스타일")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("완료") {
                dismiss()
            })
        }
    }
    
    private func styleDescription(for type: MapStyleType) -> String {
        switch type {
        case .standard:
            return "도로와 지명이 표시된 기본 지도"
        case .imagery:
            return "위성 사진으로 실제 모습을 보여주는 지도"
        case .hybrid:
            return "위성 사진에 도로와 지명을 함께 표시"
        }
    }
}

#Preview {
    FindMyCarMapView()
}