//
//  OuraSettingsView.swift
//  Fit33
//
//  Connect, disconnect, and manage Oura Ring integration.
//

import SwiftUI
import AuthenticationServices

struct OuraSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var ouraService = OuraService.shared

    var body: some View {
        ZStack {
            AnimatedOrbBackground.home(colorScheme: colorScheme)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    connectionCard
                    if ouraService.isConnected {
                        readinessPreviewCard
                        syncStatusCard
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 60)
                .padding(.top, Spacing.md)
            }
        }
        .navigationTitle("Oura Ring")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !ouraService.isConnected {
                startAuth()
            }
        }
    }

    // MARK: - Connection Card

    private var connectionCard: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: "circle.circle")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Oura Ring")
                        .font(.ds_heading3)
                    Text(ouraService.isConnected ? "Connected" : "Not connected")
                        .font(.ds_bodySmall)
                        .foregroundColor(ouraService.isConnected ? .green : .secondary)
                }
                Spacer()
            }

            if ouraService.isConnected {
                if let info = ouraService.personalInfo, let email = info.email {
                    Text("Signed in as \(email)")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    ouraService.disconnect(reason: "user_tap")
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
                .accessibilityLabel("Disconnect Oura Ring")
                .accessibilityHint("Removes Oura connection and stops syncing data.")
            } else {
                Button {
                    startAuth()
                } label: {
                    Text("Connect Oura Ring")
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
                .accessibilityLabel("Connect Oura Ring")
                .accessibilityHint("Opens Oura sign-in to link your account.")

                Text("Sync readiness score, sleep stages, HRV, activity, SpO2, and workouts from your Oura Ring.")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let error = ouraService.errorMessage {
                    Text(error)
                        .font(.ds_bodySmall)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .teal)
    }

    // MARK: - Readiness Preview

    private var readinessPreviewCard: some View {
        VStack(spacing: Spacing.md) {
            SectionHeader(title: "Today's Snapshot", icon: "heart.text.square.fill", iconColor: ouraService.currentReadinessLevel.color)

            HStack(spacing: Spacing.lg) {
                readinessMetric(
                    label: "Readiness",
                    value: ouraService.todayReadiness?.score.map { "\($0)" } ?? "--",
                    color: ouraService.currentReadinessLevel.color,
                    icon: "gauge.with.needle.fill"
                )
                readinessMetric(
                    label: "HRV",
                    value: ouraService.lastSleep?.averageHrv.map { String(format: "%.0f", $0) + "ms" } ?? "--",
                    color: .cyan,
                    icon: "waveform.path.ecg"
                )
                readinessMetric(
                    label: "Activity",
                    value: ouraService.todayActivity?.score.map { "\($0)" } ?? "--",
                    color: .blue,
                    icon: "flame.fill"
                )
                readinessMetric(
                    label: "RHR",
                    value: ouraService.lastSleep?.lowestHeartRate.map { "\($0)" } ?? "--",
                    color: .red,
                    icon: "heart.fill"
                )
            }

            if let sleep = ouraService.lastSleep,
               let efficiency = sleep.efficiency {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.indigo)
                    Text("Sleep Efficiency")
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(efficiency)%")
                        .font(.ds_statSmall)
                        .foregroundColor(.indigo)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: ouraService.currentReadinessLevel.color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's Oura snapshot. Readiness \(ouraService.todayReadiness?.score.map { "\($0)" } ?? "unavailable").")
    }

    private func readinessMetric(label: String, value: String, color: Color, icon: String) -> some View {
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
                if ouraService.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if let date = ouraService.lastSyncDate {
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
                Task { await ouraService.syncAllData(force: true) }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Now")
                }
                .font(.ds_labelMedium)
                .foregroundColor(.teal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.teal.opacity(0.1))
                )
            }
            .disabled(ouraService.isLoading)
            .accessibilityLabel("Sync Oura data now")

            if let error = ouraService.errorMessage {
                Text(error)
                    .font(.ds_bodySmall)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .teal)
    }

    // MARK: - OAuth (launches browser directly)

    @State private var hasLaunchedAuth = false

    private func startAuth() {
        guard !hasLaunchedAuth else { return }
        hasLaunchedAuth = true

        guard let authURL = ouraService.getAuthorizationURL() else {
            AppLogger.error("[OURA] Failed to build authorization URL", category: .auth)
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
                    AppLogger.debug("[OURA] User cancelled login", category: .auth)
                } else {
                    AppLogger.error("[OURA] ASWebAuth error (code \(nsError.code)): \(error.localizedDescription)", category: .auth)
                }
                return
            }

            guard let url = callbackURL else {
                AppLogger.error("[OURA] ASWebAuth returned nil callbackURL with no error", category: .auth)
                return
            }

            AppLogger.info("[OURA] ASWebAuth callback received: \(url.scheme ?? "nil")://\(url.host ?? "nil")", category: .auth)

            Task { @MainActor in
                do {
                    try await ouraService.handleCallback(url: url)
                } catch {
                    AppLogger.error("[OURA] Callback handling failed: \(error.localizedDescription)", category: .auth)
                    ouraService.errorMessage = error.localizedDescription
                }
            }
        }

        session.presentationContextProvider = WebAuthContextProvider.shared
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
}
