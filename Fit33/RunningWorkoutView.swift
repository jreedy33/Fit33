import SwiftUI
import MapKit
import CoreLocation
import Combine

// MARK: - Running Workout View
/// Main view for tracking outdoor runs with live stats and map
struct RunningWorkoutView: View {
    @StateObject private var runningManager = RunningManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showStopConfirmation = false
    @State private var showCompletionSheet = false
    @State private var completedRun: RunWorkoutResult?
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            // Background
            backgroundGradient
            
            if !runningManager.isLocationAuthorized {
                locationPermissionView
            } else if !runningManager.isRunning {
                preRunView
            } else {
                activeRunView
            }
        }
        .navigationBarBackButtonHidden(runningManager.isRunning)
        .toolbar {
            if !runningManager.isRunning {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
            }
        }
        .sheet(isPresented: $showCompletionSheet) {
            if let run = completedRun {
                RunCompletionView(result: run) {
                    showCompletionSheet = false
                    dismiss()
                }
            }
        }
        .confirmationDialog("End Run?", isPresented: $showStopConfirmation, titleVisibility: .visible) {
            Button("End Run", role: .destructive) {
                endRun()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to end this run?")
        }
        .onReceive(runningManager.$currentLocation) { location in
            if let location = location {
                withAnimation {
                    mapRegion.center = location
                }
            }
        }
    }
    
    // MARK: - Background
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.05, green: 0.12, blue: 0.08),
                Color(red: 0.03, green: 0.08, blue: 0.05),
                Color.black
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Location Permission View
    private var locationPermissionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "location.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Location Access Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("To track your runs, we need access to your location. Your route is stored locally and you control your data.")
                .font(.body)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button(action: {
                runningManager.requestLocationPermission()
            }) {
                Text("Enable Location")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
    }
    
    // MARK: - Pre-Run View
    private var preRunView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.green.opacity(0.3), .mint.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 120, height: 120)
                
                Image(systemName: "figure.run")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 8) {
                Text("Outdoor Run")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("GPS tracking • Pace • Route Map")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            // Start Button
            Button(action: {
                HapticManager.impact(.heavy)
                runningManager.startRun()
            }) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 100, height: 100)
                        .shadow(color: .green.opacity(0.5), radius: 20, y: 10)
                    
                    Text("START")
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(.black)
                }
            }
            .padding(.bottom, 60)
        }
    }
    
    // MARK: - Active Run View
    private var activeRunView: some View {
        ZStack {
            // Full screen map
            RunningMapView(
                coordinates: runningManager.routeCoordinates,
                region: $mapRegion
            )
            .ignoresSafeArea()
            
            // Overlay gradient for readability
            VStack {
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
                
                Spacer()
                
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 300)
            }
            .ignoresSafeArea()
            
            // Stats and controls overlay
            VStack(spacing: 0) {
                // Top stats bar
                HStack(spacing: 0) {
                    overlayStatCard(
                        value: runningManager.formattedDistance,
                        label: "MI",
                        color: .green
                    )
                    
                    Spacer()
                    
                    overlayStatCard(
                        value: runningManager.formattedElapsedTime,
                        label: "TIME",
                        color: .cyan
                    )
                    
                    Spacer()
                    
                    overlayStatCard(
                        value: runningManager.formattedPace,
                        label: "/MI",
                        color: .orange
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                
                Spacer()
                
                // Bottom controls section
                VStack(spacing: 16) {
                    // Secondary stats row
                    HStack(spacing: 20) {
                        miniOverlayStatCard(
                            icon: "speedometer",
                            value: runningManager.formattedCurrentPace,
                            label: "Current"
                        )
                        
                        miniOverlayStatCard(
                            icon: "flame.fill",
                            value: String(format: "%.0f", runningManager.calories),
                            label: "Cal"
                        )
                        
                        miniOverlayStatCard(
                            icon: "point.topleft.down.curvedto.point.bottomright.up",
                            value: "\(runningManager.splits.count)",
                            label: "Splits"
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Control buttons
                    HStack(spacing: 32) {
                        // Pause/Resume
                        Button(action: {
                            HapticManager.impact(.medium)
                            if runningManager.isPaused {
                                runningManager.resumeRun()
                            } else {
                                runningManager.pauseRun()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 70, height: 70)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                                    )
                                
                                Image(systemName: runningManager.isPaused ? "play.fill" : "pause.fill")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Stop
                        Button(action: {
                            HapticManager.impact(.heavy)
                            showStopConfirmation = true
                        }) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(colors: [.red, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                    .frame(width: 80, height: 80)
                                    .shadow(color: .red.opacity(0.5), radius: 20, y: 5)
                                
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.bottom, 50)
                }
            }
        }
    }
    
    // MARK: - Overlay Stat Cards (for full-screen map)
    private func overlayStatCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }
    
    private func miniOverlayStatCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Stat Cards (for pre-run view)
    private func statCard(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func miniStatCard(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
                
                Text(value)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Actions
    private func endRun() {
        if let result = runningManager.stopRun() {
            completedRun = result
            showCompletionSheet = true
        }
    }
}

// MARK: - Running Map View
struct RunningMapView: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    @Binding var region: MKCoordinateRegion
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        mapView.mapType = .standard
        
        // Dark map style
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // Update route polyline
        mapView.removeOverlays(mapView.overlays)
        
        if coordinates.count > 1 {
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            mapView.addOverlay(polyline)
        }
        
        // Center on user if we have coordinates
        if let last = coordinates.last {
            let region = MKCoordinateRegion(
                center: last,
                span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
            )
            mapView.setRegion(region, animated: true)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemGreen
                renderer.lineWidth = 5
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - Run Completion View
struct RunCompletionView: View {
    let result: RunWorkoutResult
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSplits = false
    @State private var isSavingToHealth = false
    @State private var savedToHealth = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.15, blue: 0.1), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(
                                    LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                            
                            Text("Run Complete! 🎉")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                        .padding(.top, 20)
                        
                        // Main Stats
                        VStack(spacing: 16) {
                            mainStat(value: String(format: "%.2f km", result.distanceKm), label: "Distance")
                            
                            HStack(spacing: 16) {
                                statBox(value: result.formattedDuration, label: "Duration", icon: "clock.fill", color: .cyan)
                                statBox(value: formatPace(result.averagePace), label: "Avg Pace", icon: "speedometer", color: .orange)
                            }
                            
                            HStack(spacing: 16) {
                                statBox(value: String(format: "%.0f", result.calories), label: "Calories", icon: "flame.fill", color: .red)
                                statBox(value: "\(result.splits.count)", label: "Splits", icon: "point.topleft.down.curvedto.point.bottomright.up", color: .purple)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Map Preview
                        if result.routeCoordinates.count > 1 {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Route")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                
                                RoutePreviewMap(coordinates: result.routeCoordinates)
                                    .frame(height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .padding(.horizontal, 20)
                            }
                        }
                        
                        // Splits
                        if !result.splits.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Button(action: { showSplits.toggle() }) {
                                    HStack {
                                        Text("Splits")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        Spacer()
                                        
                                        Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.white.opacity(0.6))
                                    }
                                }
                                .padding(.horizontal, 20)
                                
                                if showSplits {
                                    ForEach(result.splits) { split in
                                        HStack {
                                            Text("Km \(split.kilometer)")
                                                .foregroundColor(.white.opacity(0.7))
                                            
                                            Spacer()
                                            
                                            Text(split.formattedPace + " /km")
                                                .foregroundColor(.green)
                                                .fontWeight(.semibold)
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                        }
                        
                        // Save to Apple Health
                        if HealthKitManager.shared.saveWorkoutsToHealth {
                            Button(action: saveToHealth) {
                                HStack {
                                    if isSavingToHealth {
                                        ProgressView()
                                            .tint(.white)
                                    } else if savedToHealth {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("Saved to Apple Health")
                                    } else {
                                        Image(systemName: "heart.fill")
                                        Text("Save to Apple Health")
                                    }
                                }
                                .font(.headline)
                                .foregroundColor(savedToHealth ? .green : .white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    savedToHealth 
                                        ? Color.white.opacity(0.1) 
                                        : Color.red.opacity(0.8)
                                )
                                .cornerRadius(16)
                            }
                            .disabled(isSavingToHealth || savedToHealth)
                            .padding(.horizontal, 20)
                        }
                        
                        // Done Button
                        Button(action: onDismiss) {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func mainStat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(20)
    }
    
    private func statBox(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }
    
    private func formatPace(_ pace: Double) -> String {
        guard pace > 0 && pace < 3600 else { return "--:--" }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func saveToHealth() {
        isSavingToHealth = true
        
        Task {
            do {
                try await HealthKitManager.shared.saveRunningWorkoutToHealth(
                    startDate: result.startTime,
                    endDate: result.endTime,
                    durationSeconds: result.duration,
                    distanceMeters: result.distance,
                    caloriesBurned: result.calories
                )
                
                await MainActor.run {
                    savedToHealth = true
                    isSavingToHealth = false
                    HapticManager.notification(.success)
                }
            } catch {
                await MainActor.run {
                    isSavingToHealth = false
                    HapticManager.notification(.error)
                }
                print("❌ Failed to save running workout to Health: \(error)")
            }
        }
    }
}

// MARK: - Route Preview Map
struct RoutePreviewMap: UIViewRepresentable {
    let coordinates: [CLLocationCoordinate2D]
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isUserInteractionEnabled = false
        
        if #available(iOS 16.0, *) {
            mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        }
        
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.removeOverlays(mapView.overlays)
        mapView.removeAnnotations(mapView.annotations)
        
        guard coordinates.count > 1 else { return }
        
        // Add route
        let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
        mapView.addOverlay(polyline)
        
        // Add start/end markers
        let startAnnotation = MKPointAnnotation()
        startAnnotation.coordinate = coordinates.first!
        startAnnotation.title = "Start"
        
        let endAnnotation = MKPointAnnotation()
        endAnnotation.coordinate = coordinates.last!
        endAnnotation.title = "Finish"
        
        mapView.addAnnotations([startAnnotation, endAnnotation])
        
        // Fit to show entire route
        mapView.setVisibleMapRect(
            polyline.boundingMapRect,
            edgePadding: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
            animated: false
        )
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = UIColor.systemGreen
                renderer.lineWidth = 4
                renderer.lineCap = .round
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

#Preview {
    RunningWorkoutView()
}

