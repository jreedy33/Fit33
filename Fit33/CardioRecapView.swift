import SwiftUI
import MapKit
import CoreLocation

// MARK: - CardioRecapView
//
// Cardio Redesign Phase 1 — Wave 5a + 5b.
// New post-workout recap. Replaces `RunCompletionView` for the new
// `CardioActiveSessionHost` flow (the legacy `RunCompletionView`
// stays in `RunningWorkoutView.swift` so the WorkoutTabView ➜
// RunningWorkoutView entry point continues to work — both views can
// coexist; the legacy one is the safety net.)
//
// Sections (top → bottom):
//   1. Route preview (40%) — `RoutePreviewMap` with start/end markers
//   2. Headline tile  — distance giant number + activity badge
//   3. 2×2 stat grid  — duration / pace / calories / elevation
//   4. PR badges      — fastest split, longest run, etc. (best-effort)
//   5. Splits         — collapsible per-km/mile table
//   6. Action row     — Share + Save to Health
//   7. Done           — closes back to landing
//
// Shares the same fanout (`SupabaseManager.saveCardioWorkout` →
// `record_cardio_workout` RPC → `UserManager.completeCardioWorkout` +
// `DailyQuestService.onCardioActivityImported`) as `RunCompletionView`,
// gated by `didCompleteFanout` for idempotency. Calls
// `CardioSessionManager.markSaved()` on Done so the host fullScreenCover
// dismisses cleanly.
//
// File length budget: ≤ 300 lines per `codingrules.mdc`.
struct CardioRecapView: View {
    let result: RunWorkoutResult
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showSplits = false
    @State private var isSavingToHealth = false
    @State private var savedToHealth = false
    @State private var showShareSheet = false
    @State private var didCompleteFanout = false
    @State private var didCelebrate = false

    var body: some View {
        NavigationStack {
            ZStack {
                background
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 18) {
                        headerCelebration
                        if result.routeCoordinates.count > 1 {
                            routeMap
                        }
                        headlineTile
                        statsGrid
                        prBadges
                        if !result.splits.isEmpty {
                            splitsSection
                        }
                        actionRow
                        doneButton
                            .padding(.bottom, 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
            }
            .onAppear { onRecapAppeared() }
            .sheet(isPresented: $showShareSheet) {
                CardioShareCardSheet(result: result, accent: accent)
            }
        }
    }

    // MARK: - Background

    private var background: some View {
        LinearGradient(
            colors: [accent.opacity(0.18), Color(.systemBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }

    // MARK: - Header celebration

    private var headerCelebration: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48, weight: .bold))
                .foregroundStyle(accent.gradient)
                .scaleEffect(didCelebrate ? 1.0 : 0.6)
                .animation(.spring(response: 0.45, dampingFraction: 0.55), value: didCelebrate)
            Text("\(result.activityType.displayName) Complete")
                .font(.title2)
                .fontWeight(.bold)
            if result.goalAchieved {
                Label("Goal Achieved", systemImage: "target")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.15)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Route preview

    private var routeMap: some View {
        RoutePreviewMap(coordinates: result.routeCoordinates)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    // MARK: - Headline tile

    private var headlineTile: some View {
        VStack(spacing: 4) {
            Text(distanceHeadline)
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(accent.gradient)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(distanceUnitLabel)
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .adaptiveMaterialBackground(cornerRadius: CornerRadius.lg)
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, spacing: 10) {
            statTile(icon: "clock.fill", color: .cyan,
                     value: result.formattedDuration, label: "Duration")
            statTile(icon: "speedometer", color: .orange,
                     value: paceLabel, label: "Avg Pace")
            statTile(icon: "flame.fill", color: .red,
                     value: String(format: "%.0f", result.calories), label: "Calories")
            statTile(icon: "mountain.2.fill", color: .green,
                     value: String(format: "%.0f m", result.elevationGain), label: "Elevation")
        }
    }

    private func statTile(icon: String, color: Color, value: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .adaptiveMaterialBackground(cornerRadius: 14)
    }

    // MARK: - PR badges (best-effort)

    @ViewBuilder
    private var prBadges: some View {
        let badges = computePRBadges()
        if !badges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("HIGHLIGHTS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(1.2)
                    .foregroundColor(.secondary)
                CardioBadgeFlowLayout(spacing: 6) {
                    ForEach(badges, id: \.self) { badge in
                        Label(badge, systemImage: "star.circle.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundColor(accent)
                            .background(Capsule().fill(accent.opacity(0.14)))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Splits

    private var splitsSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSplits.toggle() }
            } label: {
                HStack {
                    Text("Splits (\(result.splits.count))")
                        .font(.headline)
                    Spacer()
                    Image(systemName: showSplits ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
            }
            .buttonStyle(.plain)
            if showSplits {
                VStack(spacing: 4) {
                    ForEach(result.splits) { split in
                        HStack {
                            Text("\(split.kilometer)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .leading)
                            Text(split.formattedPacePerMile + " /mi")
                                .font(.subheadline.monospacedDigit())
                            Spacer()
                            Text(split.formattedTime)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .adaptiveMaterialBackground(cornerRadius: 12)
            }
        }
    }

    // MARK: - Action row

    // One font (`ds_labelLarge`), one height, `CornerRadius.lg`, and a
    // shared pressed state across the whole button row (P2 design batch,
    // 2026-07-31 — the row mixed 14/16pt radii, 50/54pt heights, and had
    // no press feedback).
    private static let actionButtonHeight: CGFloat = 52

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                HapticManager.impact(.light)
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.ds_labelLarge)
                    .frame(maxWidth: .infinity, minHeight: Self.actionButtonHeight)
                    .adaptiveMaterialBackground(cornerRadius: CornerRadius.lg)
                    .foregroundColor(.primary)
            }
            .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
            if HealthKitManager.shared.saveWorkoutsToHealth {
                Button(action: saveToHealth) {
                    Label(
                        savedToHealth ? "Saved" : (isSavingToHealth ? "Saving…" : "Save to Health"),
                        systemImage: savedToHealth ? "checkmark.circle.fill" : "heart.fill"
                    )
                    .font(.ds_labelLarge)
                    .frame(maxWidth: .infinity, minHeight: Self.actionButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(savedToHealth ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                    )
                    .foregroundColor(savedToHealth ? .green : .red)
                }
                .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
                .disabled(isSavingToHealth || savedToHealth)
            }
        }
    }

    // MARK: - Done

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(.ds_labelLarge)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: Self.actionButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg).fill(accent.gradient)
                )
                .shadow(color: accent.opacity(0.35), radius: 12, y: 4)
        }
        .buttonStyle(UniversalScaleButtonStyle(scale: .standard))
    }

    // MARK: - Computed labels

    private var accent: Color {
        // Must stay in lockstep with the canonical per-activity accent in
        // OutdoorCardioActiveView / CardioLandingView (finding AD,
        // 2026-07-31: recap + share card drifted to mint/green mid-session).
        switch result.activityType {
        case .walk:         return .teal
        case .run:          return .blue
        case .outdoorCycle: return .cyan
        case .hike:         return .orange
        }
    }

    private var distanceHeadline: String {
        // Imperial-default — unit toggle ships in Wave 3b mini-onboarding.
        result.distanceMiles >= 0.01
            ? String(format: "%.2f", result.distanceMiles)
            : String(format: "%.0f", result.distance)
    }

    private var distanceUnitLabel: String {
        result.distanceMiles >= 0.01 ? "MILES" : "METERS"
    }

    private var paceLabel: String {
        guard result.averagePace > 0 else { return "—" }
        let pacePerMile = result.averagePace * 1.60934
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    // MARK: - PR detection

    private func computePRBadges() -> [String] {
        var badges: [String] = []
        if let fastest = result.splits.map(\.pace).min(),
           fastest > 0 {
            let pacePerMile = fastest * 1.60934
            let minutes = Int(pacePerMile) / 60
            let seconds = Int(pacePerMile) % 60
            badges.append(String(format: "Fastest split %d:%02d /mi", minutes, seconds))
        }
        if result.splits.count >= 3,
           let first = result.splits.first?.pace,
           let last = result.splits.last?.pace,
           last < first {
            badges.append("Negative split")
        }
        if result.distanceMiles >= 6.21 { badges.append("10K+") }
        else if result.distanceMiles >= 3.1 { badges.append("5K+") }
        if result.elevationGain >= 100 { badges.append("Hill day") }
        return badges
    }

    // MARK: - Lifecycle / fanout

    private func onRecapAppeared() {
        didCelebrate = true
        HapticManager.notification(.success)
        guard !didCompleteFanout else { return }
        didCompleteFanout = true

        Task { @MainActor in
            UserManager.shared.updateStreak()
            let payload = buildCardioWorkoutData()
            var savedWorkoutId: String?
            do {
                savedWorkoutId = try await SupabaseManager.shared.saveCardioWorkout(payload)
            } catch {
                AppLogger.error(
                    "❌ [CARDIO] recap save failed: \(error.localizedDescription)",
                    category: .network
                )
            }
            // 2026-07-31: fanout only AFTER a durable save (matches the
            // indoor flow). On failure (thrown OR nil id) queue for offline
            // retry (PR-22 residual — the RPC's external_id idempotency
            // makes this duplicate-safe); the retry queue completes the
            // XP/quest fanout after the first successful retry — running it
            // here too would double-award, and running it against a made-up
            // workout id corrupted the trail.
            if savedWorkoutId == nil {
                CloudSyncRetryQueue.shared.enqueueCardioCloudSync(payload)
            }
            if let savedWorkoutId {
                UserManager.shared.completeCardioWorkout(
                    workoutId: savedWorkoutId,
                    activityType: result.activityType.rawValue,
                    durationSeconds: Int(result.duration),
                    distanceMeters: result.distance,
                    caloriesBurned: Int(result.calories),
                    averageHeartRate: result.averageHeartRate,
                    savedViaRPC: true,
                    goalAchieved: payload.goalAchieved
                )
                await DailyQuestService.shared.onCardioActivityImported(source: "fit33")
            }
            if StravaService.shared.isConnected {
                Task.detached {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    await StravaService.shared.syncActivities(daysBack: 1, force: true)
                }
            }
        }
    }

    private func buildCardioWorkoutData() -> CardioWorkoutData {
        let routeJSON: String? = {
            guard !result.simplifiedRouteCoordinates.isEmpty else { return nil }
            let coords = result.simplifiedRouteCoordinates.map {
                ["lat": $0.latitude, "lon": $0.longitude]
            }
            guard JSONSerialization.isValidJSONObject(coords),
                  let data = try? JSONSerialization.data(withJSONObject: coords),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }()
        let splitsJSON: String? = {
            guard !result.splits.isEmpty else { return nil }
            let arr = result.splits.map {
                ["kilometer": $0.kilometer, "time": $0.time, "pace": $0.pace, "is_manual": $0.isManual] as [String: Any]
            }
            guard JSONSerialization.isValidJSONObject(arr),
                  let data = try? JSONSerialization.data(withJSONObject: arr),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }()
        return CardioWorkoutData(
            activityType: result.activityType.rawValue,
            workoutName: nil,
            goalType: result.goalType.rawKey,
            goalValue: result.goalValue > 0 ? result.goalValue : nil,
            goalAchieved: result.goalAchieved,
            durationSeconds: Int(result.duration),
            distanceMeters: result.distance,
            caloriesBurned: result.calories,
            averagePace: result.averagePace > 0 ? result.averagePace : nil,
            bestPace: result.splits.map(\.pace).min(),
            averageSpeed: result.duration > 0 ? result.distance / result.duration : nil,
            maxSpeed: nil,
            averageHeartRate: result.averageHeartRate,
            maxHeartRate: nil,
            cadence: nil,
            averagePower: nil,
            equipmentName: nil,
            equipmentType: nil,
            routeCoordinatesJSON: routeJSON,
            splitsJSON: splitsJSON,
            startedAt: result.startTime,
            completedAt: result.endTime
        )
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
                AppLogger.error("❌ [CARDIO] save to Health failed: \(error)", category: .workout)
            }
        }
    }
}

// MARK: - CardioBadgeFlowLayout (lightweight wrap layout for badge chips)
private struct CardioBadgeFlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW { x = 0; y += lineH + spacing; lineH = 0 }
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: maxW, height: y + lineH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX { x = bounds.minX; y += lineH + spacing; lineH = 0 }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}
