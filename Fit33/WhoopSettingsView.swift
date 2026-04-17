//
//  WhoopSettingsView.swift
//  Fit33
//
//  Connect, disconnect, and manage WHOOP integration.
//

import SwiftUI
import AuthenticationServices

struct WhoopSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var whoopService = WhoopService.shared

    var body: some View {
        ZStack {
            AnimatedOrbBackground.home(colorScheme: colorScheme)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    connectionCard
                    if whoopService.isConnected {
                        recoveryPreviewCard
                        syncStatusCard
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 60)
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("WHOOP")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !whoopService.isConnected {
                startAuth()
            }
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "waveform.path.ecg")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("WHOOP")
                        .font(.ds_heading3)
                    Text(whoopService.isConnected ? "Connected" : "Not connected")
                        .font(.ds_bodySmall)
                        .foregroundColor(whoopService.isConnected ? .green : .secondary)
                }
                Spacer()
            }

            if whoopService.isConnected {
                if let profile = whoopService.userProfile {
                    Text("Signed in as \(profile.fullName)")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    whoopService.disconnect()
                } label: {
                    Text("Disconnect")
                        .font(.ds_labelLarge)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color.red.opacity(0.12))
                        )
                }
                .accessibilityLabel("Disconnect WHOOP")
                .accessibilityHint("Removes WHOOP connection and stops syncing data.")
            } else {
                Button {
                    startAuth()
                } label: {
                    Text("Connect WHOOP")
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient.ds_primaryAccent
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        )
                }
                .accessibilityLabel("Connect WHOOP")
                .accessibilityHint("Opens WHOOP sign-in to link your account.")

                Text("Sync recovery score, HRV, strain, sleep stages, and workouts from your WHOOP band.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let error = whoopService.errorMessage {
                    Text(error)
                        .font(.ds_bodySmall)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel("WHOOP connection error")
                        .accessibilityValue(error)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .gray)
    }

    // MARK: - Recovery Preview

    private var recoveryPreviewCard: some View {
        VStack(spacing: Spacing.md) {
            SectionHeader(title: "Today's Snapshot", icon: "heart.text.square.fill", iconColor: whoopService.currentRecoveryLevel.color)

            HStack(spacing: Spacing.lg) {
                recoveryMetric(
                    label: "Recovery",
                    value: whoopService.todayRecovery?.recoveryScore.map { "\($0)%" } ?? "--",
                    color: whoopService.currentRecoveryLevel.color,
                    icon: "arrow.up.heart.fill"
                )
                recoveryMetric(
                    label: "HRV",
                    value: whoopService.todayRecovery?.hrvRmssdMilli.map { String(format: "%.0f", $0) + "ms" } ?? "--",
                    color: .cyan,
                    icon: "waveform.path.ecg"
                )
                recoveryMetric(
                    label: "Strain",
                    value: whoopService.todayStrain?.strain.map { String(format: "%.1f", $0) } ?? "--",
                    color: .blue,
                    icon: "flame.fill"
                )
                recoveryMetric(
                    label: "RHR",
                    value: whoopService.todayRecovery?.restingHeartRate.map { "\($0)" } ?? "--",
                    color: .red,
                    icon: "heart.fill"
                )
            }

            if let sleep = whoopService.lastSleep,
               let perf = sleep.sleepPerformancePercentage {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.indigo)
                    Text("Sleep Performance")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(perf))%")
                        .font(.ds_statSmall)
                        .foregroundColor(.indigo)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: whoopService.currentRecoveryLevel.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's WHOOP snapshot. Recovery \(whoopService.todayRecovery?.recoveryScore.map { "\($0) percent" } ?? "unavailable").")
    }

    private func recoveryMetric(label: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.ds_bodyMedium)
                .foregroundColor(color)
            Text(value)
                .font(.ds_statSmall)
                .foregroundColor(.primary)
            Text(label)
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sync Status

    private var syncStatusCard: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Text("Last Sync")
                    .font(.ds_bodyMedium)
                Spacer()
                if whoopService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let date = whoopService.lastSyncDate {
                    Text(date, style: .relative)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                } else {
                    Text("Never")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }

            Button {
                Task { await whoopService.syncAllData(force: true) }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Now")
                }
                .font(.ds_labelMedium)
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.blue.opacity(0.1))
                )
            }
            .disabled(whoopService.isLoading)
            .accessibilityLabel("Sync WHOOP data now")

            if let error = whoopService.errorMessage {
                Text(error)
                    .font(.ds_bodySmall)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("WHOOP sync error")
                    .accessibilityValue(error)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
    }

    // MARK: - OAuth (launches browser directly)

    @State private var hasLaunchedAuth = false

    private func startAuth() {
        guard !hasLaunchedAuth else { return }
        hasLaunchedAuth = true

        guard let authURL = whoopService.getAuthorizationURL() else {
            AppLogger.error("[WHOOP] Failed to build authorization URL", category: .auth)
            return
        }

        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "fit33"
        ) { callbackURL, error in
            hasLaunchedAuth = false

            if let error = error {
                let nsError = error as NSError
                if nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    AppLogger.debug("[WHOOP] User cancelled login", category: .auth)
                } else {
                    AppLogger.error("[WHOOP] ASWebAuth error (code \(nsError.code)): \(error.localizedDescription)", category: .auth)
                }
                return
            }

            guard let url = callbackURL else {
                AppLogger.error("[WHOOP] ASWebAuth returned nil callbackURL with no error", category: .auth)
                return
            }

            AppLogger.info("[WHOOP] ASWebAuth callback received: \(url.scheme ?? "nil")://\(url.host ?? "nil")", category: .auth)

            Task { @MainActor in
                do {
                    try await whoopService.handleCallback(url: url)
                } catch {
                    AppLogger.error("[WHOOP] Callback handling failed: \(error.localizedDescription)", category: .auth)
                    whoopService.errorMessage = error.localizedDescription
                }
            }
        }

        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
}
