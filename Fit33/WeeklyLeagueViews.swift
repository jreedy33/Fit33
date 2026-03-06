//
//  WeeklyLeagueViews.swift
//  Fit33
//
//  UI components for the Weekly League system.
//  Includes the compact widget for FriendsTabView and the full-screen detail view.
//

import SwiftUI

// MARK: - League Widget (for FriendsTabView)

/// Compact league card shown on the Friends tab.
/// Shows tier badge, current rank, points, and a mini leaderboard (top 3).
struct WeeklyLeagueWidget: View {
    @ObservedObject var leagueService: WeeklyLeagueService
    @Environment(\.colorScheme) private var colorScheme
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (outside card)
            HStack {
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
                
                Spacer()
                
                if let standing = standing {
                    HStack(spacing: 4) {
                        Text(standing.tierEmoji)
                            .font(.system(size: 14))
                        Text(standing.tierName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(standing.tierSwiftUIColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(standing.tierSwiftUIColor.opacity(0.15))
                    )
                }
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
                } else {
                    joinContent
                }
            }
            .buttonStyle(.plain)
        }
    }
    
    private var standing: LeagueStanding? { leagueService.standing }
    
    // MARK: - League Content (Joined)
    
    private func leagueContent(standing: LeagueStanding) -> some View {
        VStack(spacing: 14) {
            // Top row: Your rank + points + days remaining
            HStack(spacing: 16) {
                // Rank badge
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: standing.tierGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 52, height: 52)
                            .shadow(color: standing.tierSwiftUIColor.opacity(0.4), radius: 8, x: 0, y: 2)
                        
                        VStack(spacing: 0) {
                            Text("#\(standing.myRank)")
                                .font(.system(size: 18, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text("of \(standing.groupSize)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Points + status
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("\(standing.myPoints)")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("pts")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    
                    // Promotion / relegation status
                    if standing.isInPromotionZone, let nextTier = standing.nextTierName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.green)
                            Text("Promoting to \(nextTier)!")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                    } else if standing.isInRelegationZone, let prevTier = standing.prevTierName {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                            Text("Relegation zone — \(prevTier)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("Safe zone")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Days remaining
                VStack(spacing: 2) {
                    Text("\(standing.daysRemaining)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(standing.daysRemaining <= 1 ? .red : .primary)
                    Text(standing.daysRemaining == 1 ? "day left" : "days left")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 1)
            
            // Mini leaderboard (top 3 + user if not in top 3)
            miniLeaderboard(standing: standing)
            
            // "View Full Leaderboard" hint
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    Text("View Full Leaderboard")
                        .font(.caption2)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(standing.tierSwiftUIColor)
                Spacer()
            }
        }
        .padding(16)
        .sleekCard(cornerRadius: 24, accentColor: standing.tierSwiftUIColor)
    }
    
    // MARK: - Mini Leaderboard
    
    private func miniLeaderboard(standing: LeagueStanding) -> some View {
        let top3 = Array(standing.leaderboard.prefix(3))
        let userInTop3 = top3.contains(where: { $0.isCurrentUser })
        let currentUserEntry = standing.leaderboard.first(where: { $0.isCurrentUser })
        
        return VStack(spacing: 6) {
            ForEach(top3) { entry in
                leaderboardRow(entry: entry, standing: standing)
            }
            
            // Show user's row if not in top 3
            if !userInTop3, let userEntry = currentUserEntry {
                HStack(spacing: 0) {
                    ForEach(0..<3) { _ in
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                
                leaderboardRow(entry: userEntry, standing: standing)
            }
        }
    }
    
    private func leaderboardRow(entry: LeagueEntry, standing: LeagueStanding) -> some View {
        let isPromoZone = standing.promotionCount > 0 && entry.rank <= standing.promotionCount
        let isRelegZone = standing.relegationCount > 0 && entry.rank > (standing.groupSize - standing.relegationCount)
        
        return HStack(spacing: 10) {
            // Rank
            ZStack {
                if entry.rank <= 3 {
                    Text(entry.rank == 1 ? "🥇" : entry.rank == 2 ? "🥈" : "🥉")
                        .font(.system(size: 16))
                } else {
                    Text("#\(entry.rank)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .secondary)
                }
            }
            .frame(width: 28)
            
            // Photo
            CachedFriendPhoto(
                friendId: entry.userId.uuidString,
                photoUrl: entry.profilePhotoUrl,
                name: entry.displayName,
                size: 30,
                showGradientRing: entry.isCurrentUser,
                gradientColors: entry.isCurrentUser ? standing.tierGradient : [.gray.opacity(0.3)]
            )
            
            // Name
            Text(entry.isCurrentUser ? "You" : entry.firstName)
                .font(.subheadline)
                .fontWeight(entry.isCurrentUser ? .bold : .medium)
                .foregroundColor(entry.isCurrentUser ? .primary : .secondary)
                .lineLimit(1)
            
            Spacer()
            
            // Zone indicator
            if isPromoZone {
                Image(systemName: "arrow.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.green)
            } else if isRelegZone {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.red)
            }
            
            // Points
            Text("\(entry.points)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .primary)
            
            Text("pts")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(entry.isCurrentUser
                    ? standing.tierSwiftUIColor.opacity(colorScheme == .dark ? 0.12 : 0.08)
                    : Color.clear)
        )
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
        .padding(24)
        .sleekCard(cornerRadius: 24, accentColor: .yellow)
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
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 4) {
                Text("Join the Weekly League!")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text("Compete with ~30 athletes. Earn points from workouts. Top 5 get promoted!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                Text("Join Now")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
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
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(spacing: 12) {
            // Nav bar
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .padding(10)
                        .background(Circle().fill(Color.gray.opacity(0.15)))
                }
                
                Spacer()
                
                if let standing = leagueService.standing {
                    Text(standing.tierEmoji)
                        .font(.system(size: 20))
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
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Stats bar
            if let standing = leagueService.standing {
                HStack(spacing: 0) {
                    statPill(value: "#\(standing.myRank)", label: "Rank", color: standing.tierSwiftUIColor)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 30)
                    
                    statPill(value: "\(standing.myPoints)", label: "Points", color: .primary)
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 30)
                    
                    statPill(
                        value: "\(standing.daysRemaining)d",
                        label: "Remaining",
                        color: standing.daysRemaining <= 1 ? .red : .secondary
                    )
                    
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 1, height: 30)
                    
                    statPill(value: "\(standing.groupSize)", label: "Athletes", color: .secondary)
                }
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
    }
    
    private func statPill(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
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
                                .font(.system(size: 11))
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
            }
        }
        .refreshable {
            await leagueService.fetchFullLeaderboard()
        }
    }
    
    private func fullLeaderboardRow(entry: LeagueEntry, standing: LeagueStanding) -> some View {
        let isPromoZone = standing.promotionCount > 0 && entry.rank <= standing.promotionCount
        let isRelegZone = standing.relegationCount > 0 && entry.rank > (standing.groupSize - standing.relegationCount)
        
        return HStack(spacing: 12) {
            // Rank
            ZStack {
                if entry.rank <= 3 {
                    Text(entry.rank == 1 ? "🥇" : entry.rank == 2 ? "🥈" : "🥉")
                        .font(.system(size: 20))
                } else {
                    Text("#\(entry.rank)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .secondary)
                }
            }
            .frame(width: 32)
            
            // Photo
            CachedFriendPhoto(
                friendId: entry.userId.uuidString,
                photoUrl: entry.profilePhotoUrl,
                name: entry.displayName,
                size: 40,
                showGradientRing: entry.isCurrentUser,
                gradientColors: entry.isCurrentUser ? standing.tierGradient : [.gray.opacity(0.3)]
            )
            
            // Name + workouts
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.isCurrentUser ? "You" : entry.displayName)
                    .font(.subheadline)
                    .fontWeight(entry.isCurrentUser ? .bold : .medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let workouts = entry.workoutsCompleted, workouts > 0 {
                    Text("\(workouts) workout\(workouts == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Zone arrow
            if isPromoZone {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.green)
                    .padding(4)
                    .background(Circle().fill(Color.green.opacity(0.15)))
            } else if isRelegZone {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red)
                    .padding(4)
                    .background(Circle().fill(Color.red.opacity(0.15)))
            }
            
            // Points
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.points)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(entry.isCurrentUser ? standing.tierSwiftUIColor : .primary)
                Text("pts")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    entry.isCurrentUser
                        ? standing.tierSwiftUIColor.opacity(colorScheme == .dark ? 0.12 : 0.06)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 1)
    }
    
    private func zoneDivider(color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(color.opacity(0.4))
                .frame(height: 1)
            
            Text(text)
                .font(.system(size: 10, weight: .bold))
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
                .padding(.horizontal, 16)
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
            default: return "🏆"
            }
        }()
        
        return HStack(spacing: 12) {
            // Tier emoji
            Text(tierEmoji)
                .font(.system(size: 24))
                .frame(width: 36)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.tierName)
                        .font(.subheadline)
                        .fontWeight(.bold)
                    
                    if entry.wasPromoted {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10))
                            Text("Promoted")
                                .font(.caption2)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.green)
                    } else if entry.wasRelegated {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 10))
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
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("\(entry.finalPoints) pts")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
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
