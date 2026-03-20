//
//  InBodySettingsView.swift
//  Fit33
//
//  UI for connecting and managing InBody body composition integration
//  Based on InBody OAuth API: https://inbody.com/en/data
//

import SwiftUI

// MARK: - InBody Navigation Route

enum InBodyRoute: Hashable {
    case scanHistory
}

// MARK: - InBody Settings View

struct InBodySettingsView: View {
    @StateObject private var inbody = InBodyService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDisconnectAlert = false
    @State private var showingAuthSheet = false
    
    // InBody brand color
    private let inbodyBlue = Color(red: 0/255, green: 122/255, blue: 204/255)
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with Profile/Stats screens)
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            List {
                // Connection Status Section
                Section {
                    if inbody.isConnected {
                        connectedView
                    } else {
                        disconnectedView
                    }
                } header: {
                    Label("Connection", systemImage: "link")
                }
            
            // Latest Scan Section (only show if connected)
            if inbody.isConnected {
                if let scan = inbody.latestScan {
                    Section {
                        latestScanView(scan)
                    } header: {
                        Label("Latest Scan", systemImage: "figure.stand")
                    } footer: {
                        if let date = inbody.lastSyncDate {
                            Text("Last synced \(date.timeAgoDisplay())")
                        }
                    }
                    
                    // Body Composition Breakdown
                    Section {
                        compositionBreakdownView(scan)
                    } header: {
                        Label("Body Composition", systemImage: "chart.pie.fill")
                    }
                    
                    // Insights
                    let insights = inbody.getBodyCompositionInsights()
                    if !insights.isEmpty {
                        Section {
                            ForEach(insights, id: \.self) { insight in
                                Text(insight)
                                    .font(.subheadline)
                            }
                        } header: {
                            Label("Insights", systemImage: "lightbulb.fill")
                        }
                    }
                }
                
                // Scan History
                if !inbody.scanHistory.isEmpty {
                    Section {
                        ForEach(inbody.scanHistory.prefix(5)) { scan in
                            scanHistoryRow(scan)
                        }
                        
                        if inbody.scanHistory.count > 5 {
                            NavigationLink(value: InBodyRoute.scanHistory) {
                                Text("View All Scans (\(inbody.scanHistory.count))")
                                    .foregroundColor(inbodyBlue)
                            }
                        }
                    } header: {
                        Label("Recent Scans", systemImage: "clock.fill")
                    }
                }
                
                // Sync Button
                Section {
                    Button(action: {
                        Task { try? await inbody.syncMeasurements() }
                    }) {
                        HStack {
                            if inbody.isLoading {
                                ProgressView()
                                    .padding(.trailing, 8)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("Sync Now")
                        }
                    }
                    .disabled(inbody.isLoading)
                }
            }
            
            // About InBody Integration
            Section {
                aboutInBodyView
            } header: {
                Label("About", systemImage: "info.circle")
            }
        }
        .scrollContentBackground(.hidden)
        }
        .navigationTitle("InBody")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: InBodyRoute.self) { route in
            switch route {
            case .scanHistory:
                BodyCompositionHistoryView()
            }
        }
        .alert("Disconnect InBody?", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                inbody.disconnect()
            }
        } message: {
            Text("Your body composition history will remain in Fit33, but new scans won't sync until you reconnect.")
        }
        .sheet(isPresented: $showingAuthSheet) {
            InBodyAuthSheet()
        }
    }
    
    // MARK: - Connected View
    
    private var connectedView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // InBody Icon
                ZStack {
                    Circle()
                        .fill(inbodyBlue.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "figure.stand")
                        .font(.system(size: 24))
                        .foregroundColor(inbodyBlue)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.ds_bodySmall)
                        Text("Connected")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                    
                    if let profile = inbody.userProfile {
                        Text(profile.name ?? profile.email ?? "InBody User")
                            .font(.headline)
                    }
                }
                
                Spacer()
                
                // InBody logo placeholder
                Text("InBody")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(inbodyBlue)
            }
            
            Divider()
            
            Button(action: { showingDisconnectAlert = true }) {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect")
                }
                .font(.subheadline)
                .foregroundColor(.red)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    // MARK: - Disconnected View
    
    private var disconnectedView: some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect InBody")
                        .font(.headline)
                    Text("Sync body composition data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundColor(inbodyBlue)
            }
            
            Button(action: { showingAuthSheet = true }) {
                HStack {
                    Image(systemName: "figure.stand")
                    Text("Connect with InBody")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [inbodyBlue, inbodyBlue.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    // MARK: - Latest Scan View
    
    private func latestScanView(_ scan: BodyCompositionScan) -> some View {
        VStack(spacing: 16) {
            // Main metrics grid
            HStack(spacing: 16) {
                metricCard(
                    icon: "scalemass.fill",
                    value: String(format: "%.1f", scan.weightLbs),
                    unit: "lbs",
                    label: "Weight",
                    color: .blue
                )
                
                if let bf = scan.bodyFatPercentage {
                    metricCard(
                        icon: "percent",
                        value: String(format: "%.1f", bf),
                        unit: "%",
                        label: "Body Fat",
                        color: .orange
                    )
                }
                
                if let smm = scan.skeletalMuscleMassKg {
                    metricCard(
                        icon: "figure.strengthtraining.traditional",
                        value: String(format: "%.1f", smm * 2.20462),
                        unit: "lbs",
                        label: "Muscle",
                        color: .green
                    )
                }
            }
            
            // InBody Score if available
            if let score = scan.inbodyScore {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("InBody Score: ")
                        .foregroundColor(.secondary)
                    Text("\(score)")
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(score))
                    Text("/ 100")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(.top, 8)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
    
    private func metricCard(icon: String, value: String, unit: String, label: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.ds_heading3)
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
    
    // MARK: - Composition Breakdown View
    
    private func compositionBreakdownView(_ scan: BodyCompositionScan) -> some View {
        VStack(spacing: 12) {
            if let bf = scan.bodyFatPercentage,
               let smm = scan.skeletalMuscleMassKg {
                // Visual bar showing composition
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        // Muscle portion
                        let musclePercent = min((smm / scan.weightKg) * 100, 50)
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: geometry.size.width * (musclePercent / 100))
                        
                        // Fat portion
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: geometry.size.width * (bf / 100))
                        
                        // Other (water, bone, etc.)
                        Rectangle()
                            .fill(Color.blue.opacity(0.5))
                    }
                }
                .frame(height: 12)
                .cornerRadius(6)
                
                // Legend
                HStack(spacing: 16) {
                    legendItem(color: .green, label: "Muscle")
                    legendItem(color: .orange, label: "Fat")
                    legendItem(color: .blue.opacity(0.5), label: "Other")
                }
                .font(.caption2)
            }
            
            // Detailed metrics
            VStack(spacing: 8) {
                if let lbm = scan.leanBodyMassKg {
                    compositionRow(label: "Lean Body Mass", value: "\(String(format: "%.1f", lbm * 2.20462)) lbs")
                }
                if let water = scan.bodyWaterKg {
                    compositionRow(label: "Total Body Water", value: "\(String(format: "%.1f", water * 2.20462)) lbs")
                }
                if let bmi = scan.bmi {
                    compositionRow(label: "BMI", value: String(format: "%.1f", bmi))
                }
                if let bmr = scan.bmr {
                    compositionRow(label: "BMR", value: "\(Int(bmr)) kcal/day")
                }
                if let vf = scan.visceralFatLevel {
                    compositionRow(
                        label: "Visceral Fat",
                        value: "\(vf)",
                        valueColor: vf <= 9 ? .green : (vf <= 14 ? .orange : .red)
                    )
                }
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundColor(.secondary)
        }
    }
    
    private func compositionRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(valueColor)
        }
        .font(.subheadline)
    }
    
    // MARK: - Scan History Row
    
    private func scanHistoryRow(_ scan: BodyCompositionScan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.measuredAt, style: .date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack(spacing: 8) {
                    Text("\(String(format: "%.1f", scan.weightLbs)) lbs")
                    if let bf = scan.bodyFatPercentage {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(String(format: "%.1f", bf))% BF")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let score = scan.inbodyScore {
                Text("\(score)")
                    .font(.headline)
                    .foregroundColor(scoreColor(score))
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    // MARK: - About View
    
    private var aboutInBodyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What syncs from InBody?")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                integrationBullet("Weight & Body Fat Percentage")
                integrationBullet("Skeletal Muscle Mass")
                integrationBullet("Lean Body Mass & BMI")
                integrationBullet("Basal Metabolic Rate (BMR)")
                integrationBullet("Visceral Fat Level")
                integrationBullet("InBody Score")
            }
            
            Divider()
                .padding(.vertical, Spacing.xs)
            
            Text("How it helps your goals")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                benefitBullet("More accurate calorie calculations using your actual BMR")
                benefitBullet("Track muscle gain vs fat loss separately")
                benefitBullet("Personalized workout recommendations")
                benefitBullet("Better body recomposition tracking")
            }
            
            Divider()
                .padding(.vertical, Spacing.xs)
            
            Text("Compatible Devices")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("InBody Dial H30, H20, InBodyBAND3, and professional InBody devices at gyms")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    private func integrationBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption)
                .foregroundColor(.green)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func benefitBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundColor(.yellow)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - InBody Auth Sheet

struct InBodyAuthSheet: View {
    @StateObject private var inbody = InBodyService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    
    private let inbodyBlue = Color(red: 0/255, green: 122/255, blue: 204/255)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                // InBody Logo & Description
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(inbodyBlue.opacity(0.1))
                            .frame(width: 100, height: 100)
                        
                        Image(systemName: "figure.stand")
                            .font(.system(size: 44))
                            .foregroundColor(inbodyBlue)
                    }
                    
                    Text("Connect to InBody")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Sync your body composition data to get personalized insights and track your progress beyond just weight.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Permissions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Fit33 will be able to:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    permissionRow(icon: "scalemass.fill", text: "Read your weight & body composition")
                    permissionRow(icon: "figure.strengthtraining.traditional", text: "Access muscle mass data")
                    permissionRow(icon: "flame.fill", text: "View your BMR for accurate calories")
                    permissionRow(icon: "chart.line.uptrend.xyaxis", text: "Track your progress over time")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: CornerRadius.md).fill(Color(.systemGray6)))
                .padding(.horizontal)
                
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Connect Button
                Button(action: startAuth) {
                    HStack {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "link")
                            Text("Connect with InBody")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [inbodyBlue, inbodyBlue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(CornerRadius.md)
                }
                .disabled(isAuthenticating)
                .padding(.horizontal)
                
                // Info text
                Text("You'll be redirected to InBody to sign in")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer().frame(height: 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: inbody.isConnected) { _, isConnected in
                if isConnected {
                    dismiss()
                }
            }
            .onOpenURL { url in
                handleCallback(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InBodyCallback"))) { notification in
                if let url = notification.object as? URL {
                    handleCallback(url)
                }
            }
        }
    }
    
    private func permissionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(inbodyBlue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
    
    private func startAuth() {
        guard let authURL = inbody.getAuthorizationURL() else {
            errorMessage = "Could not create authorization URL"
            return
        }
        
        isAuthenticating = true
        errorMessage = nil
        
        // Open InBody auth in browser
        UIApplication.shared.open(authURL)
    }
    
    private func handleCallback(_ url: URL) {
        guard url.scheme == "fit33" && url.host == "inbody" else { return }
        
        Task {
            do {
                try await inbody.handleCallback(url: url)
                await MainActor.run {
                    isAuthenticating = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAuthenticating = false
                }
            }
        }
    }
}

// MARK: - Body Composition History View

struct BodyCompositionHistoryView: View {
    @StateObject private var inbody = InBodyService.shared
    
    var body: some View {
        List {
            ForEach(inbody.scanHistory) { scan in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(scan.measuredAt, style: .date)
                            .font(.headline)
                        Spacer()
                        if let score = scan.inbodyScore {
                            Text("Score: \(score)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 16) {
                        metricPill(label: "Weight", value: "\(String(format: "%.1f", scan.weightLbs)) lbs")
                        
                        if let bf = scan.bodyFatPercentage {
                            metricPill(label: "Body Fat", value: "\(String(format: "%.1f", bf))%")
                        }
                        
                        if let smm = scan.skeletalMuscleMassKg {
                            metricPill(label: "Muscle", value: "\(String(format: "%.1f", smm * 2.20462)) lbs")
                        }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        }
        .navigationTitle("Scan History")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func metricPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Compact InBody Card (for Dashboard)

struct InBodyCompactCard: View {
    @StateObject private var inbody = InBodyService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private let inbodyBlue = Color(red: 0/255, green: 122/255, blue: 204/255)
    
    var body: some View {
        if inbody.isConnected, let scan = inbody.latestScan {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "figure.stand")
                        .foregroundColor(inbodyBlue)
                    Text("Body Composition")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text(scan.measuredAt, style: .relative)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 20) {
                    compactMetric(
                        value: String(format: "%.1f", scan.weightLbs),
                        unit: "lbs",
                        label: "Weight"
                    )
                    
                    if let bf = scan.bodyFatPercentage {
                        compactMetric(
                            value: String(format: "%.1f", bf),
                            unit: "%",
                            label: "Body Fat"
                        )
                    }
                    
                    if let smm = scan.skeletalMuscleMassKg {
                        compactMetric(
                            value: String(format: "%.1f", smm * 2.20462),
                            unit: "lbs",
                            label: "Muscle"
                        )
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
            .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
        }
    }
    
    private func compactMetric(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InBodySettingsView()
    }
}
