import SwiftUI
import MapKit
import CoreLocation
import simd

struct FindMyCarMapView: View {
    @StateObject private var bluetoothManager = BluetoothManager()
    @StateObject private var nearbyInteractionManager: NearbyInteractionManager
    @StateObject private var locationManager = LocationManager()
    
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var showingDeviceList = false
    @State private var isScanning = false
    @State private var scanTimer: Timer?
    @State private var mapStyle: MapStyle = .standard(elevation: .realistic)
    @State private var hasInitializedCamera = false
    @State private var routeToVehicle: MKRoute?
    @State private var showingRoute = false
    
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

                    if let route = routeToVehicle, showingRoute {
                        MapPolyline(route)
                    }
                }
                .mapStyle(mapStyle)
                .mapControls {
                    MapCompass()
                    MapScaleView()
                    MapUserLocationButton()
                    MapPitchToggle()
                }
                .foregroundStyle(Color.secondary)
                .onAppear {
                    locationManager.requestLocationPermission()
                    if !hasInitializedCamera, let userLocation = locationManager.userLocation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: userLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))
                        hasInitializedCamera = true
                    }

                    // 경로 표시 알림 리스너 등록
                    NotificationCenter.default.addObserver(
                        forName: NSNotification.Name("ShowRouteToVehicle"),
                        object: nil,
                        queue: .main
                    ) { notification in
                        if let device = notification.object as? QorvoDevice {
                            showRouteToVehicle(device)
                        }
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
                    showingRoute: $showingRoute,
                    startScanning: startScanning,
                    stopScanning: stopScanning,
                    onVehicleSelected: { device in
                        centerMapOnVehicle(device)
                    }
                )
                .presentationDetents([
                    .height(300),
                    .height(500),
                    .large
                ])
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
        bluetoothManager.discoveredDevices.removeAll { device in
            !DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
        }
        bluetoothManager.startScanning()

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
    
    private func centerMapOnVehicle(_ device: QorvoDevice) {
        guard let savedLocation = LocationStorage.shared.getLastLocation(for: device.bleUniqueID) else {
            return
        }

        withAnimation(.easeInOut(duration: 1.0)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: savedLocation,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    private func showRouteToVehicle(_ device: QorvoDevice) {
        // 이미 경로가 표시되어 있으면 숨기기
        if showingRoute {
            hideRoute()
            return
        }

        guard let vehicleLocation = LocationStorage.shared.getLastLocation(for: device.bleUniqueID),
              let userLocation = locationManager.userLocation else {
            return
        }

        let sourcePlacemark = MKPlacemark(coordinate: userLocation)
        let destinationPlacemark = MKPlacemark(coordinate: vehicleLocation)

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: sourcePlacemark)
        request.destination = MKMapItem(placemark: destinationPlacemark)
        request.transportType = .walking

        let directions = MKDirections(request: request)

        Task {
            do {
                let response = try await directions.calculate()

                await MainActor.run {
                    if let route = response.routes.first {
                        routeToVehicle = route
                        showingRoute = true

                        // 경로를 포함하는 영역으로 지도 확대
                        let rect = route.polyline.boundingMapRect
                        let region = MKCoordinateRegion(rect)

                        // 여백을 위해 span을 약간 늘림
                        let expandedRegion = MKCoordinateRegion(
                            center: region.center,
                            span: MKCoordinateSpan(
                                latitudeDelta: region.span.latitudeDelta * 1.3,
                                longitudeDelta: region.span.longitudeDelta * 1.3
                            )
                        )

                        withAnimation(.easeInOut(duration: 1.0)) {
                            cameraPosition = .region(expandedRegion)
                        }
                    }
                }
            } catch {
                print("경로 계산 실패: \(error.localizedDescription)")
            }
        }
    }

    private func hideRoute() {
        withAnimation(.easeInOut(duration: 0.5)) {
            showingRoute = false
            routeToVehicle = nil
        }
    }
}

struct DeviceListSheetView: View {
    @ObservedObject var bluetoothManager: BluetoothManager
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    @Binding var isScanning: Bool
    @Binding var showingRoute: Bool
    let startScanning: () -> Void
    let stopScanning: () -> Void
    let onVehicleSelected: (QorvoDevice) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var showButtons: Bool = false

    var body: some View {
        NavigationView {
            deviceListView
            .navigationTitle("나의 차량")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    navigationBarTrailingButton
                }
            }
        }
        .onReceive(bluetoothManager.$connectionStatus) { status in
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
        .disabled(false)
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

                Text("차량 검색 중...")
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

                    Text("차량 연결 및 추적")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()

                connectionStatusIndicator
            }

            if let connectedDevice = bluetoothManager.discoveredDevices.first(where: { $0.blePeripheralStatus == statusConnected || $0.blePeripheralStatus == statusRanging }) {
                activeSessionCard(for: connectedDevice)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: bluetoothManager.discoveredDevices.first(where: { $0.blePeripheralStatus == statusConnected || $0.blePeripheralStatus == statusRanging }) != nil)
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

    @ViewBuilder
    private func activeSessionCard(for device: QorvoDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "location.circle.fill")
                        .foregroundColor(nearbyInteractionManager.isSessionActive ? .purple : .blue)
                    Text("차량 찾기")
                        .font(.headline)
                        .fontWeight(.medium)
                    Spacer()
                }
                
                Text(nearbyInteractionManager.isSessionActive ? "초광대역(UWB) 연결" : "블루투스 연결")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if nearbyInteractionManager.isSessionActive {
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
                    Text("위치 정보 수신 중")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("상태")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(bluetoothDistanceText(for: device))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    
                    Spacer()
                }
            }
            
            if showButtons {
                HStack(spacing: 8) {
                    if nearbyInteractionManager.isSessionActive {
                        Text("블루투스만 사용")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(24)
                            .onTapGesture {
                                bluetoothManager.stopUWB(deviceID: device.bleUniqueID)
                            }
                    } else {
                        Text("초광대역으로 연결")
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(.green.opacity(0.1))
                            .foregroundColor(.green)
                            .cornerRadius(24)
                            .onTapGesture {
                                bluetoothManager.initializeUWB(deviceID: device.bleUniqueID)
                            }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding()
        .background(Color(nearbyInteractionManager.isSessionActive ? .purple : .blue).opacity(0.1))
        .cornerRadius(32)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.3)) {
                showButtons.toggle()
            }
        }
    }

    private var noDevicesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text("차량이 발견되지 않았습니다.")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("Bluetooth를 켜고 스캔을 시작해주세요.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private var deviceListSection: some View {
        LazyVStack(spacing: 16) {
            let savedDevices = bluetoothManager.discoveredDevices.filter { device in
                DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
            }

            if !savedDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("저장된 차량")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(savedDevices, id: \.bleUniqueID) { device in
                        DeviceCard(
                            device: device,
                            bluetoothManager: bluetoothManager,
                            nearbyInteractionManager: nearbyInteractionManager,
                            isSaved: true,
                            showingRoute: $showingRoute,
                            onVehicleSelected: onVehicleSelected
                        )
                    }
                }
            }
            
            let newDevices = bluetoothManager.discoveredDevices.filter { device in
                !DeviceStorage.shared.isDeviceSaved(device.bleUniqueID)
            }

            if !newDevices.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("새로 발견된 차량")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(newDevices, id: \.bleUniqueID) { device in
                        DeviceCard(
                            device: device,
                            bluetoothManager: bluetoothManager,
                            nearbyInteractionManager: nearbyInteractionManager,
                            isSaved: false,
                            showingRoute: $showingRoute,
                            onVehicleSelected: onVehicleSelected
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
    @Binding var showingRoute: Bool
    let onVehicleSelected: (QorvoDevice) -> Void
    @State private var currentAddress: String = ""
    @State private var showButtons: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "car.fill")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(statusColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.blePeripheralName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let locationInfo = LocationStorage.shared.getLocationWithTimestamp(for: device.bleUniqueID) {
                        let addressText = currentAddress.isEmpty ? "위치 정보 없음" : currentAddress
                        let timeText = formatTimestamp(locationInfo.timestamp)
                        
                        Text("\(addressText)・\(timeText)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // UWB 활성화 시 정확한 거리와 방향 표시
                    if let location = device.uwbLocation, !location.noUpdate, location.distance > 0 {
                        Text(formatDistance(Double(location.distance)))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        DirectionIndicator(direction: location.direction)
                    }
                    // 블루투스 연결 시 RSSI 기반 상태 표시
                    else if device.blePeripheralStatus == statusConnected {
                        Text(bluetoothDistanceText(for: device))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.blue)
                    }
                    // 저장된 위치가 있을 때 실제 거리 표시 (연결되지 않은 경우)
                    else if let savedLocation = LocationStorage.shared.getLastLocation(for: device.bleUniqueID),
                            let userLocation = CLLocationManager().location?.coordinate {
                        let savedCLLocation = CLLocation(latitude: savedLocation.latitude, longitude: savedLocation.longitude)
                        let currentLocation = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude)
                        let distance = savedCLLocation.distance(from: currentLocation)
                        
                        Text(formatDistance(distance))
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // 저장된 차량이고 위치 정보가 있으면 지도로 이동
                if isSaved && LocationStorage.shared.getLastLocation(for: device.bleUniqueID) != nil {
                    onVehicleSelected(device)
                }
                
                // 모든 차량에 대해 버튼 토글
                withAnimation(.easeInOut(duration: 0.3)) {
                    showButtons.toggle()
                }
            }
            .onAppear {
                loadAddressForDevice()
            }

            if showButtons {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        deviceActionButton
                            .frame(maxWidth: .infinity, minHeight: 36)

                        if isSaved {
                            Text(showingRoute ? "경로 표시 해제" : "경로 표시")
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(.purple.opacity(0.1))
                                .foregroundColor(.purple)
                                .cornerRadius(24)
                                .onTapGesture {
                                    // MapView에서 경로 표시 기능 호출
                                    NotificationCenter.default.post(
                                        name: NSNotification.Name("ShowRouteToVehicle"),
                                        object: device
                                    )
                                }
                        }
                    }

                    if isSaved {
                        HStack(spacing: 8) {
                            Text("차량 삭제")
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(24)
                                .onTapGesture {
                                    bluetoothManager.removeSavedDevice(device.bleUniqueID)
                                }
                        }
                    } else if !isSaved && (device.blePeripheralStatus == statusConnected || device.blePeripheralStatus == statusRanging) {
                        HStack(spacing: 8) {
                            Text("차량 등록")
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(24)
                                .onTapGesture {
                                    bluetoothManager.saveCurrentDevice(device)
                                }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
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
                Text("연결")
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.primary.opacity(0.1))
                    .foregroundColor(.primary)
                    .cornerRadius(24)
                    .onTapGesture {
                        bluetoothManager.connect(to: device)
                    }
            }

        case statusConnected, statusRanging:
            Text("연결 해제")
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.orange.opacity(0.1))
                .foregroundColor(.orange)
                .cornerRadius(24)
                .onTapGesture {
                    if nearbyInteractionManager.isSessionActive {
                        nearbyInteractionManager.stopSession()
                    }
                    bluetoothManager.disconnect()
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
        let timeInterval = Date().timeIntervalSince(date)
        
        if timeInterval < 60 && (device.blePeripheralStatus == statusConnected || device.blePeripheralStatus == statusRanging) {
            return "지금"
        }
        
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
        
        // 백그라운드에서 지오코딩 실행
        DispatchQueue.global(qos: .utility).async {
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error = error {
                    print("Reverse geocoding failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        completion("")
                    }
                    return
                }
                
                guard let placemark = placemarks?.first else {
                    DispatchQueue.main.async {
                        completion("")
                    }
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
                DispatchQueue.main.async {
                    completion(address.isEmpty ? "위치 정보 없음" : address)
                }
            }
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
    @State private var currentStatus: String = ""

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
        .onAppear {
            updateStatus()
        }
        .onReceive(bluetoothManager.$discoveredDevices) { _ in
            updateStatus()
        }
    }

    private func updateStatus() {
        if let currentDevice = bluetoothManager.discoveredDevices.first(where: { $0.bleUniqueID == device.bleUniqueID }) {
            currentStatus = currentDevice.blePeripheralStatus ?? ""
        } else {
            currentStatus = device.blePeripheralStatus ?? ""
        }

        print("Device \(device.blePeripheralName) updated status: \(currentStatus)")
    }

    private var statusColor: Color {
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
            .presentationDetents([
                .height(300),
                .height(380),
            ])
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
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(MapStyleType.allCases, id: \.self) { styleType in
                        Button(action: {
                            selectedType = styleType
                            selectedStyle = styleType.mapStyle
                        }) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(.primary.opacity(0.15))
                                        .frame(width: 48, height: 48)
                                    
                                    Image(systemName: styleType.icon)
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.primary)
                                }
                                
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
                            .padding()
                            .background(selectedType == styleType ? Color.blue.opacity(0.1) : Color.clear)
                            .cornerRadius(32)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding()
            }
            .navigationTitle("지도 스타일")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
            }
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

// MARK: - Helper Functions
func formatDistance(_ distance: Double) -> String {
    if distance >= 1000 {
        let kilometers = distance / 1000
        return String(format: "%.1fkm", kilometers)
    } else {
        return String(format: "%.0fm", distance)
    }
}

func bluetoothDistanceText(for device: QorvoDevice) -> String {
    guard let rssi = device.bleRSSI else {
        return "근처에 없음"
    }

    let rssiValue = rssi.intValue
    if rssiValue >= -50 {
        return "매우 가까움"
    } else if rssiValue >= -70 {
        return "가까움"
    } else if rssiValue >= -85 {
        return "근처에 있음"
    } else {
        return "멀리 있음"
    }
}

#Preview {
    FindMyCarMapView()
}
