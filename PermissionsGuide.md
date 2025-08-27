# FindMyCar 권한 설정 가이드

이 앱이 정상적으로 작동하려면 Xcode 프로젝트 설정에서 다음 권한들을 추가해야 합니다.

## 필수 권한 설정

### 1. Info.plist 권한 추가
Xcode에서 FindMyCar 타겟을 선택하고 Info 탭에서 다음 키-값 쌍들을 추가하세요:

#### Bluetooth 권한
- **Key**: `NSBluetoothAlwaysUsageDescription`
- **Type**: String  
- **Value**: `FindMyCar needs Bluetooth access to connect to your DWM3001CDK device for precise location tracking.`

- **Key**: `NSBluetoothPeripheralUsageDescription` 
- **Type**: String
- **Value**: `FindMyCar uses Bluetooth to discover and connect to your DWM3001CDK tracking device.`

#### Nearby Interaction 권한  
- **Key**: `NSNearbyInteractionUsageDescription`
- **Type**: String
- **Value**: `FindMyCar uses Nearby Interaction to provide precise distance, direction, and elevation measurements to your tracking device.`

- **Key**: `NSNearbyInteractionAllowOnceUsageDescription`
- **Type**: String  
- **Value**: `Allow FindMyCar to use Nearby Interaction for precise location tracking of your device.`

### 2. Required Device Capabilities
Info.plist에 다음을 추가:

- **Key**: `UIRequiredDeviceCapabilities`
- **Type**: Array
- **Item 0**: `bluetooth-le` (String)

### 3. Background Modes (선택사항)
백그라운드에서 동작이 필요한 경우:

- **Key**: `UIBackgroundModes`  
- **Type**: Array
- **Item 0**: `bluetooth-central` (String)
- **Item 1**: `nearby-interaction` (String)

### 4. Framework 추가
프로젝트의 "Frameworks, Libraries, and Embedded Content"에 다음을 추가:
- `CoreBluetooth.framework`
- `NearbyInteraction.framework`

## DWM3001CDK 연결 설정

### Bluetooth 서비스 UUID
앱에서 사용하는 주요 UUID들:
- **Nearby Interaction Service**: `48FE`
- **Accessory Configuration Characteristic**: `48FE`

### 연결 과정
1. **Bluetooth 스캔**: DWM3001CDK 디바이스 검색
2. **디바이스 연결**: 발견된 디바이스에 연결
3. **서비스 발견**: Nearby Interaction 서비스 확인
4. **특성 읽기**: Accessory Configuration Data 획득
5. **UWB 세션 시작**: Nearby Interaction 세션 초기화
6. **측정 수행**: 거리, 방향, 높이 측정

## 사용 방법
1. 앱을 실행하고 "Scan Devices" 버튼을 탭
2. 발견된 DWM3001CDK 디바이스에 "Connect" 버튼을 탭  
3. 연결이 완료되면 "Start UWB" 버튼을 탭
4. 실시간으로 거리, 방향, 높이 정보를 확인

## 문제 해결
- **Bluetooth 권한 오류**: iOS 설정에서 앱의 Bluetooth 권한을 확인
- **Nearby Interaction 오류**: 디바이스가 U1/U2 칩을 지원하는지 확인
- **연결 실패**: DWM3001CDK가 올바른 펌웨어를 실행하고 있는지 확인