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
    
    // Services as non-subscribing references — only used in lifecycle modifiers and helpers.
    // Each body section that needs live data owns its own @StateObject via a wrapper view,
    // so a @Published change only recomputes that section, not the entire 2800-line body.
    private let friendService = FriendService.shared
    private let rankingService = FriendRankingService.shared
    private let challengeService = ChallengeService.shared
    private let communityService = CommunityChallengeService.shared
    private let privateChallengeService = PrivateChallengeService.shared
    private let contactsService = ContactsService.shared
    private let leagueService = WeeklyLeagueService.shared
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    
    @State private var showingFriendsList = false
    @State private var showingFriendSearch = false
    @State private var showingFriendProfile: ProfileUser?
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
    @State private var cachedSuggestions: [SuggestedFriend] = []
    @State private var hasAppearedBefore = false
    @State private var challengeGlowPhase: Double = 0
    @State private var challengeToCancel: UUID?
    @State private var showingPrivateChallengeCreation = false
    
    // MARK: - Live Refresh State
    @State private var lastRefreshedAt: Date?
    @State private var lastContactsRefreshAt: Date?
    @State private var isManualRefreshing = false
    @State private var activeRefreshTask: Task<Void, Never>?

    // Sprint 2 Q2-27: 30s staggered polling Timer removed. Live updates now
    // come from Supabase Realtime subscriptions (friendships, friend_activity_feed,
    // community/private challenge channels) and user-initiated pull-to-refresh.
    
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
            PinnedTabHeader {
                FriendsHeaderWrapper(navigationPath: $navigationPath)
            }

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    FriendsStoriesWrapper(
                        navigationPath: $navigationPath,
                        sentRequestIds: $sentRequestIds,
                        requestSentAnimationIds: $requestSentAnimationIds,
                        cachedSuggestions: $cachedSuggestions,
                        showingFriendProfile: $showingFriendProfile
                    )
                        .padding(.bottom, 24)
                    
                    // Remaining sections deferred via LazyVStack
                    LazyVStack(spacing: 24) {
                        // Top 3 Best Friends spotlight
                        FriendsSpotlightWrapper(navigationPath: $navigationPath, showingFriendProfile: $showingFriendProfile)
                        
                        // Weekly League widget
                        FriendsLeagueWrapper(navigationPath: $navigationPath)
                        
                        // Active Challenges — 2 stacked per page, grouped by type
                        VStack(alignment: .leading, spacing: 12) {
                            FriendsChallengeHeaderWrapper(showingChallengeCreation: $showingChallengeCreation)
                            DashboardChallengesWrapper(showingChallengeCreation: $showingChallengeCreation, reducedGlow: true, stackedMode: true)
                        }
                        
                        // Private Challenges (invite-only communities)
                        FriendsPrivateChallengeWrapper(
                            navigationPath: $navigationPath,
                            showingPrivateChallengeCreation: $showingPrivateChallengeCreation
                        )
                        
                        // Community Challenges (leaderboard widgets)
                        FriendsCommunityWrapper(
                            selectedCommunityChallenge: $selectedCommunityChallenge,
                            showingAllCommunities: $showingAllCommunities
                        )
                        
                        // Friend Activity Feed (replaces Quick Actions)
                        FriendActivityFeedSection()
                        
                        // Bottom padding for tab bar
                        Spacer(minLength: 100)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                activeRefreshTask?.cancel()
                await ChallengeService.shared.syncAllTrackingToChallenges()
                await PrivateChallengeService.shared.syncAllTrackingToPrivateChallenges()
                await CommunityChallengeService.shared.syncAllTrackingToCommunityChallenges()
                await refreshAllFriendsData(force: true)
                lastRefreshedAt = Date()
                updateCachedSuggestions()
            }

            }   // closes VStack(spacing: 0) — pinned-header wrapper
            .padding(.top, TabPinnedChrome.rootTopPullUp)
            }
            .navigationBarHidden(true)
            .adaptiveToolbarBackground()
            .navigationDestination(for: String.self) { destination in
                if destination == "FriendsList" {
                    FriendsListView()
                } else if destination == "FriendRequests" {
                    FriendsListView(initialTab: 1)
                } else if destination == "FriendSearch" {
                    FriendsListView(initialTab: 2)
                } else if destination == "CommunityHub" {
                    CommunityChallengesHubView()
                } else if destination == "LeagueDetail" {
                    WeeklyLeagueDetailView()
                } else if destination == "LeagueInfo" {
                    WeeklyLeagueInfoView()
                } else if destination.hasPrefix("PrivateChallenge_") {
                    let idStr = String(destination.dropFirst("PrivateChallenge_".count))
                    if let challenge = PrivateChallengeService.shared.myChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        PrivateChallengeDetailView(challenge: challenge)
                    }
                }
            }
            .navigationDestination(for: ActiveChallenge.self) { challenge in
                ChallengeDetailView(challenge: challenge)
            }
            .navigationDestination(for: ActiveGroupChallenge.self) { challenge in
                GroupChallengeDetailView(challenge: challenge)
            }
            .navigationDestination(item: $selectedCommunityChallenge) { challenge in
                CommunityDetailView(challengeId: challenge.challengeId, challengeTitle: challenge.title)
            }
        }
        // MARK: - Deep Link Route Handling (single handler via onAppear + onChange)
        .onChange(of: deepLinkManager.pendingFriendsRoute) { _, route in
            guard let route = route else { return }
            deepLinkManager.pendingFriendsRoute = nil
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.15))
                guard !Task.isCancelled else { return }
                navigationPath.append(route)
                AppLogger.debug("👥 [DEEPLINK] Friends tab pushed route: \(route)", category: .social)
            }
        }
        .onAppear {
            if let route = deepLinkManager.pendingFriendsRoute {
                deepLinkManager.pendingFriendsRoute = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    guard !Task.isCancelled else { return }
                    navigationPath.append(route)
                    AppLogger.debug("👥 [DEEPLINK] Friends tab pushed route on appear: \(route)", category: .social)
                }
            }
        }
        .task {
            guard SupabaseManager.shared.isAuthenticated else { return }

            hasAppearedBefore = true
            updateCachedSuggestions()
            // Sprint 2 Q2-27: 30s polling timer removed. Live updates now come
            // from Supabase Realtime subscriptions and pull-to-refresh.
            
            // Fire suggestion refresh independently (once per app session).
            // This runs PYMK + contacts in parallel, not gated behind Batch 1+2,
            // so suggestions load fast even when challenge/league data is slow.
            await contactsService.refreshSuggestionsIfNeeded()
            updateCachedSuggestions()
        }
        .onAppear {
            // Mark community widgets as visible so rank arrows stay and update live
            communityService.markCommunityViewVisible()
            NewUserJourneyTracker.shared.logScreen("friends_tab")
            
            // Auto-refresh when returning to this tab (after initial load)
            if hasAppearedBefore {
                // Keep sentRequestIds (local sends this session) and merge with server-confirmed sent requests
                // so suggestions that already have pending requests stay hidden
                let confirmedSentIds = Set(friendService.sentRequests.map { $0.toUserId })
                sentRequestIds.formUnion(confirmedSentIds)
                requestSentAnimationIds.removeAll()
                
                // ⚡️ PERF FIX: Only do a FULL refresh if stale (> 30s since last).
                // Quick tab switches (< 30s apart) just re-start the timer.
                let isStale = lastRefreshedAt.map { Date().timeIntervalSince($0) > 30 } ?? true
                if isStale {
                    activeRefreshTask?.cancel()
                    activeRefreshTask = Task {
                        await refreshAllFriendsData(force: false)
                        lastRefreshedAt = Date()
                    }
                }
                // Sprint 2 Q2-27: no auto-refresh timer.
            }
        }
        .onDisappear {
            // Preserve rank deltas — user will see accumulated changes on return
            communityService.markCommunityViewHidden()

            // Cancel any in-flight refresh to save battery.
            activeRefreshTask?.cancel()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active && oldPhase != .active {
                // App foregrounded → only refresh if stale (> 30s).
                // Heavy sync (HealthKit push + pull) is already handled by Fit33App's
                // foreground handler. We just need to refresh the display data here.
                let isStale = lastRefreshedAt.map { Date().timeIntervalSince($0) > 30 } ?? true
                if isStale {
                    activeRefreshTask?.cancel()
                    activeRefreshTask = Task {
                        await refreshAllFriendsData(force: false)
                        lastRefreshedAt = Date()
                    }
                }
                // Sprint 2 Q2-27: no auto-refresh timer on foreground.
            }
        }
        .sheet(item: $showingFriendProfile) { profileUser in
            NavigationStack {
                FriendProfileView(user: profileUser)
            }
        }
        .sheet(isPresented: $showingCommunityHub) {
            CommunityChallengesHubView()
        }
        .sheet(isPresented: $showingAllCommunities) {
            AllCommunityChallengesView()
        }
        .fullScreenCover(isPresented: $showingPrivateChallengeCreation) {
            NavigationStack {
                PrivateChallengeCreationFlow()
                    .environmentObject(userManager)
            }
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
    
    // MARK: - Live Refresh (Realtime + pull-to-refresh)
    // Sprint 2 Q2-27: replaced the 30s staggered polling timer with Supabase
    // Realtime subscriptions. Challenge/league/friend state is now pushed
    // live; the tab relies on `.refreshable` for user-initiated refreshes.

    // MARK: - Header
    
    // MARK: - Suggestion Cache
    
    private func updateCachedSuggestions() {
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let serverSentIds = Set(friendService.sentRequests.map { $0.toUserId })
        let allExcludedSentIds = sentRequestIds.union(serverSentIds)
        let fresh = contactsService.allSuggestions(
            excludingFriendIds: existingFriendIds,
            excludingSentIds: allExcludedSentIds
        )
        if !fresh.isEmpty {
            cachedSuggestions = fresh
        }
    }
    
    // MARK: - Refresh Helper
    
    /// Central refresh for all Friends tab data.
    private func refreshAllFriendsData(force: Bool) async {
        // Batch 1: Fast social data (parallel) — lightweight, always fetch
        async let friends: () = friendService.fetchFriends()
        async let ranked: () = rankingService.fetchRankedFriends()
        async let pending: () = friendService.fetchPendingRequests()
        async let invites: () = challengeService.fetchPendingInvites()
        async let privateInvites: () = PrivateChallengeService.shared.fetchPendingInvites()
        async let activityFeed: () = ActivityFeedService.shared.fetchFeed()
        _ = await (friends, ranked, pending, invites, privateInvites, activityFeed)
        
        // Batch 2: Challenge data + league — all types in parallel
        async let active: () = challengeService.fetchActiveChallenges()
        async let groups: () = challengeService.fetchActiveGroupChallenges()
        async let community: () = communityService.refreshAll(force: force)
        async let privateChallenges: () = PrivateChallengeService.shared.refreshAll(force: force)
        async let league: () = leagueService.fetchOrJoinLeague(force: force)
        _ = await (active, groups, community, privateChallenges, league)
        
        // Batch 3: Contacts + PYMK — HEAVY operations (hashes 2000+ phone numbers).
        // Only on explicit pull-to-refresh. Normal per-session refresh runs independently
        // via contactsService.refreshSuggestionsIfNeeded() in .task, so suggestions
        // aren't blocked behind Batch 1+2.
        if force {
            lastContactsRefreshAt = Date()
            async let pymk: () = contactsService.fetchPeopleYouMayKnow()
            if contactsService.canAccessContacts {
                async let contactRefresh: () = contactsService.fetchContactsAndFindFriends()
                _ = await (pymk, contactRefresh)
            } else {
                _ = await pymk
            }
        }
    }
    
    // MARK: - Header
    
    private var friendsHeaderView: some View {
        HStack(alignment: .center) {
            Text("Friends")
                .font(.ds_displayLarge)
                .italic()
                .foregroundStyle(
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0.0),
                            .init(color: .white, location: 0.68),
                            .init(color: Color.cyan, location: 0.82),
                            .init(color: Color.blue, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: Color.cyan.opacity(0.2), radius: 4, x: 0, y: 1)
                .frame(height: 55)
            
            Spacer()
            
            friendsRequestsBadge
        }
        .padding(.horizontal, Spacing.xxs)
    }
    
    private var friendsRequestsBadge: some View {
        let friendCount = friendService.friends.count
        let requestCount = friendService.pendingRequests.count
        
        return HStack(spacing: 0) {
            Button {
                HapticManager.selectionChanged()
                navigationPath.append("FriendsList")
            } label: {
                HStack(spacing: 3) {
                    Text("\(friendCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Friends")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friendCount) friends")
            .accessibilityHint("Opens your friends list")
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 6)
            
            Button {
                HapticManager.selectionChanged()
                navigationPath.append("FriendRequests")
            } label: {
                HStack(spacing: 3) {
                    Text("\(requestCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(requestCount > 0 ? .blue : .primary)
                    Text(requestCount == 1 ? "Request" : "Requests")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    if requestCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(requestCount) friend requests")
            .accessibilityHint("Opens your friend requests")
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Add Friends Bar (Non-Friends from Contacts)
    
    private var friendStoriesBar: some View {
        // Combined suggestions: mutual friends (friends-of-friends) first, then contacts
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let serverSentIds = Set(friendService.sentRequests.map { $0.toUserId })
        let allExcludedSentIds = sentRequestIds.union(serverSentIds)
        let freshSuggestions = contactsService.allSuggestions(
            excludingFriendIds: existingFriendIds,
            excludingSentIds: allExcludedSentIds
        )
        let suggestions = freshSuggestions.isEmpty ? cachedSuggestions : freshSuggestions
        
        return Group {
            if !suggestions.isEmpty || contactsService.canAccessContacts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
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
                                        .font(.ds_heading2)
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
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, Spacing.xxs)
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
                                .font(.ds_heading3)
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
                    .adaptiveSleekCard(cornerRadius: 18, accentColor: .blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func contactSuggestionCircle(suggestion: SuggestedFriend) -> some View {
        let isSent = requestSentAnimationIds.contains(suggestion.userId)
        
        return Button(action: {
            guard !isSent else { return }
            HapticManager.selectionChanged()
            showingFriendProfile = ProfileUser(suggested: suggestion)
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
                                .font(.ds_heading3)
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
                                .font(.ds_heading3)
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
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Quick Action Tiles (Add Friend, New Challenge, Join Community)
    
    private var friendsQuickActionTiles: some View {
        HStack(spacing: 12) {
            FriendsQuickTile(
                icon: "trophy.fill",
                title: "Challenge",
                subtitle: "Compete head-to-head",
                gradient: [.orange, .red],
                action: { showingChallengeCreation = true }
            )
            
            FriendsQuickTile(
                icon: "globe.americas.fill",
                title: "Community",
                subtitle: "Global leaderboards",
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
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    .padding(Spacing.md)
                    .adaptiveSleekCard(cornerRadius: 24, accentColor: .blue)
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
            showingFriendProfile = ProfileUser(friend: friend)
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
                        .font(.ds_bodyRegular)
                        .offset(x: 4, y: 4)
                }
                
                HStack(spacing: 2) {
                    Text(rankedFriend.displayName.components(separatedBy: " ").first ?? "Friend")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if friend.isVerified == true || friend.isGoldVerified == true {
                        VerifiedBadge(size: 10, isGold: friend.isGoldVerified == true)
                    }
                }
                
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
                        .font(.ds_heading3)
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
                    .font(.ds_heading1)
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
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing)
                )
                .cornerRadius(25)
                .shadow(color: .cyan.opacity(0.3), radius: 10, x: 0, y: 4)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .adaptiveSleekCard(cornerRadius: 24, accentColor: .cyan)
    }
    
    // MARK: - Weekly League Widget
    
    private var weeklyLeagueSection: some View {
        WeeklyLeagueWidget(
            leagueService: leagueService,
            onTap: {
                if leagueService.standing != nil {
                    navigationPath.append("LeagueDetail")
                } else {
                    Task {
                        await leagueService.fetchOrJoinLeague(force: true)
                        if leagueService.standing != nil {
                            navigationPath.append("LeagueDetail")
                        }
                    }
                }
            },
            onShowInfo: {
                navigationPath.append("LeagueInfo")
            }
        )
    }
    
    // MARK: - Active Challenges Carousel
    
    private var activeChallengesCarousel: some View {
        // Sort by opponent freshness BEFORE the 3-card cap so the user lands
        // on a challenge whose opponent has actually moved today, not a
        // sibling that's still showing "0 · 16h ago". Mirrors the dashboard
        // carousel ordering. See
        // `Array<ActiveChallenge>.sortedByOpponentFreshness` in
        // ChallengeService.swift.
        let activeIds = Set(challengeService.activeChallenges.map { $0.id })
        let activeChallenges = Array(challengeService.activeChallenges.sortedByOpponentFreshness().prefix(3))
        let groupChallenges = challengeService.activeGroupChallenges.filter { $0.iHaveAccepted }
        let activeCount = activeChallenges.count + groupChallenges.count
        
        var seenPendingIds = Set<UUID>()
        let remainingSlots = max(0, 3 - activeCount)
        let pendingSent = challengeService.pendingSentChallenges
            .filter { pending in
                guard !pending.title.isEmpty && pending.durationDays > 0 else { return false }
                guard !activeIds.contains(pending.challengeId) else { return false }
                guard !seenPendingIds.contains(pending.challengeId) else { return false }
                seenPendingIds.insert(pending.challengeId)
                return true
            }
            .prefix(remainingSlots)
        let pendingArray = Array(pendingSent)
        let pendingCount = pendingArray.count
        
        let showDefaultInCarousel = activeCount == 0 && pendingCount > 0 && pendingCount < 3
        let totalWidgetCount = activeCount + pendingCount + (showDefaultInCarousel ? 1 : 0)
        let safePageIndex = totalWidgetCount > 0 ? min(max(0, activeChallengePageIndex), totalWidgetCount - 1) : 0
        
        return Group {
            if totalWidgetCount > 0 {
                VStack(spacing: 4) {
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
                        
                        if activeCount > 0 {
                            Text("\(activeCount) active")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, Spacing.xxs)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                    }
                    
                    if totalWidgetCount > 1 {
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
                                
                                ForEach(Array(pendingArray.enumerated()), id: \.offset) { index, pending in
                                    friendsTabPendingSentCard(challenge: pending)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + index) ? 1 : 0)
                                }
                                
                                if showDefaultInCarousel {
                                    noChallengesCard
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + pendingCount) ? 1 : 0)
                                }
                            }
                            .offset(x: -CGFloat(safePageIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: safePageIndex)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 && totalWidgetCount > 0 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && activeChallengePageIndex < totalWidgetCount - 1 {
                                            activeChallengePageIndex += 1
                                        } else if horizontalAmount > 0 && activeChallengePageIndex > 0 {
                                            activeChallengePageIndex -= 1
                                        }
                                    }
                                }
                        )
                        
                        HStack(spacing: 6) {
                            ForEach(0..<totalWidgetCount, id: \.self) { index in
                                Capsule()
                                    .fill(safePageIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: safePageIndex == index ? 20 : 8, height: 6)
                                    .padding(.vertical, 19)
                                    .contentShape(Rectangle())
                                    .animation(.easeOut(duration: 0.2), value: safePageIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        activeChallengePageIndex = index
                                    }
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    } else if let challenge = activeChallenges.first {
                        activeChallengeCard(challenge: challenge)
                    } else if let group = groupChallenges.first {
                        groupChallengeCard(challenge: group)
                    } else if let firstPending = pendingArray.first {
                        let singlePendingCount = 2
                        let singleSafeIndex = min(max(0, activeChallengePageIndex), singlePendingCount - 1)
                        
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                friendsTabPendingSentCard(challenge: firstPending)
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 0 ? 1 : 0)
                                
                                noChallengesCard
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 1 ? 1 : 0)
                            }
                            .offset(x: -CGFloat(singleSafeIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: activeChallengePageIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 8)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && activeChallengePageIndex < 1 {
                                            activeChallengePageIndex = 1
                                        } else if horizontalAmount > 0 && activeChallengePageIndex > 0 {
                                            activeChallengePageIndex = 0
                                        }
                                    }
                                }
                        )
                        
                        HStack(spacing: 6) {
                            ForEach(0..<2, id: \.self) { index in
                                Circle()
                                    .fill(singleSafeIndex == index ? Color.orange : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(singleSafeIndex == index ? 1.0 : 0.8)
                                    .padding(.vertical, 19)
                                    .contentShape(Rectangle())
                                    .animation(.easeOut(duration: 0.2), value: singleSafeIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        activeChallengePageIndex = index
                                    }
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
                .onChange(of: challengeService.activeChallenges.count) { _, _ in
                    activeChallengePageIndex = 0
                }
                .onChange(of: challengeService.pendingSentChallenges.count) { _, _ in
                    activeChallengePageIndex = 0
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
                        .font(.ds_heading3)
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
                    .font(.ds_bodyRegular)
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Spacing.sm)
            
            // Inner gray status bar — identical to home screen
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, Spacing.xxs)
                
                if isAccountability {
                    friendsTabAccountabilityBar(challenge: challenge, typeColor: typeColor, typeGradient: typeGradient)
                } else {
                    friendsTabCompetitionBar(challenge: challenge, typeColor: typeColor, typeGradient: typeGradient)
                }
            }
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.black.opacity(0.03))
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(typeColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
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
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [typeColor.opacity(colorScheme == .dark ? 0.35 : 0.25), typeColor.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .padding(.horizontal, Spacing.xxs)
    }
    
    // MARK: - Pending Sent Challenge Card
    
    private func friendsTabPendingSentCard(challenge: PendingSentChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        let target = challenge.dailyTarget ?? 0
        let formatted = target >= 1000 ? "\(target / 1000)K" : "\(target)"
        
        return VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                CachedFriendPhoto(
                    friendId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName ?? "Friend",
                    size: 48,
                    showGradientRing: true,
                    gradientColors: [.orange, .yellow]
                )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(challenge.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(resolvedType.emoji)
                            .font(.ds_bodySmall)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                        Text("Sent to \(opponentFirst)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 4, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(formatted) \(challenge.targetUnit)/day")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("PENDING")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.85))
                            )
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(challenge.durationDays) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Waiting to accept")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    HapticManager.impact(.medium)
                    challengeToCancel = challenge.challengeId
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.ds_caption)
                        Text("Cancel")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
        .alert("Cancel Challenge?", isPresented: Binding(
            get: { challengeToCancel == challenge.challengeId },
            set: { if !$0 { challengeToCancel = nil } }
        )) {
            Button("Keep It", role: .cancel) { challengeToCancel = nil }
            Button("Cancel Challenge", role: .destructive) {
                Task {
                    await challengeService.cancelPendingChallenge(challengeId: challenge.challengeId)
                    challengeToCancel = nil
                }
            }
        } message: {
            Text("This will cancel the challenge sent to \(challenge.opponentName ?? "your friend").")
        }
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
                        .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                    .font(.ds_bodySmall)
                
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
                        .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
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
                        .font(.ds_bodySmall)
                    Text(resolver.formattedProgress(for: challenge))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(myDone ? .green : typeColor)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(oppDone ? "✅" : "⬜")
                        .font(.ds_bodySmall)
                    Text(opponentFirst)
                        .font(.caption2)
                        .foregroundColor(oppDone ? .green : .secondary)
                        .lineLimit(1)
                }
                
                // Shared streak
                HStack(spacing: 4) {
                    if challenge.myCurrentStreak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.ds_caption)
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
                        .font(.ds_bodySmall).fontWeight(.bold)
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
        // Wearable Personalization Phase 5 — new wearable-sourced types.
        case .sleepHours: return "Rest up tonight!"
        case .readinessAverage: return "Keep the green days coming!"
        case .strainBudget: return "Train smart today!"
        // Sprint 20260811 — new ChallengeType cases.
        case .cycling: return "Saddle up and ride today!"
        case .swim: return "Hit the pool together!"
        case .stairsClimbed: return "Take the stairs today!"
        case .totalVolumeLifted: return "Move some weight today!"
        case .mindBodyMinutes: return "Roll out the mat together!"
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
                        .font(.ds_heading3)
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
                        .font(.ds_caption)
                    Text("\(participantCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(Capsule().fill(Color.gray.opacity(0.15)))
            }
            .padding(Spacing.md)
            
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
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(resolvedType.color.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
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
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [resolvedType.color.opacity(colorScheme == .dark ? 0.35 : 0.25), resolvedType.color.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: resolvedType.color.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .padding(.horizontal, Spacing.xxs)
    }
    
    private var noChallengesCard: some View {
        let challengeColor = Color.orange
        
        return Button { showingChallengeCreation = true } label: {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(challengeColor.opacity(0.3), lineWidth: 4)
                            .frame(width: 48, height: 48)
                        
                        Text("🏆")
                            .font(.ds_heading2)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge a Friend!")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Compete head-to-head on fitness goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(challengeColor)
                        .frame(width: 4, height: 36)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steps, Workouts & More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            Text("7-30 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Daily goals")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(challengeColor)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.ds_caption)
                        Text("Challenge")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, Color(red: 1.0, green: 0.6, blue: 0.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(.plain)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
        .onAppear {
            // QP invariant #13: gate decorative rotating glow on Low Power + Reduce Motion.
            // Observed 17-21fps scroll FPS drops in 1.38 (53) with Low Power on — every
            // continuous 360° glow on-screen means a rotation update per frame during scroll.
            guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
                  !UIAccessibility.isReduceMotionEnabled else { return }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                challengeGlowPhase = 360
            }
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
                            .font(.ds_heading2)
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
                            
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(2.5))
                                guard !Task.isCancelled else { return }
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
            .padding(Spacing.md)
            .adaptiveSleekCard(cornerRadius: 24, accentColor: .purple)
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
                
                Button {
                    HapticManager.impact(.light)
                    showingPrivateChallengeCreation = true
                } label: {
                    HStack(spacing: 2) {
                        Text("Create New")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                    )
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
    }
    
    private func privateChallengeRow(challenge: PrivateChallenge) -> some View {
        let type = challenge.resolvedType
        let resolver = ChallengeProgressResolver.shared
        let liveValue = resolver.liveProgress(for: challenge)
        let progress = challenge.dailyTarget > 0 ? min(1.0, Double(liveValue) / Double(challenge.dailyTarget)) : 0
        let liveTargetHit = liveValue >= challenge.dailyTarget
        
        return HStack(spacing: 12) {
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
                
                if let coverUrl = challenge.coverImageUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Text(challenge.displayEmoji)
                                .font(.ds_heading3)
                        }
                    }
                } else {
                    Text(challenge.displayEmoji)
                        .font(.ds_heading3)
                }
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
                    
                    // Progress (live from HealthKit/tracking)
                    Text("\(liveValue)/\(challenge.dailyTarget) \(challenge.targetUnit)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(liveTargetHit ? .green : .secondary)
                    
                    if liveTargetHit {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_caption)
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
                .font(.ds_labelMedium)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 6)
                    .blur(radius: 4)
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 3)
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.14), Color(white: 0.09)]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.purple.opacity(colorScheme == .dark ? 0.4 : 0.3),
                                Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: .purple.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        .overlay(alignment: .topTrailing) {
            // Pulsing red indicator for unread chat messages.
            // `hasUnreadChat` is an O(1) dict lookup; the dot itself re-evaluates
            // automatically because `myChallenges` is @Published and re-renders cards
            // whenever `lastChatAt` updates (existing realtime chat INSERT handler).
            if privateChallengeService.hasUnreadChat(for: challenge) {
                UnreadPulsingDot()
                    .padding(8)
                    .accessibilityLabel("New messages")
            }
        }
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
                    HStack(spacing: 2) {
                        Text("Browse")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                    )
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
                                .font(.ds_caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(colors: [.green.opacity(0.8), .mint.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                    }
                }
            }
            
            // ── Personalized Discover (only show if user has no challenges) ──
            if myChallenges.isEmpty {
                let friendCommunities = communityService.discoverableChallenges.prefix(2)
                
                if !friendCommunities.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(friendCommunities)) { challenge in
                            FriendDiscoveryCard(challenge: challenge) {
                                HapticManager.impact(.medium)
                                Task {
                                    _ = await communityService.joinChallengeFriendGated(challengeId: challenge.challengeId)
                                }
                            }
                        }
                    }
                } else {
                    let goalAligned = goalAlignedFeaturedChallenges
                    if !goalAligned.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(goalAligned) { challenge in
                                FeaturedChallengeCard(challenge: challenge) {
                                    HapticManager.impact(.medium)
                                    Task {
                                        _ = await communityService.joinChallenge(code: challenge.joinCode)
                                        await communityService.fetchFeaturedChallenges()
                                        await communityService.fetchMyChallenges()
                                    }
                                }
                            }
                        }
                    } else if !featured.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(Array(featured)) { challenge in
                                FeaturedChallengeCard(challenge: challenge) {
                                    HapticManager.impact(.medium)
                                    Task {
                                        _ = await communityService.joinChallenge(code: challenge.joinCode)
                                        await communityService.fetchFeaturedChallenges()
                                        await communityService.fetchMyChallenges()
                                    }
                                }
                            }
                        }
                    } else {
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
                        .adaptiveSleekCard(cornerRadius: 24, accentColor: .green)
                    }
                }
            }
        }
    }
    
    /// Top 2 featured challenges that align with the user's onboarding fitness goal.
    /// Falls back to the first 2 unjoined featured challenges if no goal match is found.
    private var goalAlignedFeaturedChallenges: [FeaturedCommunityChallenge] {
        let unjoined = communityService.featuredChallenges.filter { !$0.alreadyJoined }
        guard !unjoined.isEmpty else { return [] }
        
        let goal = userManager.currentUser?.fitnessGoal ?? "General Fitness"
        let preferredTypes: Set<String> = {
            switch goal {
            case "Build Muscle":
                return ["lift", "workout_streak", "protein"]
            case "Get Lean":
                return ["calories", "active_minutes", "steps"]
            case "Maintain Weight":
                return ["steps", "active_minutes", "hydrate"]
            case "Improve Endurance":
                return ["steps", "run", "walk", "active_minutes"]
            default:
                return ["steps", "active_minutes", "workout_streak", "hydrate"]
            }
        }()
        
        let matched = unjoined.filter { preferredTypes.contains($0.challengeType) }
        if matched.count >= 2 {
            return Array(matched.prefix(2))
        } else if !matched.isEmpty {
            let rest = unjoined.filter { !preferredTypes.contains($0.challengeType) }
            return Array((matched + rest).prefix(2))
        }
        return Array(unjoined.prefix(2))
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
                    .font(.ds_heading3)
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
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        LinearGradient(colors: typeGradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .cornerRadius(CornerRadius.lg)
                    .shadow(color: resolvedType.color.opacity(0.25), radius: 6, x: 0, y: 2)
            }
        }
        .padding(14)
        .adaptiveSleekCard(cornerRadius: 18, accentColor: resolvedType.color)
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
                        .font(.ds_heading3)
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
            .padding(.vertical, Spacing.md)
            .adaptiveSleekCard(cornerRadius: 18, accentColor: gradient.first ?? .blue)
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
                            .font(.ds_heading2)
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
                .padding(Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.xl)
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
    var subtitle: String? = nil
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
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
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

// MARK: - Isolated Wrapper Views
// Each wrapper owns its own @StateObject so a @Published change only recomputes
// the wrapper's subtree, not the entire FriendsTabView body.

/// Friends tab title for inline nav / floating top bar (reusable with `FriendsHeaderActionsView`).
struct FriendsHeaderTitleView: View {
    var body: some View {
        Text("Friends")
            .font(.ds_displayLarge)
            .italic()
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0.0),
                        .init(color: .white, location: 0.68),
                        .init(color: Color.cyan, location: 0.82),
                        .init(color: Color.blue, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .shadow(color: Color.cyan.opacity(0.2), radius: 4, x: 0, y: 1)
            .frame(height: 55)
            .fixedSize()
    }
}

/// Friends count + requests capsule (pairs with `FriendsHeaderTitleView` in toolbars or legacy header).
struct FriendsHeaderActionsView: View {
    @StateObject private var friendService = FriendService.shared
    @Binding var navigationPath: NavigationPath
    
    var body: some View {
        let friendCount = friendService.friends.count
        let requestCount = friendService.pendingRequests.count
        
        HStack(spacing: 0) {
            Button {
                HapticManager.selectionChanged()
                navigationPath.append("FriendsList")
            } label: {
                HStack(spacing: 3) {
                    Text("\(friendCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Friends")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(friendCount) friends")
            .accessibilityHint("Opens your friends list")
            
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 1, height: 14)
                .padding(.horizontal, 6)
            
            Button {
                HapticManager.selectionChanged()
                navigationPath.append("FriendRequests")
            } label: {
                HStack(spacing: 3) {
                    Text("\(requestCount)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(requestCount > 0 ? .blue : .primary)
                    Text(requestCount == 1 ? "Request" : "Requests")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    if requestCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(requestCount) friend requests")
            .accessibilityHint("Opens your friend requests")
        }
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
    }
}

struct FriendsHeaderWrapper: View {
    @Binding var navigationPath: NavigationPath
    // Subscribe so the sub-brief stays in sync as friends / requests /
    // activity feed change. Same singletons the rest of the tab uses —
    // no extra fetches.
    @StateObject private var friendService = FriendService.shared
    @StateObject private var activityFeedService = ActivityFeedService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            HStack(alignment: .center) {
                FriendsHeaderTitleView()
                Spacer()
                FriendsHeaderActionsView(navigationPath: $navigationPath)
            }

            Text(headerSubBriefCopy)
                .font(.ds_bodyMedium)
                .foregroundColor(.adaptiveSecondaryText)
                .padding(.leading, Spacing.xxs)
        }
        .padding(.horizontal, Spacing.xxs)
    }

    /// Personalized one-line nudge under the "Friends" title.
    /// Mirrors the Workout / Home / Exercises / Nutrition header rhythm.
    /// See `TabHeaderInsightProvider.friendsSubBrief` — it prioritizes
    /// pending requests, then surfaces a friend's recent workout / PR /
    /// challenge as a "send a challenge" nudge.
    private var headerSubBriefCopy: String {
        TabHeaderInsightProvider.friendsSubBrief(
            friendsCount: friendService.friends.count,
            pendingRequestCount: friendService.pendingRequests.count,
            recentActivities: activityFeedService.activities
        )
    }
}

struct FriendsStoriesWrapper: View {
    @StateObject private var friendService = FriendService.shared
    @StateObject private var contactsService = ContactsService.shared
    @Binding var navigationPath: NavigationPath
    @Binding var sentRequestIds: Set<UUID>
    @Binding var requestSentAnimationIds: Set<UUID>
    @Binding var cachedSuggestions: [SuggestedFriend]
    @Binding var showingFriendProfile: ProfileUser?
    
    var body: some View {
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let serverSentIds = Set(friendService.sentRequests.map { $0.toUserId })
        let allExcludedSentIds = sentRequestIds.union(serverSentIds)
        let freshSuggestions = contactsService.allSuggestions(
            excludingFriendIds: existingFriendIds,
            excludingSentIds: allExcludedSentIds
        )
        let suggestions = freshSuggestions.isEmpty ? cachedSuggestions : freshSuggestions
        
        Group {
            if !suggestions.isEmpty || contactsService.canAccessContacts {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        Button(action: {
                            HapticManager.selectionChanged()
                            navigationPath.append("FriendSearch")
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
                                        .font(.ds_heading2)
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
                        
                        ForEach(suggestions.prefix(15)) { suggestion in
                            FriendsSuggestionCircle(
                                suggestion: suggestion,
                                isSent: requestSentAnimationIds.contains(suggestion.userId),
                                onTap: {
                                    let sent = FriendService.shared.sentRequests.contains { $0.toUserId == suggestion.userId }
                                    showingFriendProfile = ProfileUser(suggested: suggestion, hasSentRequest: sent)
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .scale(scale: 0.5).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, Spacing.xxs)
                    .padding(.vertical, Spacing.xxs)
                }
            } else if !contactsService.canAccessContacts {
                Button(action: {
                    HapticManager.selectionChanged()
                    navigationPath.append("FriendSearch")
                }) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(colors: [.blue.opacity(0.2), .cyan.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                                )
                                .frame(width: 44, height: 44)
                            Image(systemName: "person.crop.rectangle.stack")
                                .font(.ds_heading3)
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
                    .adaptiveSleekCard(cornerRadius: 18, accentColor: .blue)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FriendsSuggestionCircle: View {
    let suggestion: SuggestedFriend
    let isSent: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: {
            guard !isSent else { return }
            HapticManager.selectionChanged()
            onTap()
        }) {
            VStack(spacing: 5) {
                ZStack {
                    CachedFriendPhoto(
                        friendId: suggestion.userId.uuidString,
                        photoUrl: suggestion.profilePhotoUrl,
                        name: suggestion.name ?? suggestion.username ?? "?",
                        size: 58,
                        showGradientRing: false,
                        gradientColors: [.blue.opacity(0.6), .cyan.opacity(0.4)]
                    )
                    
                    if isSent {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 58, height: 58)
                        
                        VStack(spacing: 2) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_heading3)
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
                .overlay(alignment: .bottomTrailing) {
                    if !isSent {
                        ZStack {
                            Circle()
                                .fill(Color(.systemBackground))
                                .frame(width: 22, height: 22)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.ds_heading3)
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
}

struct FriendsSpotlightWrapper: View {
    @StateObject private var rankingService = FriendRankingService.shared
    @Binding var navigationPath: NavigationPath
    @Binding var showingFriendProfile: ProfileUser?
    
    var body: some View {
        let topThree = Array(rankingService.rankedFriends.prefix(3))
        let friends = FriendService.shared.friends
        
        Group {
            if topThree.count >= 1 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "star.circle.fill")
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.title3)
                        Text("Your Inner Circle")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                    }
                    
                    HStack(spacing: 12) {
                        ForEach(Array(topThree.enumerated()), id: \.element.id) { index, rankedFriend in
                            if let friend = friends.first(where: { $0.friendId == rankedFriend.friendId }) {
                                FriendsSpotlightCard(
                                    friend: friend,
                                    rankedFriend: rankedFriend,
                                    rank: index + 1,
                                    onTap: { showingFriendProfile = ProfileUser(friend: friend) }
                                )
                            }
                        }
                        
                        if topThree.count < 3 {
                            ForEach(topThree.count..<3, id: \.self) { _ in
                                Button(action: {
                                    HapticManager.selectionChanged()
                                    navigationPath.append("FriendSearch")
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(LinearGradient(colors: [Color.gray.opacity(0.15), Color.gray.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                .frame(width: 52, height: 52)
                                                .overlay(Circle().stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                                            Image(systemName: "plus")
                                                .font(.ds_heading3)
                                                .foregroundColor(.gray.opacity(0.5))
                                        }
                                        Text("Add").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                                        Text("friend").font(.caption2).foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .adaptiveSleekCard(cornerRadius: 24, accentColor: .blue)
                }
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.cyan.opacity(0.2), .blue.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 72, height: 72)
                        Image(systemName: "person.2.fill")
                            .font(.ds_heading1)
                            .foregroundStyle(LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    VStack(spacing: 6) {
                        Text("Find Your Fit Friends").font(.title3).fontWeight(.bold)
                        Text("Add friends to challenge, compete, and motivate each other!")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                    }
                    Button(action: { HapticManager.impact(.medium); navigationPath.append("FriendSearch") }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                            Text("Find Friends").fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg).padding(.vertical, Spacing.sm)
                        .background(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(25)
                        .shadow(color: .cyan.opacity(0.3), radius: 10, x: 0, y: 4)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity)
                .adaptiveSleekCard(cornerRadius: 24, accentColor: .cyan)
            }
        }
    }
}

struct FriendsSpotlightCard: View {
    let friend: Friend
    let rankedFriend: RankedFriend
    let rank: Int
    let onTap: () -> Void
    
    var body: some View {
        let medalColor: [Color] = {
            switch rank {
            case 1: return [.yellow, .orange]
            case 2: return [.gray, .white]
            case 3: return [.orange, .brown]
            default: return [.blue, .cyan]
            }
        }()
        let medalEmoji = rank == 1 ? "🥇" : rank == 2 ? "🥈" : "🥉"
        
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
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
                    Text(medalEmoji).font(.ds_bodyRegular).offset(x: 4, y: 4)
                }
                HStack(spacing: 2) {
                    Text(rankedFriend.displayName.components(separatedBy: " ").first ?? "Friend")
                        .font(.caption).fontWeight(.semibold).foregroundColor(.primary).lineLimit(1)
                    if friend.isVerified == true || friend.isGoldVerified == true {
                        VerifiedBadge(size: 10, isGold: friend.isGoldVerified == true)
                    }
                }
                Text("\(rankedFriend.challengesTogether) challenges")
                    .font(.caption2).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct FriendsLeagueWrapper: View {
    @StateObject private var leagueService = WeeklyLeagueService.shared
    @ObservedObject private var privacyManager = PrivacySettingsManager.shared
    @Binding var navigationPath: NavigationPath
    
    var body: some View {
        if !privacyManager.hideFromWeeklyLeague {
            WeeklyLeagueWidget(
                leagueService: leagueService,
                onTap: {
                    if leagueService.standing != nil {
                        navigationPath.append("LeagueDetail")
                    } else {
                        Task {
                            await leagueService.fetchOrJoinLeague(force: true)
                            if leagueService.standing != nil {
                                navigationPath.append("LeagueDetail")
                            }
                        }
                    }
                },
                onShowInfo: {
                    navigationPath.append("LeagueInfo")
                }
            )
        }
    }
}

struct FriendsChallengeHeaderWrapper: View {
    @StateObject private var challengeService = ChallengeService.shared
    @Binding var showingChallengeCreation: Bool
    
    var body: some View {
        if !challengeService.activeChallenges.isEmpty || !challengeService.activeGroupChallenges.isEmpty || !challengeService.pendingSentChallenges.isEmpty {
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
                Button {
                    HapticManager.impact(.light)
                    showingChallengeCreation = true
                } label: {
                    HStack(spacing: 2) {
                        Text("Start a Challenge")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, Color(red: 1.0, green: 0.4, blue: 0.1)], startPoint: .leading, endPoint: .trailing)
                    )
                }
                .accessibilityLabel("Start a Challenge")
                .accessibilityHint("Opens the challenge creation flow")
            }
        }
    }
}

struct FriendsPrivateChallengeWrapper: View {
    @StateObject private var privateChallengeService = PrivateChallengeService.shared
    @Binding var navigationPath: NavigationPath
    @Binding var showingPrivateChallengeCreation: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingAllPrivateChallenges = false
    
    var body: some View {
        let challenges = privateChallengeService.myChallenges
        
        VStack(alignment: .leading, spacing: 12) {
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
                    Button {
                        HapticManager.impact(.light)
                        showingAllPrivateChallenges = true
                    } label: {
                        HStack(spacing: 2) {
                            Text("See All")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                    }
                } else {
                    Button {
                        HapticManager.impact(.light)
                        showingPrivateChallengeCreation = true
                    } label: {
                        HStack(spacing: 2) {
                            Text("Create New")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                    }
                }
            }
            
            if challenges.isEmpty {
                privateChallengeEmptyCard
            } else {
                ForEach(challenges.prefix(3)) { challenge in
                    NavigationLink(value: "PrivateChallenge_\(challenge.challengeId.uuidString)") {
                        FriendsPrivateChallengeRow(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .fullScreenCover(isPresented: $showingAllPrivateChallenges) {
            AllPrivateChallengesView(showingCreation: $showingPrivateChallengeCreation)
        }
    }
    
    private var privateChallengeEmptyCard: some View {
        Button {
            HapticManager.impact(.light)
            showingPrivateChallengeCreation = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(colors: [.purple.opacity(0.3), .pink.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 4, dash: [6, 4])
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(
                            LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Invite 3+ Friends to a Private Challenge")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("Create an invite-only group with custom goals & leaderboards")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer(minLength: 0)
                
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                    Text("Create")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing)
                        )
                )
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 6).blur(radius: 4)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 3)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(
                            colors: colorScheme == .dark ? [Color(white: 0.14), Color(white: 0.09)] : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top, endPoint: .bottom
                        ))
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(LinearGradient(
                            colors: colorScheme == .dark ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear] : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        ), lineWidth: 1.5)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create a Private Challenge")
        .accessibilityHint("Opens the private challenge creation flow")
    }
}

struct FriendsPrivateChallengeRow: View {
    let challenge: PrivateChallenge
    @Environment(\.colorScheme) private var colorScheme
    // Observing the service here (not via @StateObject — the parent wrapper already
    // owns one) lets SwiftUI re-evaluate `hasUnreadChat(for:)` when `myChallenges`
    // OR `chatUnreadChangeToken` publish, without needing a second subscription.
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared

    var body: some View {
        let resolver = ChallengeProgressResolver.shared
        let liveValue = resolver.liveProgress(for: challenge)
        let progress = challenge.dailyTarget > 0 ? min(1.0, Double(liveValue) / Double(challenge.dailyTarget)) : 0
        let liveTargetHit = liveValue >= challenge.dailyTarget
        let hasUnread = privateChallengeService.hasUnreadChat(for: challenge)
        
        HStack(spacing: 12) {
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
                
                if let coverUrl = challenge.coverImageUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        } else {
                            Text(challenge.displayEmoji)
                                .font(.ds_heading3)
                        }
                    }
                } else {
                    Text(challenge.displayEmoji)
                        .font(.ds_heading3)
                }
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(challenge.title)
                    .font(.subheadline).fontWeight(.bold).foregroundColor(.primary).lineLimit(1)
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Image(systemName: "person.2.fill").font(.system(size: 9))
                        Text("\(challenge.formattedMemberCount)").font(.caption2)
                    }.foregroundColor(.secondary)
                    Text("•").font(.caption2).foregroundColor(.secondary)
                    Text("\(liveValue)/\(challenge.dailyTarget) \(challenge.targetUnit)")
                        .font(.caption2).fontWeight(.medium)
                        .foregroundColor(liveTargetHit ? .green : .secondary)
                    if liveTargetHit {
                        Image(systemName: "checkmark.circle.fill").font(.ds_caption).foregroundColor(.green)
                    }
                    if let streak = challenge.myCurrentStreak, streak > 0 {
                        Text("•").font(.caption2).foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Text("🔥").font(.system(size: 9))
                            Text("\(streak)").font(.caption2).fontWeight(.semibold).foregroundColor(.orange)
                        }
                    }
                }
            }
            
            Spacer()
            
            if let rank = challenge.myRank, rank > 0 {
                VStack(spacing: 2) {
                    Text(rank <= 3 ? ["🥇", "🥈", "🥉"][rank - 1] : "#\(rank)")
                        .font(.system(size: rank <= 3 ? 16 : 12, weight: .bold))
                    if rank > 3 {
                        Text("rank").font(.system(size: 8)).foregroundColor(.secondary)
                    }
                }
            }
            
            Image(systemName: "chevron.right").font(.ds_labelMedium).foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.purple.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    .offset(y: 6).blur(radius: 4)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 3)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: colorScheme == .dark ? [Color(white: 0.14), Color(white: 0.09)] : [Color.white, Color.white.opacity(0.95)],
                        startPoint: .top, endPoint: .bottom
                    ))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LinearGradient(
                        colors: colorScheme == .dark ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear] : [Color.white, Color.white.opacity(0.5), Color.clear],
                        startPoint: .top, endPoint: .bottom
                    ), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(LinearGradient(
                        colors: [Color.purple.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.pink.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1)
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
        .shadow(color: .purple.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        .overlay(alignment: .topTrailing) {
            if hasUnread {
                UnreadPulsingDot()
                    .padding(8)
                    .accessibilityLabel("New messages")
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
    }
}

// MARK: - Unread Pulsing Dot
//
// Tiny red indicator used on private-challenge cards when there are unread chat
// messages. The dot animates only while visible (SwiftUI auto-pauses off-screen
// animations) and only when the user hasn't opted out via Reduce Motion or Low
// Power Mode — per `QUALITY_PERFORMANCE_AGENT` invariant #13.
struct UnreadPulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    // 9pt dot + 3pt halo = 15pt visual footprint; small enough not to overlap the
    // rank badge / chevron, large enough to be unmistakable.
    private let dotSize: CGFloat = 9

    private var shouldAnimate: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        ZStack {
            // Soft halo (animated when not reduce-motion).
            Circle()
                .fill(Color.red.opacity(0.35))
                .frame(width: dotSize, height: dotSize)
                .scaleEffect(pulse && shouldAnimate ? 2.1 : 1.0)
                .opacity(pulse && shouldAnimate ? 0.0 : 0.7)

            // Solid dot with a subtle white border so it reads against any card.
            Circle()
                .fill(Color.red)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                )
                .frame(width: dotSize, height: dotSize)
                .shadow(color: Color.red.opacity(0.6), radius: 3, x: 0, y: 0)
        }
        .accessibilityHidden(false)
        .onAppear {
            guard shouldAnimate else { return }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - All Private Challenges View

struct AllPrivateChallengesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var privateChallengeService = PrivateChallengeService.shared
    @Binding var showingCreation: Bool

    private var groupedChallenges: [(type: ChallengeType, challenges: [PrivateChallenge])] {
        let challenges = privateChallengeService.myChallenges
        let grouped = Dictionary(grouping: challenges) { $0.resolvedType }
        return grouped
            .map { (type: $0.key, challenges: $0.value) }
            .sorted { $0.type.displayName < $1.type.displayName }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(groupedChallenges, id: \.type) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text(group.type.emoji)
                                        .font(.title3)
                                    Text(group.type.displayName)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                    Spacer()
                                    Text("\(group.challenges.count)")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.purple)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                                }
                                .padding(.horizontal, 4)

                                ForEach(group.challenges) { challenge in
                                    NavigationLink(value: "PrivateChallenge_\(challenge.challengeId.uuidString)") {
                                        FriendsPrivateChallengeRow(challenge: challenge)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Private Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { destination in
                if destination.hasPrefix("PrivateChallenge_") {
                    let idStr = String(destination.dropFirst("PrivateChallenge_".count))
                    if let challenge = PrivateChallengeService.shared.myChallenges.first(where: { $0.challengeId.uuidString == idStr }) {
                        PrivateChallengeDetailView(challenge: challenge)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.impact(.light)
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            showingCreation = true
                        }
                    } label: {
                        Text("Create New")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                    }
                }
            }
        }
    }
}

struct FriendsCommunityWrapper: View {
    @StateObject private var communityService = CommunityChallengeService.shared
    @EnvironmentObject var userManager: UserManager
    @Binding var selectedCommunityChallenge: CommunityChallenge?
    @Binding var showingAllCommunities: Bool
    @State private var showingCommunityHub = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        let myChallenges = communityService.myChallenges
        let featured = communityService.featuredChallenges.filter { !$0.alreadyJoined }.prefix(2)
        
        VStack(alignment: .leading, spacing: 12) {
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
                    HStack(spacing: 2) {
                        Text("Browse")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing)
                    )
                }
            }
            
            if !myChallenges.isEmpty {
                ForEach(myChallenges.prefix(3)) { challenge in
                    Button {
                        selectedCommunityChallenge = challenge
                    } label: {
                        CommunityLeaderboardWidget(challenge: challenge)
                    }
                    .buttonStyle(.plain)
                }
                
                if myChallenges.count > 3 {
                    Button(action: {
                        HapticManager.selectionChanged()
                        showingAllCommunities = true
                    }) {
                        HStack(spacing: 8) {
                            Text("See all \(myChallenges.count) challenges")
                                .font(.subheadline).fontWeight(.semibold)
                            Image(systemName: "chevron.right").font(.ds_caption)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(LinearGradient(colors: [.green.opacity(0.8), .mint.opacity(0.8)], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(14)
                    }
                }
            }
            
            if myChallenges.isEmpty {
                let friendCommunities = communityService.discoverableChallenges.prefix(2)
                
                if !friendCommunities.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(Array(friendCommunities)) { challenge in
                            FriendDiscoveryCard(challenge: challenge) {
                                HapticManager.impact(.medium)
                                Task {
                                    _ = await communityService.joinChallengeFriendGated(challengeId: challenge.challengeId)
                                }
                            }
                        }
                    }
                } else {
                    let goalAligned = goalAlignedFeatured
                    if !goalAligned.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(goalAligned) { challenge in
                                FeaturedChallengeCard(challenge: challenge) {
                                    HapticManager.impact(.medium)
                                    Task {
                                        _ = await communityService.joinChallenge(code: challenge.joinCode)
                                        await communityService.fetchFeaturedChallenges()
                                        await communityService.fetchMyChallenges()
                                    }
                                }
                            }
                        }
                    } else if !featured.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(Array(featured)) { challenge in
                                FeaturedChallengeCard(challenge: challenge) {
                                    HapticManager.impact(.medium)
                                    Task {
                                        _ = await communityService.joinChallenge(code: challenge.joinCode)
                                        await communityService.fetchFeaturedChallenges()
                                        await communityService.fetchMyChallenges()
                                    }
                                }
                            }
                        }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "globe.americas.fill")
                                .font(.system(size: 36))
                                .foregroundColor(.green.opacity(0.4))
                            Text("Compete on global leaderboards")
                                .font(.subheadline).foregroundColor(.secondary)
                            Button(action: {
                                HapticManager.impact(.medium)
                                showingCommunityHub = true
                            }) {
                                Text("Browse Challenges")
                                    .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                    .padding(.horizontal, 20).padding(.vertical, 10)
                                    .background(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                    .cornerRadius(20)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        .adaptiveSleekCard(cornerRadius: 24, accentColor: .green)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCommunityHub) {
            CommunityChallengesHubView()
        }
    }
    
    private var goalAlignedFeatured: [FeaturedCommunityChallenge] {
        let unjoined = communityService.featuredChallenges.filter { !$0.alreadyJoined }
        guard !unjoined.isEmpty else { return [] }
        let goal = userManager.currentUser?.fitnessGoal ?? "General Fitness"
        let preferredTypes: Set<String> = {
            switch goal {
            case "Build Muscle": return ["lift", "workout_streak", "protein"]
            case "Get Lean": return ["calories", "active_minutes", "steps"]
            case "Maintain Weight": return ["steps", "active_minutes", "hydrate"]
            case "Improve Endurance": return ["steps", "run", "walk", "active_minutes"]
            default: return ["steps", "active_minutes", "workout_streak", "hydrate"]
            }
        }()
        let matched = unjoined.filter { preferredTypes.contains($0.challengeType) }
        if matched.count >= 2 { return Array(matched.prefix(2)) }
        if !matched.isEmpty {
            let rest = unjoined.filter { !preferredTypes.contains($0.challengeType) }
            return Array((matched + rest).prefix(2))
        }
        return Array(unjoined.prefix(2))
    }
}

// MARK: - Preview

#Preview {
    FriendsTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
        .environmentObject(WorkoutManager.shared)
}
