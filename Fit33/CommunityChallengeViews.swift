//
//  CommunityChallengeViews.swift
//  Fit33
//
//  Community Challenge UI — Browse, Join, Leaderboard, Create
//  These open challenges let unlimited users compete on a real-time leaderboard.
//

import SwiftUI

// MARK: - Community Challenges Hub

struct CommunityChallengesHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = CommunityChallengeService.shared
    @State private var selectedTab = 0  // 0 = My Challenges, 1 = Discover
    @State private var showingCreate = false
    @State private var showingJoinByCode = false
    @State private var joinCode = ""
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
                    .padding(.horizontal, 16)
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
                        await service.fetchMyChallenges()
                        await service.fetchFeaturedChallenges()
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
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
            }
            .task {
                await service.fetchMyChallenges()
                await service.fetchFeaturedChallenges()
            }
            .sheet(isPresented: $showingCreate) {
                CommunityCreateChallengeView()
            }
            .alert("Join by Code", isPresented: $showingJoinByCode) {
                TextField("Enter 6-digit code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button("Cancel", role: .cancel) { joinCode = "" }
                Button("Join") {
                    Task {
                        let _ = await service.joinChallenge(code: joinCode)
                        joinCode = ""
                    }
                }
            } message: {
                Text("Enter the challenge join code shared with you.")
            }
            .navigationDestination(item: $selectedChallenge) { challenge in
                CommunityLeaderboardView(challengeId: challenge.challengeId, initialTitle: challenge.title)
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
        LazyVStack(spacing: 12) {
            if service.myChallenges.isEmpty {
                emptyChallengesCard
            } else {
                ForEach(service.myChallenges) { challenge in
                    Button {
                        selectedChallenge = challenge
                    } label: {
                        MyCommunityChallengCard(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
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
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(12)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
    }
    
    // MARK: - Discover Tab
    
    private var discoverContent: some View {
        LazyVStack(spacing: 12) {
            if service.featuredChallenges.isEmpty {
                ProgressView()
                    .padding(.top, 40)
            } else {
                // Official challenges
                let official = service.featuredChallenges.filter(\.isOfficial)
                if !official.isEmpty {
                    sectionHeader("Official Fit33 Challenges", emoji: "⭐")
                    ForEach(official) { challenge in
                        FeaturedChallengeCard(challenge: challenge) {
                            Task {
                                let _ = await service.joinChallenge(code: challenge.joinCode)
                                await service.fetchFeaturedChallenges()
                            }
                        }
                    }
                }
                
                // Community created
                let community = service.featuredChallenges.filter { !$0.isOfficial }
                if !community.isEmpty {
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
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 40)
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

// MARK: - My Community Challenge Card

struct MyCommunityChallengCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let challenge: CommunityChallenge
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack(spacing: 12) {
                // Emoji badge
                Text(challenge.displayEmoji)
                    .font(.system(size: 32))
                
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
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack(spacing: 8) {
                        Label("\(challenge.formattedParticipantCount) joined", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let rank = challenge.myRank, rank > 0 {
                            Text("Rank #\(rank)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
                
                // Today's progress ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                        .frame(width: 44, height: 44)
                    
                    Circle()
                        .trim(from: 0, to: challenge.todayProgressPercentage)
                        .stroke(
                            challenge.targetHitToday ? Color.green : challenge.resolvedType.color,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                    
                    if challenge.targetHitToday {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.green)
                    } else {
                        Text("\(Int(challenge.todayProgressPercentage * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.primary)
                    }
                }
            }
            
            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Today: \(challenge.myTodayProgress ?? 0)/\(challenge.dailyTarget) \(challenge.targetUnit)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if let streak = challenge.myCurrentStreak, streak > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(streak)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 6)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: challenge.targetHitToday ? [.green, .mint] : challenge.resolvedType.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * challenge.todayProgressPercentage, height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}

// MARK: - Featured Challenge Card

struct FeaturedChallengeCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let challenge: FeaturedCommunityChallenge
    let onJoin: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(challenge.displayEmoji)
                    .font(.system(size: 36))
                
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
                                .foregroundColor(.blue)
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
            
            // Stats row
            HStack(spacing: 16) {
                Label("\(challenge.formattedParticipantCount) members", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(challenge.dailyTarget) \(challenge.targetUnit)/day", systemImage: "target")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if challenge.alreadyJoined {
                    Text("Joined")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                } else {
                    Button(action: onJoin) {
                        Text("Join")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                            )
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        )
    }
}


// MARK: - Community Leaderboard View

struct CommunityLeaderboardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var service = CommunityChallengeService.shared
    
    let challengeId: UUID
    let initialTitle: String
    
    @State private var leaderboard: CommunityLeaderboardResponse?
    @State private var isLoading = true
    @State private var showingShare = false
    @State private var showingLeave = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
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
                        
                        // My rank card
                        myRankCard(lb)
                        
                        // Share/Invite banner
                        shareBanner(lb)
                        
                        // Leaderboard list
                        leaderboardList(lb)
                        
                        // Leave button
                        leaveButton
                    }
                    .padding(.horizontal, 16)
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
            if let lb = leaderboard {
                let url = URL(string: "https://fit33.app/c/\(lb.inviteSlug)")!
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
    }
    
    private func loadLeaderboard() async {
        leaderboard = await service.getLeaderboard(challengeId: challengeId)
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
            .padding(.horizontal, 12)
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
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(cardBackground)
        )
    }
    
    // MARK: - My Rank Card
    
    private func myRankCard(_ lb: CommunityLeaderboardResponse) -> some View {
        HStack(spacing: 16) {
            // Rank
            VStack(spacing: 2) {
                Text("#\(lb.myRank)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: lb.myRank <= 3 ? [.yellow, .orange] : [.primary, .primary.opacity(0.8)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                Text("Your Rank")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Today's progress
            VStack(spacing: 2) {
                Text("\(lb.myTodayProgress)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(lb.myTodayProgress >= lb.dailyTarget ? .green : .primary)
                Text("Today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Days completed
            VStack(spacing: 2) {
                Text("\(lb.myDaysCompleted)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Days")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
                .frame(height: 40)
            
            // Streak
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text("\(lb.myCurrentStreak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                }
                Text("Streak")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: Color.blue.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Share Banner
    
    private func shareBanner(_ lb: CommunityLeaderboardResponse) -> some View {
        Button(action: { showingShare = true }) {
            HStack(spacing: 12) {
                Image(systemName: "megaphone.fill")
                    .font(.system(size: 20))
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
    
    // MARK: - Leaderboard List
    
    private func leaderboardList(_ lb: CommunityLeaderboardResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Leaderboard")
                    .font(.headline)
                
                Spacer()
                
                Text("Top \(lb.leaderboard?.count ?? 0)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let entries = lb.leaderboard, !entries.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LeaderboardRow(
                            entry: entry,
                            dailyTarget: lb.dailyTarget,
                            targetUnit: lb.targetUnit,
                            isCurrentUser: entry.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString
                        )
                        
                        if index < entries.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            } else {
                Text("No leaderboard data yet. Be the first to log progress!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(cardBackground)
                    )
            }
        }
    }
    
    // MARK: - Leave Button
    
    private var leaveButton: some View {
        Button(action: { showingLeave = true }) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.square")
                    .font(.system(size: 16))
                Text("Leave Challenge")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.1 : 0.05))
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }
}

// MARK: - Leaderboard Row

struct LeaderboardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: CommunityLeaderboardEntry
    let dailyTarget: Int
    let targetUnit: String
    let isCurrentUser: Bool
    
    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .orange
        default: return .secondary
        }
    }
    
    private var rankEmoji: String? {
        switch entry.rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank
            if let emoji = rankEmoji {
                Text(emoji)
                    .font(.system(size: 20))
                    .frame(width: 32)
            } else {
                Text("#\(entry.rank)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .frame(width: 32)
            }
            
            // Avatar
            if let photoUrl = entry.profilePhotoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(entry.firstName.prefix(1)))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            // Name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.firstName)
                        .font(.subheadline)
                        .fontWeight(isCurrentUser ? .bold : .medium)
                        .foregroundColor(isCurrentUser ? .blue : .primary)
                    
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
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Progress
            HStack(spacing: 6) {
                Text("\(entry.todayProgress)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(entry.targetHitToday ? .green : .primary)
                
                if entry.targetHitToday {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            isCurrentUser
                ? RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(colorScheme == .dark ? 0.1 : 0.05))
                : RoundedRectangle(cornerRadius: 10).fill(Color.clear)
        )
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
                                                .font(.system(size: 24))
                                            Text(type.rawValue)
                                                .font(.system(size: 10))
                                                .fontWeight(.medium)
                                                .foregroundColor(selectedType == type ? .white : .primary)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
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
                                        .font(.system(size: 28))
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
                                        .font(.system(size: 28))
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
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
                            .padding(.vertical, 16)
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
                        .padding(32)
                        
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
                            .padding(.vertical, 16)
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
                                .padding(.vertical, 16)
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

// MARK: - Make CommunityChallenge Hashable for NavigationDestination

extension CommunityChallenge: Hashable {
    static func == (lhs: CommunityChallenge, rhs: CommunityChallenge) -> Bool {
        lhs.challengeId == rhs.challengeId
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(challengeId)
    }
}
