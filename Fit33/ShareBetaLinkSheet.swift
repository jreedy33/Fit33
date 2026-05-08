//
//  ShareBetaLinkSheet.swift
//  Fit33
//
//  Surfaces the canonical TestFlight invite link so power users can
//  hand the beta to a friend in two taps. Presented from the pinned
//  "Share Beta Link" affordance directly under the dashboard's
//  "Welcome back, NAME" line (`DashboardView+Header.swift` →
//  `pinnedShareBetaRow`).
//
//  UX:
//    - Displays the full TestFlight URL in a copy-friendly chip.
//    - Primary CTA: "Copy Link" → writes to UIPasteboard, gives haptic
//      success feedback, swaps the button to a "Copied!" state for
//      ~1.6s so the user has visual confirmation.
//    - Secondary CTA: native share sheet (`ShareLink`) so the link can
//      go to Messages / Mail / etc. without leaving the app.
//
//  Keep this sheet simple — it's a Beta-period affordance and may be
//  removed (or moved into Settings → About) once the app ships GA.
//

import SwiftUI

struct ShareBetaLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Canonical TestFlight invite. Update here if Apple ever rotates
    /// the public-link slug for the Fit33 beta group.
    private let betaLink = "https://testflight.apple.com/join/mUPmxbVE"

    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue.opacity(0.85), .cyan.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 68, height: 68)
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.top, 24)
                .accessibilityHidden(true)

                Text("Share the Fit33 Beta")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.primary)

                Text("Send this TestFlight invite to friends or family so they can try Fit33 before it hits the App Store.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.top, 1)
                Text(betaLink)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.blue.opacity(0.25), lineWidth: 1)
            )
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Beta link, \(betaLink)")

            VStack(spacing: 10) {
                Button(action: copyLink) {
                    HStack(spacing: 8) {
                        Image(systemName: didCopy ? "checkmark.circle.fill" : "doc.on.doc.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text(didCopy ? "Copied!" : "Copy Link")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(didCopy ? Color.green : Color.blue)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(didCopy ? "Link copied" : "Copy beta link to clipboard")
                .accessibilityHint("Copies the TestFlight invite URL to your clipboard")

                ShareLink(item: URL(string: betaLink) ?? URL(fileURLWithPath: "/")) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Share via…")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 1.2)
                    )
                }
                .accessibilityHint("Opens the system share sheet for the TestFlight link")

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Close")
                .accessibilityHint("Dismisses the share beta link dialog")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Spacer(minLength: 12)
        }
        .padding(.bottom, 16)
    }

    private func copyLink() {
        UIPasteboard.general.string = betaLink
        HapticManager.notification(.success)
        AppLogger.debug("[SHARE_BETA] Copied TestFlight invite link to clipboard", category: .ui)
        withAnimation(.easeInOut(duration: 0.2)) {
            didCopy = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeInOut(duration: 0.25)) {
                didCopy = false
            }
        }
    }
}

#Preview {
    ShareBetaLinkSheet()
}
