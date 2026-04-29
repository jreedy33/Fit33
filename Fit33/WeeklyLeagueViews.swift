//
//  WeeklyLeagueViews.swift
//  Fit33
//
//  UI components for the Weekly League system.
//  Includes the compact widget for FriendsTabView and the full-screen detail view.
//

import SwiftUI

// MARK: - Verified Badge

/// Checkmark badge — blue for verified users, gold for top 5 in the Verified league
struct VerifiedBadge: View {
    var size: CGFloat = 14
    var isGold: Bool = false
    
    var body: some View {
        ZStack {
            if isGold {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.6, green: 0.42, blue: 0.0),
                                Color(red: 0.75, green: 0.55, blue: 0.05),
                                Color(red: 1.0, green: 0.88, blue: 0.3),
                                Color(red: 1.0, green: 0.95, blue: 0.6),
                                Color(red: 0.85, green: 0.68, blue: 0.1)
                            ],
                            startPoint: .bottomTrailing,
                            endPoint: .topLeading
                        )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.78, blue: 0.0).opacity(0.6), radius: 4, x: 0, y: 0)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: size))
                    .foregroundColor(Color(red: 0.11, green: 0.63, blue: 0.95))
            }
        }
        .accessibilityLabel(isGold ? "Gold Verified" : "Verified")
        .accessibilityHidden(false)
    }
}

// MARK: - League Widget (for FriendsTabView)

/// Compact league card shown on the Friends tab.
/// Shows tier badge, current rank, points, and a mini leaderboard (top 3).
struct WeeklyLeagueWidget: View {
    @ObservedObject var leagueService: WeeklyLeagueService
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingProfile: ProfileUser?
    let onTap: () -> Void
    /// When set, the info `(i)` button calls this closure instead of presenting
    /// a sheet. Hosting tab views (Friends) wire this up to push
    /// `WeeklyLeagueInfoView` onto their `NavigationStack` so the info content
    /// reads as a real page (custom header + orb background) rather than a
    /// generic modal.
    var onShowInfo: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (outside card)
            HStack(spacing: 6) {
                Image(systemName: "trophy.circle.fill")
                    .foregroundStyle(
                        LinearGradient(
                            colors: standing?.tierGradient ?? [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .font(.title3)
                Text("Weekly League")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Button {
                    HapticManager.impact(.light)
                    onShowInfo?()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("How weekly leagues work")
                .accessibilityHint("Opens the Weekly League info page")
            }
            
            // Card content
            Button(action: {
                HapticManager.selectionChanged()
                onTap()
            }) {
                if let standing = standing {
                    leagueContent(standing: standing)
                } else if leagueService.isLoading {
                    loadingContent
                } else if leagueService.notPlaced {
                    notPlacedContent
                } else {
                    joinContent
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $showingProfile) { profileUser in
            NavigationStack {
                FriendProfileView(user: profileUser)
            }
        }
    }
    
    private var standing: LeagueStanding? { leagueService.standing }
    
    // MARK: - League Content (Joined)
    
    private var myWorkoutsThisWeek: Int {
        guard let standing = standing else { return 0 }
        return standing.leaderboard.first(where: { $0.isCurrentUser })?.workoutsCompleted ?? 0
    }
    
    private var pointsGapText: String? {
        guard let standing = standing else { return nil }
        if standing.myRank == 1 {
            if let second = standing.leaderboard.first(where: { $0.rank == 2 }) {
                let gap = standing.myPoints - second.points
                return gap > 0 ? "Leading by \(gap) pts" : "Tied for 1st"
            }
            return nil
        }
        if let above = standing.leaderboard.first(where: { $0.rank == standing.myRank - 1 }) {
            let gap = above.points - standing.myPoints
            return gap > 0 ? "\(gap) pts behind #\(standing.myRank - 1)" : "Tied at #\(standing.myRank)"
        }
        return nil
    }
    
    private func leagueContent(standing: LeagueStanding) -> some View {
        VStack(spacing: 10) {
            // Tier banner + motivational context
            HStack(spacing: 10) {
                // Tier badge capsule
                HStack(spacing: 5) {
                    Text(standing.tierEmoji)
                        .font(.system(size: 16))
                    Text(standing.tierName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: standing.tierGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                
                Spacer()
                
                // Workouts this week
                HStack(spacing: 3) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 9))
                        .foregroundColor(standing.tierSwiftUIColor)
                    Text("\(myWorkoutsThisWeek)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("this week")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                if standing.daysRemaining <= 2 {
                    Text("⏰")
                        .font(.system(size: 12))
                }
            }
            
            // Points gap + position bar
            VStack(spacing: 6) {
                if let gapText = pointsGapText {
                    HStack(spacing: 4) {
                        Image(systemName: standing.myRank == 1 ? "crown.fill" : "arrow.up.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(standing.myRank == 1 ? .yellow : standing.tierSwiftUIColor)
                        Text(gapText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(standing.myRank == 1 ? .primary : .secondary)
                        Spacer()
                    }
                }
                
                leaguePositionBar(standing: standing)
            }
            
            // Compact stats row
            HStack(spacing: 0) {
                // Rank
                statCell(
                    value: "#\(standing.myRank)",
                    label: "of \(standing.groupSize)",
                    valueColor: standing.tierSwiftUIColor
                )
                
                thinDivider
                
                // Points
                statCell(
                    value: "\(standing.myPoints)",
                    label: "pts",
                    valueColor: .primary
                )
                
                thinDivider
                
                // Status
                VStack(spacing: 2) {
                    if standing.isInPromotionZone {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.green)
                        Text("Promoting")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                    } else if standing.isInRelegationZone {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                        Text("Relegation")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.red)
                    } else {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("Safe zone")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                
                thinDivider
                
                // Days left
                statCell(
                    value: "\(standing.daysRemaining)",
                    label: standing.daysRemaining == 1 ? "day left" : "days left",
                    valueColor: standing.daysRemaining <= 1 ? .red : .primary
                )
            }
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(standing.tierSwiftUIColor.opacity(colorScheme == .dark ? 0.06 : 0.04))
            )
            
            // Mini leaderboard (top 3 + user if not in top 3)
            miniLeaderboard(standing: standing)
            
            // "View Full Leaderboard" hint
            HStack(spacing: 4) {
                Spacer()
                Text("View Full Leaderboard")
                    .font(.caption2)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
            }
            .foregroundColor(standing.tierSwiftUIColor)
        }
        .padding(Spacing.sm)
        .sleekCard(cornerRadius: 20, accentColor: standing.tierSwiftUIColor)
    }
    
    private func statCell(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var thinDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 28)
    }
    
    /// Rank position bar: relegation (red) | safety (grey) | promotion (green)
    /// Left = bottom of league (demotion), Right = top (promotion)
    private func leaguePositionBar(standing: LeagueStanding) -> some View {
        let total = max(standing.groupSize, 1)
        let promoFraction = CGFloat(standing.promotionCount) / CGFloat(total)
        let relegFraction = CGFloat(standing.relegationCount) / CGFloat(total)
        let userPosition = 1.0 - CGFloat(standing.myRank - 1) / CGFloat(max(total - 1, 1))
        
        return GeometryReader { geo in
            let w = geo.size.width
            
            ZStack(alignment: .leading) {
                // Base track (safety zone color)
                Capsule()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(height: 6)
                
                // Relegation zone — left edge
                if relegFraction > 0 {
                    Capsule()
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.3 : 0.25))
                        .frame(width: w * relegFraction, height: 6)
                }
                
                // Promotion zone — right edge
                if promoFraction > 0 {
                    Capsule()
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.3 : 0.25))
                        .frame(width: w * promoFraction, height: 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                // User marker dot
                Circle()
                    .fill(standing.tierSwiftUIColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: standing.tierSwiftUIColor.opacity(0.5), radius: 3)
                    .offset(x: max(0, min(w - 10, w * userPosition - 5)))
            }
        }
        .frame(height: 10)
        .clipped()
    }
    
    /// Thin per-row position bar showing where a specific rank falls in the zones
    private func rowPositionBar(rank: Int, standing: LeagueStanding) -> some View {
        let total = max(standing.groupSize, 1)
        let promoFraction = CGFloat(standing.promotionCount) / CGFloat(total)
        let relegFraction = CGFloat(standing.relegationCount) / CGFloat(total)
        let position = 1.0 - CGFloat(rank - 1) / CGFloat(max(total - 1, 1))
        
        return GeometryReader { geo in
            let w = geo.size.width
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .frame(height: 3)
                
                if relegFraction > 0 {
                    Capsule()
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.2 : 0.15))
                        .frame(width: w * relegFraction, height: 3)
                }
                
                if promoFraction > 0 {
                    Capsule()
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.15))
                        .frame(width: w * promoFraction, height: 3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .offset(x: max(0, min(w - 6, w * position - 3)))
            }
        }
        .frame(height: 6)
        .clipped()
    }
    
    // MARK: - Mini Leaderboard
    
    private func miniLeaderboard(standing: LeagueStanding) -> some View {
        let top3 = Array(standing.leaderboard.prefix(3))
        let userInTop3 = top3.contains(where: { $0.isCurrentUser })
        let currentUserEntry = standing.leaderboard.first(where: { $0.isCurrentUser })
        
        return VStack(spacing: 4) {
            ForEach(top3) { entry in
                leaderboardRow(entry: entry, standing: standing)
            }
            
            if !userInTop3, let userEntry = currentUserEntry {
                HStack(spacing: 4) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 2.5, height: 2.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 1)
                
                leaderboardRow(entry: userEntry, standing: standing)
            }
        }
    }
    
    private func leaderboardRow(entry: LeagueEntry, standing: LeagueStanding) -> some View {
        let isPromoZone = standing.promotionCount > 0 && entry.rank <= standing.promotionCount
        let isRelegZone = standing.relegationCount > 0 && entry.rank > (standing.groupSize - standing.relegationCount)
        
        return Button {
            guard !entry.isCurrentUser else { return }
            showingProfile = ProfileUser(leagueEntry: entry)
        } label: {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                ZStack {
                    if entry.rank <= 3 {
                        Text(entry.rank == 1 ? "🥇" : entry.rank == 2 ? "🥈" : "🥉")
                            .font(.system(size: 14))
                    } else {
                        Text("#\(entry.rank)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .secondary)
                    }
                }
                .frame(width: 24)
                
                CachedFriendPhoto(
                    friendId: entry.userId.uuidString,
                    photoUrl: entry.profilePhotoUrl,
                    name: entry.displayName,
                    size: 26,
                    showGradientRing: entry.isCurrentUser || entry.isFriend == true,
                    gradientColors: entry.isCurrentUser
                        ? standing.tierGradient
                        : entry.isFriend == true ? [.green, .green.opacity(0.6)] : [.gray.opacity(0.3)]
                )
                
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(entry.isCurrentUser ? "You" : entry.firstName)
                            .font(.system(size: 13, weight: entry.isCurrentUser ? .bold : .medium))
                            .foregroundColor(entry.isCurrentUser ? .primary : .secondary)
                            .lineLimit(1)
                        
                        if entry.isVerified == true || entry.isGoldVerified == true {
                            VerifiedBadge(size: 11, isGold: entry.isGoldVerified == true || (standing.tierRank == 7 && entry.rank <= 5))
                        }
                    }
                    
                    if !entry.isCurrentUser, entry.isFriend == true {
                        Text("Friend")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.green)
                    } else if !entry.isCurrentUser, let mc = entry.mutualFriendCount, mc > 0 {
                        Text("\(mc) mutual")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                if isPromoZone {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.green)
                } else if isRelegZone {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.red)
                }
                
                HStack(spacing: 2) {
                    Text("\(entry.points)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .primary)
                    Text("pts")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            
            // Mini position bar per row
            rowPositionBar(rank: entry.rank, standing: standing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(entry.isCurrentUser
                    ? standing.tierSwiftUIColor.opacity(colorScheme == .dark ? 0.12 : 0.08)
                    : Color.clear)
        )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading State
    
    private var loadingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Loading league...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.lg)
        .sleekCard(cornerRadius: 24, accentColor: .yellow)
    }
    
    // MARK: - Not Placed (missed Monday placement)
    
    private var notPlacedContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.gray.opacity(0.2), .gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        LinearGradient(colors: [.gray, .secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 4) {
                Text("League Starts Monday")
                    .font(.headline)
                    .fontWeight(.bold)
                
                if let tierName = leagueService.notPlacedTierName {
                    Text("You'll be placed in the \(tierName) league when the new week begins.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Open the app on Monday to be placed in next week's league.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.ds_bodySmall)
                Text("Next Week")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.5))
            .cornerRadius(20)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: 24, accentColor: .gray)
    }
    
    // MARK: - Join Prompt (first time)
    
    private var joinContent: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.yellow.opacity(0.2), .orange.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 56, height: 56)
                
                Image(systemName: "trophy.fill")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 4) {
                Text("Join the Weekly League!")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Compete with friends & ~30 athletes. Earn points from workouts. Top 5 get promoted!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.ds_bodySmall)
                Text("Join Now")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, 10)
            .background(
                LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
            )
            .cornerRadius(20)
            .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: 24, accentColor: .yellow)
    }
}

// MARK: - League Detail View (Full Leaderboard)

struct WeeklyLeagueDetailView: View {
    @ObservedObject var leagueService = WeeklyLeagueService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedTab = 0 // 0: Leaderboard, 1: History
    @State private var hasLoadedFull = false
    @State private var showingProfile: ProfileUser?
    
    var body: some View {
        ZStack {
            // Background
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                
                // Tab picker
                tabPicker
                
                // Content
                if selectedTab == 0 {
                    leaderboardTab
                } else {
                    historyTab
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            if !hasLoadedFull {
                await leagueService.fetchFullLeaderboard()
                await leagueService.fetchHistory()
                hasLoadedFull = true
            }
        }
        .sheet(item: $showingProfile) { profileUser in
            NavigationStack {
                FriendProfileView(user: profileUser)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Nav bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Circle().fill(Color.gray.opacity(0.15)))
                }
                
                Spacer()
                
                if let standing = leagueService.standing {
                    Text(standing.tierEmoji)
                        .font(.ds_heading3)
                    Text("\(standing.tierName) League")
                        .font(.title3)
                        .fontWeight(.bold)
                } else {
                    Text("Weekly League")
                        .font(.title3)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                // Placeholder for balance
                Color.clear.frame(width: 36, height: 36)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 8)
            
            if let standing = leagueService.standing {
                HStack(spacing: 0) {
                    statPill(value: "#\(standing.myRank)", label: "Rank", color: standing.tierSwiftUIColor)
                    
                    statDivider
                    
                    statPill(value: "\(standing.myPoints)", label: "Points", color: .primary)
                    
                    statDivider
                    
                    if standing.connectionsInLeague > 0 {
                        statPill(
                            value: "\(standing.connectionsInLeague)",
                            label: standing.friendsInLeague > 0 ? "Friends" : "Mutual",
                            color: .green
                        )
                        
                        statDivider
                    }
                    
                    statPill(
                        value: "\(standing.daysRemaining)d",
                        label: "Remaining",
                        color: standing.daysRemaining <= 1 ? .red : .secondary
                    )
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, Spacing.md)
                
                detailLeaguePositionBar(standing: standing)
                    .padding(.horizontal, Spacing.md)
            }
        }
        .padding(.bottom, 8)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 30)
    }
    
    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                .foregroundColor(color)
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func detailLeaguePositionBar(standing: LeagueStanding) -> some View {
        let total = max(standing.groupSize, 1)
        let promoFraction = CGFloat(standing.promotionCount) / CGFloat(total)
        let relegFraction = CGFloat(standing.relegationCount) / CGFloat(total)
        let userPosition = 1.0 - CGFloat(standing.myRank - 1) / CGFloat(max(total - 1, 1))
        
        return GeometryReader { geo in
            let w = geo.size.width
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(height: 6)
                
                if relegFraction > 0 {
                    Capsule()
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.3 : 0.25))
                        .frame(width: w * relegFraction, height: 6)
                }
                
                if promoFraction > 0 {
                    Capsule()
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.3 : 0.25))
                        .frame(width: w * promoFraction, height: 6)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Circle()
                    .fill(standing.tierSwiftUIColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: standing.tierSwiftUIColor.opacity(0.5), radius: 3)
                    .offset(x: max(0, min(w - 10, w * userPosition - 5)))
            }
        }
        .frame(height: 10)
        .clipped()
    }
    
    private func fullRowPositionBar(rank: Int, standing: LeagueStanding) -> some View {
        let total = max(standing.groupSize, 1)
        let promoFraction = CGFloat(standing.promotionCount) / CGFloat(total)
        let relegFraction = CGFloat(standing.relegationCount) / CGFloat(total)
        let position = 1.0 - CGFloat(rank - 1) / CGFloat(max(total - 1, 1))
        
        return GeometryReader { geo in
            let w = geo.size.width
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(colorScheme == .dark ? 0.12 : 0.08))
                    .frame(height: 3)
                
                if relegFraction > 0 {
                    Capsule()
                        .fill(Color.red.opacity(colorScheme == .dark ? 0.2 : 0.15))
                        .frame(width: w * relegFraction, height: 3)
                }
                
                if promoFraction > 0 {
                    Capsule()
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.15))
                        .frame(width: w * promoFraction, height: 3)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                
                Circle()
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .offset(x: max(0, min(w - 6, w * position - 3)))
            }
        }
        .frame(height: 6)
        .clipped()
    }
    
    // MARK: - Tab Picker
    
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(["Leaderboard", "History"], id: \.self) { tab in
                let index = tab == "Leaderboard" ? 0 : 1
                let isSelected = selectedTab == index
                
                Button(action: {
                    HapticManager.selectionChanged()
                    withAnimation(.spring(response: 0.3)) { selectedTab = index }
                }) {
                    VStack(spacing: 6) {
                        Text(tab)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .bold : .medium)
                            .foregroundColor(isSelected ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(isSelected ? (leagueService.standing?.tierSwiftUIColor ?? .blue) : Color.clear)
                            .frame(height: 3)
                            .cornerRadius(1.5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
    
    // MARK: - Leaderboard Tab
    
    private var leaderboardTab: some View {
        ScrollView {
            if let standing = leagueService.standing {
                VStack(spacing: 2) {
                    // Promotion zone label
                    if standing.promotionCount > 0 {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.ds_labelSmall)
                                .foregroundColor(.green)
                            Text("Promotion Zone — Top \(standing.promotionCount) advance to \(standing.nextTierName ?? "next tier")")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    }

                    ForEach(standing.leaderboard) { entry in
                        fullLeaderboardRow(entry: entry, standing: standing)

                        // Zone dividers
                        if entry.rank == standing.promotionCount && standing.promotionCount > 0 {
                            zoneDivider(color: .green, text: "▲ Promotion cutoff")
                        }
                        if standing.relegationCount > 0 && entry.rank == (standing.groupSize - standing.relegationCount) {
                            zoneDivider(color: .red, text: "▼ Relegation zone")
                        }
                    }

                    Spacer(minLength: 100)
                }
            } else if leagueService.isLoading {
                ProgressView("Loading leaderboard...")
                    .padding(.top, 40)
            } else if leagueService.notPlaced {
                leaderboardNotPlacedState
            } else {
                // Bug-intel fingerprint eb6ce765 — previously this branch was
                // empty, so a failed or pre-placement load rendered a black
                // ScrollView with just the header chevron. Now we always show
                // an explanatory state with a retry button.
                leaderboardEmptyErrorState
            }
        }
        .refreshable {
            await leagueService.fetchFullLeaderboard()
        }
    }

    /// Shown when `WeeklyLeagueService.notPlaced` is true — the user joined
    /// mid-week and placement happens on the next Monday rollup (see the
    /// Weekly League Monday-only placement invariant in SUPABASE_AGENT.md).
    private var leaderboardNotPlacedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("You're not placed yet")
                .font(.headline)
            if let tier = leagueService.notPlacedTierName {
                Text("You'll start in the \(tier) tier next week.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Placements run every Monday. Keep logging workouts — you'll see your rank once the next week starts.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let next = leagueService.notPlacedNextWeek {
                Text("Next placement: \(next)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    /// Shown when standing is nil and we're not loading and not in the
    /// `notPlaced` state — i.e. fetch failed, user offline, or the standing
    /// was never populated. Always offer a retry path so we never fall back
    /// to a bare black screen.
    private var leaderboardEmptyErrorState: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            Text("Leaderboard unavailable")
                .font(.headline)
            Text(leagueService.error
                 ?? "We couldn't load the leaderboard. Check your connection and try again.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Task {
                    // `fetchOrJoinLeague` runs the full placement/standing
                    // query from scratch (and joins if needed);
                    // `fetchFullLeaderboard` needs a groupId and would
                    // short-circuit again if standing is still nil.
                    await leagueService.fetchOrJoinLeague(force: true)
                    if leagueService.standing != nil {
                        await leagueService.fetchFullLeaderboard()
                    }
                }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .cornerRadius(20)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
    
    private func fullLeaderboardRow(entry: LeagueEntry, standing: LeagueStanding) -> some View {
        let isPromoZone = standing.promotionCount > 0 && entry.rank <= standing.promotionCount
        let isRelegZone = standing.relegationCount > 0 && entry.rank > (standing.groupSize - standing.relegationCount)
        let showHideOption = !entry.isCurrentUser && entry.isFriend != true
        
        return Button {
            guard !entry.isCurrentUser else { return }
            showingProfile = ProfileUser(leagueEntry: entry)
        } label: {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    if entry.rank <= 3 {
                        Text(entry.rank == 1 ? "🥇" : entry.rank == 2 ? "🥈" : "🥉")
                            .font(.ds_heading3)
                    } else {
                        Text("#\(entry.rank)")
                            .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .secondary)
                    }
                }
                .frame(width: 32)
                
                CachedFriendPhoto(
                    friendId: entry.userId.uuidString,
                    photoUrl: entry.profilePhotoUrl,
                    name: entry.displayName,
                    size: 40,
                    showGradientRing: entry.isCurrentUser || entry.isFriend == true,
                    gradientColors: entry.isCurrentUser
                        ? standing.tierGradient
                        : entry.isFriend == true ? [.green, .green.opacity(0.6)] : [.gray.opacity(0.3)]
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    if !entry.isCurrentUser, entry.isFriend == true {
                        Text("Friend")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                    
                    HStack(spacing: 6) {
                        Text(entry.isCurrentUser ? "You" : entry.displayName)
                            .font(.subheadline)
                            .fontWeight(entry.isCurrentUser ? .bold : .medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if entry.isVerified == true || entry.isGoldVerified == true {
                            VerifiedBadge(size: 13, isGold: entry.isGoldVerified == true || (standing.tierRank == 7 && entry.rank <= 5))
                        }
                    }
                    
                    if entry.isCurrentUser || entry.isFriend == true {
                        if let workouts = entry.workoutsCompleted, workouts > 0 {
                            Text("\(workouts) workout\(workouts == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if let mc = entry.mutualFriendCount, mc > 0 {
                        Text("\(mc) mutual friend\(mc == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.blue.opacity(0.8))
                    }
                }
                
                Spacer()
                
                if isPromoZone {
                    Image(systemName: "chevron.up")
                        .font(.ds_caption)
                        .foregroundColor(.green)
                        .padding(Spacing.xxs)
                        .background(Circle().fill(Color.green.opacity(0.15)))
                } else if isRelegZone {
                    Image(systemName: "chevron.down")
                        .font(.ds_caption)
                        .foregroundColor(.red)
                        .padding(Spacing.xxs)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
                
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(entry.points)")
                        .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .primary)
                    Text("pts")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            
            fullRowPositionBar(rank: entry.rank, standing: standing)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    entry.isCurrentUser
                        ? standing.tierSwiftUIColor.opacity(colorScheme == .dark ? 0.12 : 0.06)
                        : entry.isFriend == true
                            ? Color.green.opacity(colorScheme == .dark ? 0.06 : 0.03)
                            : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    entry.isCurrentUser
                        ? standing.tierSwiftUIColor.opacity(0.3)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .contextMenu {
            if showHideOption {
                Button(role: .destructive) {
                    Task { await leagueService.hideUser(entry.userId) }
                } label: {
                    Label("Hide This Person", systemImage: "eye.slash")
                }
            }
        }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 1)
    }
    
    private func zoneDivider(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color.opacity(0.4))
                .frame(height: 1)
            
            Text(text)
                .font(.ds_caption)
                .foregroundColor(color)
                .lineLimit(1)
            
            Rectangle()
                .fill(color.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    
    // MARK: - History Tab
    
    private var historyTab: some View {
        ScrollView {
            if leagueService.history.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No History Yet")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Complete your first league week to see your results here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(40)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(leagueService.history) { entry in
                        historyRow(entry: entry)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
            }
            
            Spacer(minLength: 100)
        }
    }
    
    private func historyRow(entry: LeagueHistoryEntry) -> some View {
        let tierEmoji: String = {
            switch entry.tierRank {
            case 1: return "🥉"
            case 2: return "🥈"
            case 3: return "🥇"
            case 4: return "💎"
            case 5: return "💠"
            case 6: return "👑"
            case 7: return "✅"
            default: return "🏆"
            }
        }()
        
        return HStack(spacing: 12) {
            // Tier emoji
            Text(tierEmoji)
                .font(.ds_heading2)
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.tierName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    if entry.wasPromoted {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.ds_caption)
                            Text("Promoted")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.green)
                    } else if entry.wasRelegated {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.ds_caption)
                            Text("Relegated")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Text("Week of \(entry.weekStart)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Result
            VStack(alignment: .trailing, spacing: 2) {
                Text("#\(entry.finalRank)")
                    .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                Text("\(entry.finalPoints) pts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Weekly League Info Page

/// Full page (NavigationLink push) that explains the Weekly League system.
/// Replaces the legacy `WeeklyLeagueInfoSheet` modal — pushed from the
/// `(i)` button on `WeeklyLeagueWidget`.
///
/// Visual contract (DESIGN_AGENT invariants 5 / 9 / 11):
/// - `AnimatedOrbBackground.friends(colorScheme:)` — canonical blue/cyan orb
///   that matches `WeeklyLeagueDetailView` so the league flow stays cohesive.
/// - Hidden system nav bar + custom in-layout chevron header.
/// - Primary content cards use `.sleekCard()`; numbers/spacing/radii/fonts use
///   the `Spacing.*` / `CornerRadius.*` / `Font.ds_*` tokens.
struct WeeklyLeagueInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var leagueService = WeeklyLeagueService.shared
    
    private struct Tier {
        let emoji: String
        let name: String
        let blurb: String
        let rank: Int
        let color: Color
    }
    
    private let tiers: [Tier] = [
        Tier(emoji: "🥉", name: "Bronze",   blurb: "Where every athlete starts",         rank: 1, color: Color(red: 0.80, green: 0.50, blue: 0.20)),
        Tier(emoji: "🥈", name: "Silver",   blurb: "Showing up, week after week",        rank: 2, color: Color(red: 0.75, green: 0.75, blue: 0.78)),
        Tier(emoji: "🥇", name: "Gold",     blurb: "Consistent and climbing",            rank: 3, color: Color(red: 0.95, green: 0.78, blue: 0.20)),
        Tier(emoji: "💎", name: "Platinum", blurb: "Strong week-over-week presence",     rank: 4, color: Color(red: 0.55, green: 0.78, blue: 0.95)),
        Tier(emoji: "🔷", name: "Diamond",  blurb: "Top performers across the app",      rank: 5, color: Color(red: 0.40, green: 0.62, blue: 0.95)),
        Tier(emoji: "🔥", name: "Elite",    blurb: "Relentless. Rare air.",              rank: 6, color: Color(red: 1.00, green: 0.45, blue: 0.20)),
        Tier(emoji: "✅", name: "Verified", blurb: "Top 5 here earn the gold checkmark", rank: 7, color: Color(red: 0.11, green: 0.63, blue: 0.95))
    ]
    
    private var standing: LeagueStanding? { leagueService.standing }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                header
                
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        heroBanner
                        howItWorksCard
                        tierLadderCard
                        pointsCard
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xl)
                }
            }
        }
        .navigationBarHidden(true)
    }
    
    // MARK: - Header (custom in-layout, matches WeeklyLeagueDetailView)
    
    private var header: some View {
        HStack {
            Button {
                HapticManager.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.ds_labelLarge)
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(Circle().fill(Color.gray.opacity(0.15)))
            }
            .accessibilityLabel("Back")
            
            Spacer()
            
            Text("Weekly League")
                .font(.title3)
                .fontWeight(.bold)
            
            Spacer()
            
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.xs)
    }
    
    // MARK: - Hero
    
    private var heroBanner: some View {
        let accent = standing?.tierSwiftUIColor ?? .blue
        let gradient = standing?.tierGradient ?? [.blue, .cyan]
        let tierName = standing?.tierName
        let pendingTierName = leagueService.notPlacedTierName
        
        return HStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                    .shadow(color: accent.opacity(0.35), radius: 12, x: 0, y: 4)
                
                Text(standing?.tierEmoji ?? "🏆")
                    .font(.system(size: 28))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Train all week. Climb the ladder.")
                    .font(.ds_heading3)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let tierName {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.ds_caption)
                        Text("You're in \(tierName)")
                            .font(.ds_labelMedium)
                    }
                    .foregroundColor(accent)
                } else if let pendingTierName {
                    Text("You'll join \(pendingTierName) at next reset")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                } else {
                    Text("Train this week to get placed")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: accent)
    }
    
    // MARK: - How It Works
    
    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel("How it works", icon: "sparkles", iconColor: .blue)
            
            VStack(alignment: .leading, spacing: Spacing.sm) {
                stepRow(number: 1, text: "New league every Monday at 12 AM UTC")
                stepRow(number: 2, text: "Earn points by training — strength, cardio, even short sessions count")
                stepRow(number: 3, text: "Top of your league promotes; bottom relegates")
                stepRow(number: 4, text: "Your tier carries forward — keep climbing")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
    }
    
    // MARK: - Tier Ladder
    
    private var tierLadderCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel("The ladder", icon: "chart.bar.fill", iconColor: standing?.tierSwiftUIColor ?? .blue)
            
            VStack(spacing: 0) {
                ForEach(Array(tiers.reversed().enumerated()), id: \.element.rank) { index, tier in
                    tierRow(tier: tier)
                    
                    if index < tiers.count - 1 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 0.5)
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: standing?.tierSwiftUIColor ?? .blue)
    }
    
    private func tierRow(tier: Tier) -> some View {
        let isCurrent = standing?.tierName == tier.name
        
        return HStack(spacing: Spacing.sm) {
            Group {
                if tier.rank == 7 {
                    VerifiedBadge(size: 20)
                } else {
                    Text(tier.emoji)
                        .font(.system(size: 22))
                }
            }
            .frame(width: 28, alignment: .center)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(tier.name)
                    .font(.ds_bodyMedium)
                    .fontWeight(isCurrent ? .bold : .semibold)
                    .foregroundColor(.primary)
                
                Text(tier.blurb)
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
            
            if isCurrent {
                Text("YOU")
                    .font(.ds_caption)
                    .fontWeight(.bold)
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: standing?.tierGradient ?? [tier.color, tier.color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    )
            }
        }
        .padding(.vertical, Spacing.xs)
        .background(
            isCurrent
                ? RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(tier.color.opacity(colorScheme == .dark ? 0.10 : 0.06))
                : nil
        )
    }
    
    // MARK: - Points
    
    private var pointsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel("Earn points by", icon: "bolt.fill", iconColor: .orange)
            
            HStack(spacing: Spacing.xs) {
                pointPill(icon: "dumbbell.fill",       label: "Strength",  color: .blue)
                pointPill(icon: "figure.run",          label: "Cardio",    color: .cyan)
                pointPill(icon: "flame.fill",          label: "Streaks",   color: .orange)
            }
            
            Text("Stay consistent — the league rewards weeks, not single PRs.")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .padding(.top, Spacing.xxs)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: .orange)
    }
    
    private func pointPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
            Text(label)
                .font(.ds_labelMedium)
        }
        .foregroundColor(color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.10))
        )
        .overlay(
            Capsule()
                .stroke(color.opacity(0.25), lineWidth: 0.5)
        )
    }
    
    // MARK: - Shared label
    
    private func sectionLabel(_ title: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.ds_bodySmall)
                .foregroundColor(iconColor)
            Text(title.uppercased())
                .font(.ds_labelSmall)
                .fontWeight(.semibold)
                .tracking(0.6)
                .foregroundColor(.secondary)
        }
    }
    
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.ds_labelMedium)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
            
            Text(text)
                .font(.ds_bodyMedium)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    WeeklyLeagueWidget(
        leagueService: WeeklyLeagueService.shared,
        onTap: {}
    )
    .padding()
}
