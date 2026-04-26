//
//  WatchContentView.swift
//  Fit33Watch
//
//  Realtime Widget Server Pull — Phase 8a (2026-04-26).
//
//  Minimal foreground UI. The watch app's purpose is to be a headless
//  background writer; the foreground view exists only so:
//    1. The user can verify the app is working (last-sync timestamp).
//    2. The first launch can prompt for HealthKit + Notifications
//       authorization (background-only apps can't surface auth
//       prompts at all).
//    3. The user has a place to tap "Open on iPhone" if they need to
//       fix something the watch can't handle alone (sign in, accept
//       a challenge, change preferences).
//
//  Design intent: this is an at-a-glance reassurance screen, NOT a
//  miniature companion to the iPhone app. We deliberately do NOT
//  render challenge progress here — the iPhone widget surface is
//  the source of truth, and duplicating it on the wrist would force
//  another network call from a process that's supposed to stay
//  background.
//

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var lifecycle: WatchLifecycle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fit33")
                    .font(.headline)

                Text("Background sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(lifecycle.lastSyncStatus)
                    .font(.caption)
                    .foregroundStyle(.primary)

                if let lastAt = lifecycle.lastSyncAt {
                    Text("Last sync: \(Self.relativeFormatter.localizedString(for: lastAt, relativeTo: Date()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Placeholder; we re-render the row on every state push
                // and don't want a redundant "tap to refresh" since the
                // watch should be doing this on its own.
                Divider()

                Text("Steps + active energy stream from your wrist to your iPhone challenges automatically.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
