import SwiftUI

// MARK: - Workout Settings Side Panel

struct WorkoutSettingsPanel: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool
    @Binding var showingPremiumUpsell: Bool
    
    @AppStorage("workoutWeightUnit") private var useKg: Bool = false
    @AppStorage("workoutPerSideMode") private var isPerSideGlobal: Bool = false
    @AppStorage("defaultBarWeight") private var barWeight: Double = 45
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds: Int = 90
    @AppStorage("autoStartRestTimer") private var autoStartRestTimer: Bool = true
    @AppStorage("defaultSetCount") private var defaultSetCount: Int = 3
    @AppStorage("keepScreenOnDuringWorkout") private var keepScreenOn: Bool = true
    @AppStorage("workoutSoundEffects") private var soundEffects: Bool = true
    @AppStorage("showMusicPlayer") private var showMusicPlayer: Bool = true
    
    let onMinimize: () -> Void
    /// Finding M (2026-07-31): the only way out of a strength workout used
    /// to be FINISH — no discard affordance existed anywhere.
    let onDiscard: () -> Void
    
    @State private var showingDiscardConfirmation = false
    
    private var barWeightOptions: [Double] { useKg ? [20, 15, 10] : [45, 35, 25] }
    private var unitLabel: String { useKg ? "kg" : "lb" }
    
    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    weightSection
                    defaultSetsSection
                    restTimerSection
                    generalSection
                    removeAdsButton
                    minimizeButton
                    discardButton
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 12)
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            colorScheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.10)
                : Color(UIColor.systemGroupedBackground)
        )
    }
    
    // MARK: - Header
    
    private var panelHeader: some View {
        HStack {
            Text("Settings")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Spacer()
            Button {
                HapticManager.selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
    
    // MARK: - Weight Section
    
    private var weightSection: some View {
        sectionCard {
            sectionLabel("WEIGHT")
            
            rowWithPicker(title: "Unit") {
                Picker("", selection: $useKg) {
                    Text("lb").tag(false)
                    Text("kg").tag(true)
                }
                .pickerStyle(.segmented)
            }
            
            Divider().opacity(0.3)
            
            rowWithPicker(title: "Entry Mode") {
                Picker("", selection: $isPerSideGlobal) {
                    Text("Total").tag(false)
                    Text("Per Side").tag(true)
                }
                .pickerStyle(.segmented)
            }
            
            Divider().opacity(0.3)
            
            rowWithPicker(title: "Bar Weight") {
                Picker("", selection: $barWeight) {
                    ForEach(barWeightOptions, id: \.self) { w in
                        Text("\(Int(w)) \(unitLabel)").tag(w)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - Default Sets Section
    
    private var defaultSetsSection: some View {
        sectionCard {
            sectionLabel("DEFAULT SETS")
            
            VStack(spacing: 6) {
                Text("Sets Per Exercise")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Button {
                        if defaultSetCount > 1 { defaultSetCount -= 1; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultSetCount > 1 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultSetCount <= 1)
                    
                    Spacer()
                    
                    Text("\(defaultSetCount)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        if defaultSetCount < 10 { defaultSetCount += 1; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultSetCount < 10 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultSetCount >= 10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Rest Timer Section
    
    private var restTimerSection: some View {
        sectionCard {
            sectionLabel("REST TIMER")
            
            VStack(spacing: 6) {
                Text("Default Rest")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack {
                    Button {
                        if defaultRestSeconds > 0 { defaultRestSeconds -= 15; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultRestSeconds > 0 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultRestSeconds <= 0)
                    
                    Spacer()
                    
                    Text(formatRestTime(defaultRestSeconds))
                        .font(.title2)
                        .fontWeight(.bold)
                        .fontDesign(.rounded)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        if defaultRestSeconds < 300 { defaultRestSeconds += 15; HapticManager.selectionChanged() }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(defaultRestSeconds < 300 ? .blue : .secondary.opacity(0.3))
                    }
                    .disabled(defaultRestSeconds >= 300)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            
            Divider().opacity(0.3)
            
            toggleRow(title: "Auto-Start Timer", isOn: $autoStartRestTimer)
        }
    }
    
    // MARK: - General Section
    
    private var generalSection: some View {
        sectionCard {
            sectionLabel("GENERAL")
            toggleRow(title: "Keep Screen On", isOn: $keepScreenOn)
                .onChange(of: keepScreenOn) { _, newValue in
                    UIApplication.shared.isIdleTimerDisabled = newValue
                }
            Divider().opacity(0.3)
            toggleRow(title: "Sound Effects", isOn: $soundEffects)
            Divider().opacity(0.3)
            musicPlayerRow
        }
    }
    
    private var musicPlayerRow: some View {
        HStack {
            Text("Music Player")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            if !PremiumManager.shared.isPremiumUser {
                Image(systemName: "crown.fill")
                    .font(.caption2)
                    .foregroundColor(.yellow)
            }
            
            Spacer()
            
            if PremiumManager.shared.isPremiumUser {
                Toggle("", isOn: $showMusicPlayer)
                    .labelsHidden()
                    .tint(.blue)
            } else {
                Button {
                    HapticManager.impact(.medium)
                    showingPremiumUpsell = true
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    // MARK: - Remove Ads
    
    @ViewBuilder
    private var removeAdsButton: some View {
        if !PremiumManager.shared.isPremiumUser {
            Button {
                HapticManager.impact(.medium)
                showingPremiumUpsell = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text("Remove Ads")
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.cardBackground))
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Minimize
    
    private var minimizeButton: some View {
        Button {
            HapticManager.impact(.medium)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
            onMinimize()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.compress.vertical")
                Text("Minimize Workout")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(.orange)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Discard
    
    private var discardButton: some View {
        Button(role: .destructive) {
            HapticManager.impact(.medium)
            showingDiscardConfirmation = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text("Discard Workout")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .confirmationDialog("Discard this workout?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard Workout", role: .destructive) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isPresented = false }
                onDiscard()
            }
            Button("Keep Working", role: .cancel) { }
        } message: {
            Text("All sets from this session will be deleted. This can't be undone.")
        }
    }
    
    // MARK: - Reusable Components
    
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.cardBackground))
    }
    
    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
    
    private func rowWithPicker<Content: View>(title: String, @ViewBuilder picker: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            picker()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn.wrappedValue },
                set: { newValue in
                    HapticManager.selectionChanged()
                    isOn.wrappedValue = newValue
                }
            ))
                .labelsHidden()
                .tint(.blue)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
    
    private func formatRestTime(_ seconds: Int) -> String {
        if seconds == 0 { return "Off" }
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 && s > 0 { return "\(m):\(String(format: "%02d", s))" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
