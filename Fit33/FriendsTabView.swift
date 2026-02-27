import SwiftUI
import CoreData

// MARK: - Friends Tab View
/// The main social hub — friend circles, active challenges, recommended challenges,
/// community challenges, and quick friend search. High-energy, engaging design.

struct FriendsTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @StateObject private var friendService = FriendService.shared
    @StateObject private var rankingService = FriendRankingService.shared
    @StateObject private var challengeService = ChallengeService.shared
    @StateObject private var communityService = CommunityChallengeService.shared
    @StateObject private var privateChallengeService = PrivateChallengeService.shared
    @StateObject private var contactsService = ContactsService.shared
    
    @State private var showingFriendsList = false
    @State private var showingFriendSearch = false
    @State private var showingFriendProfile: Friend?
    @State private var showingCommunityHub = false
    @State private var showingChallengeCreation = false
    @State private var activeChallengePageIndex = 0
    @State private var sentRecommendedChallenge = false
    @State private var showingSentConfirmation = false
    @State private var navigationPath = NavigationPath()
    @State private var sentRequestIds: Set<UUID> = [] // Track sent friend requests for instant UI
    @State private var requestSentAnimationIds: Set<UUID> = [] // Temporary "Request Sent" animation state
    @State private var selectedCommunityChallenge: CommunityChallenge?
    @State private var showingAllCommunities = false
    @State private var hasAppearedBefore = false
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // Custom header
                    friendsHeaderView
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    
                    VStack(spacing: 24) {
                        // Instagram-style friend stories bar
                        friendStoriesBar
                        
                        // Top 3 Best Friends spotlight
                        topFriendsSpotlight
                        
                        // Quick action tiles: Add Friend, New Challenge, Join Community
                        friendsQuickActionTiles
                        
                        // Active Challenges carousel
                        activeChallengesCarousel
                        
                        // Private Challenges (invite-only communities)
                        if !privateChallengeService.myChallenges.isEmpty {
                            privateChallengeWidget
                        }
                        
                        // Community Challenges (leaderboard widgets)
                        communityChallengeWidget
                        
                        // Recommended Challenge for You — only when no active community challenges
                        if communityService.myChallenges.isEmpty {
                            recommendedChallengeWidget
                        }
                        
                        // Quick Actions
                        socialQuickActions
                        
                        // Bottom padding for tab bar
                        Spacer(minLength: 100)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .refreshable {
                // Pull-to-refresh: refresh everything in parallel for speed
                await refreshAllFriendsData(force: true)
            }
            .background(
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
            )
            .navigationBarHidden(true)
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { destination in
                if destination == "FriendsList" {
                    FriendsListView()
                } else if destination == "CommunityHub" {
                    CommunityChallengesHubView()
                }
            }
            .navigationDestination(item: $selectedCommunityChallenge) { challenge in
                CommunityDetailView(challengeId: challenge.challengeId, challengeTitle: challenge.title)
            }
        }
        .task {
            // ⚡️ INSTANT DISPLAY: FriendService and FriendRankingService load cached
            // data in their init(), so the Friends tab shows populated data immediately.
            // This .task just refreshes from the server in the background.
            
            // Small debounce to avoid competing with Dashboard's initial load
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            guard !Task.isCancelled else { return }
            
            await refreshAllFriendsData(force: false)
            hasAppearedBefore = true
        }
        .onAppear {
            // Auto-refresh when returning to this tab (after initial load)
            if hasAppearedBefore {
                // Clear sent IDs so stale markers don't block refreshed suggestions
                sentRequestIds.removeAll()
                requestSentAnimationIds.removeAll()
                Task {
                    await refreshAllFriendsData(force: false)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Auto-refresh when app comes back to foreground
            if newPhase == .active && oldPhase != .active {
                Task {
                    await refreshAllFriendsData(force: false)
                }
            }
        }
        .sheet(item: $showingFriendProfile) { friend in
            NavigationStack {
                FriendProfileView(friend: friend)
            }
        }
        .sheet(isPresented: $showingFriendsList) {
            NavigationStack {
                FriendsListView()
            }
        }
        .sheet(isPresented: $showingFriendSearch) {
            NavigationStack {
                FriendsListView(initialTab: 2)
            }
        }
        .sheet(isPresented: $showingCommunityHub) {
            CommunityChallengesHubView()
        }
        .sheet(isPresented: $showingAllCommunities) {
            AllCommunityChallengesView()
        }
        .fullScreenCover(isPresented: $showingChallengeCreation) {
            NavigationStack {
                ChallengeFlowStartView()
                    .environmentObject(userManager)
            }
        }
        .overlay(
            sentConfirmationOverlay
        )
    }
    
    // MARK: - Header
    
    // MARK: - Refresh Helper
    
    /// Central refresh for all Friends tab data.
    /// Uses throttling in CommunityChallengeService/PrivateChallengeService to avoid redundant calls.
    private func refreshAllFriendsData(force: Bool) async {
        // Batch 1: Fast social data (parallel)
        async let friends: () = friendService.fetchFriends()
        async let ranked: () = rankingService.fetchRankedFriends()
        async let pending: () = friendService.fetchPendingRequests()
        async let invites: () = challengeService.fetchPendingInvites()
        async let privateInvites: () = PrivateChallengeService.shared.fetchPendingInvites()
        _ = await (friends, ranked, pending, invites, privateInvites)
        
        // Batch 2: Challenge data — all types in parallel
        async let active: () = challengeService.fetchActiveChallenges()
        async let groups: () = challengeService.fetchActiveGroupChallenges()
        async let community: () = communityService.refreshAll(force: force)
        async let privateChallenges: () = PrivateChallengeService.shared.refreshAll(force: force)
        _ = await (active, groups, community, privateChallenges)
        
        // Batch 3: Friend suggestions (contacts + mutual friends in parallel)
        async let pymk: () = contactsService.fetchPeopleYouMayKnow()
        if contactsService.canAccessContacts {
            async let contactRefresh: () = contactsService.fetchContactsAndFindFriends()
            _ = await (pymk, contactRefresh)
        } else {
            _ = await pymk
        }
    }
    
    // MARK: - Header
    
    private var friendsHeaderView: some View {
        HStack {
            Text("Friends")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue, Color(red: 0.5, green: 0.3, blue: 0.95).opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.cyan.opacity(0.4), radius: 6, x: 0, y: 2)
            
            Spacer()
        }
        .padding(.leading, 4)
    }
    
    // MARK: - Add Friends Bar (Non-Friends from Contacts)
    
    private var friendStoriesBar: some View {
        // Combined suggestions: mutual friends (friends-of-friends) first, then contacts
        // Cross-reference against actual FriendService.friends to exclude existing friends
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let suggestions = contactsService.allSuggestions(
            excludingFriendIds: existingFriendIds,
            excludingSentIds: sentRequestIds
        )
        
        return Group {
            if !suggestions.isEmpty || contactsService.canAccessContacts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        // Search / Find friends circle
                        Button(action: {
                            HapticManager.selectionChanged()
                            showingFriendSearch = true
                        }) {
                            VStack(spacing: 5) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [.blue.opacity(0.2), .cyan.opacity(0.15)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 58, height: 58)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                                                    style: StrokeStyle(lineWidth: 2.5, dash: [6, 4])
                                                )
                                                .frame(width: 66, height: 66)
                                        )
                                    
                                    Image(systemName: "person.badge.plus")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(
                                            LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                        )
                                }
                                .frame(width: 64, height: 64)
                                
                                Text("Add Friends")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                        
                        // Friend suggestions (mutuals first, then contacts)
                        ForEach(suggestions.prefix(15)) { suggestion in
                            contactSuggestionCircle(suggestion: suggestion)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .scale(scale: 0.5).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                }
            } else if !contactsService.canAccessContacts {
                // Prompt to enable contacts
                Button(action: {
                    HapticManager.selectionChanged()
                    showingFriendsList = true
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.blue.opacity(0.2), .cyan.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 44, height: 44)
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.system(size: 18))
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find friends from contacts")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            Text("See who's already on Fit33")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .sleekCard(cornerRadius: 18, accentColor: .blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func contactSuggestionCircle(suggestion: SuggestedFriend) -> some View {
        let isSent = requestSentAnimationIds.contains(suggestion.userId)
        
        return Button(action: {
            guard !isSent else { return }
            HapticManager.impact(.medium)
            
            // Show "Request Sent" animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                requestSentAnimationIds.insert(suggestion.userId)
            }
            
            // Send friend request
            Task {
                let success = await friendService.sendFriendRequest(toUserId: suggestion.userId)
                if !success {
                    // Revert animation if failed
                    withAnimation(.spring(response: 0.3)) {
                        requestSentAnimationIds.remove(suggestion.userId)
                    }
                } else {
                    // After brief delay, slide out and replace with next suggestion
                    try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        sentRequestIds.insert(suggestion.userId)
                        requestSentAnimationIds.remove(suggestion.userId)
                    }
                }
            }
        }) {
            VStack(spacing: 5) {
                ZStack {
                    // Profile photo (cached) or initials
                    CachedFriendPhoto(
                        friendId: suggestion.userId.uuidString,
                        photoUrl: suggestion.profilePhotoUrl,
                        name: suggestion.name ?? suggestion.username ?? "?",
                        size: 58,
                        showGradientRing: false,
                        gradientColors: [.blue.opacity(0.6), .cyan.opacity(0.4)]
                    )
                    
                    // "Request Sent" overlay
                    if isSent {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 58, height: 58)
                        
                        VStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.green)
                            Text("Sent")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: isSent ? [.green.opacity(0.6), .green.opacity(0.3)] : [.blue.opacity(0.5), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 66, height: 66)
                )
                // Blue + badge (bottom-right corner)
                .overlay(alignment: .bottomTrailing) {
                    if !isSent {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 22, height: 22)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                        }
                        .offset(x: 2, y: 2)
                    }
                }
                
                Text(suggestion.name?.components(separatedBy: " ").first ?? suggestion.username ?? "Add")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSent ? .green : .primary)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }
    
    private func suggestionInitialsCircle(suggestion: SuggestedFriend) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [.blue.opacity(0.7), .cyan.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 58, height: 58)
            
            Text(suggestion.initials)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Quick Action Tiles (Add Friend, New Challenge, Join Community)
    
    private var friendsQuickActionTiles: some View {
        HStack(spacing: 12) {
            // New Challenge → same flow as "Challenge a Friend" on home screen
            FriendsQuickTile(
                icon: "trophy.fill",
                title: "New\nChallenge",
                gradient: [.orange, .red],
                action: { showingChallengeCreation = true }
            )
            
            // Join Community → community challenges hub
            FriendsQuickTile(
                icon: "globe.americas.fill",
                title: "Join\nCommunity",
                gradient: [.green, .mint],
                action: { showingCommunityHub = true }
            )
        }
    }
    
    // MARK: - Top 3 Best Friends Spotlight
    
    private var topFriendsSpotlight: some View {
        let topThree = Array(rankingService.rankedFriends.prefix(3))
        
        return Group {
            if topThree.count >= 1 {
                VStack(alignment: .leading, spacing: 12) {
                    // Header OUTSIDE the card
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.yellow, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.title3)
                        Text("Your Inner Circle")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    // Card content
                    HStack(spacing: 12) {
                        ForEach(Array(topThree.enumerated()), id: \.element.id) { index, rankedFriend in
                            if let friend = friendService.friends.first(where: { $0.friendId == rankedFriend.friendId }) {
                                topFriendCard(friend: friend, rankedFriend: rankedFriend, rank: index + 1)
                            }
                        }
                        
                        if topThree.count < 3 {
                            ForEach(topThree.count..<3, id: \.self) { _ in
                                emptyFriendSlot
                            }
                        }
                    }
                    .padding(16)
                    .sleekCard(cornerRadius: 24, accentColor: .yellow)
                }
            } else {
                noFriendsYetCard
            }
        }
    }
    
    private func topFriendCard(friend: Friend, rankedFriend: RankedFriend, rank: Int) -> some View {
        let medalColor: [Color] = {
            switch rank {
            case 1: return [.yellow, .orange]
            case 2: return [.gray, .white]
            case 3: return [.orange, .brown]
            default: return [.blue, .cyan]
            }
        }()
        let medalEmoji = rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉"
        
        return Button(action: {
            HapticManager.selectionChanged()
            showingFriendProfile = friend
        }) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    CachedFriendPhoto(
                        friendId: friend.friendId.uuidString,
                        photoUrl: friend.profilePhotoUrl,
                        name: friend.friendName ?? friend.friendUsername ?? "Friend",
                        size: 52,
                        showGradientRing: true,
                        gradientColors: medalColor
                    )
                    
                    Text(medalEmoji)
                        .font(.system(size: 16))
                        .offset(x: 4, y: 4)
                }
                
                Text(rankedFriend.displayName.components(separatedBy: " ").first ?? "Friend")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(rankedFriend.challengesTogether) challenges")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyFriendSlot: some View {
        Button(action: {
            HapticManager.selectionChanged()
            showingFriendsList = true
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        )
                    
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.gray.opacity(0.5))
                }
                
                Text("Add")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("friend")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private var noFriendsYetCard: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.cyan.opacity(0.2), .blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 72, height: 72)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            VStack(spacing: 6) {
                Text("Find Your Fit Friends")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Text("Add friends to challenge, compete, and motivate each other!")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                HapticManager.impact(.medium)
                showingFriendsList = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.plus")
                    Text("Find Friends")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(25)
                .shadow(color: .cyan.opacity(0.3), radius: 10, x: 0, y: 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .sleekCard(cornerRadius: 24, accentColor: .cyan)
    }
    
    // MARK: - Active Challenges Carousel
    
    private var activeChallengesCarousel: some View {
        let activeChallenges = challengeService.activeChallenges
        let groupChallenges = challengeService.activeGroupChallenges.filter { $0.iHaveAccepted }
        let totalCards = activeChallenges.count + groupChallenges.count
        let safePageIndex = totalCards > 0 ? min(max(0, activeChallengePageIndex), totalCards - 1) : 0
        
        return Group {
            if totalCards > 0 {
                VStack(spacing: 4) {
                    // Header — same style as home screen
                    HStack {
                        Image(systemName: "flame.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.title3)
                        Text("Active Challenges")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Text("\(totalCards) active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )
                    }
                    
                    if totalCards > 1 {
                        // Multiple cards — swipeable GeometryReader (same as home screen)
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                ForEach(Array(activeChallenges.enumerated()), id: \.element.id) { index, challenge in
                                    activeChallengeCard(challenge: challenge)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == index ? 1 : 0)
                                }
                                
                                ForEach(Array(groupChallenges.enumerated()), id: \.element.id) { index, group in
                                    groupChallengeCard(challenge: group)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeChallenges.count + index) ? 1 : 0)
                                }
                            }
                            .offset(x: -CGFloat(safePageIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: safePageIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 && totalCards > 0 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && activeChallengePageIndex < totalCards - 1 {
                                            activeChallengePageIndex += 1
                                        } else if horizontalAmount > 0 && activeChallengePageIndex > 0 {
                                            activeChallengePageIndex -= 1
                                        }
                                    }
                                }
                        )
                        
                        // Page indicators (dash and dot style — same as home)
                        HStack(spacing: 6) {
                            ForEach(0..<totalCards, id: \.self) { index in
                                Capsule()
                                    .fill(safePageIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: safePageIndex == index ? 20 : 8, height: 6)
                                    .animation(.easeOut(duration: 0.2), value: safePageIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        activeChallengePageIndex = index
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                    } else if let challenge = activeChallenges.first {
                        // Single 1v1 challenge
                        activeChallengeCard(challenge: challenge)
                    } else if let group = groupChallenges.first {
                        // Single group challenge
                        groupChallengeCard(challenge: group)
                    }
                }
            } else {
                noChallengesCard
            }
        }
    }
    
    private func activeChallengeCard(challenge: ActiveChallenge) -> some View {
        let isAccountability = challenge.mode == .accountability
        let resolvedType = challenge.resolvedType
        let typeColor = resolvedType.color
        let typeGradient = resolvedType.gradientColors
        let resolver = ChallengeProgressResolver.shared
        let myProgress = resolver.liveProgress(for: challenge)
        let oppProgress = challenge.opponentTodayProgress ?? 0
        let amWinning = myProgress > oppProgress
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        
        return VStack(spacing: 0) {
            // Header row — identical to home screen
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Text(resolvedType.emoji)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(isAccountability ? "with \(opponentFirst)" : "vs \(opponentFirst)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(challenge.daysRemaining)d left")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(typeColor)
                    }
                }
                
                Spacer()
                
                Text(isAccountability ? "🤝" : "⚔️")
                    .font(.system(size: 16))
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            // Inner gray status bar — identical to home screen
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, 4)
                
                if isAccountability {
                    friendsTabAccountabilityBar(challenge: challenge, typeColor: typeColor, typeGradient: typeGradient)
                } else {
                    friendsTabCompetitionBar(challenge: challenge, typeColor: typeColor, typeGradient: typeGradient)
                }
            }
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.black.opacity(0.03))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 24)
                    .stroke(
                        LinearGradient(
                            colors: [typeColor.opacity(0.5), typeGradient.last?.opacity(0.3) ?? typeColor.opacity(0.3), typeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: typeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .padding(.horizontal, 4)
    }
    
    // MARK: - Competition Bar (head-to-head with avatars + swords)
    
    private func friendsTabCompetitionBar(challenge: ActiveChallenge, typeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let resolvedType = challenge.resolvedType
        let myProgress = resolver.liveProgress(for: challenge)
        let oppProgress = challenge.opponentTodayProgress ?? 0
        let amWinning = myProgress > oppProgress
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        
        return HStack(spacing: 8) {
            // Your side
            HStack(spacing: 8) {
                friendsChallengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: amWinning,
                    gradientColors: typeGradient,
                    size: 36
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text("You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        if amWinning {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Text(resolver.formatValue(myProgress, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(amWinning ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .leading)
            }
            
            Spacer(minLength: 4)
            
            // VS divider with score diff
            VStack(spacing: 2) {
                Text("⚔️")
                    .font(.system(size: 14))
                
                if myProgress != oppProgress {
                    let diff = abs(myProgress - oppProgress)
                    let diffStr = resolver.formatValue(diff, unit: challenge.targetUnit, type: resolvedType)
                    Text(amWinning ? "+\(diffStr)" : "-\(diffStr)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(amWinning ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: 30)
            
            Spacer(minLength: 4)
            
            // Opponent side
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        if !amWinning && oppProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                        Text(opponentFirst)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(resolver.formatValue(oppProgress, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(!amWinning && oppProgress > 0 ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .trailing)
                
                friendsChallengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: !amWinning && oppProgress > 0,
                    gradientColors: [.orange, .red],
                    size: 36
                )
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    // MARK: - Accountability Bar (buddy check-in)
    
    private func friendsTabAccountabilityBar(challenge: ActiveChallenge, typeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let resolvedType = challenge.resolvedType
        let myProgress = resolver.liveProgress(for: challenge)
        let oppProgress = challenge.opponentTodayProgress ?? 0
        let myDone = challenge.dailyTarget.map { myProgress >= $0 } ?? false
        let oppDone = challenge.dailyTarget.map { oppProgress >= $0 } ?? false
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Buddy"
        let livePercent = resolver.progressPercentage(for: challenge)
        
        return HStack(spacing: 12) {
            // Both avatars together with status
            HStack(spacing: -8) {
                friendsChallengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: myDone,
                    gradientColors: typeGradient,
                    size: 36
                )
                .zIndex(1)
                
                friendsChallengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: oppDone,
                    gradientColors: typeGradient,
                    size: 36
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Live progress value for "my" side
                HStack(spacing: 4) {
                    Text(myDone ? "✅" : "⬜")
                        .font(.system(size: 12))
                    Text(resolver.formattedProgress(for: challenge))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(myDone ? .green : typeColor)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(oppDone ? "✅" : "⬜")
                        .font(.system(size: 12))
                    Text(opponentFirst)
                        .font(.caption2)
                        .foregroundColor(oppDone ? .green : .secondary)
                        .lineLimit(1)
                }
                
                // Shared streak
                HStack(spacing: 4) {
                    if challenge.myCurrentStreak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(challenge.myCurrentStreak)-day streak together")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    } else {
                        Text(friendsTabAccountabilityEncouragement(for: resolvedType))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Daily progress ring — type-colored with live percentage
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 3)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: livePercent)
                    .stroke(
                        LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                
                if myDone && oppDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(livePercent * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    private func friendsTabAccountabilityEncouragement(for type: ChallengeType) -> String {
        switch type {
        case .hydrate: return "Drink up together today!"
        case .protein: return "Hit your protein today!"
        case .calories: return "Burn it together!"
        case .steps: return "Start stepping today!"
        case .walk: return "Get walking today!"
        case .run: return "Lace up and go!"
        case .lift: return "Hit the weights today!"
        case .activeMinutes: return "Get moving today!"
        case .workoutStreak: return "Start your streak today!"
        }
    }
    
    // MARK: - Challenge Avatar Helper (Friends Tab)
    
    private func friendsChallengeAvatar(isUser: Bool, userId: String? = nil, photoUrl: String?, name: String?, done: Bool, gradientColors: [Color], size: CGFloat = 36) -> some View {
        let borderWidth: CGFloat = size > 30 ? 2 : 1.5
        
        return Group {
            if isUser {
                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: borderWidth))
                } else {
                    CachedFriendPhoto(
                        friendId: SupabaseManager.shared.currentUser?.id.uuidString ?? "me",
                        photoUrl: nil,
                        name: name ?? "You",
                        size: size,
                        showGradientRing: false,
                        gradientColors: gradientColors
                    )
                    .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: borderWidth))
                }
            } else {
                CachedFriendPhoto(
                    friendId: userId ?? UUID().uuidString,
                    photoUrl: photoUrl,
                    name: name ?? "Friend",
                    size: size,
                    showGradientRing: false,
                    gradientColors: gradientColors
                )
                .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: borderWidth))
            }
        }
    }
    
    private func groupChallengeCard(challenge: ActiveGroupChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let typeGradient = resolvedType.gradientColors
        let participantCount = challenge.memberCount
        
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    Text(resolvedType.emoji)
                        .font(.system(size: 18))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("\(participantCount) participants")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 10))
                    Text("\(participantCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.gray.opacity(0.15)))
            }
            .padding(16)
            
            // Progress bar
            let target = challenge.dailyTarget ?? 0
            let liveProgress = ChallengeProgressResolver.shared.liveProgress(for: challenge)
            let progressPct = target > 0 ? min(1.0, Double(liveProgress) / Double(target)) : 0
            
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 8)
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(LinearGradient(colors: typeGradient, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * progressPct, height: 8)
                    }
                }
                .frame(height: 8)
                
                HStack {
                    Text("\(liveProgress) / \(target) \(challenge.targetUnit)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(progressPct * 100))%")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(resolvedType.color)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .sleekCard(cornerRadius: 20, accentColor: resolvedType.color)
        .padding(.horizontal, 4)
    }
    
    private var noChallengesCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header OUTSIDE the card
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Active Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            // Card content
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.orange.opacity(0.2), .red.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                Text("No active challenges yet")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Challenge a friend and start competing!")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    HapticManager.impact(.medium)
                    showingChallengeCreation = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                        Text("Start a Challenge")
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(20)
                    .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 2)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .sleekCard(cornerRadius: 24, accentColor: .orange)
        }
    }
    
    // MARK: - Recommended Challenge Widget
    
    private var recommendedChallengeWidget: some View {
        let topFriend = rankingService.rankedFriends.first
        
        // Generate a smart recommendation based on user activity
        let recommendedType: ChallengeType = {
            // Pick a challenge type that's popular and engaging
            let types: [ChallengeType] = [.steps, .workoutStreak, .hydrate, .activeMinutes]
            let hour = Calendar.current.component(.hour, from: Date())
            if hour < 12 { return .steps }       // Morning → steps
            if hour < 17 { return .activeMinutes } // Afternoon → active minutes
            return .workoutStreak                    // Evening → workout streak
        }()
        
        let challengeTitle: String = {
            switch recommendedType {
            case .steps: return "👟 10K Steps Challenge"
            case .workoutStreak: return "🔥 7-Day Workout Streak"
            case .hydrate: return "💧 Daily Hydration Goal"
            case .activeMinutes: return "⏱️ 30 Active Minutes"
            default: return "🏆 Weekly Challenge"
            }
        }()
        
        let challengeDescription: String = {
            if let friend = topFriend {
                let firstName = friend.displayName.components(separatedBy: " ").first ?? "your friend"
                return "We think you and \(firstName) would crush this!"
            }
            return "Challenge a friend and level up together!"
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header OUTSIDE the card
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Recommended for You")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            // Card content
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    // Challenge type icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: recommendedType.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                            .shadow(color: recommendedType.color.opacity(0.3), radius: 8, x: 0, y: 2)
                        
                        Text(recommendedType.emoji)
                            .font(.system(size: 24))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(challengeTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text(challengeDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                }
                
                // Friend preview + Send button
                HStack(spacing: 12) {
                    if let friend = topFriend {
                        HStack(spacing: 8) {
                            CachedFriendPhoto(
                                friendId: friend.friendId.uuidString,
                                photoUrl: friend.profilePhotoUrl,
                                name: friend.displayName,
                                size: 32,
                                showGradientRing: true,
                                gradientColors: [.purple, .pink]
                            )
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Send to")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(friend.displayName.components(separatedBy: " ").first ?? "Friend")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        HapticManager.impact(.medium)
                        if !sentRecommendedChallenge {
                            sentRecommendedChallenge = true
                            showingSentConfirmation = true
                            
                            // Auto-dismiss confirmation after 2.5s
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                                showingSentConfirmation = false
                            }
                            
                            // Actually create the challenge
                            if let friend = topFriend {
                                Task {
                                    await sendRecommendedChallenge(
                                        type: recommendedType,
                                        title: challengeTitle,
                                        friendId: friend.friendId
                                    )
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: sentRecommendedChallenge ? "checkmark.circle.fill" : "paperplane.fill")
                            Text(sentRecommendedChallenge ? "Sent!" : "Send Challenge")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: sentRecommendedChallenge ? [.green, .mint] : [.purple, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(20)
                        .shadow(color: (sentRecommendedChallenge ? Color.green : Color.purple).opacity(0.3), radius: 8, x: 0, y: 2)
                    }
                    .disabled(sentRecommendedChallenge)
                }
            }
            .padding(16)
            .sleekCard(cornerRadius: 24, accentColor: .purple)
        }
    }
    
    private func sendRecommendedChallenge(type: ChallengeType, title: String, friendId: UUID) async {
        // Build challenge parameters based on type
        let dailyTarget: Int = {
            switch type {
            case .steps: return 10000
            case .workoutStreak: return 1
            case .hydrate: return 2500
            case .activeMinutes: return 30
            default: return 10000
            }
        }()
        
        let unit: String = {
            switch type {
            case .steps: return "steps"
            case .workoutStreak: return "workouts"
            case .hydrate: return "ml"
            case .activeMinutes: return "minutes"
            default: return "steps"
            }
        }()
        
        _ = await challengeService.createChallenge(
            opponentId: friendId,
            type: type,
            title: "⚔️ " + title,
            dailyTarget: dailyTarget,
            targetUnit: unit,
            durationDays: 7
        )
    }
    
    // MARK: - Community Challenge Widget
    
    // MARK: - Private Challenges Widget
    
    private var privateChallengeWidget: some View {
        let challenges = privateChallengeService.myChallenges
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Private Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                if challenges.count > 3 {
                    Text("\(challenges.count) total")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.purple)
                }
            }
            
            // Active private challenge cards (max 3)
            ForEach(challenges.prefix(3)) { challenge in
                NavigationLink(value: "PrivateChallenge_\(challenge.challengeId.uuidString)") {
                    privateChallengeRow(challenge: challenge)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationDestination(for: String.self) { value in
            if value.hasPrefix("PrivateChallenge_") {
                let idStr = String(value.dropFirst("PrivateChallenge_".count))
                if let challenge = privateChallengeService.myChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                    PrivateChallengeDetailView(challenge: challenge)
                }
            }
        }
    }
    
    private func privateChallengeRow(challenge: PrivateChallenge) -> some View {
        let type = challenge.resolvedType
        let progress = challenge.todayProgressPercentage
        
        return HStack(spacing: 12) {
            // Emoji + progress ring
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 4)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                
                Text(challenge.displayEmoji)
                    .font(.system(size: 20))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Members
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(challenge.formattedMemberCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    // Progress
                    Text("\(challenge.myTodayProgress ?? 0)/\(challenge.dailyTarget) \(challenge.targetUnit)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(challenge.targetHitToday ? .green : .secondary)
                    
                    if challenge.targetHitToday {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                    
                    // Streak
                    if let streak = challenge.myCurrentStreak, streak > 0 {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 2) {
                            Text("🔥")
                                .font(.system(size: 9))
                            Text("\(streak)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Rank badge
            if let rank = challenge.myRank, rank > 0 {
                VStack(spacing: 2) {
                    Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "#\(rank)")
                        .font(.system(size: rank <= 3 ? 16 : 12, weight: .bold))
                    
                    if rank > 3 {
                        Text("rank")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .pink.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Community Challenges Widget
    
    private var communityChallengeWidget: some View {
        let myChallenges = communityService.myChallenges
        let featured = communityService.featuredChallenges.filter { !$0.alreadyJoined }.prefix(2)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "globe.americas.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Community Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    HapticManager.selectionChanged()
                    showingCommunityHub = true
                }) {
                    Text("Browse")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
            
            // ── My Active Community Challenges (leaderboard widgets, max 3) ──
            if !myChallenges.isEmpty {
                ForEach(myChallenges.prefix(3)) { challenge in
                    Button {
                        selectedCommunityChallenge = challenge
                    } label: {
                        CommunityLeaderboardWidget(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
                
                // "See all" button when 4+ challenges
                if myChallenges.count > 3 {
                    Button(action: {
                        HapticManager.selectionChanged()
                        showingAllCommunities = true
                    }) {
                        HStack(spacing: 8) {
                            Text("See all \(myChallenges.count) challenges")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(colors: [.green.opacity(0.8), .mint.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                    }
                }
            }
            
            // ── Discover (only show if user has no challenges) ──
            if myChallenges.isEmpty {
                if !featured.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(Array(featured)) { challenge in
                            communityDiscoverRow(challenge: challenge)
                        }
                    }
                } else {
                    // Empty state — no challenges at all
                    VStack(spacing: 12) {
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green.opacity(0.4))
                        
                        Text("Compete on global leaderboards")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Button(action: {
                            HapticManager.impact(.medium)
                            showingCommunityHub = true
                        }) {
                            Text("Browse Challenges")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .sleekCard(cornerRadius: 24, accentColor: .green)
                }
            }
        }
    }
    
    private func communityDiscoverRow(challenge: FeaturedCommunityChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let typeGradient = resolvedType.gradientColors
        
        return HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Text(challenge.displayEmoji)
                    .font(.system(size: 20))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9))
                        Text("\(challenge.formattedParticipantCount)")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    
                    if challenge.isOfficial {
                        HStack(spacing: 2) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                            Text("Official")
                                .font(.caption2)
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                HapticManager.impact(.medium)
                Task {
                    _ = await communityService.joinChallenge(code: challenge.joinCode)
                    await communityService.fetchFeaturedChallenges()
                    await communityService.fetchMyChallenges()
                }
            }) {
                Text("Join")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: typeGradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(16)
                    .shadow(color: resolvedType.color.opacity(0.25), radius: 6, x: 0, y: 2)
            }
        }
        .padding(14)
        .sleekCard(cornerRadius: 18, accentColor: resolvedType.color)
    }
    
    // MARK: - Social Quick Actions
    
    private var socialQuickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Quick Actions")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
            }
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                quickActionCard(
                    icon: "person.2.fill",
                    title: "Friends",
                    subtitle: "\(friendService.friends.count) friends",
                    gradient: [.cyan, .blue],
                    action: { showingFriendsList = true }
                )
                
                quickActionCard(
                    icon: "trophy.fill",
                    title: "Challenge",
                    subtitle: "Start new",
                    gradient: [.orange, .red],
                    action: { showingChallengeCreation = true }
                )
                
                quickActionCard(
                    icon: "globe.americas.fill",
                    title: "Community",
                    subtitle: "Join challenges",
                    gradient: [.green, .mint],
                    action: { showingCommunityHub = true }
                )
                
                quickActionCard(
                    icon: "qrcode.viewfinder",
                    title: "Scan QR",
                    subtitle: "Add friend",
                    gradient: [.purple, .pink],
                    action: { showingFriendsList = true }
                )
            }
        }
    }
    
    private func quickActionCard(icon: String, title: String, subtitle: String, gradient: [Color], action: @escaping () -> Void) -> some View {
        Button(action: {
            HapticManager.selectionChanged()
            action()
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: gradient.map { $0.opacity(0.2) }, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .sleekCard(cornerRadius: 18, accentColor: gradient.first ?? .blue)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Sent Confirmation Overlay
    
    private var sentConfirmationOverlay: some View {
        Group {
            if showingSentConfirmation {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 56, height: 56)
                            .shadow(color: .green.opacity(0.4), radius: 15, x: 0, y: 0)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text("Challenge Sent!")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Text("They'll get a notification")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                )
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showingSentConfirmation)
            }
        }
    }
}

// MARK: - Friends Quick Action Tile (Tall/Skinny – matches Nutrition quick action style)

struct FriendsQuickTile: View {
    let icon: String
    let title: String
    let gradient: [Color]
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBg: [Color] {
        colorScheme == .dark
            ? [Color(white: 0.14), Color(white: 0.09)]
            : [Color.white, Color.white.opacity(0.95)]
    }
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: gradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: gradient[0].opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(
                ZStack {
                    // Color glow underneath
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(gradient[0].opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 6)
                        .blur(radius: 4)
                    
                    // Shadow layer
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 3)
                    
                    // Main card
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: cardBg,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Inner highlight
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
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
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [gradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3), gradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: gradient[0].opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    FriendsTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
        .environmentObject(WorkoutManager.shared)
}
