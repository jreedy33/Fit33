//
//  CommunityChallengeViews.swift
//  Fit33
//
//  Community Challenge UI — Browse, Join, Leaderboard, Create
//  These open challenges let unlimited users compete on a real-time leaderboard.
//

import SwiftUI

// MARK: - Challenge Rules

/// A single rule line for a community challenge.
struct ChallengeRule: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

/// Generates clear, specific rules for each community challenge so members
/// know exactly what earns credit and how progress is tracked.
enum ChallengeRulesHelper {
    
    /// Returns full rules for a community challenge.
    static func rules(
        title: String,
        challengeType: String,
        dailyTarget: Int,
        targetUnit: String
    ) -> [ChallengeRule] {
        let slug = title.lowercased()
        
        // ── Official challenge-specific rules ──
        
        if slug.contains("lunchtime walk") {
            return [
                ChallengeRule(icon: "🎯", text: "Walk or run for \(dailyTarget)+ minutes"),
                ChallengeRule(icon: "⏰", text: "Activity between 12 PM – 3 PM"),
                ChallengeRule(icon: "🏃", text: "Walking & running workouts both count"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from Apple Health"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("morning walk") {
            return [
                ChallengeRule(icon: "🎯", text: "Walk \(dailyTarget.formatted()) steps before noon"),
                ChallengeRule(icon: "🌅", text: "Get your steps in first thing"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from iPhone & Apple Watch"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("no rest day") {
            return [
                ChallengeRule(icon: "🎯", text: "Complete at least 1 workout every day"),
                ChallengeRule(icon: "✅", text: "Any type — weights, cardio, yoga, HIIT, stretching"),
                ChallengeRule(icon: "📝", text: "Log your workout in the app to get credit"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("hydro homies") {
            let ozEquiv = Int(Double(dailyTarget) / 29.5735)
            return [
                ChallengeRule(icon: "🎯", text: "Drink at least \(dailyTarget) ml (\(ozEquiv) oz) of water"),
                ChallengeRule(icon: "💧", text: "Log each glass or bottle as you drink"),
                ChallengeRule(icon: "📝", text: "Manual tracking — tap + to log water"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("protein club") {
            return [
                ChallengeRule(icon: "🎯", text: "Hit \(dailyTarget)g of protein from meals"),
                ChallengeRule(icon: "🍗", text: "All logged meals & snacks count toward your total"),
                ChallengeRule(icon: "📝", text: "Log meals to track protein automatically"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("burn") && slug.contains("club") {
            return [
                ChallengeRule(icon: "🎯", text: "Burn \(dailyTarget)+ active calories through exercise"),
                ChallengeRule(icon: "✅", text: "Any workout or exercise counts"),
                ChallengeRule(icon: "📱", text: "Auto-synced from Apple Health"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        if slug.contains("30 min movement") || slug.contains("30-min") {
            return [
                ChallengeRule(icon: "🎯", text: "\(dailyTarget)+ minutes of any activity"),
                ChallengeRule(icon: "✅", text: "Walking, running, cycling, swimming — all movement counts"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from Apple Watch"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
        
        // ── Generic rules by challenge type ──
        
        switch challengeType {
        case "steps":
            return [
                ChallengeRule(icon: "🎯", text: "Walk \(dailyTarget.formatted()) steps in a day"),
                ChallengeRule(icon: "✅", text: "All steps count — walking, running, daily movement"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from iPhone & Apple Watch"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "hydrate":
            let unitDisplay = targetUnit.lowercased() == "oz"
                ? "\(dailyTarget) oz"
                : "\(dailyTarget) ml (\(Int(Double(dailyTarget) / 29.5735)) oz)"
            return [
                ChallengeRule(icon: "🎯", text: "Drink at least \(unitDisplay) of water"),
                ChallengeRule(icon: "💧", text: "Log each glass or bottle in the app"),
                ChallengeRule(icon: "📝", text: "Manual tracking — tap + to log water"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "protein":
            return [
                ChallengeRule(icon: "🎯", text: "Hit \(dailyTarget)g of protein from meals"),
                ChallengeRule(icon: "✅", text: "Protein from all logged meals & snacks counts"),
                ChallengeRule(icon: "📝", text: "Log your meals to track automatically"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "calories":
            return [
                ChallengeRule(icon: "🎯", text: "Burn \(dailyTarget)+ active calories"),
                ChallengeRule(icon: "✅", text: "Any exercise or workout counts"),
                ChallengeRule(icon: "📱", text: "Auto-synced from Apple Health"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "active_minutes":
            return [
                ChallengeRule(icon: "🎯", text: "\(dailyTarget)+ minutes of activity"),
                ChallengeRule(icon: "✅", text: "Walking, running, cycling — any movement counts"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from Apple Watch"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "walk":
            return [
                ChallengeRule(icon: "🎯", text: "Walk for \(dailyTarget)+ \(targetUnit)"),
                ChallengeRule(icon: "✅", text: "Walking & running workouts both count"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from activity data"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "run":
            return [
                ChallengeRule(icon: "🎯", text: "Run for \(dailyTarget)+ \(targetUnit)"),
                ChallengeRule(icon: "✅", text: "Outdoor & treadmill runs count"),
                ChallengeRule(icon: "📱", text: "Auto-tracked from activity data"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        case "workout_streak":
            return [
                ChallengeRule(icon: "🎯", text: "Complete at least \(dailyTarget) workout\(dailyTarget > 1 ? "s" : "")"),
                ChallengeRule(icon: "✅", text: "Any type — weights, cardio, yoga, HIIT"),
                ChallengeRule(icon: "📝", text: "Log your workout in the app"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        default:
            return [
                ChallengeRule(icon: "🎯", text: "Hit \(dailyTarget) \(targetUnit) daily"),
                ChallengeRule(icon: "🔄", text: "Resets daily at midnight"),
            ]
        }
    }
    
    /// Compact 1-line summary for widgets and small cards.
    static func compactSummary(
        title: String,
        challengeType: String,
        dailyTarget: Int,
        targetUnit: String
    ) -> String {
        let slug = title.lowercased()
        
        if slug.contains("lunchtime walk") {
            return "\(dailyTarget) min walk/run · 12–3 PM · Auto-tracked"
        }
        if slug.contains("morning walk") {
            return "\(dailyTarget.formatted()) steps before noon · Auto-tracked"
        }
        
        switch challengeType {
        case "steps":
            return "\(dailyTarget.formatted()) steps daily · Auto-tracked"
        case "hydrate":
            return "\(dailyTarget) \(targetUnit) water daily · Log in app"
        case "protein":
            return "\(dailyTarget)g protein daily · Log meals"
        case "calories":
            return "\(dailyTarget) cal burned daily · Auto-tracked"
        case "active_minutes":
            return "\(dailyTarget) min active daily · Auto-tracked"
        case "walk":
            return "\(dailyTarget) min walking daily · Auto-tracked"
        case "run":
            return "\(dailyTarget) min running daily · Auto-tracked"
        case "workout_streak":
            return "\(dailyTarget) workout\(dailyTarget > 1 ? "s" : "") daily · Log in app"
        default:
            return "\(dailyTarget) \(targetUnit) daily"
        }
    }
}

/// Full rules card shown on the community challenge detail page.
struct ChallengeRulesCard: View {
    let rules: [ChallengeRule]
    let themeColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.ds_labelMedium)
                    .foregroundColor(themeColor)
                Text("Challenge Rules")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(rules) { rule in
                    HStack(alignment: .top, spacing: 8) {
                        Text(rule.icon)
                            .font(.ds_bodySmall)
                            .frame(width: 20)
                        Text(rule.text)
                            .font(.caption)
                            .foregroundColor(colorScheme == .dark ? .secondary : Color(white: 0.35))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [themeColor.opacity(0.08), themeColor.opacity(0.03), Color(white: 0.08)]
                                : [themeColor.opacity(0.05), themeColor.opacity(0.02), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: themeColor.opacity(colorScheme == .dark ? 0.08 : 0.04), location: 0),
                                .init(color: .clear, location: 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.15 : 0.10), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [themeColor.opacity(0.35), themeColor.opacity(0.10)]
                            : [themeColor.opacity(0.20), themeColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

/// Compact rules summary line for widgets and small cards.
struct CompactRulesLine: View {
    let title: String
    let challengeType: String
    let dailyTarget: Int
    let targetUnit: String
    let themeColor: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(themeColor.opacity(0.5))
            Text(ChallengeRulesHelper.compactSummary(
                title: title,
                challengeType: challengeType,
                dailyTarget: dailyTarget,
                targetUnit: targetUnit
            ))
                .font(.ds_labelSmall)
                .foregroundColor(themeColor.opacity(0.6))
                .lineLimit(1)
        }
    }
}

// MARK: - Community Challenges Hub

struct CommunityChallengesHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = CommunityChallengeService.shared
    @State private var selectedTab = 1  // 0 = My Challenges, 1 = Discover
    @State private var showingCreate = false
    @State private var showingJoinByCode = false
    @State private var joinCode = ""
    @State private var showPrivateJoinSheet = false
    @State private var pendingPrivateJoinCode = ""
    @State private var showCommunityJoinSheet = false
    @State private var pendingCommunityJoinCode = ""
    @State private var selectedChallenge: CommunityChallenge?
    @State private var selectedFeatured: FeaturedCommunityChallenge?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab selector
                    HStack(spacing: 0) {
                        tabButton(title: "My Challenges", index: 0)
                        tabButton(title: "Discover", index: 1)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 8)
                    
                    // Content
                    ScrollView {
                        if selectedTab == 0 {
                            myChallengesContent
                        } else {
                            discoverContent
                        }
                    }
                    .refreshable {
                        await service.refreshAll(force: true)
                    }
                }
            }
            .navigationTitle("Community Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: { showingCreate = true }) {
                            Label("Create Challenge", systemImage: "plus.circle")
                        }
                        Button(action: { showingJoinByCode = true }) {
                            Label("Join by Code", systemImage: "qrcode")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.ds_heading3)
                    }
                }
            }
            .task {
                await service.fetchMyChallenges()
                await service.fetchFeaturedChallenges()
            }
            .onAppear {
                service.markCommunityViewVisible()
            }
            .onDisappear {
                service.markCommunityViewHidden()
            }
            .sheet(isPresented: $showingCreate) {
                CommunityCreateChallengeView()
            }
            .alert("Join by Code", isPresented: $showingJoinByCode) {
                TextField("Enter 6-digit code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button("Cancel", role: .cancel) { joinCode = "" }
                Button("Next") {
                    let code = joinCode
                    joinCode = ""
                    Task {
                        // Try community challenge lookup first
                        let communityPreview = await service.lookupChallenge(code: code)
                        if communityPreview != nil {
                            await MainActor.run {
                                pendingCommunityJoinCode = code
                                showCommunityJoinSheet = true
                            }
                            return
                        }
                        
                        // If not found as community, try private challenge lookup
                        let privatePreview = await PrivateChallengeService.shared.lookupByCode(code: code)
                        await MainActor.run {
                            if privatePreview != nil {
                                pendingPrivateJoinCode = code
                                showPrivateJoinSheet = true
                            } else {
                                // Neither found — show private join sheet which will show "not found"
                                pendingPrivateJoinCode = code
                                showPrivateJoinSheet = true
                            }
                        }
                    }
                }
            } message: {
                Text("Enter the challenge join code shared with you.")
            }
            .sheet(isPresented: $showPrivateJoinSheet) {
                PrivateChallengeJoinSheet(code: pendingPrivateJoinCode)
            }
            .sheet(isPresented: $showCommunityJoinSheet) {
                CommunityJoinSheet(codeOrSlug: pendingCommunityJoinCode)
            }
            .navigationDestination(item: $selectedChallenge) { challenge in
                CommunityDetailView(challengeId: challenge.challengeId, challengeTitle: challenge.title)
            }
        }
    }
    
    private func tabButton(title: String, index: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.3)) { selectedTab = index }
        }) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(selectedTab == index ? .bold : .medium)
                    .foregroundColor(selectedTab == index ? .primary : .secondary)
                
                Rectangle()
                    .fill(selectedTab == index ? Color.blue : Color.clear)
                    .frame(height: 2)
                    .cornerRadius(1)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }
    
    // MARK: - My Challenges Tab
    
    private var myChallengesContent: some View {
        LazyVStack(spacing: 16) {
            if service.myChallenges.isEmpty {
                emptyChallengesCard
            } else {
                ForEach(service.myChallenges) { challenge in
                    Button {
                        selectedChallenge = challenge
                    } label: {
                        CommunityLeaderboardWidget(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 16)
        .padding(.bottom, 40)
    }
    
    private var emptyChallengesCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 48))
                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text("No Community Challenges Yet")
                .font(.title3)
                .fontWeight(.bold)
            
            Text("Join a community challenge to compete on a global leaderboard with thousands of Fit33 users!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: { selectedTab = 1 }) {
                Text("Browse Challenges")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
    }
    
    // MARK: - Discover Tab
    
    private var discoverContent: some View {
        VStack(spacing: 16) {
            // ── Recommended For You (top 2 friend-populated communities) ──
            let recommendedChallenges = Array(service.discoverableChallenges.prefix(2))
            if !recommendedChallenges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Recommended for You", emoji: "⭐")
                    Text("Communities your friends are crushing — join them!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    ForEach(recommendedChallenges) { fc in
                        FriendDiscoveryCard(challenge: fc) {
                            Task {
                                let _ = await service.joinChallengeFriendGated(challengeId: fc.id)
                            }
                        }
                    }
                }
            }
            
            // ── Friends' Communities (remaining, after the top 2) ──
            let remainingFriendChallenges = Array(service.discoverableChallenges.dropFirst(2))
            if !remainingFriendChallenges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Friends' Communities", emoji: "👥")
                    
                    ForEach(remainingFriendChallenges) { fc in
                        FriendDiscoveryCard(challenge: fc) {
                            Task {
                                let _ = await service.joinChallengeFriendGated(challengeId: fc.id)
                            }
                        }
                    }
                }
            }
            
            if service.featuredChallenges.isEmpty && service.discoverableChallenges.isEmpty {
                ProgressView()
                    .padding(.top, 40)
            } else {
                // Official challenges — only show ones the user hasn't joined yet
                let official = service.featuredChallenges.filter { $0.isOfficial && !$0.alreadyJoined }
                if !official.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Official Fit33 Challenges", emoji: "🏅")
                        ForEach(official) { challenge in
                            FeaturedChallengeCard(challenge: challenge) {
                                Task {
                                    let _ = await service.joinChallenge(code: challenge.joinCode)
                                    await service.fetchFeaturedChallenges()
                                }
                            }
                        }
                    }
                }
                
                // Community created — only show ones the user hasn't joined yet
                let community = service.featuredChallenges.filter { !$0.isOfficial && !$0.alreadyJoined }
                if !community.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionHeader("Community Created", emoji: "🌍")
                        ForEach(community) { challenge in
                            FeaturedChallengeCard(challenge: challenge) {
                                Task {
                                    let _ = await service.joinChallenge(code: challenge.joinCode)
                                    await service.fetchFeaturedChallenges()
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 16)
        .padding(.bottom, 40)
        .task {
            await service.fetchDiscoverableChallenges()
        }
    }
    
    private func sectionHeader(_ title: String, emoji: String) -> some View {
        HStack {
            Text("\(emoji) \(title)")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.top, 8)
    }
}

// MARK: - Community Leaderboard Widget (Mini)
/// The star of the show: a compact leaderboard card that shows top 5-10
/// members with their progress, streaks, and your rank at a glance.

struct CommunityLeaderboardWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var communityService = CommunityChallengeService.shared
    @ObservedObject private var progressResolver = ChallengeProgressResolver.shared
    let challenge: CommunityChallenge
    
    private var themeColor: Color { resolvedType.color }
    private var themeGradient: [Color] { resolvedType.gradientColors }
    
    private var resolvedType: ChallengeType {
        challenge.resolvedType
    }
    
    /// Live "my today" progress — uses local HealthKit/tracking data so the widget
    /// shows current values immediately, even before the server has been synced.
    private var liveMyTodayProgress: Int {
        progressResolver.liveProgress(for: challenge)
    }
    
    /// Whether today's target is hit based on live data
    private var liveTargetHitToday: Bool {
        liveMyTodayProgress >= challenge.dailyTarget
    }
    
    /// Live progress percentage (0.0–1.0) based on local data
    private var liveProgressPercentage: Double {
        progressResolver.progressPercentage(for: challenge)
    }
    
    private var topEntries: [LeaderboardSnippetEntry] {
        let entries = challenge.topParticipants ?? []
        return Array(entries.prefix(challenge.leaderboardDisplayCount))
    }
    
    private var friendAvatars: [CommunityFriendInfo] {
        challenge.friendsIn ?? []
    }
    
    /// Rank deltas for this specific challenge
    private var challengeDeltas: [UUID: Int] {
        communityService.rankDeltas[challenge.challengeId] ?? [:]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Header: Challenge identity + your rank ──
            challengeHeader
            
            // ── Compact rules summary ──
            CompactRulesLine(
                title: challenge.title,
                challengeType: challenge.challengeType,
                dailyTarget: challenge.dailyTarget,
                targetUnit: challenge.targetUnit,
                themeColor: themeColor
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 8)
            
            // ── Friends in this community (avatar row) ──
            if !friendAvatars.isEmpty {
                friendsRow
            }
            
            // ── Your stats banner ──
            myStatsBanner
            
            // ── Mini leaderboard rows ──
            if !topEntries.isEmpty {
                miniLeaderboard
            } else {
                emptyLeaderboardPlaceholder
            }
            
            // ── Footer: See full leaderboard ──
            footerBar
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 6)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 3)
                
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.14), Color(white: 0.09)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                themeColor.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                themeGradient.last?.opacity(colorScheme == .dark ? 0.3 : 0.2) ?? themeColor.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: themeColor.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        .animation(.default, value: challenge.myTodayProgress)
        .animation(.default, value: challenge.myRank)
    }
    
    // MARK: - Challenge Header
    
    private var challengeHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                    .frame(width: 40, height: 40)
                Text(challenge.displayEmoji)
                    .font(.ds_heading3)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if challenge.isOfficial {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundColor(themeColor)
                    }
                }
                
                HStack(spacing: 8) {
                    Label("\(challenge.formattedParticipantCount)", systemImage: "person.2.fill")
                        .font(.caption2)
                        .foregroundColor(themeColor.opacity(0.7))
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(themeColor.opacity(0.3))
                    
                    Text("\(challenge.dailyTarget) \(challenge.targetUnit)/day")
                        .font(.caption2)
                        .foregroundColor(themeColor.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Rank badge
            if let rank = challenge.myRank, rank > 0 {
                VStack(spacing: 1) {
                    Text(rankEmoji(for: rank) ?? "#\(rank)")
                        .font(rankEmoji(for: rank) != nil ? .system(size: 20) : .system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            rank <= 3
                                ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                        .contentTransition(.numericText())
                    Text("rank")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
    
    // MARK: - Friends Row
    
    private var friendsRow: some View {
        HStack(spacing: 6) {
            // Overlapping friend avatars (with photos)
            HStack(spacing: -8) {
                ForEach(Array(friendAvatars.prefix(5).enumerated()), id: \.element.userId) { index, friend in
                    friendAvatarCircle(friend: friend, index: index, size: 28)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 2)
                        )
                        .zIndex(Double(5 - index))
                }
            }
            
            if friendAvatars.count <= 3 {
                Text(friendAvatars.map { $0.displayName.components(separatedBy: " ").first ?? $0.displayName }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(friendAvatars.count) friends in this community")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, 8)
    }
    
    /// Friend avatar with photo support — cached for instant loading
    private func friendAvatarCircle(friend: CommunityFriendInfo, index: Int, size: CGFloat) -> some View {
        CachedFriendPhoto(
            friendId: friend.userId.uuidString,
            photoUrl: friend.profilePhotoUrl,
            name: friend.displayName,
            size: size,
            showGradientRing: false,
            gradientColors: friendGradient(for: index)
        )
    }
    
    private func friendInitialCircle(friend: CommunityFriendInfo, index: Int, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(avatarColor(for: index))
                .frame(width: size, height: size)
            Text(friendInitial(friend.displayName))
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private func friendInitial(_ name: String) -> String {
        String(name.prefix(1)).uppercased()
    }
    
    private func avatarColor(for index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal]
        return colors[index % colors.count]
    }
    
    private func friendGradient(for index: Int) -> [Color] {
        let gradients: [[Color]] = [
            [.blue, .cyan], [.purple, .pink], [.pink, .orange], [.orange, .yellow], [.teal, .green]
        ]
        return gradients[index % gradients.count]
    }
    
    // MARK: - My Stats Banner
    
    private var myStatsBanner: some View {
        HStack(spacing: 0) {
            // Today's progress (live from HealthKit / tracking services)
            statPill(
                value: progressResolver.formattedProgress(for: challenge),
                label: "today",
                valueColor: liveTargetHitToday ? themeColor : .primary,
                icon: liveTargetHitToday ? "checkmark.circle.fill" : nil,
                iconColor: themeColor
            )
            
            dividerLine
            
            // Days completed
            statPill(
                value: "\(challenge.myDaysCompleted ?? 0)",
                label: "days",
                valueColor: .primary
            )
            
            dividerLine
            
            // Current streak
            statPill(
                value: "\(challenge.myCurrentStreak ?? 0)",
                label: "streak",
                valueColor: (challenge.myCurrentStreak ?? 0) > 0 ? .orange : .primary,
                icon: (challenge.myCurrentStreak ?? 0) > 0 ? "flame.fill" : nil,
                iconColor: .orange
            )
            
            dividerLine
            
            // Best streak
            statPill(
                value: "\(challenge.myBestStreak ?? 0)",
                label: "best",
                valueColor: .secondary
            )
        }
        .padding(.vertical, Spacing.xs)
        .padding(.horizontal, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(themeColor.opacity(colorScheme == .dark ? 0.10 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.08), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, 8)
    }
    
    private func statPill(value: String, label: String, valueColor: Color, icon: String? = nil, iconColor: Color = .clear) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.ds_caption)
                        .foregroundColor(iconColor)
                }
                Text(value)
                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(valueColor)
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var dividerLine: some View {
        Rectangle()
            .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.12))
            .frame(width: 1, height: 28)
    }
    
    // MARK: - Mini Leaderboard
    
    private var miniLeaderboard: some View {
        VStack(spacing: 0) {
            // Column headers — clean spacing aligned with row content
            HStack(spacing: 0) {
                Text("MEMBER")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(themeColor.opacity(0.5))
                    .textCase(.uppercase)
                
                Spacer()
                
                Text("TODAY")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(themeColor.opacity(0.5))
                    .textCase(.uppercase)
                    .frame(width: 52, alignment: .trailing)
                
                Text("STREAK")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(themeColor.opacity(0.5))
                    .textCase(.uppercase)
                    .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            ForEach(Array(topEntries.enumerated()), id: \.element.id) { index, entry in
                let delta = challengeDeltas[entry.userId] ?? 0
                miniLeaderboardRow(entry: entry, rankDelta: delta, isLast: index == topEntries.count - 1)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeColor.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, 6)
    }
    
    private func miniLeaderboardRow(entry: LeaderboardSnippetEntry, rankDelta: Int, isLast: Bool) -> some View {
        let isMe = entry.isCurrentUser
        // Use live HealthKit/tracking data for current user so the widget
        // shows real-time local values instead of stale DB data.
        // For other members, show DB-reported todayProgress (updated via realtime).
        let displayProgress = isMe ? liveMyTodayProgress : entry.todayProgress
        let displayTargetHit = isMe ? liveTargetHitToday : entry.targetHitToday
        
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                // Rank badge + delta arrow
                HStack(spacing: 1) {
                    // Rank change arrow (green ▲ / red ▼)
                    if rankDelta > 0 {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.green)
                            .transition(.scale.combined(with: .opacity))
                    } else if rankDelta < 0 {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.red)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Group {
                        if let emoji = rankEmoji(for: entry.rank) {
                            Text(emoji)
                                .font(.ds_bodySmall)
                        } else {
                            Text("\(entry.rank)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                }
                .frame(width: rankDelta != 0 ? 30 : 20, alignment: .center)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: rankDelta)
                
                // Avatar (cached)
                CachedFriendPhoto(
                    friendId: entry.userId.uuidString,
                    photoUrl: entry.profilePhotoUrl,
                    name: entry.displayName,
                    size: 22,
                    showGradientRing: false,
                    gradientColors: isMe ? [resolvedType.color, resolvedType.color.opacity(0.7)] : [.gray.opacity(0.4), .gray.opacity(0.3)]
                )
                
                // Name
                HStack(spacing: 3) {
                    Text(entry.firstName)
                        .font(.system(size: 12, weight: isMe ? .bold : .medium))
                        .foregroundColor(isMe ? resolvedType.color : .primary)
                        .lineLimit(1)
                    
                    if entry.isVerified == true || entry.isGoldVerified == true {
                        VerifiedBadge(size: 10, isGold: entry.isGoldVerified == true)
                    }
                    
                    if isMe {
                        Text("you")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(resolvedType.color.opacity(0.7))
                    }
                }
                
                Spacer()
                
                // Today's progress (live for current user, DB for others)
                HStack(spacing: 2) {
                    Text(!isMe && displayProgress == 0 ? "–" : "\(displayProgress)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(!isMe && displayProgress == 0 ? .secondary.opacity(0.5) : (displayTargetHit ? themeColor : .primary))
                        .contentTransition(.numericText())
                    
                    if displayTargetHit {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(themeColor)
                    }
                }
                .frame(width: 52, alignment: .trailing)
                
                // Streak
                HStack(spacing: 2) {
                    if entry.currentStreak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                    Text(entry.currentStreak > 0 ? "\(entry.currentStreak)" : "-")
                        .font(.system(size: 11, weight: entry.currentStreak > 0 ? .bold : .regular, design: .rounded))
                        .foregroundColor(entry.currentStreak > 0 ? .orange : .secondary.opacity(0.5))
                }
                .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isMe
                    ? RoundedRectangle(cornerRadius: 6).fill(resolvedType.color.opacity(colorScheme == .dark ? 0.10 : 0.05))
                    : RoundedRectangle(cornerRadius: 6).fill(Color.clear)
            )
            
            if !isLast {
                Rectangle()
                    .fill(themeColor.opacity(colorScheme == .dark ? 0.06 : 0.04))
                    .frame(height: 0.5)
                    .padding(.horizontal, 10)
            }
        }
    }
    
    private func avatarPlaceholder(initial: String, isMe: Bool) -> some View {
        Circle()
            .fill(
                isMe
                    ? LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 22, height: 22)
            .overlay(
                Text(initial)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isMe ? .white : .secondary)
            )
    }
    
    private var emptyLeaderboardPlaceholder: some View {
        HStack {
            Image(systemName: "chart.bar.fill")
                .font(.ds_bodySmall)
                .foregroundColor(themeColor.opacity(0.35))
            Text("Leaderboard updates as members log progress")
                .font(.caption2)
                .foregroundColor(themeColor.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(themeColor.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, 6)
    }
    
    // MARK: - Footer
    
    private var footerBar: some View {
        HStack {
            // Progress bar (today) — uses live local data
            let progressPct = liveProgressPercentage
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: themeGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progressPct, height: 4)
                        .shadow(color: themeColor.opacity(0.4), radius: 3, x: 0, y: 1)
                }
            }
            .frame(height: 4)
            
            Text("\(Int(progressPct * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(themeColor)
                .contentTransition(.numericText())
                .frame(width: 32, alignment: .trailing)
            
            Image(systemName: "chevron.right")
                .font(.ds_caption).fontWeight(.semibold)
                .foregroundColor(themeColor.opacity(0.5))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [themeColor.opacity(colorScheme == .dark ? 0.06 : 0.03), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(themeColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .frame(height: 0.5)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0, bottomLeadingRadius: 20,
                bottomTrailingRadius: 20, topTrailingRadius: 0
            )
        )
    }
    
    // MARK: - Helpers
    
    private func rankEmoji(for rank: Int) -> String? {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }
}


// MARK: - Featured Challenge Card (Discover Tab)

struct FeaturedChallengeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let challenge: FeaturedCommunityChallenge
    let onJoin: () -> Void
    
    private var tc: Color { challenge.resolvedType.color }
    private var tg: [Color] { challenge.resolvedType.gradientColors }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors: tg, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
                        .frame(width: 44, height: 44)
                    Text(challenge.displayEmoji)
                        .font(.ds_heading2)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(challenge.title)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if challenge.isOfficial {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundColor(tc)
                        }
                    }
                    
                    if let desc = challenge.description {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
            }
            
            // Compact rules
            CompactRulesLine(
                title: challenge.title,
                challengeType: challenge.challengeType,
                dailyTarget: challenge.dailyTarget,
                targetUnit: challenge.targetUnit,
                themeColor: tc
            )
            .padding(.bottom, 2)
            
            // Stats row
            HStack(spacing: 16) {
                Label("\(challenge.formattedParticipantCount) members", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(tc.opacity(0.7))
                
                Label("\(challenge.dailyTarget) \(challenge.targetUnit)/day", systemImage: "target")
                    .font(.caption)
                    .foregroundColor(tc.opacity(0.7))
                
                Spacer()
                
                if challenge.alreadyJoined {
                    Text("Joined")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(tc)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(tc.opacity(0.15))
                        )
                } else {
                    Button(action: onJoin) {
                        Text("Join")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(colors: tg, startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                            .shadow(color: tc.opacity(0.35), radius: 4, x: 0, y: 2)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [tc.opacity(0.08), tc.opacity(0.03), Color(white: 0.08)]
                                : [tc.opacity(0.05), tc.opacity(0.02), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tc.opacity(colorScheme == .dark ? 0.08 : 0.05), location: 0),
                                .init(color: .clear, location: 0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: tc.opacity(colorScheme == .dark ? 0.18 : 0.12), radius: 10, x: 0, y: 5)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.04), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [tc.opacity(0.40), tc.opacity(0.10)]
                            : [tc.opacity(0.25), tc.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}


// MARK: - Community Leaderboard View (Full)

struct CommunityLeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = CommunityChallengeService.shared
    @ObservedObject private var progressResolver = ChallengeProgressResolver.shared
    
    let challengeId: UUID
    let initialTitle: String
    
    @State private var leaderboard: CommunityLeaderboardResponse?
    @State private var isLoading = true
    @State private var showingShare = false
    @State private var showingLeave = false
    @State private var showingProfile: ProfileUser?
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: colorScheme == .dark
                    ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                    : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
            } else if let lb = leaderboard {
                ScrollView {
                    VStack(spacing: 20) {
                        // Challenge info header
                        challengeHeader(lb)
                        
                        // My rank card (enriched)
                        myRankCard(lb)
                        
                        // Share/Invite banner
                        shareBanner(lb)
                        
                        // Full leaderboard list
                        leaderboardList(lb)
                        
                        // Leave button
                        leaveButton
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(initialTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingShare = true }) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .task {
            await loadLeaderboard()
        }
        .refreshable {
            await loadLeaderboard()
        }
        .sheet(isPresented: $showingShare) {
            if let lb = leaderboard,
               let url = URL(string: "https://fit33.app/c/\(lb.inviteSlug)") {
                ShareLink(
                    item: url,
                    subject: Text(lb.challengeTitle),
                    message: Text("Join me on the \(lb.challengeTitle) challenge on Fit33! \(lb.participantCount) people are in. Can you beat me?")
                ) {
                    Text("Share Challenge")
                }
            }
        }
        .alert("Leave Challenge?", isPresented: $showingLeave) {
            Button("Keep", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task {
                    let _ = await service.leaveChallenge(challengeId: challengeId)
                    dismiss()
                }
            }
        } message: {
            Text("You can always rejoin later.")
        }
        .sheet(item: $showingProfile) { profileUser in
            NavigationStack {
                FriendProfileView(user: profileUser)
            }
        }
    }
    
    private func loadLeaderboard() async {
        leaderboard = await service.getLeaderboard(challengeId: challengeId, limit: 50)
        isLoading = false
    }
    
    // MARK: - Challenge Header
    
    private func challengeHeader(_ lb: CommunityLeaderboardResponse) -> some View {
        VStack(spacing: 8) {
            Text(lb.challengeEmoji ?? "🌍")
                .font(.system(size: 48))
            
            Text(lb.challengeTitle)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Label("\(lb.participantCount) members", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(lb.dailyTarget) \(lb.targetUnit)/day", systemImage: "target")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Join code pill
            HStack(spacing: 6) {
                Text("Code: \(lb.joinCode)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Image(systemName: "doc.on.doc")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.1))
            )
            .onTapGesture {
                UIPasteboard.general.string = lb.joinCode
                HapticManager.notification(.success)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: 20, accentColor: .blue)
    }
    
    // MARK: - My Rank Card (Enriched)
    
    private func myRankCard(_ lb: CommunityLeaderboardResponse) -> some View {
        HStack(spacing: 0) {
            // Rank
            VStack(spacing: 2) {
                Text("#\(lb.myRank)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: lb.myRank <= 3 ? [.yellow, .orange] : [.primary, .primary.opacity(0.8)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .contentTransition(.numericText())
                Text("Rank")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            dividerLine(height: 40)
            
            // Today's progress (live from HealthKit / tracking)
            VStack(spacing: 2) {
                Text("\(progressResolver.liveProgress(for: lb))")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(progressResolver.targetHitToday(for: lb) ? .green : .primary)
                    .contentTransition(.numericText())
                Text("Today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            dividerLine(height: 40)
            
            // Days completed
            VStack(spacing: 2) {
                Text("\(lb.myDaysCompleted)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("Days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            dividerLine(height: 40)
            
            // Streak
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text("\(lb.myCurrentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Image(systemName: "flame.fill")
                        .font(.ds_bodySmall)
                        .foregroundColor(.orange)
                }
                Text("Streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            
            dividerLine(height: 40)
            
            // Best streak
            VStack(spacing: 2) {
                Text("\(lb.myBestStreak)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .contentTransition(.numericText())
                Text("Best")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 16, accentColor: .blue)
    }
    
    private func dividerLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 1, height: height)
    }
    
    // MARK: - Share Banner
    
    private func shareBanner(_ lb: CommunityLeaderboardResponse) -> some View {
        Button(action: { showingShare = true }) {
            HStack(spacing: 12) {
                Image(systemName: "megaphone.fill")
                    .font(.ds_heading3)
                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Invite Friends")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Share this challenge and grow the leaderboard!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color.blue.opacity(0.1) : Color.blue.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Full Leaderboard List
    
    private func leaderboardList(_ lb: CommunityLeaderboardResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Leaderboard")
                    .font(.headline)
                
                Spacer()
                
                Text("\(lb.leaderboard?.count ?? 0) of \(lb.participantCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let entries = lb.leaderboard, !entries.isEmpty {
                // Column headers
                HStack(spacing: 0) {
                    Text("")
                        .frame(width: 36)
                    Text("")
                        .frame(width: 40)
                    Text("Member")
                        .font(.ds_caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.leading, 8)
                    Spacer()
                    Text("Today")
                        .font(.ds_caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .frame(width: 55, alignment: .trailing)
                    Text("Days")
                        .font(.ds_caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .frame(width: 40, alignment: .trailing)
                    Text("Streak")
                        .font(.ds_caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .frame(width: 48, alignment: .trailing)
                }
                .padding(.horizontal, 14)
                
                VStack(spacing: 0) {
                    let deltas = service.rankDeltas[lb.challengeId] ?? [:]
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        let isMe = entry.isCurrentUser ?? (entry.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString)
                        Button {
                            guard !isMe else { return }
                            showingProfile = ProfileUser(communityEntry: entry)
                        } label: {
                            fullLeaderboardRow(
                                entry: entry,
                                dailyTarget: lb.dailyTarget,
                                targetUnit: lb.targetUnit,
                                isCurrentUser: isMe,
                                rankDelta: deltas[entry.userId] ?? 0
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if index < entries.count - 1 {
                            Divider()
                                .padding(.leading, 76)
                                .padding(.trailing, 14)
                                .opacity(0.5)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                )
            } else {
                Text("No leaderboard data yet. Be the first to log progress!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.cardBackground)
                    )
            }
        }
    }
    
    private func fullLeaderboardRow(entry: CommunityLeaderboardEntry, dailyTarget: Int, targetUnit: String, isCurrentUser: Bool, rankDelta: Int = 0) -> some View {
        HStack(spacing: 0) {
            // Rank + delta arrow
            HStack(spacing: 2) {
                if rankDelta > 0 {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                        .transition(.scale.combined(with: .opacity))
                } else if rankDelta < 0 {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                        .transition(.scale.combined(with: .opacity))
                }
                
                Group {
                    switch entry.rank {
                    case 1: Text("🥇").font(.ds_heading3)
                    case 2: Text("🥈").font(.ds_heading3)
                    case 3: Text("🥉").font(.ds_heading3)
                    default:
                        Text("#\(entry.rank)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            .frame(width: rankDelta != 0 ? 44 : 36, alignment: .center)
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: rankDelta)
            
            // Avatar (cached)
            CachedFriendPhoto(
                friendId: entry.userId.uuidString,
                photoUrl: entry.profilePhotoUrl,
                name: entry.displayName,
                size: 36,
                showGradientRing: false,
                gradientColors: isCurrentUser ? [.blue, .purple] : [.gray.opacity(0.3), .gray.opacity(0.2)]
            )
            
            // Name + streak detail
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.firstName)
                        .font(.subheadline)
                        .fontWeight(isCurrentUser ? .bold : .medium)
                        .foregroundColor(isCurrentUser ? .blue : .primary)
                    
                    if entry.isVerified == true || entry.isGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: entry.isGoldVerified == true)
                    }
                    
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                if entry.currentStreak > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.orange)
                        Text("\(entry.currentStreak) day streak")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                        if let best = entry.bestStreak, best > entry.currentStreak {
                            Text("(best: \(best))")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.leading, 8)
            
            Spacer()
            
            // Today's progress
            HStack(spacing: 3) {
                Text(!isCurrentUser && entry.todayProgress == 0 ? "–" : "\(entry.todayProgress)")
                    .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                    .foregroundColor(!isCurrentUser && entry.todayProgress == 0 ? .secondary.opacity(0.5) : (entry.targetHitToday ? .green : .primary))
                    .contentTransition(.numericText())
                
                if entry.targetHitToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_bodySmall)
                        .foregroundColor(.green)
                }
            }
            .frame(width: 55, alignment: .trailing)
            
            // Days
            Text("\(entry.daysCompleted)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            
            // Streak
            HStack(spacing: 2) {
                if entry.currentStreak > 0 {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                }
                Text(entry.currentStreak > 0 ? "\(entry.currentStreak)" : "-")
                    .font(.system(size: 13, weight: entry.currentStreak > 0 ? .bold : .regular, design: .rounded))
                    .foregroundColor(entry.currentStreak > 0 ? .orange : .secondary.opacity(0.5))
            }
            .frame(width: 48, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isCurrentUser
                ? RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(colorScheme == .dark ? 0.1 : 0.05))
                : RoundedRectangle(cornerRadius: 10).fill(Color.clear)
        )
    }
    
    // MARK: - Leave Button
    
    private var leaveButton: some View {
        Button(action: { showingLeave = true }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                    .font(.ds_bodyRegular)
                Text("Leave Challenge")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.1 : 0.05))
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}


// MARK: - Create Community Challenge View

struct CommunityCreateChallengeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var title = ""
    @State private var description = ""
    @State private var selectedType: ChallengeActivityType = .steps
    @State private var dailyTarget = 10000
    @State private var emoji = "🌍"
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var createdJoinCode = ""
    @State private var createdSlug = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Title
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Challenge Name")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            TextField("e.g. 10K Steps Daily", text: $title)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        // Description
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description (optional)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            TextField("What's this challenge about?", text: $description, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(3)
                        }
                        
                        // Activity type
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Activity Type")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                                ForEach(ChallengeActivityType.allCases, id: \.self) { type in
                                    Button(action: {
                                        selectedType = type
                                        dailyTarget = defaultTarget(for: type)
                                        HapticManager.impact(.light)
                                    }) {
                                        VStack(spacing: 4) {
                                            Text(type.emoji)
                                                .font(.ds_heading2)
                                            Text(type.rawValue)
                                                .font(.ds_caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(selectedType == type ? .white : .primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Spacing.xs)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10)
                                                .fill(selectedType == type
                                                    ? LinearGradient(colors: type.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                                                    : LinearGradient(colors: [Color.gray.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        
                        // Daily target
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Daily Target")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            HStack {
                                Button(action: {
                                    if dailyTarget > 1 { dailyTarget -= stepAmount(for: selectedType) }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.ds_heading1)
                                        .foregroundColor(.blue)
                                }
                                
                                Spacer()
                                
                                VStack(spacing: 2) {
                                    Text("\(dailyTarget)")
                                        .font(.system(size: 32, weight: .bold, design: .rounded))
                                    Text(unitLabel(for: selectedType))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    dailyTarget += stepAmount(for: selectedType)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.ds_heading1)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                            )
                        }
                        
                        // Create button
                        Button(action: { Task { await createChallenge() } }) {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: "globe.americas.fill")
                                    Text("Create Community Challenge")
                                        .fontWeight(.bold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(14)
                        }
                        .disabled(title.isEmpty || isCreating)
                        .opacity(title.isEmpty ? 0.5 : 1)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Challenge Created! 🌍", isPresented: $showingSuccess) {
                Button("Share") {
                    // Copy join code
                    UIPasteboard.general.string = createdJoinCode
                    dismiss()
                }
                Button("Done") { dismiss() }
            } message: {
                Text("Your community challenge is live! Share code \(createdJoinCode) with friends, or share the link: fit33.app/c/\(createdSlug)")
            }
        }
    }
    
    private func createChallenge() async {
        isCreating = true
        
        let id = await CommunityChallengeService.shared.createChallenge(
            challengeType: challengeTypeString(for: selectedType),
            title: title,
            description: description.isEmpty ? nil : description,
            emoji: selectedType.emoji,
            dailyTarget: dailyTarget,
            targetUnit: unitLabel(for: selectedType)
        )
        
        isCreating = false
        
        if id != nil {
            // Refresh to get the join code
            await CommunityChallengeService.shared.fetchMyChallenges()
            if let created = CommunityChallengeService.shared.myChallenges.first(where: { $0.challengeId == id }) {
                createdJoinCode = created.joinCode
                createdSlug = created.inviteSlug
            }
            showingSuccess = true
        }
    }
    
    private func challengeTypeString(for type: ChallengeActivityType) -> String {
        switch type {
        case .steps: return "steps"
        case .walk: return "walk"
        case .run: return "run"
        case .lift: return "lift"
        case .hydrate: return "hydrate"
        case .calories: return "calories"
        case .protein: return "protein"
        case .activeMinutes: return "active_minutes"
        case .workoutStreak: return "workout_streak"
        case .sleep: return "sleep"
        }
    }
    
    private func unitLabel(for type: ChallengeActivityType) -> String {
        switch type {
        case .steps: return "steps"
        case .walk, .run, .activeMinutes: return "minutes"
        case .lift, .workoutStreak: return "workouts"
        case .hydrate: return "ml"
        case .calories: return "calories"
        case .protein: return "grams"
        case .sleep: return "hours"
        }
    }
    
    private func defaultTarget(for type: ChallengeActivityType) -> Int {
        switch type {
        case .steps: return 10000
        case .walk: return 30
        case .run: return 20
        case .lift: return 1
        case .hydrate: return 2000
        case .calories: return 500
        case .protein: return 150
        case .activeMinutes: return 30
        case .workoutStreak: return 1
        case .sleep: return 7
        }
    }
    
    private func stepAmount(for type: ChallengeActivityType) -> Int {
        switch type {
        case .steps: return 1000
        case .walk, .run, .activeMinutes: return 5
        case .lift, .workoutStreak: return 1
        case .hydrate: return 250
        case .calories: return 50
        case .protein: return 10
        case .sleep: return 1
        }
    }
}


// MARK: - Community Challenge Join Sheet (from Deep Link)

struct CommunityJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let codeOrSlug: String
    
    @State private var preview: CommunityChallengePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var joined = false
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading challenge...")
                } else if let preview = preview {
                    VStack(spacing: 24) {
                        Spacer()
                        
                        // Challenge preview
                        VStack(spacing: 16) {
                            Text(preview.displayEmoji)
                                .font(.system(size: 64))
                            
                            Text(preview.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            if let desc = preview.description {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            HStack(spacing: 20) {
                                VStack {
                                    Text("\(preview.participantCount)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text("Members")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack {
                                    Text("\(preview.dailyTarget)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text("\(preview.targetUnit)/day")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let creator = preview.creatorName ?? preview.creatorUsername {
                                Text("Created by \(creator)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(Spacing.xl)
                        
                        Spacer()
                        
                        // Join button
                        if preview.alreadyJoined || joined {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Already Joined!")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(14)
                            .padding(.horizontal, 20)
                        } else {
                            Button(action: { Task { await joinChallenge() } }) {
                                HStack(spacing: 8) {
                                    if isJoining {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "person.badge.plus")
                                        Text("Join Challenge")
                                            .fontWeight(.bold)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(14)
                            }
                            .disabled(isJoining)
                            .padding(.horizontal, 20)
                        }
                        
                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.bottom, 40)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Challenge Not Found")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("This challenge may have ended or the link may be invalid.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
            }
            .navigationTitle("Join Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                preview = await CommunityChallengeService.shared.lookupChallenge(code: codeOrSlug)
                isLoading = false
            }
        }
    }
    
    private func joinChallenge() async {
        isJoining = true
        let id = await CommunityChallengeService.shared.joinChallenge(
            code: codeOrSlug.count <= 6 ? codeOrSlug : nil,
            slug: codeOrSlug.count > 6 ? codeOrSlug : nil
        )
        isJoining = false
        
        if id != nil {
            joined = true
            HapticManager.notification(.success)
        } else {
            error = "Failed to join. Please try again."
        }
    }
}

// MARK: - Private Challenge Join Sheet (from Code Entry or Deep Link)

/// Shows a private challenge preview with a "Join" button.
/// Used when a user enters a private challenge code or opens a /pc/ deep link.
struct PrivateChallengeJoinSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let code: String
    
    @State private var preview: PrivateChallengePreview?
    @State private var isLoading = true
    @State private var isJoining = false
    @State private var joined = false
    @State private var joinedChallengeId: UUID?
    @State private var error: String?
    
    private let themeGradient: [Color] = [.purple, .blue]
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.06, blue: 0.14), Color(red: 0.05, green: 0.04, blue: 0.08)]
                        : [Color(red: 0.96, green: 0.95, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading challenge...")
                } else if let preview = preview {
                    VStack(spacing: 24) {
                        Spacer()
                        
                        // Challenge preview card
                        VStack(spacing: 16) {
                            emojiRing(for: preview)
                            
                            // Private badge
                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.ds_caption)
                                Text("Private Challenge")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 10)
                            .padding(.vertical, Spacing.xxs)
                            .background(Color.purple.opacity(0.12))
                            .clipShape(Capsule())
                            
                            Text(preview.title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .multilineTextAlignment(.center)
                            
                            if let desc = preview.description, !desc.isEmpty {
                                Text(desc)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            
                            // Stats row
                            HStack(spacing: 24) {
                                VStack(spacing: 4) {
                                    Text("\(preview.memberCount)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text("Members")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                VStack(spacing: 4) {
                                    Text("\(preview.dailyTarget)")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                    Text("\(preview.targetUnit)/day")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let max = preview.maxMembers {
                                    VStack(spacing: 4) {
                                        Text("\(max)")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                        Text("Max")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            if let creator = preview.creatorName ?? preview.creatorUsername {
                                Text("Created by \(creator)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(Spacing.xl)
                        
                        Spacer()
                        
                        // Join / Already Joined button
                        if preview.alreadyJoined || joined {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(joined ? "Joined!" : "Already Joined!")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(14)
                            .padding(.horizontal, 20)
                        } else {
                            Button(action: { Task { await joinChallenge() } }) {
                                HStack(spacing: 8) {
                                    if isJoining {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    } else {
                                        Image(systemName: "person.badge.plus")
                                        Text("Join Challenge")
                                            .fontWeight(.bold)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.md)
                                .background(
                                    LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(14)
                            }
                            .disabled(isJoining)
                            .padding(.horizontal, 20)
                        }
                        
                        if let error = error {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 40)
                } else {
                    // Not found state
                    VStack(spacing: 16) {
                        Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Challenge Not Found")
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("This private challenge may have ended or the code may be invalid.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
            }
            .navigationTitle("Join Private Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                // Look up both community and private — show whichever matches
                preview = await PrivateChallengeService.shared.lookupByCode(code: code)
                isLoading = false
            }
        }
    }
    
    private func emojiRing(for preview: PrivateChallengePreview) -> some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(colors: preview.resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 3
                )
                .frame(width: 80, height: 80)
            Text(preview.displayEmoji)
                .font(.system(size: 40))
        }
    }
    
    private func joinChallenge() async {
        isJoining = true
        let id = await PrivateChallengeService.shared.joinByCode(code: code)
        isJoining = false
        
        if let id = id {
            joinedChallengeId = id
            joined = true
            HapticManager.notification(.success)
        } else {
            error = "Failed to join. Please try again."
        }
    }
}

// MARK: - Friend Discovery Card

/// Shows a community that the user's friends are in but the user hasn't joined yet.
/// Displays overlapping friend avatars and a prominent "Join" button.
struct FriendDiscoveryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let challenge: DiscoverableCommunityChallenge
    let onJoin: () -> Void
    
    private var friends: [CommunityFriendInfo] {
        challenge.friendsInChallenge ?? []
    }
    
    private var tc: Color { challenge.resolvedType.color }
    private var tg: [Color] { challenge.resolvedType.gradientColors }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: emoji + title + target
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(LinearGradient(colors: tg, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                        .frame(width: 36, height: 36)
                    Text(challenge.displayEmoji)
                        .font(.ds_bodyLarge)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(challenge.dailyTarget) \(challenge.targetUnit)/day")
                        .font(.caption2)
                        .foregroundColor(tc.opacity(0.7))
                }
                
                Spacer()
            }
            
            // Compact rules
            CompactRulesLine(
                title: challenge.title,
                challengeType: challenge.challengeType,
                dailyTarget: challenge.dailyTarget,
                targetUnit: challenge.targetUnit,
                themeColor: tc
            )
            
            // Friends row: stacked photos + friend names + Join button
            HStack(spacing: 8) {
                // Stacked friend profile photos
                HStack(spacing: -8) {
                    ForEach(Array(friends.prefix(5).enumerated()), id: \.element.userId) { index, friend in
                        CachedFriendPhoto(
                            friendId: friend.userId.uuidString,
                            photoUrl: friend.profilePhotoUrl,
                            name: friend.displayName,
                            size: 28
                        )
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        .zIndex(Double(5 - index))
                    }
                    
                    // "+N" overflow circle if more than 5 friends
                    if friends.count > 5 {
                        ZStack {
                            Circle()
                                .fill(tc.opacity(0.2))
                                .frame(width: 28, height: 28)
                            Text("+\(friends.count - 5)")
                                .font(.ds_caption)
                                .foregroundColor(tc)
                        }
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    }
                }
                
                // Friend name text
                if friends.count == 1 {
                    Text("\(friends[0].displayName.components(separatedBy: " ").first ?? friends[0].displayName) is in this")
                        .font(.caption)
                        .foregroundColor(tc.opacity(0.7))
                        .lineLimit(1)
                } else {
                    let firstNames = friends.prefix(2).map { $0.displayName.components(separatedBy: " ").first ?? $0.displayName }
                    let extra = friends.count > 2 ? " +\(friends.count - 2)" : ""
                    Text("\(firstNames.joined(separator: ", "))\(extra) are in this")
                        .font(.caption)
                        .foregroundColor(tc.opacity(0.7))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Join button (compact, inline)
                Button(action: onJoin) {
                    Text("Join")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(colors: tg, startPoint: .leading, endPoint: .trailing)
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [tc.opacity(0.10), tc.opacity(0.03), Color(white: 0.08)]
                                : [tc.opacity(0.06), tc.opacity(0.02), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: tc.opacity(colorScheme == .dark ? 0.10 : 0.06), location: 0),
                                .init(color: .clear, location: 0.3)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .shadow(color: tc.opacity(colorScheme == .dark ? 0.20 : 0.15), radius: 12, x: 0, y: 6)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.05), radius: 6, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [tc.opacity(0.45), tc.opacity(0.12)]
                            : [tc.opacity(0.30), tc.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Community Detail View (Expanded Stats)

/// Full detail view shown when user taps into a community widget.
/// Shows leaderboard, community stats, friend highlights, and encouragement.
struct CommunityDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var progressResolver = ChallengeProgressResolver.shared
    let challengeId: UUID
    let challengeTitle: String
    
    @State private var detail: CommunityDetailResponse?
    @State private var isLoading = true
    @State private var showingLeaveConfirmation = false
    @State private var isLeaving = false
    @State private var showShareSheet = false
    
    /// Previous leaderboard ranks for computing deltas locally
    @State private var previousDetailRanks: [UUID: Int] = [:]
    /// Rank deltas for the detail leaderboard: userId → delta
    @State private var detailRankDeltas: [UUID: Int] = [:]
    
    /// Live "my today" progress using local HealthKit / tracking data
    private var liveMyTodayProgress: Int {
        guard let d = detail else { return 0 }
        return progressResolver.liveProgress(for: d)
    }
    
    /// Live target hit check
    private var liveTargetHitToday: Bool {
        guard let d = detail else { return false }
        return liveMyTodayProgress >= d.dailyTarget
    }
    
    /// Reusable themed card background for detail sections
    private func themedCard(color tc: Color, cornerRadius: CGFloat = 14) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [tc.opacity(0.08), tc.opacity(0.03), Color(white: 0.08)]
                            : [tc.opacity(0.05), tc.opacity(0.02), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: tc.opacity(colorScheme == .dark ? 0.08 : 0.04), location: 0),
                            .init(color: .clear, location: 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .shadow(color: tc.opacity(colorScheme == .dark ? 0.15 : 0.10), radius: 8, x: 0, y: 4)
    }
    
    private func themedOutline(color tc: Color, cornerRadius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [tc.opacity(0.35), tc.opacity(0.10)]
                        : [tc.opacity(0.20), tc.opacity(0.05)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                } else if let detail {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Challenge header card
                            detailHeader(detail)
                            
                            // Challenge rules
                            ChallengeRulesCard(
                                rules: ChallengeRulesHelper.rules(
                                    title: detail.title,
                                    challengeType: detail.challengeType,
                                    dailyTarget: detail.dailyTarget,
                                    targetUnit: detail.targetUnit
                                ),
                                themeColor: detail.resolvedType.color
                            )
                            
                            // Your stats
                            myStatsSection(detail)
                            
                            // Community pulse
                            communityPulseSection(detail)
                            
                            // Friends in community
                            if let friends = detail.friendsIn, !friends.isEmpty {
                                friendsSection(friends, count: detail.friendsCount, type: detail.resolvedType)
                            }
                            
                            // Encouragement
                            if let encouragement = detail.encouragement, !encouragement.isEmpty {
                                encouragementBanner(encouragement, type: detail.resolvedType)
                            }
                            
                            // Top leaderboard
                            if let leaders = detail.topLeaderboard, !leaders.isEmpty {
                                leaderboardSection(leaders, type: detail.resolvedType)
                            }
                            
                            // Leave community
                            leaveCommunityButton(type: detail.resolvedType)
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("Could not load community details")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(challengeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if detail != nil {
                            Button(action: { showShareSheet = true }) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.ds_bodyMedium)
                            }
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let detail, let url = detail.shareURL {
                ShareSheet(items: [
                    CommunityChallengeService.shared.shareMessage(for: detail),
                    url
                ])
            }
        }
        .task {
            let result = await CommunityChallengeService.shared.getChallengeDetail(challengeId: challengeId)
            storeRanksAndComputeDeltas(from: result)
            detail = result
            isLoading = false
        }
        .refreshable {
            let result = await CommunityChallengeService.shared.getChallengeDetail(challengeId: challengeId)
            storeRanksAndComputeDeltas(from: result)
            detail = result
        }
        .onAppear {
            if !isLoading && detail != nil {
                Task {
                    let result = await CommunityChallengeService.shared.getChallengeDetail(challengeId: challengeId)
                    storeRanksAndComputeDeltas(from: result)
                    detail = result
                }
            }
        }
        .alert("Leave Community?", isPresented: $showingLeaveConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                Task {
                    isLeaving = true
                    let success = await CommunityChallengeService.shared.leaveChallenge(challengeId: challengeId)
                    isLeaving = false
                    if success {
                        await CommunityChallengeService.shared.fetchMyChallenges()
                        dismiss()
                    }
                }
            }
        } message: {
            Text("You'll lose your streak and leaderboard position. You can rejoin later if a friend is still in the community.")
        }
    }
    
    // MARK: - Rank Delta Tracking
    
    private func storeRanksAndComputeDeltas(from result: CommunityDetailResponse?) {
        guard let leaders = result?.topLeaderboard, !leaders.isEmpty else { return }
        
        // Build current ranks
        var currentRanks: [UUID: Int] = [:]
        for entry in leaders {
            currentRanks[entry.userId] = entry.rank
        }
        
        // Compute deltas if we have previous data
        if !previousDetailRanks.isEmpty {
            var newDeltas: [UUID: Int] = [:]
            for entry in leaders {
                if let prev = previousDetailRanks[entry.userId] {
                    let delta = prev - entry.rank // positive = climbed up
                    if delta != 0 {
                        newDeltas[entry.userId] = delta
                    }
                }
            }
            detailRankDeltas = newDeltas
        }
        
        previousDetailRanks = currentRanks
    }
    
    // MARK: - Leave Community Button
    
    private func leaveCommunityButton(type: ChallengeType) -> some View {
        Button(action: {
            HapticManager.notification(.warning)
            showingLeaveConfirmation = true
        }) {
            HStack(spacing: 8) {
                if isLeaving {
                    ProgressView()
                        .tint(.red)
                } else {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                Text(isLeaving ? "Leaving..." : "Leave Community")
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.red.opacity(0.8))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.red.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.red.opacity(colorScheme == .dark ? 0.15 : 0.10), lineWidth: 1)
            )
        }
        .disabled(isLeaving)
        .padding(.top, 8)
    }
    
    // MARK: - Detail Header
    
    private func detailHeader(_ d: CommunityDetailResponse) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: d.resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 50, height: 50)
                Text(d.displayEmoji)
                    .font(.ds_heading2)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(d.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Label("\(d.participantCount)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(d.resolvedType.color.opacity(0.7))
                    
                    if let max = d.maxParticipants {
                        Text("/ \(max)")
                            .font(.caption)
                            .foregroundColor(d.resolvedType.color.opacity(0.5))
                    }
                    
                    Text("•")
                        .foregroundColor(d.resolvedType.color.opacity(0.3))
                    
                    Text("\(d.dailyTarget) \(d.targetUnit)/day")
                        .font(.caption)
                        .foregroundColor(d.resolvedType.color.opacity(0.7))
                }
            }
            
            Spacer()
            
            // Rank badge
            VStack(spacing: 2) {
                Text("#\(d.myRank)")
                    .font(.ds_statSmall)
                    .foregroundStyle(
                        d.myRank <= 3
                            ? LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                            : LinearGradient(colors: d.resolvedType.gradientColors, startPoint: .top, endPoint: .bottom)
                    )
                Text("rank")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Spacing.md)
        .background(themedCard(color: d.resolvedType.color, cornerRadius: CornerRadius.lg))
        .overlay(themedOutline(color: d.resolvedType.color, cornerRadius: CornerRadius.lg))
    }
    
    // MARK: - My Stats Section
    
    private func myStatsSection(_ d: CommunityDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your Stats")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today's Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(liveMyTodayProgress)/\(d.dailyTarget) \(d.targetUnit)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(liveTargetHitToday ? d.resolvedType.color : .primary)
                }
                
                GeometryReader { geo in
                    let livePct = d.dailyTarget > 0 ? min(1.0, Double(liveMyTodayProgress) / Double(d.dailyTarget)) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(d.resolvedType.color.opacity(0.12))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: d.resolvedType.gradientColors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * livePct, height: 8)
                            .shadow(color: d.resolvedType.color.opacity(0.4), radius: 3, x: 0, y: 1)
                    }
                }
                .frame(height: 8)
            }
            
            // Stat pills
            HStack(spacing: 12) {
                detailStatPill(value: "\(d.myDaysCompleted)", label: "Days", icon: "calendar", color: d.resolvedType.color)
                detailStatPill(value: "\(d.myCurrentStreak)", label: "Streak", icon: "flame.fill", color: d.myCurrentStreak > 0 ? .orange : .secondary)
                detailStatPill(value: "\(d.myBestStreak)", label: "Best", icon: "star.fill", color: .yellow)
                detailStatPill(value: "\(d.myTotalProgress)", label: "Total \(d.targetUnit)", icon: "sum", color: d.resolvedType.color)
            }
        }
        .padding(14)
        .background(themedCard(color: d.resolvedType.color))
        .overlay(themedOutline(color: d.resolvedType.color))
    }
    
    // MARK: - Community Pulse
    
    private func communityPulseSection(_ d: CommunityDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("🌍 Community Pulse")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(d.resolvedType.color)
                        .frame(width: 6, height: 6)
                    Text("\(d.totalActiveToday) active today")
                        .font(.caption2)
                        .foregroundColor(d.resolvedType.color.opacity(0.7))
                }
            }
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                pulseCard(
                    title: "Avg Progress Today",
                    value: "\(d.avgTodayProgress) \(d.targetUnit)",
                    icon: "chart.bar.fill",
                    color: .blue
                )
                pulseCard(
                    title: "Top Progress Today",
                    value: "\(d.topTodayProgress) \(d.targetUnit)",
                    icon: "arrow.up.right",
                    color: .green
                )
                pulseCard(
                    title: "Avg Streak",
                    value: String(format: "%.1f days", d.avgStreak),
                    icon: "flame",
                    color: .orange
                )
                pulseCard(
                    title: "Completion Rate",
                    value: "\(Int(d.completionRateToday * 100))%",
                    icon: "checkmark.circle",
                    color: .purple
                )
            }
        }
        .padding(14)
        .background(themedCard(color: d.resolvedType.color))
        .overlay(themedOutline(color: d.resolvedType.color))
    }
    
    // MARK: - Friends Section
    
    private func friendsSection(_ friends: [CommunityFriendInfo], count: Int, type: ChallengeType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("👥 Friends Here")
                    .font(.subheadline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(type.color)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(type.color.opacity(0.12)))
            }
            
            ForEach(Array(friends.prefix(10).enumerated()), id: \.element.userId) { index, friend in
                HStack(spacing: 10) {
                    // Friend avatar with photo
                    detailFriendAvatar(friend: friend, type: type, size: 32)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(friend.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let username = friend.username {
                            Text("@\(username)")
                                .font(.caption2)
                                .foregroundColor(type.color.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            
            if count > 10 {
                Text("+ \(count - 10) more friends")
                    .font(.caption)
                    .foregroundColor(type.color.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(14)
        .background(themedCard(color: type.color))
        .overlay(themedOutline(color: type.color))
    }
    
    /// Friend avatar with photo support for detail view
    private func detailFriendAvatar(friend: CommunityFriendInfo, type: ChallengeType, size: CGFloat) -> some View {
        CachedFriendPhoto(
            friendId: friend.userId.uuidString,
            photoUrl: friend.profilePhotoUrl,
            name: friend.displayName,
            size: size,
            showGradientRing: false,
            gradientColors: type.gradientColors
        )
    }
    
    private func detailFriendInitialCircle(initial: String, type: ChallengeType, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: type.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
            Text(initial)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Encouragement Banner
    
    private func encouragementBanner(_ text: String, type: ChallengeType) -> some View {
        HStack(spacing: 10) {
            Text("💪")
                .font(.title2)
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .italic()
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [type.color.opacity(0.12), type.color.opacity(0.04)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(type.color.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Leaderboard Section
    
    private func leaderboardSection(_ leaders: [LeaderboardSnippetEntry], type: ChallengeType) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🏆 Leaderboard")
                .font(.subheadline)
                .fontWeight(.bold)
            
            ForEach(leaders) { entry in
                let delta = detailRankDeltas[entry.userId] ?? 0
                
                HStack(spacing: 10) {
                    // Rank + delta
                    VStack(spacing: 1) {
                        Text(rankDisplay(entry.rank))
                            .font(.system(size: entry.rank <= 3 ? 18 : 14, weight: .bold, design: .rounded))
                        
                        // Rank change indicator
                        if delta > 0 {
                            HStack(spacing: 1) {
                                Image(systemName: "arrowtriangle.up.fill")
                                    .font(.system(size: 6))
                                Text("+\(delta)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.green)
                        } else if delta < 0 {
                            HStack(spacing: 1) {
                                Image(systemName: "arrowtriangle.down.fill")
                                    .font(.system(size: 6))
                                Text("\(delta)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .frame(width: 34)
                    
                    // Avatar with photo
                    leaderboardAvatar(entry: entry, type: type, size: 32)
                    
                    // Name
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(entry.name ?? entry.username ?? "User")
                                .font(.subheadline)
                                .fontWeight(entry.isCurrentUser ? .bold : .medium)
                            if entry.isCurrentUser {
                                Text("(You)")
                                    .font(.caption2)
                                    .foregroundColor(type.color)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Streak
                    if entry.currentStreak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(entry.currentStreak)")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                    }
                    
                    // Days completed
                    Text("\(entry.daysCompleted)d")
                        .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, Spacing.xxs)
                .padding(.horizontal, Spacing.xs)
                .background(
                    entry.isCurrentUser
                        ? RoundedRectangle(cornerRadius: CornerRadius.sm).fill(type.color.opacity(0.06))
                        : RoundedRectangle(cornerRadius: CornerRadius.sm).fill(Color.clear)
                )
            }
        }
        .padding(14)
        .background(themedCard(color: type.color))
        .overlay(themedOutline(color: type.color))
    }
    
    /// Leaderboard avatar with cached photo support for detail view
    private func leaderboardAvatar(entry: LeaderboardSnippetEntry, type: ChallengeType, size: CGFloat) -> some View {
        CachedFriendPhoto(
            friendId: entry.userId.uuidString,
            photoUrl: entry.profilePhotoUrl,
            name: entry.displayName,
            size: size,
            showGradientRing: false,
            gradientColors: entry.isCurrentUser ? [type.color, type.color.opacity(0.7)] : [.gray.opacity(0.3), .gray.opacity(0.2)]
        )
    }
    
    private func leaderboardInitialCircle(entry: LeaderboardSnippetEntry, type: ChallengeType, size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(entry.isCurrentUser ? type.color.opacity(0.3) : Color.gray.opacity(0.15))
                .frame(width: size, height: size)
            Text(String((entry.name ?? entry.username ?? "?").prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(entry.isCurrentUser ? type.color : .secondary)
        }
    }
    
    // MARK: - Helper Views
    
    private func detailStatPill(value: String, label: String, icon: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            Text(value)
                .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.sm)
                .fill(Color.gray.opacity(colorScheme == .dark ? 0.1 : 0.05))
        )
    }
    
    private func pulseCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
    }
    
    private func rankDisplay(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "#\(rank)"
        }
    }
    
    private func friendColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .pink, .orange, .teal]
        return colors[index % colors.count]
    }
}

// MARK: - All Community Challenges (Full List)

/// Dedicated screen showing ALL active community challenges.
/// Launched from the "See all X challenges" button on the Friends tab.
struct AllCommunityChallengesView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityChallengeService.shared
    @State private var selectedChallenge: CommunityChallenge?
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if service.myChallenges.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green.opacity(0.3))
                        Text("No active challenges")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Join a community challenge to get started!")
                            .font(.subheadline)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(service.myChallenges) { challenge in
                                Button {
                                    selectedChallenge = challenge
                                } label: {
                                    CommunityLeaderboardWidget(challenge: challenge)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, 12)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await service.refreshAll(force: true)
                    }
                }
            }
            .navigationTitle("My Communities")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                service.markCommunityViewVisible()
            }
            .onDisappear {
                service.markCommunityViewHidden()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Text("\(service.myChallenges.count) active")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                }
            }
            .navigationDestination(item: $selectedChallenge) { challenge in
                CommunityDetailView(challengeId: challenge.challengeId, challengeTitle: challenge.title)
            }
        }
    }
}

// MARK: - Make CommunityChallenge Hashable for NavigationDestination

extension CommunityChallenge: Hashable {
    static func == (lhs: CommunityChallenge, rhs: CommunityChallenge) -> Bool {
        lhs.challengeId == rhs.challengeId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(challengeId)
    }
}
