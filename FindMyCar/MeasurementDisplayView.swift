import SwiftUI
import simd

struct MeasurementDisplayView: View {
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Main Distance Display
            VStack(spacing: 12) {
                Text("Distance to Device")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if let distance = nearbyInteractionManager.distance {
                    VStack(spacing: 4) {
                        Text(getDistanceDescription())
                            .font(.system(size: 42, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text("(\(String(format: "%.3f", distance)) meters)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Measuring...")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(color: .gray.opacity(0.2), radius: 8, x: 0, y: 4)
            
            // Direction and Elevation Display
            HStack(spacing: 16) {
                // Direction Card
                MeasurementCard(
                    title: "Direction",
                    value: getDirectionDescription(),
                    icon: "location.north.circle.fill",
                    color: .blue
                )
                
                // Elevation Card
                MeasurementCard(
                    title: "Elevation",
                    value: getElevationDescription(),
                    icon: "arrow.up.arrow.down.circle.fill",
                    color: .green
                )
            }
            
            // Direction Compass
            if nearbyInteractionManager.direction != nil {
                DirectionCompassView(direction: nearbyInteractionManager.direction)
            }
            
            // Last Update Time
            if let lastUpdate = nearbyInteractionManager.lastUpdate {
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                    Text("Updated \(timeAgo(from: lastUpdate))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
    
    private func timeAgo(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
    
    private func getDistanceDescription() -> String {
        guard let distance = nearbyInteractionManager.distance else {
            return "No Distance"
        }

        if distance < 0.5 {
            return "\(Int(distance * 100)) cm"
        } else if distance < 100 {
            return String(format: "%.1f m", distance)
        } else if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return "\(Int(distance)) m"
        }
    }
    
    private func getDirectionDescription() -> String {
        guard let direction = nearbyInteractionManager.direction else {
            return "No Direction"
        }
        
        let x = direction.x
        let z = direction.z
        
        // Calculate angle from forward direction
        let angle = atan2(Double(x), Double(-z)) * 180 / Double.pi
        let normalizedAngle = angle < 0 ? angle + 360 : angle
        
        // Convert to cardinal directions
        if normalizedAngle >= 337.5 || normalizedAngle < 22.5 {
            return "North"
        } else if normalizedAngle >= 22.5 && normalizedAngle < 67.5 {
            return "North East"
        } else if normalizedAngle >= 67.5 && normalizedAngle < 112.5 {
            return "East"
        } else if normalizedAngle >= 112.5 && normalizedAngle < 157.5 {
            return "South East"
        } else if normalizedAngle >= 157.5 && normalizedAngle < 202.5 {
            return "South"
        } else if normalizedAngle >= 202.5 && normalizedAngle < 247.5 {
            return "South West"
        } else if normalizedAngle >= 247.5 && normalizedAngle < 292.5 {
            return "West"
        } else {
            return "North West"
        }
    }
    
    private func getElevationDescription() -> String {
        guard let elevation = nearbyInteractionManager.elevation else {
            return "Unknown"
        }
        
        if elevation > 0.1 {
            return "Above"
        } else if elevation < -0.1 {
            return "Below"
        } else {
            return "Same Level"
        }
    }
}

struct MeasurementCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct DirectionCompassView: View {
    let direction: simd_float3?
    @State private var previousAngle: Double = 0
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Direction Compass")
                .font(.headline)
                .foregroundColor(.secondary)
            
            ZStack {
                // Compass Background
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                    .frame(width: 150, height: 150)
                
                // Direction Lines
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1, height: 20)
                        .offset(y: -65)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
                
                // Direction Labels
                Text("N")
                    .font(.caption.weight(.bold))
                    .offset(y: -80)
                
                Text("E")
                    .font(.caption.weight(.bold))
                    .offset(x: 80)
                
                Text("S")
                    .font(.caption.weight(.bold))
                    .offset(y: 80)
                
                Text("W")
                    .font(.caption.weight(.bold))
                    .offset(x: -80)
                
                // Direction Indicator
                if let direction = direction {
                    DirectionArrow()
                        .fill(Color.red)
                        .frame(width: 8, height: 40)
                        .offset(y: -35)
                        .rotationEffect(.degrees(smoothAngleFromDirection(direction)))
                        .animation(.easeInOut(duration: 0.3), value: smoothAngleFromDirection(direction))
                }
                
                // Center Dot
                Circle()
                    .fill(Color.primary)
                    .frame(width: 8, height: 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }
    
    private func smoothAngleFromDirection(_ direction: simd_float3) -> Double {
        let x = Double(direction.x)
        let z = Double(direction.z)
        
        // Calculate angle from forward direction (negative z-axis)
        let rawAngle = atan2(x, -z) * 180 / Double.pi
        let normalizedAngle = rawAngle < 0 ? rawAngle + 360 : rawAngle
        
        // Handle 0/360 degree boundary to prevent full rotation
        let angleDifference = normalizedAngle - previousAngle
        
        var smoothedAngle: Double
        if abs(angleDifference) > 180 {
            // We're crossing the 0/360 boundary
            if angleDifference > 0 {
                // Going from ~360 to ~0, subtract 360 from new angle
                smoothedAngle = normalizedAngle - 360
            } else {
                // Going from ~0 to ~360, add 360 to new angle  
                smoothedAngle = normalizedAngle + 360
            }
        } else {
            smoothedAngle = normalizedAngle
        }
        
        DispatchQueue.main.async {
            self.previousAngle = smoothedAngle
        }
        
        return smoothedAngle
    }
}

struct DirectionArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        
        // Arrow shape
        path.move(to: CGPoint(x: width/2, y: 0))
        path.addLine(to: CGPoint(x: 0, y: height * 0.7))
        path.addLine(to: CGPoint(x: width/2, y: height * 0.5))
        path.addLine(to: CGPoint(x: width, y: height * 0.7))
        path.closeSubpath()
        
        return path
    }
}

struct DetailedMeasurementsView: View {
    @ObservedObject var nearbyInteractionManager: NearbyInteractionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detailed Measurements")
                .font(.headline)
            
            if let direction = nearbyInteractionManager.direction {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Raw Direction Vector:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        MeasurementRow(label: "X", value: String(format: "%.3f", direction.x))
                        MeasurementRow(label: "Y", value: String(format: "%.3f", direction.y))
                        MeasurementRow(label: "Z", value: String(format: "%.3f", direction.z))
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            if let distance = nearbyInteractionManager.distance {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Distance Measurements:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        MeasurementRow(label: "Meters", value: String(format: "%.3f m", distance))
                        MeasurementRow(label: "Centimeters", value: String(format: "%.1f cm", distance * 100))
                        MeasurementRow(label: "Feet", value: String(format: "%.2f ft", distance * 3.28084))
                    }
                    .font(.system(.body, design: .monospaced))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
}

struct MeasurementRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    VStack {
        MeasurementDisplayView(
            nearbyInteractionManager: {
                let bluetoothManager = BluetoothManager()
                let manager = NearbyInteractionManager(bluetoothManager: bluetoothManager)
                // Simulate some test data
                manager.distance = 2.5
                manager.direction = simd_float3(0.5, 0.1, -0.8)
                manager.elevation = 0.3
                manager.lastUpdate = Date()
                return manager
            }()
        )
        
        Spacer()
        
        DetailedMeasurementsView(
            nearbyInteractionManager: {
                let bluetoothManager = BluetoothManager()
                let manager = NearbyInteractionManager(bluetoothManager: bluetoothManager)
                manager.distance = 2.5
                manager.direction = simd_float3(0.5, 0.1, -0.8)
                return manager
            }()
        )
    }
    .padding()
}