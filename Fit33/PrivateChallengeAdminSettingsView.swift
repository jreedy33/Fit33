//
//  PrivateChallengeAdminSettingsView.swift
//  Fit33
//
//  Admin settings panel for Private Challenges — change goals, manage members,
//  toggle settings, and configure the challenge. Only accessible by admins.
//

import SwiftUI

struct PrivateChallengeAdminSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var service = PrivateChallengeService.shared
    
    let detail: PrivateChallengeDetail
    
    // Editable settings
    @State private var title: String
    @State private var description: String
    @State private var emoji: String
    @State private var dailyTarget: Int
    @State private var showLeaderboard: Bool
    @State private var allowMemberInvites: Bool
    @State private var notificationsEnabled: Bool
    @State private var maxMembers: Int
    
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    
    init(detail: PrivateChallengeDetail) {
        self.detail = detail
        _title = State(initialValue: detail.title)
        _description = State(initialValue: detail.description ?? "")
        _emoji = State(initialValue: detail.displayEmoji)
        _dailyTarget = State(initialValue: detail.dailyTarget)
        _showLeaderboard = State(initialValue: detail.showLeaderboard)
        _allowMemberInvites = State(initialValue: detail.allowMemberInvites)
        _notificationsEnabled = State(initialValue: detail.notificationsEnabled)
        _maxMembers = State(initialValue: detail.maxMembers ?? 50)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "gearshape.2.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                            
                            Text("Admin Settings")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Configure your private challenge")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        // Challenge Info Section
                        sectionCard(title: "Challenge Info") {
                            VStack(spacing: 16) {
                                // Title
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Challenge Name")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    TextField("Challenge name", text: $title)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .padding(Spacing.sm)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(10)
                                }
                                
                                // Description
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Description")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    TextField("Description (optional)", text: $description, axis: .vertical)
                                        .font(.body)
                                        .foregroundColor(.white)
                                        .lineLimit(2...4)
                                        .padding(Spacing.sm)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(10)
                                }
                            }
                        }
                        
                        // Goal Section
                        sectionCard(title: "Daily Goal") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Target")
                                        .font(.subheadline)
                                        .foregroundColor(.white.opacity(0.7))
                                    Spacer()
                                    
                                    HStack(spacing: 12) {
                                        Button(action: {
                                            let step = goalStep(for: detail.targetUnit)
                                            if dailyTarget > step { dailyTarget -= step }
                                            HapticManager.impact(.light)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.ds_heading2)
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                        
                                        Text("\(dailyTarget)")
                                            .font(.system(size: 22, weight: .bold, design: .rounded))
                                            .foregroundColor(.white)
                                            .frame(minWidth: 60)
                                        
                                        Button(action: {
                                            let step = goalStep(for: detail.targetUnit)
                                            dailyTarget += step
                                            HapticManager.impact(.light)
                                        }) {
                                            Image(systemName: "plus.circle.fill")
                                                .font(.ds_heading2)
                                                .foregroundColor(.purple)
                                        }
                                    }
                                }
                                
                                Text("\(dailyTarget) \(detail.targetUnit) per day")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.5))
                                
                                if dailyTarget != detail.dailyTarget {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.caption2)
                                        Text("Changing the goal will notify all members")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(.orange)
                                    .padding(.top, 4)
                                }
                            }
                        }
                        
                        // Settings Toggles
                        sectionCard(title: "Settings") {
                            VStack(spacing: 14) {
                                settingsRow(
                                    icon: "trophy.fill",
                                    iconColor: .yellow,
                                    title: "Show Leaderboard",
                                    subtitle: "Members can see rankings",
                                    toggle: $showLeaderboard
                                )
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                settingsRow(
                                    icon: "person.badge.plus",
                                    iconColor: .blue,
                                    title: "Allow Member Invites",
                                    subtitle: "Any member can invite others",
                                    toggle: $allowMemberInvites
                                )
                                
                                Divider().background(Color.white.opacity(0.1))
                                
                                settingsRow(
                                    icon: "bell.fill",
                                    iconColor: .orange,
                                    title: "Notifications",
                                    subtitle: "Send push notifications for milestones",
                                    toggle: $notificationsEnabled
                                )
                            }
                        }
                        
                        // Capacity
                        sectionCard(title: "Capacity") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Max Members")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Currently \(detail.memberCount) of \(maxMembers)")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                
                                Spacer()
                                
                                HStack(spacing: 12) {
                                    Button(action: {
                                        if maxMembers > max(detail.memberCount, 5) { maxMembers -= 5 }
                                        HapticManager.impact(.light)
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.ds_heading2)
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    
                                    Text("\(maxMembers)")
                                        .font(.ds_statSmall)
                                        .foregroundColor(.white)
                                        .frame(width: 40)
                                    
                                    Button(action: {
                                        if maxMembers < 500 { maxMembers += 5 }
                                        HapticManager.impact(.light)
                                    }) {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.ds_heading2)
                                            .foregroundColor(.purple)
                                    }
                                }
                            }
                        }
                        
                        // Challenge Stats (read-only)
                        sectionCard(title: "Stats") {
                            VStack(spacing: 10) {
                                statsRow(label: "Total Members", value: "\(detail.memberCount)")
                                statsRow(label: "Total Completions", value: "\(detail.totalCompletions)")
                                statsRow(label: "Today's Completion Rate", value: "\(Int(detail.completionRateToday * 100))%")
                                statsRow(label: "Pending Invites", value: "\(detail.pendingInvitesCount)")
                                statsRow(label: "Join Code", value: detail.joinCode)
                            }
                        }
                        
                        // Save Button
                        Button(action: { saveSettings() }) {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                        .scaleEffect(0.9)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.ds_heading3)
                                    Text("Save Changes")
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .shadow(color: .purple.opacity(0.4), radius: 12, x: 0, y: 6)
                        }
                        .disabled(isSaving)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Settings Saved! ✅", isPresented: $showSaveConfirmation) {
                Button("Done") { dismiss() }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white.opacity(0.4))
                .tracking(1)
            
            content()
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
    
    private func settingsRow(icon: String, iconColor: Color, title: String, subtitle: String, toggle: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
            
            Toggle("", isOn: toggle)
                .labelsHidden()
                .tint(.purple)
        }
    }
    
    private func statsRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
    
    private func goalStep(for unit: String) -> Int {
        switch unit.lowercased() {
        case "steps": return 1000
        case "minutes": return 5
        case "ml": return 100
        case "oz": return 4
        case "calories": return 50
        case "grams": return 10
        case "workouts": return 1
        case "hours": return 1
        default: return 1
        }
    }
    
    private func saveSettings() {
        isSaving = true
        Task {
            let success = await service.updateChallenge(
                challengeId: detail.challengeId,
                title: title != detail.title ? title : nil,
                description: description != (detail.description ?? "") ? description : nil,
                emoji: emoji != detail.displayEmoji ? emoji : nil,
                dailyTarget: dailyTarget != detail.dailyTarget ? dailyTarget : nil,
                allowMemberInvites: allowMemberInvites != detail.allowMemberInvites ? allowMemberInvites : nil,
                showLeaderboard: showLeaderboard != detail.showLeaderboard ? showLeaderboard : nil,
                notificationsEnabled: notificationsEnabled != detail.notificationsEnabled ? notificationsEnabled : nil,
                maxMembers: maxMembers != (detail.maxMembers ?? 50) ? maxMembers : nil
            )
            
            isSaving = false
            if success {
                showSaveConfirmation = true
            }
        }
    }
}
