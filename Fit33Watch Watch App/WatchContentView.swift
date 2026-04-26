//
//  WatchContentView.swift
//  Fit33Watch
//
//  Watch UI Phase 1 (2026-04-26).
//
//  Thin wrapper around `WatchTodayView` that adds the small footer
//  with last-sync status (preserved from the previous headless-only
//  watch app). The Today screen does the real work; this file exists
//  primarily so callers don't have to reach into `WatchTodayView`
//  for layout tweaks and so we keep the historical name `Fit33WatchApp`
//  binds to (`WatchContentView()`).
//

import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var lifecycle: WatchLifecycle

    var body: some View {
        WatchTodayView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                lastSyncFooter
            }
    }

    @ViewBuilder
    private var lastSyncFooter: some View {
        if let lastAt = lifecycle.lastSyncAt {
            Text("Synced \(Self.relativeFormatter.localizedString(for: lastAt, relativeTo: Date()))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        } else {
            Text(lifecycle.lastSyncStatus)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
