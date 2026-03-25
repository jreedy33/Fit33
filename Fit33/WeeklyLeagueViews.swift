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
    @State private var showingLeagueInfo = false
    let onTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header (outside card)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
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
                            showingLeagueInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.ds_bodyRegular).fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(leagueSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                if let standing = standing {
                    HStack(spacing: 4) {
                        Text(standing.tierEmoji)
                            .font(.ds_bodySmall)
                        Text(standing.tierName)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(standing.tierSwiftUIColor)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, Spacing.xxs)
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
        .sheet(isPresented: $showingLeagueInfo) {
            WeeklyLeagueInfoSheet(standing: standing)
                .presentationDragIndicator(.visible)
        }
    }
    
    private var standing: LeagueStanding? { leagueService.standing }
    
    private var leagueSubtitle: String {
        guard let standing = standing else {
            return "Compete weekly with friends & nearby athletes. Earn points from workouts to climb tiers."
        }
        
        let socialPrefix: String = {
            let friends = standing.friendsInLeague
            let connections = standing.connectionsInLeague
            if friends > 0 {
                return "You know \(friends) \(friends == 1 ? "person" : "people") here. "
            } else if connections > 0 {
                return "\(connections) mutual connection\(connections == 1 ? "" : "s") in your league. "
            }
            return ""
        }()
        
        if standing.isInPromotionZone, let next = standing.nextTierName {
            return "\(socialPrefix)Top \(standing.promotionCount) — on track to \(next)! \(standing.daysRemaining)d left."
        } else if standing.isInRelegationZone {
            return "\(socialPrefix)Bottom \(standing.relegationCount) get relegated. \(standing.daysRemaining)d left."
        } else {
            let promoSpots = standing.promotionCount > 0 ? "Top \(standing.promotionCount) promote each week." : "Climb the ranks each week."
            return "\(socialPrefix)\(promoSpots)"
        }
    }
    
    // MARK: - League Content (Joined)
    
    private func leagueContent(standing: LeagueStanding) -> some View {
        VStack(spacing: 10) {
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
        
        return HStack(spacing: 8) {
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
                Text(entry.isCurrentUser ? "You" : entry.firstName)
                    .font(.system(size: 13, weight: entry.isCurrentUser ? .bold : .medium))
                    .foregroundColor(entry.isCurrentUser ? .primary : .secondary)
                    .lineLimit(1)
                
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
        .padding(.vertical, 5)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 8)
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
        .padding(Spacing.lg)
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
            }
        }
        .refreshable {
            await leagueService.fetchFullLeaderboard()
        }
    }
    
    private func fullLeaderboardRow(entry: LeagueEntry, standing: LeagueStanding) -> some View {
        let isPromoZone = standing.promotionCount > 0 && entry.rank <= standing.promotionCount
        let isRelegZone = standing.relegationCount > 0 && entry.rank > (standing.groupSize - standing.relegationCount)
        let showHideOption = !entry.isCurrentUser && entry.isFriend != true
        
        return HStack(spacing: 12) {
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
                HStack(spacing: 6) {
                    Text(entry.isCurrentUser ? "You" : entry.displayName)
                        .font(.subheadline)
                        .fontWeight(entry.isCurrentUser ? .bold : .medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if !entry.isCurrentUser, entry.isFriend == true {
                        Text("Friend")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                }
                
                if let workouts = entry.workoutsCompleted, workouts > 0 {
                    HStack(spacing: 4) {
                        Text("\(workouts) workout\(workouts == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if !entry.isCurrentUser, let mc = entry.mutualFriendCount, mc > 0 {
                            Text("·")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("\(mc) mutual friend\(mc == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.8))
                        }
                    }
                } else if !entry.isCurrentUser, let mc = entry.mutualFriendCount, mc > 0 {
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

// MARK: - Weekly League Info Sheet

struct WeeklyLeagueInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let standing: LeagueStanding?
    
    private let tiers: [(emoji: String, name: String, rank: Int)] = [
        ("🥉", "Bronze", 1),
        ("🥈", "Silver", 2),
        ("🥇", "Gold", 3),
        ("💎", "Platinum", 4),
        ("🔷", "Diamond", 5),
        ("🔥", "Elite", 6)
    ]
    
    private var exampleCompetitor: LeagueEntry? {
        standing?.leaderboard.first(where: { !$0.isCurrentUser })
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    howItWorksSection
                    tiersSection
                    promotionSection
                    pointsSection
                    
                    if let competitor = exampleCompetitor, let standing = standing {
                        exampleSection(competitor: competitor, tier: standing.tierName)
                    }
                }
                .padding()
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(white: 0.08), Color(white: 0.05)]
                        : [Color(white: 0.98), Color(white: 0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Weekly Leagues")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - Hero
    
    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.yellow.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 80
                        )
                    )
                    .frame(width: 140, height: 140)
                
                Image(systemName: "trophy.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: standing?.tierGradient ?? [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Compete Weekly")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Every week you're placed in a league with friends and athletes at your tier. Work out to earn points and climb the leaderboard!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xs)
        }
    }
    
    // MARK: - How It Works
    
    private var howItWorksSection: some View {
        infoCard(title: "How It Works", icon: "questionmark.circle.fill", color: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                infoRow(step: "1", text: "Leagues reset every Monday at midnight UTC")
                infoRow(step: "2", text: "Complete workouts to earn points throughout the week")
                infoRow(step: "3", text: "Top finishers promote to the next tier; bottom finishers relegate")
                infoRow(step: "4", text: "Your tier persists across weeks — keep climbing!")
            }
        }
    }
    
    // MARK: - Tiers
    
    private var tiersSection: some View {
        infoCard(title: "League Tiers", icon: "star.circle.fill", color: .yellow) {
            VStack(spacing: 8) {
                ForEach(tiers, id: \.rank) { tier in
                    HStack(spacing: 12) {
                        Text(tier.emoji)
                            .font(.title3)
                            .frame(width: 32)
                        
                        Text(tier.name)
                            .font(.subheadline)
                            .fontWeight(standing?.tierName == tier.name ? .bold : .regular)
                        
                        Spacer()
                        
                        if standing?.tierName == tier.name {
                            Text("You're here")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(standing?.tierSwiftUIColor ?? .blue)
                                )
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                    
                    if tier.rank < tiers.count {
                        Divider()
                    }
                }
            }
        }
    }
    
    // MARK: - Promotion / Relegation
    
    private var promotionSection: some View {
        infoCard(title: "Promotion & Relegation", icon: "arrow.up.arrow.down.circle.fill", color: .green) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Promotion")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Top finishers in your league move up to the next tier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Relegation")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Bottom finishers drop down a tier — stay active to hold your spot!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 10) {
                    Image(systemName: "shield.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Safe Zone")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Everyone in the middle stays at their current tier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Points
    
    private var pointsSection: some View {
        infoCard(title: "Earning Points", icon: "bolt.circle.fill", color: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Points are earned from completed workouts. The more consistent you are, the more points you'll accumulate throughout the week.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    pointBadge(label: "Workout", value: "+pts")
                    pointBadge(label: "Daily Login", value: "+pts")
                    pointBadge(label: "Consistency", value: "bonus")
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Example
    
    private func exampleSection(competitor: LeagueEntry, tier: String) -> some View {
        infoCard(title: "Your League", icon: "person.2.circle.fill", color: .cyan) {
            Text("For example, you and \(competitor.firstName) are both competing in \(tier) this week. Keep pushing to stay ahead!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Shared Components
    
    private func infoCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
        )
    }
    
    private func infoRow(step: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue))
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func pointBadge(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.1))
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
