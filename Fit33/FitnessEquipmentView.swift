import SwiftUI

// MARK: - Fitness Equipment Connection View
struct FitnessEquipmentView: View {
    @StateObject private var bluetoothManager = BluetoothFitnessManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showingLiveWorkout = false
    
    private let accentColor = Color(red: 0.2, green: 0.8, blue: 1.0)
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                backgroundGradient
                
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    // Content
                    if bluetoothManager.connectionState == .connected {
                        connectedDeviceView
                    } else {
                        scanningContentView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelLarge)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
            .fullScreenCover(isPresented: $showingLiveWorkout) {
                if let device = bluetoothManager.connectedDevice {
                    EquipmentWorkoutView(device: device)
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        AnimatedOrbBackground.workout(colorScheme: colorScheme)
            .ignoresSafeArea(.all, edges: .all)
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 32))
                    .foregroundColor(accentColor)
            }
            
            VStack(spacing: 4) {
                Text("Connect Equipment")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Find nearby fitness machines")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
    
    // MARK: - Scanning Content
    private var scanningContentView: some View {
        VStack(spacing: 20) {
            // Status & Scan Button
            connectionStatusView
            
            // Discovered Devices List
            if !bluetoothManager.discoveredDevices.isEmpty {
                discoveredDevicesSection
            } else if bluetoothManager.isScanning {
                scanningPlaceholder
            } else {
                emptyStatePlaceholder
            }
            
            Spacer()
            
            // Tips
            tipsSection
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Connection Status View
    private var connectionStatusView: some View {
        VStack(spacing: 16) {
            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(bluetoothManager.connectionState.description)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
            }
            
            // Scan Button
            Button(action: {
                HapticManager.impact(.medium)
                if bluetoothManager.isScanning {
                    bluetoothManager.stopScanning()
                } else {
                    bluetoothManager.startScanning()
                }
            }) {
                HStack {
                    if bluetoothManager.isScanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    Text(bluetoothManager.isScanning ? "Stop Scanning" : "Scan for Equipment")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accentColor)
                )
            }
            .disabled(!bluetoothManager.isBluetoothAvailable)
            .opacity(bluetoothManager.isBluetoothAvailable ? 1.0 : 0.5)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    private var statusColor: Color {
        switch bluetoothManager.connectionState {
        case .connected: return .green
        case .connecting, .scanning: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
    
    // MARK: - Discovered Devices Section
    private var discoveredDevicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEARBY EQUIPMENT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            ForEach(bluetoothManager.discoveredDevices) { device in
                DiscoveredDeviceCard(device: device) {
                    bluetoothManager.connect(to: device)
                }
            }
        }
    }
    
    // MARK: - Scanning Placeholder
    private var scanningPlaceholder: some View {
        VStack(spacing: 16) {
            // Animated scanning indicator
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(accentColor.opacity(0.3), lineWidth: 2)
                        .frame(width: CGFloat(60 + i * 40), height: CGFloat(60 + i * 40))
                        .scaleEffect(bluetoothManager.isScanning ? 1.2 : 1.0)
                        .opacity(bluetoothManager.isScanning ? 0.0 : 1.0)
                        .animation(
                            Animation.easeOut(duration: 1.5)
                                .repeatForever(autoreverses: false)
                                .delay(Double(i) * 0.3),
                            value: bluetoothManager.isScanning
                        )
                }
                
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(accentColor)
            }
            .frame(height: 140)
            
            Text("Searching for nearby equipment...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Empty State
    private var emptyStatePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
            
            Text("No equipment found")
                .font(.headline)
                .foregroundColor(.white.opacity(0.6))
            
            Text("Make sure your equipment is powered on\nand Bluetooth is enabled")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Connected Device View
    private var connectedDeviceView: some View {
        VStack(spacing: 24) {
            if let device = bluetoothManager.connectedDevice {
                // Connected device card
                VStack(spacing: 20) {
                    HStack(spacing: 16) {
                        // Device icon
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: device.type.icon)
                                .font(.system(size: 26))
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            HStack {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 8, height: 8)
                                Text("Connected")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            bluetoothManager.disconnect()
                        }) {
                            Text("Disconnect")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                        }
                    }
                    
                    // Live data preview
                    liveDataPreview
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                )
                
                // Start Workout Button
                Button(action: {
                    HapticManager.impact(.heavy)
                    showingLiveWorkout = true
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Workout")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green)
                    )
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Live Data Preview
    private var liveDataPreview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            LiveDataCell(
                icon: "speedometer",
                value: String(format: "%.1f", bluetoothManager.liveData.speed),
                unit: "km/h",
                color: .cyan
            )
            
            LiveDataCell(
                icon: "heart.fill",
                value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--",
                unit: "BPM",
                color: .red
            )
            
            LiveDataCell(
                icon: "flame.fill",
                value: "\(bluetoothManager.liveData.calories)",
                unit: "cal",
                color: .orange
            )
        }
    }
    
    // MARK: - Tips Section
    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("COMPATIBLE EQUIPMENT")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.5))
                .tracking(1)
            
            HStack(spacing: 16) {
                EquipmentTypeIcon(type: .treadmill)
                EquipmentTypeIcon(type: .indoorBike)
                EquipmentTypeIcon(type: .rower)
                EquipmentTypeIcon(type: .elliptical)
            }
            
            Text("Works with FTMS-compatible machines from Concept2, Life Fitness, Technogym, NordicTrack, and more.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .padding(.bottom, 20)
    }
}

// MARK: - Discovered Device Card
struct DiscoveredDeviceCard: View {
    let device: DiscoveredFitnessDevice
    let onConnect: () -> Void
    
    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 14) {
                    // Device icon
                    ZStack {
                        Circle()
                            .fill((Color(hex: device.type.color.primary) ?? .gray).opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: device.type.icon)
                            .font(.ds_heading2)
                            .foregroundColor(Color(hex: device.type.color.primary) ?? .gray)
                    }
                
                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text(device.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        // Signal strength
                        SignalStrengthIndicator(rssi: device.rssi)
                    }
                }
                
                Spacer()
                
                // Connect button
                Text("Connect")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .stroke(Color.cyan.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Signal Strength Indicator
struct SignalStrengthIndicator: View {
    let rssi: Int
    
    private var bars: Int {
        if rssi >= -50 { return 4 }
        else if rssi >= -60 { return 3 }
        else if rssi >= -70 { return 2 }
        else { return 1 }
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i < bars ? Color.green : Color.white.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 2))
            }
        }
    }
}

// MARK: - Live Data Cell
struct LiveDataCell: View {
    let icon: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_bodyRegular)
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(unit)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Equipment Type Icon
struct EquipmentTypeIcon: View {
    let type: FitnessEquipmentType
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: type.icon)
                .font(.ds_heading3)
                .foregroundColor(Color(hex: type.color.primary) ?? .gray)
            
            Text(type.rawValue)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}


// MARK: - Equipment Workout View (Live Session)
struct EquipmentWorkoutView: View {
    let device: DiscoveredFitnessDevice
    @StateObject private var bluetoothManager = BluetoothFitnessManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var isWorkoutActive = false
    @State private var showEndConfirmation = false
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    (Color(hex: device.type.color.primary) ?? .cyan).opacity(0.15),
                    Color.black
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Button(action: {
                        if isWorkoutActive {
                            showEndConfirmation = true
                        } else {
                            dismiss()
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.ds_labelLarge)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(device.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                    
                    Spacer()
                    
                    // Placeholder for symmetry
                    Color.clear.frame(width: 36, height: 36)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Spacer()
                
                // Main Stats
                VStack(spacing: 30) {
                    // Timer
                    Text(formatTime(elapsedTime))
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    // Primary Metrics
                    HStack(spacing: 40) {
                        PrimaryMetric(
                            value: String(format: "%.2f", bluetoothManager.liveData.distance / 1000),
                            unit: "km",
                            label: "Distance"
                        )
                        
                        PrimaryMetric(
                            value: String(format: "%.1f", bluetoothManager.liveData.speed),
                            unit: "km/h",
                            label: "Speed"
                        )
                        
                        PrimaryMetric(
                            value: "\(bluetoothManager.liveData.calories)",
                            unit: "cal",
                            label: "Calories"
                        )
                    }
                    
                    // Secondary Metrics based on equipment type
                    secondaryMetricsView
                }
                
                Spacer()
                
                // Control Button
                Button(action: {
                    HapticManager.impact(.heavy)
                    if isWorkoutActive {
                        showEndConfirmation = true
                    } else {
                        startWorkout()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(isWorkoutActive ? Color.red : (Color(hex: device.type.color.primary) ?? .cyan))
                            .frame(width: 100, height: 100)
                            .shadow(color: (isWorkoutActive ? Color.red : (Color(hex: device.type.color.primary) ?? .cyan)).opacity(0.5), radius: 20, y: 10)
                        
                        Image(systemName: isWorkoutActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 60)
            }
        }
        .alert("End Workout?", isPresented: $showEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                endWorkout()
            }
        } message: {
            Text("Are you sure you want to end this workout?")
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    @ViewBuilder
    private var secondaryMetricsView: some View {
        HStack(spacing: 24) {
            switch device.type {
            case .treadmill:
                SecondaryMetric(icon: "arrow.up.right", value: String(format: "%.1f%%", bluetoothManager.liveData.incline), label: "Incline")
                SecondaryMetric(icon: "heart.fill", value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--", label: "Heart Rate", color: .red)
                
            case .indoorBike:
                SecondaryMetric(icon: "circle.dotted", value: "\(bluetoothManager.liveData.cadence)", label: "Cadence")
                SecondaryMetric(icon: "bolt.fill", value: "\(bluetoothManager.liveData.power)", label: "Power (W)", color: .yellow)
                SecondaryMetric(icon: "heart.fill", value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--", label: "Heart Rate", color: .red)
                
            case .rower:
                SecondaryMetric(icon: "arrow.left.arrow.right", value: "\(bluetoothManager.liveData.strokeRate)", label: "Stroke Rate")
                SecondaryMetric(icon: "bolt.fill", value: "\(bluetoothManager.liveData.power)", label: "Power (W)", color: .yellow)
                SecondaryMetric(icon: "heart.fill", value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--", label: "Heart Rate", color: .red)
                
            case .elliptical:
                SecondaryMetric(icon: "gauge", value: "\(bluetoothManager.liveData.resistance)", label: "Resistance")
                SecondaryMetric(icon: "heart.fill", value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--", label: "Heart Rate", color: .red)
                
            case .unknown:
                SecondaryMetric(icon: "heart.fill", value: bluetoothManager.liveData.heartRate > 0 ? "\(bluetoothManager.liveData.heartRate)" : "--", label: "Heart Rate", color: .red)
            }
        }
    }
    
    private func startWorkout() {
        isWorkoutActive = true
        elapsedTime = 0
        bluetoothManager.startWorkoutRecording()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }
    
    private func endWorkout() {
        isWorkoutActive = false
        timer?.invalidate()
        
        if let summary = bluetoothManager.stopWorkoutRecording() {
            // NOTE: Bluetooth equipment workout saving will be implemented
            // when the BLE integration goes live. Requires mapping BLE workout
            // data → CardioWorkoutData and calling SupabaseManager.saveCardioWorkout().
            print("Workout completed: \(summary)")
        }
        
        dismiss()
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Primary Metric
struct PrimaryMetric: View {
    let value: String
    let unit: String
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// MARK: - Secondary Metric
struct SecondaryMetric: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = .white
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_bodyRegular)
                .foregroundColor(color.opacity(0.7))
            
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(minWidth: 70)
    }
}

#Preview {
    FitnessEquipmentView()
}
