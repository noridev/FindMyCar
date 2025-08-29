import SwiftUI
import MapKit
import CoreLocation

struct FindMyCarMapView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var nearbyInteractionManager: NearbyInteractionManager
    @StateObject private var locationManager = LocationManager()
    
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingDeviceList = false
    @State private var isScanning = false
    @State private var scanTimer: Timer?
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
                    UserAnnotation()
                    
                    ForEach(Array(deviceAnnotations.enumerated()), id: \.offset) { index, annotation in
                        Annotation(annotation.title, coordinate: annotation.coordinate, anchor: .bottom) {
                            CarAnnotationView(device: annotation.device, bluetoothManager: bluetoothManager)
                        }
                    }
                }
                .mapStyle(mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                    MapPitchToggle()
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
                    MapStyleControl(
                        selectedStyle: $mapStyle
                    )
                    .padding(.leading, 16)
                    .padding(.top, 8)
                    Spacer()
                }
                Spacer()
            }
            .sheet(isPresented: $showingDeviceList) {
                DeviceListSheetView(
                    bluetoothManager: bluetoothManager,
                    nearbyInteractionManager: nearbyInteractionManager,
                    isScanning: $isScanning,
                    startScanning: startScanning,
                    stopScanning: stopScanning
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

    private func startScanning() {
        isScanning = true
        // 새 스캔 시작 시 저장되지 않은 디바이스만 제거
        bluetoothManager.discoveredDevices.removeAll { device in
            !DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
        }
        bluetoothManager.startScanning()

        // 30초 후 자동 중지
        scanTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { _ in
            stopScanning()
        }
    }

    private func stopScanning() {
        isScanning = false
        bluetoothManager.stopScanning()
        scanTimer?.invalidate()
        scanTimer = nil
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
    @Binding var isScanning: Bool
    let startScanning: () -> Void
    let stopScanning: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            deviceListView
            .navigationTitle("Find My Car")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: navigationBarTrailingButton)
        }
        .onReceive(bluetoothManager.$connectionStatus) { status in
            // 연결 성공 시 스캔 중단
            if case .connected = status, isScanning {
                stopScanning()
            }
        }
    }

    @ViewBuilder
    private var navigationBarTrailingButton: some View {
        Button(action: {
            if isScanning {
                stopScanning()
            } else {
                startScanning()
            }
        }) {
            Image(systemName: isScanning ? "stop" : "plus")
                .font(.system(size: 18, weight: .medium))
        }
        .disabled(bluetoothManager.isScanning && !isScanning)
    }

    private var deviceListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerSection

                if bluetoothManager.discoveredDevices.isEmpty && !isScanning {
                    noDevicesView
                } else if !bluetoothManager.discoveredDevices.isEmpty {
                    deviceListSection
                }

                // 스캔 중일 때 하단에 프로그래스 표시
                if isScanning {
                    scanningProgressView
                }
            }
            .padding()
        }
    }

    private var scanningProgressView: some View {
        VStack(spacing: 32) {
            Spacer()
                .frame(height: 20)

            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.0)

                Text("기기 검색 중...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
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
        LazyVStack(spacing: 16) {
            // 저장된 디바이스 섹션
            let savedDevices = bluetoothManager.discoveredDevices.filter { device in
                DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
            }

            if !savedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("저장된 디바이스")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(savedDevices, id: \.bleUniqueID) { device in
                        DeviceCard(
                            device: device,
                            bluetoothManager: bluetoothManager,
                            nearbyInteractionManager: nearbyInteractionManager,
                            isSaved: true
                        )
                    }
                }
            }

            // 새로 발견된 디바이스 섹션
            let newDevices = bluetoothManager.discoveredDevices.filter { device in
                !DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
            }

            if !newDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("새로 발견된 디바이스")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(newDevices, id: \.bleUniqueID) { device in
                        DeviceCard(
                            device: device,
                            bluetoothManager: bluetoothManager,
                            nearbyInteractionManager: nearbyInteractionManager,
                            isSaved: false
                        )
                    }
                }
            }
        }
    }

}

struct DeviceCard: View {
    let device: QorvoDevice
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    let isSaved: Bool
    @State private var currentAddress: String = ""

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 원형 기기 아이콘 (왼쪽)
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(statusColor)
                }
                
                // 기기 정보 (중앙)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.blePeripheralName)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if isSaved {
                            Image(systemName: "bookmark.fill")
                                .foregroundColor(.blue)
                                .font(.system(size: 12))
                        }
                    }
                    
                    if !currentAddress.isEmpty {
                        Text(currentAddress)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    if let locationInfo = LocationStorage.shared.getLocationWithTimestamp(for: device.bleUniqueID) {
                        Text("마지막으로 확인: \(formatTimestamp(locationInfo.timestamp))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 거리 정보 (오른쪽)
                if let location = device.uwbLocation, !location.noUpdate, location.distance > 0 {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(String(format: "%.0f", location.distance))m")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        DirectionIndicator(direction: location.direction)
                    }
                }
            }
            .onAppear {
                loadAddressForDevice()
            }

            // 버튼들을 가로로 꽉차게 배치
            HStack(spacing: 8) {
                deviceActionButton
                    .frame(maxWidth: .infinity, minHeight: 36)

                if device.blePeripheralStatus == statusRanging {
                    Button("UWB 중지") {
                        bluetoothManager.stopUWB(deviceID: device.bleUniqueID)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.orange.opacity(0.1))
                    .foregroundColor(.orange)
                    .cornerRadius(24)

                    Button("위치 저장") {
                        saveCurrentLocation()
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.purple.opacity(0.1))
                    .foregroundColor(.purple)
                    .cornerRadius(24)
                }

                if isSaved {
                    Button("기기 삭제") {
                        bluetoothManager.removeSavedDevice(device.bleUniqueID)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.red.opacity(0.1))
                    .foregroundColor(.red)
                    .cornerRadius(24)
                } else if device.blePeripheralStatus == statusConnected || device.blePeripheralStatus == statusRanging {
                    Button("기기 저장") {
                        bluetoothManager.saveCurrentDevice(device)
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(24)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(32)
    }

    @ViewBuilder
    private var deviceActionButton: some View {
        switch device.blePeripheralStatus {
        case statusDiscovered:
            if bluetoothManager.connectionStatus == .connecting {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.gray.opacity(0.1))
                .cornerRadius(24)
            } else {
                Button("연결") {
                    bluetoothManager.connect(to: device)
                }
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.primary.opacity(0.1))
                .foregroundColor(.primary)
                .cornerRadius(24)
            }

        case statusConnected:
            Button("UWB 시작") {
                bluetoothManager.initializeUWB(deviceID: device.bleUniqueID)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(.green.opacity(0.1))
            .foregroundColor(.green)
            .cornerRadius(24)

        case statusRanging:
            EmptyView()

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
    
    private func loadAddressForDevice() {
        guard let locationInfo = LocationStorage.shared.getLocationWithTimestamp(for: device.bleUniqueID) else {
            return
        }
        
        let location = CLLocation(latitude: locationInfo.coordinate.latitude, longitude: locationInfo.coordinate.longitude)
        reverseGeocode(location: location) { address in
            DispatchQueue.main.async {
                self.currentAddress = address
            }
        }
    }
    
    private func reverseGeocode(location: CLLocation, completion: @escaping (String) -> Void) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            if let error = error {
                print("Reverse geocoding failed: \(error.localizedDescription)")
                completion("")
                return
            }
            
            guard let placemark = placemarks?.first else {
                completion("")
                return
            }
            
            var addressComponents: [String] = []
            
            if let locality = placemark.locality {
                addressComponents.append(locality)
            }
            if let thoroughfare = placemark.thoroughfare {
                addressComponents.append(thoroughfare)
            }
            if let subThoroughfare = placemark.subThoroughfare {
                addressComponents.append(subThoroughfare)
            }
            
            let address = addressComponents.joined(separator: " ")
            completion(address.isEmpty ? "위치 정보 없음" : address)
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
    let bluetoothManager: BluetoothManager
    @State private var isAnimating = false
    @State private var currentStatus: String = ""

    var body: some View {
        ZStack {
            // 외부 링 (트래킹 중일 때만 표시)
            if currentStatus == statusRanging {
                Circle()
                    .stroke(statusColor, lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(isAnimating ? 1.2 : 1.0)
                    .opacity(isAnimating ? 0.0 : 0.8)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: isAnimating)
            }

            // 배경 원
            Circle()
                .fill(statusColor.opacity(0.3))
                .frame(width: 60, height: 60)

            // 메인 원
            Circle()
                .fill(statusColor)
                .frame(width: 40, height: 40)

            // 차량 아이콘
            Image(systemName: "car.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        .onAppear {
            updateStatus()
        }
        .onReceive(bluetoothManager.$discoveredDevices) { _ in
            updateStatus()
        }
    }

    private func updateStatus() {
        // BluetoothManager에서 현재 디바이스의 최신 상태를 가져옴
        if let currentDevice = bluetoothManager.discoveredDevices.first(where: { $0.bleUniqueID == device.bleUniqueID }) {
            currentStatus = currentDevice.blePeripheralStatus ?? ""
        } else {
            currentStatus = device.blePeripheralStatus ?? ""
        }

        if currentStatus == statusRanging {
            isAnimating = true
        } else {
            isAnimating = false
        }

        print("Device \(device.blePeripheralName) updated status: \(currentStatus)")
    }

    private var statusColor: Color {
        // 디버깅을 위해 현재 상태 출력
        print("Device \(device.blePeripheralName) status: \(currentStatus)")

        switch currentStatus {
        case statusConnected:
            print("Status: Connected -> Green")
            return .green
        case statusRanging:
            print("Status: Ranging -> Blue")
            return .blue
        default:
            print("Status: Default -> Gray")
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

struct MapStyleControl: View {
    @Binding var selectedStyle: MapStyle
    
    @State private var selectedType: MapStyleType = .standard
    @State private var showingStylePicker = false
    
    var body: some View {
        VStack(spacing: 1) {
            Button(action: {
                showingStylePicker = true
            }) {
                let baseImage = Image(systemName: selectedType.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                
                if #available(iOS 26.0, *) {
                    baseImage.glassEffect()
                } else {
                    baseImage.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                }
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
