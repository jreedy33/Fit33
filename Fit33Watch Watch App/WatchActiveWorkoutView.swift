//
//  WatchActiveWorkoutView.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Cardio HKWorkoutSession UI — three-option picker (Run / Walk /
//  Other) → live screen with duration + HR + Finish. The resulting
//  `HKWorkout` sample is auto-imported by the iPhone's HK observer
//  so no Supabase write is needed from the watch.
//
//  Lifecycle owner is `WatchWorkoutSessionManager`, which holds the
//  HKWorkoutSession + HKLiveWorkoutBuilder strongly so the queries
//  stay running for the duration of the session.
//

import SwiftUI
import HealthKit

struct WatchActiveWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = WatchWorkoutSessionManager()

    var body: some View {
        Group {
            switch session.state {
            case .picker:
                pickerView
            case .running, .ending:
                liveView
            case .finished:
                finishedView
            }
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if session.state == .picker {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("Start Cardio")
                    .font(.headline)
                    .padding(.top, 4)
                ForEach(WatchWorkoutSessionManager.WorkoutKind.allCases, id: \.self) { kind in
                    Button {
                        session.start(kind: kind)
                    } label: {
                        HStack {
                            Image(systemName: kind.symbol)
                            Text(kind.label)
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Live

    private var liveView: some View {
        VStack(spacing: 8) {
            Text(session.kindLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(session.formattedDuration)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(session.heartRateString)
                    .font(.system(.body, design: .rounded).weight(.medium))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            Button {
                Task {
                    await session.finish()
                    dismiss()
                }
            } label: {
                Text(session.state == .ending ? "Saving…" : "Finish")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(session.state == .ending)
        }
        .padding(.horizontal, 6)
    }

    private var finishedView: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("Saved")
                .font(.headline)
        }
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 800_000_000)
                dismiss()
            }
        }
    }
}
