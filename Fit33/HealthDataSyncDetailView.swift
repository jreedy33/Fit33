//
//  HealthDataSyncDetailView.swift
//  Fit33
//
//  Settings → Privacy & Security → Health Data
//
//  Surfaces the user-visible disclosure that we sync HealthKit-derived data
//  to our cloud (App Review HIG passive-disclosure / Privacy requirement).
//  Lists every category that flows into Supabase from HealthKitManager and
//  exposes a destructive "Stop syncing & delete cloud copy" control.
//
//  Owned by INFRA_SECURITY_AGENT.md (App Store compliance / privacy posture).
//  Any new HealthKit category that gets synced to Supabase MUST be added to
//  the "Categories synced" list below in the same PR (Infra invariant 33).
//

import SwiftUI

struct HealthDataSyncDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPurgeConfirmation = false
    @State private var showRequestReceivedBanner = false
    @State private var isPurging = false
    @State private var showPurgeErrorAlert = false
    @State private var purgeErrorMessage = ""

    /// Categories of HealthKit data Fit33 reads + writes to Supabase.
    /// MUST stay in sync with `HealthKitManager.requestAuthorization()` —
    /// adding a new HK type to that authorization set requires adding the
    /// matching label here so the user-visible disclosure stays honest.
    private let syncedCategories: [(label: String, icon: String)] = [
        ("Steps", "figure.walk"),
        ("Active Energy", "flame.fill"),
        ("Workouts", "figure.strengthtraining.traditional"),
        ("Body Weight", "scalemass.fill"),
        ("Height", "ruler.fill"),
        ("Biological Sex", "person.fill"),
        ("Date of Birth", "calendar")
    ]

    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)

            ScrollView {
                VStack(spacing: Spacing.lg) {
                    heroSection
                    bodyParagraph
                    statusCard
                    learnMoreLink
                    destructiveButton
                }
                .padding(Spacing.lg)
                .padding(.bottom, Spacing.xxl)
            }

            if showRequestReceivedBanner {
                VStack {
                    Spacer()
                    requestReceivedBanner
                        .padding(.bottom, Spacing.xl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .ignoresSafeArea(.keyboard)
            }
        }
        .navigationTitle("Health Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Stop syncing health data?", isPresented: $showPurgeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Stop & Delete", role: .destructive) {
                handlePurgeRequest()
            }
        } message: {
            Text("This deletes your synced health data from Fit33's servers. Your Apple Health data remains untouched on your device.")
        }
        .alert("Couldn't delete health data", isPresented: $showPurgeErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(purgeErrorMessage)
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.red, Color.pink, Color(red: 1.0, green: 0.45, blue: 0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.red.opacity(0.25), radius: 12, x: 0, y: 6)
                .padding(.top, Spacing.lg)

            Text("Health Data Sync")
                .font(.ds_heading1)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var bodyParagraph: some View {
        Text("Fit33 syncs your activity, workouts, body measurements, and recovery data to our secure cloud so it's available across your devices. Data is encrypted in transit and at rest, and is never sold or shared with third parties.")
            .font(.ds_bodyRegular)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.xs)
    }

    // MARK: - Status Card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 10, height: 10)
                    .shadow(color: Color.green.opacity(0.6), radius: 4, x: 0, y: 0)

                Text("Sync status")
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)

                Spacer()

                Text("Enabled")
                    .font(.ds_labelMedium)
                    .foregroundColor(.green)
            }

            Divider()
                .opacity(0.4)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Categories synced")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
                    .padding(.bottom, Spacing.xxs)

                ForEach(syncedCategories, id: \.label) { item in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: item.icon)
                            .font(.ds_bodySmall)
                            .foregroundColor(.blue)
                            .frame(width: 22)

                        Text(item.label)
                            .font(.ds_bodyRegular)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sync status enabled. \(syncedCategories.count) categories synced.")
    }

    // MARK: - Learn More

    @ViewBuilder
    private var learnMoreLink: some View {
        Link(destination: LegalURLs.privacy) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.ds_bodySmall)
                Text("Learn more about how we handle your data")
                    .font(.ds_labelMedium)
                Image(systemName: "arrow.up.right.square")
                    .font(.ds_bodySmall)
            }
            .foregroundColor(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, Spacing.xs)
    }

    // MARK: - Destructive Button

    private var destructiveButton: some View {
        Button {
            HapticManager.impact(.medium)
            showPurgeConfirmation = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "trash.fill")
                    .font(.ds_labelLarge)
                Text("Stop syncing & delete cloud copy")
                    .font(.ds_labelLarge)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.red.opacity(colorScheme == .dark ? 0.15 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(Color.red.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, Spacing.md)
        .accessibilityLabel("Stop syncing and delete cloud copy of your health data")
        .accessibilityHint("Asks for confirmation before queuing a server-side purge.")
    }

    // MARK: - Banner

    private var requestReceivedBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.ds_labelLarge)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Cloud copy deleted")
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
                Text("Sync is off. Your synced health data was removed from Fit33's servers.")
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 6)
        )
        .padding(.horizontal, Spacing.lg)
    }

    // MARK: - Actions

    /// Wired to the real `purge_user_health_data` RPC (migration
    /// `supabase/20260726_purge_user_health_data_rpc.sql`, audit PR-10).
    /// On success we ALSO stop future syncing (`HealthKitService.disconnect()`)
    /// so "Stop syncing & delete cloud copy" does exactly what it says.
    /// On failure we surface an honest error alert — we never claim deletion
    /// happened when it didn't (Infra invariant 33).
    private func handlePurgeRequest() {
        guard !isPurging else { return }
        isPurging = true

        Task { @MainActor in
            defer { isPurging = false }
            do {
                _ = try await SupabaseManager.shared.supabaseClient
                    .rpc("purge_user_health_data")
                    .execute()

                // Stop future syncing so deleted data doesn't re-appear on
                // the next background sync tick.
                HealthKitService.shared.disconnect()

                AppLogger.info(
                    "[HealthDataSyncDetailView] Health data purge completed + HK sync disconnected",
                    category: .health
                )
                HapticManager.notification(.success)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    showRequestReceivedBanner = true
                }
            } catch {
                AppLogger.error(
                    "[HealthDataSyncDetailView] Health data purge FAILED: \(error.localizedDescription)",
                    category: .health
                )
                HapticManager.notification(.error)
                purgeErrorMessage = "We couldn't reach the server, so nothing was deleted. Please check your connection and try again."
                showPurgeErrorAlert = true
                return
            }

            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                showRequestReceivedBanner = false
            }
        }
    }
}

#Preview {
    NavigationStack {
        HealthDataSyncDetailView()
    }
}
