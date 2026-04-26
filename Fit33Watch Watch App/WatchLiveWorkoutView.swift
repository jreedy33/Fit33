//
//  WatchLiveWorkoutView.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Strength-workout mirror. Auto-presented over `WatchTodayView`
//  whenever the iPhone publishes `liveWorkout.active = true`.
//
//  Three states (driven by `WatchLiveWorkoutStore`):
//    1. Resting  → big circular countdown of `restRemainingSec`,
//                 fires `.notification` haptic on expiry. The
//                 user can still tap "Mark Done" if they actually
//                 finish early; that's a no-op-redundant event but
//                 idempotent on the phone.
//    2. Working  → big "Mark Done" button (≥44pt tap target) +
//                 set/exercise summary above.
//    3. End-of-workout → `WatchTodayStore` hasn't received any
//                 active payload, but the phone still hasn't pushed
//                 `active: false` — extremely brief; we render the
//                 working layout with the last known values.
//
//  No End/Cancel button: workout lifecycle is owned by the phone
//  (PE invariant 33 — wrist is enrichment, not source of truth).
//

import SwiftUI

struct WatchLiveWorkoutView: View {
    @EnvironmentObject private var liveStore: WatchLiveWorkoutStore

    /// Capture of the largest remaining-seconds we've seen for the
    /// current `restEndsAt` so the ring progress is ~accurate even
    /// though the phone doesn't ship the original duration.
    @State private var restTotalCapture: Int = 0

    var body: some View {
        VStack(spacing: 8) {
            header
            Spacer(minLength: 4)
            primaryControl
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 8)
        .onChange(of: liveStore.restEndsAt) { _, _ in
            // New rest period (or rest cleared) — reset the captured
            // total so the ring fills from 0 again.
            restTotalCapture = liveStore.restRemainingSec
        }
        .onChange(of: liveStore.restRemainingSec) { _, newValue in
            if newValue > restTotalCapture { restTotalCapture = newValue }
        }
    }

    private var header: some View {
        VStack(spacing: 2) {
            Text(liveStore.exerciseName.isEmpty ? "Workout" : liveStore.exerciseName)
                .font(.system(.headline, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(setSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var setSubtitle: String {
        let setNumber = liveStore.setIndex + 1
        let total = max(liveStore.totalSets, setNumber)
        var line = "Set \(setNumber) of \(total)"
        if let weight = liveStore.targetWeight, weight > 0 {
            let weightStr = weight.truncatingRemainder(dividingBy: 1) == 0
                ? "\(Int(weight))"
                : String(format: "%.1f", weight)
            line += " · \(weightStr) × \(liveStore.targetReps)"
        } else if liveStore.targetReps > 0 {
            line += " · \(liveStore.targetReps) reps"
        }
        return line
    }

    @ViewBuilder
    private var primaryControl: some View {
        if liveStore.restEndsAt != nil {
            restCountdown
        } else {
            markDoneButton
        }
    }

    private var markDoneButton: some View {
        Button {
            liveStore.completeCurrentSet()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                Text("Mark Done")
                    .font(.system(.body, design: .rounded).weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Color.green, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mark current set done")
    }

    private var restCountdown: some View {
        let total = max(1, restTotalSec)
        let remaining = max(0, liveStore.restRemainingSec)
        let progress = 1.0 - (Double(remaining) / Double(total))
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: max(0.0001, min(1.0, progress)))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: progress)
                VStack(spacing: 0) {
                    Text(formatRest(remaining))
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                    Text("Rest")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)
        }
    }

    /// Approximate original rest duration — see `restTotalCapture`
    /// above for the rationale (phone only ships `restEndsAt`).
    private var restTotalSec: Int {
        max(restTotalCapture, liveStore.restRemainingSec)
    }

    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
