//
//  AddHomescreenWidgetSheet.swift
//  Fit33
//
//  Step-by-step guide for adding the active-challenge widget to the
//  iOS home screen. iOS does NOT expose any public URL scheme or API
//  for programmatically adding a widget or opening the widget gallery
//  for a specific app, so the best UX we can ship is a clear, visual
//  instructional sheet. (As of iOS 18.) See:
//    • `WidgetCenter` — only `reloadTimelines` / `getCurrentConfigurations`,
//      no install affordance.
//    • Apple's HIG explicitly says widget discovery is system-driven.
//
//  Lifecycle:
//    • Presented from `ChallengeDetailView`'s top-of-screen CTA.
//    • Dismisses via the `Done` button or sheet drag.
//

import SwiftUI

// MARK: - Instructional Sheet

struct AddHomescreenWidgetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, title: step.title, body: step.body, symbol: step.symbol)
                        }
                    }
                    
                    proTip
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xl)
            }
            .navigationTitle("Add to Home Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("See your challenge at a glance")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text("Track scores and trash-talk live from your home screen.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.04))
            )
        }
    }
    
    // MARK: - Step row
    
    private func stepRow(number: Int, title: String, body: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.ds_bodyMedium)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.ds_caption)
                        .foregroundColor(.accentColor)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                Text(body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Pro tip
    
    private var proTip: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "lightbulb.fill")
                .font(.ds_bodyRegular)
                .foregroundColor(.yellow)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Pro tip")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Text("Long-press the widget after adding it, then tap **Edit Widget** to pick which challenge it shows. You can stack multiple Fit33 widgets — one per active challenge.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.yellow.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
    }
    
    // MARK: - Step content
    
    private struct Step {
        let title: String
        let body: String
        let symbol: String
    }
    
    private static let steps: [Step] = [
        Step(
            title: "Long-press your home screen",
            body: "Touch and hold an empty area of your iPhone home screen until the apps start jiggling.",
            symbol: "hand.point.up.left.fill"
        ),
        Step(
            title: "Tap the + button",
            body: "Tap the plus icon in the top-left corner to open the widget gallery.",
            symbol: "plus.circle.fill"
        ),
        Step(
            title: "Search for Fit33",
            body: "Type \"Fit33\" in the search bar at the top of the gallery.",
            symbol: "magnifyingglass"
        ),
        Step(
            title: "Pick Active Challenge",
            body: "Choose the Active Challenge widget, swipe to pick a size, then tap Add Widget.",
            symbol: "rectangle.stack.fill"
        ),
        Step(
            title: "Tap Done",
            body: "Tap Done in the top-right to finish. Your live score and any incoming smack-talk will appear automatically.",
            symbol: "checkmark.circle.fill"
        )
    ]
}

#Preview {
    AddHomescreenWidgetSheet()
}
