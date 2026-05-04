import SwiftUI
import CoreData

// MARK: - ProfileUser (universal model for any user profile)

struct ProfileUser: Identifiable {
    let userId: UUID
    let name: String?
    let username: String?
    let email: String?
    let fitnessGoal: String?
    let experienceLevel: String?
    let profilePhotoUrl: String?
    let isFriend: Bool
    let hasOutgoingRequest: Bool
    let hasIncomingRequest: Bool
    let friendshipId: UUID?
    let friendsSince: Date?
    let totalWorkoutsShared: Int
    let isVerified: Bool
    let isGoldVerified: Bool
    let mutualFriendCount: Int?

    var id: UUID { userId }

    var displayName: String {
        if let username = username, !username.isEmpty {
            return "@\(username)"
        }
        return name ?? email ?? "Unknown"
    }

    var initials: String {
        if let name = name, !name.isEmpty {
            let components = name.split(separator: " ")
            if components.count >= 2 {
                return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
            }
            return String(name.prefix(2)).uppercased()
        }
        if let username = username, !username.isEmpty {
            return String(username.prefix(2)).uppercased()
        }
        return "?"
    }

    init(friend: Friend) {
        self.userId = friend.friendId
        self.name = friend.friendName
        self.username = friend.friendUsername
        self.email = friend.friendEmail
        self.fitnessGoal = friend.fitnessGoal
        self.experienceLevel = friend.experienceLevel
        self.profilePhotoUrl = friend.profilePhotoUrl
        self.isFriend = true
        self.hasOutgoingRequest = false
        self.hasIncomingRequest = false
        self.friendshipId = friend.friendshipId
        self.friendsSince = friend.friendsSince
        self.totalWorkoutsShared = friend.totalWorkoutsShared
        self.isVerified = friend.isVerified ?? false
        self.isGoldVerified = friend.isGoldVerified ?? false
        self.mutualFriendCount = nil
    }

    init(searchResult: UserSearchResult, hasSentRequest: Bool = false) {
        self.userId = searchResult.userId
        self.name = searchResult.name
        self.username = searchResult.username
        self.email = searchResult.email
        self.fitnessGoal = searchResult.fitnessGoal
        self.experienceLevel = searchResult.experienceLevel
        self.profilePhotoUrl = searchResult.profilePhotoUrl
        self.isFriend = searchResult.isFriend
        self.hasOutgoingRequest = (searchResult.hasOutgoingRequest ?? searchResult.hasPendingRequest) || hasSentRequest
        self.hasIncomingRequest = searchResult.hasIncomingRequest ?? false
        self.friendshipId = nil
        self.friendsSince = nil
        self.totalWorkoutsShared = 0
        self.isVerified = searchResult.isVerified ?? false
        self.isGoldVerified = searchResult.isGoldVerified ?? false
        self.mutualFriendCount = nil
    }

    init(suggested: SuggestedFriend, hasSentRequest: Bool = false) {
        self.userId = suggested.userId
        self.name = suggested.name
        self.username = suggested.username
        self.email = suggested.email
        self.fitnessGoal = suggested.fitnessGoal
        self.experienceLevel = nil
        self.profilePhotoUrl = suggested.profilePhotoUrl
        self.isFriend = suggested.isFriend
        self.hasOutgoingRequest = suggested.hasOutgoingRequest || hasSentRequest
        self.hasIncomingRequest = suggested.hasIncomingRequest
        self.friendshipId = nil
        self.friendsSince = nil
        self.totalWorkoutsShared = 0
        self.isVerified = suggested.isVerified ?? false
        self.isGoldVerified = suggested.isGoldVerified ?? false
        self.mutualFriendCount = suggested.mutualFriendCount
    }

    init(leagueEntry: LeagueEntry) {
        self.userId = leagueEntry.userId
        self.name = leagueEntry.name
        self.username = leagueEntry.username
        self.email = nil
        self.fitnessGoal = nil
        self.experienceLevel = nil
        self.profilePhotoUrl = leagueEntry.profilePhotoUrl
        self.isFriend = leagueEntry.isFriend ?? false
        self.hasOutgoingRequest = false
        self.hasIncomingRequest = false
        self.friendshipId = nil
        self.friendsSince = nil
        self.totalWorkoutsShared = 0
        self.isVerified = leagueEntry.isVerified ?? false
        self.isGoldVerified = leagueEntry.isGoldVerified ?? false
        self.mutualFriendCount = leagueEntry.mutualFriendCount
    }

    init(communityEntry: CommunityLeaderboardEntry) {
        self.userId = communityEntry.userId
        self.name = communityEntry.name
        self.username = communityEntry.username
        self.email = nil
        self.fitnessGoal = nil
        self.experienceLevel = nil
        self.profilePhotoUrl = communityEntry.profilePhotoUrl
        self.isFriend = false
        self.hasOutgoingRequest = false
        self.hasIncomingRequest = false
        self.friendshipId = nil
        self.friendsSince = nil
        self.totalWorkoutsShared = 0
        self.isVerified = communityEntry.isVerified ?? false
        self.isGoldVerified = communityEntry.isGoldVerified ?? false
        self.mutualFriendCount = nil
    }

    @MainActor
    init(activity: FriendActivity) {
        let matchedFriend = FriendService.shared.friends.first(where: { $0.friendId == activity.userId })
        self.userId = activity.userId
        self.name = activity.userName
        self.username = activity.userUsername
        self.email = nil
        self.fitnessGoal = matchedFriend?.fitnessGoal
        self.experienceLevel = matchedFriend?.experienceLevel
        self.profilePhotoUrl = activity.userProfilePhotoUrl
        self.isFriend = matchedFriend != nil
        self.hasOutgoingRequest = false
        self.hasIncomingRequest = false
        self.friendshipId = matchedFriend?.friendshipId
        self.friendsSince = matchedFriend?.friendsSince
        self.totalWorkoutsShared = matchedFriend?.totalWorkoutsShared ?? 0
        self.isVerified = false
        self.isGoldVerified = false
        self.mutualFriendCount = nil
    }

    /// Look up the full Friend model from FriendService (needed for actions like create workout/challenge)
    @MainActor
    var asFriend: Friend? {
        FriendService.shared.friends.first(where: { $0.friendId == userId })
    }
}

// MARK: - Friend Profile View
/// Shows a friend's or non-friend's profile with contextual actions
struct FriendProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    let user: ProfileUser

    /// Convenience init that wraps a Friend into a ProfileUser
    init(friend: Friend) {
        self.user = ProfileUser(friend: friend)
    }

    /// Primary init accepting any ProfileUser
    init(user: ProfileUser) {
        self.user = user
    }
    
    @State private var showingCreateWorkout = false
    @State private var showingCreateChallenge = false
    @State private var showingChallengeFlow = false
    @State private var showingUnfriendConfirmation = false
    @State private var showingBlockConfirmation = false
    @State private var isUnfriending = false
    @State private var isBlocking = false
    @State private var isSendingRequest = false
    @State private var requestSent = false
    @State private var friendChallenges: [FriendChallenge] = []
    @State private var selectedChallenge: ActiveChallenge?
    @State private var showingChallengeDetail = false
    @State private var activeChallengesWithFriend: [ActiveChallenge] = []
    @State private var sentWorkoutsToFriend: [SentWorkout] = []
    @State private var mutualFriends: [MutualFriend] = []

    // 2026-05-04 — Path to 33 (annual Olympian track). Friend's stackable
    // season badges are publicly readable to accepted friends (RLS policy
    // `users_select_friend_olympian_seasons` in 20260504_olympian_path.sql).
    // Loaded on profile appearance; stays empty + hides for friends with
    // no completed seasons yet.
    @State private var friendOlympianSeasons: [OlympianSeasonBadge] = []

    // Mutual-friend section. Friend profile shows a compact card (count +
    // stacked avatars + "See all"). Non-friend profile shows the same card
    // PLUS a "See friends >" CTA that opens `UserFriendsListView`
    // (Instagram-style list of every friend the target user has, with
    // per-row Add/Pending/Friends/Accept state).
    @State private var showingMutualsList = false
    @State private var showingUserFriendsList = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with friends tab)
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        profileHeader

                        if user.isFriend {
                            // Mutual friends preview sits directly under the
                            // profile header (above Goal/Level/Shared) so the
                            // option to start a quick group/private challenge
                            // is the first thing visible after the user's name.
                            if !mutualFriends.isEmpty {
                                mutualFriendsCompactSection
                            }

                            statsSection

                            if !friendOlympianSeasons.isEmpty {
                                friendOlympianBadgesSection
                            }

                            if let activeChallenge = activeChallengesWithFriend.first {
                                activeChallengeSection(challenge: activeChallenge)
                            }

                            createWorkoutButton
                            createChallengeButton

                            if !friendChallenges.isEmpty {
                                challengeHistorySection
                            }

                            sharedHistorySection

                            VStack(spacing: Spacing.xs) {
                                unfriendButton
                                blockButton
                            }
                        } else {
                            nonFriendStatsSection

                            // Same compact stacked-rings card the friend
                            // profile uses — single tap opens
                            // `MutualFriendsListView` in read-only mode
                            // (challenge CTA hidden because there's no
                            // primary friend to seed a challenge with).
                            if !mutualFriends.isEmpty {
                                mutualFriendsCompactSection
                            }

                            // "See friends >" Instagram-style entry into
                            // the target user's full friend list.
                            seeUserFriendsButton

                            addFriendButton
                            blockButton
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            // Phase 12 rage-shake fix (2026-04-24) — see PrivateChallengeDetailView.
            .trackScreen(.friendProfile, metadata: ["friend_id": user.userId.uuidString])
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            // 2026-04-28 redesign: send-workout flow is multi-step creation
            // (name → exercises → preview → send), so it presents as
            // `.fullScreenCover` per Design Agent's navigation rules.
            // The redesigned `CreateWorkoutForFriendView` lives in
            // `Fit33/SendWorkoutToFriendView.swift`.
            .fullScreenCover(isPresented: $showingCreateWorkout) {
                if let friend = user.asFriend {
                    CreateWorkoutForFriendView(friend: friend)
                        .environmentObject(WorkoutManager.shared)
                        .environmentObject(UserManager.shared)
                }
            }
            .sheet(isPresented: $showingCreateChallenge, onDismiss: {
                AppLogger.debug("🔔 [CHALLENGE SHEET] onDismiss callback triggered", category: .social)
            }) {
                if let friend = user.asFriend {
                    ChallengeSetupView(friend: friend)
                        .onAppear {
                            AppLogger.debug("🔔 [CHALLENGE SHEET] Sheet content appeared", category: .social)
                        }
                }
            }
            .onChange(of: showingCreateChallenge) { oldValue, newValue in
                AppLogger.debug("🔔 [CHALLENGE SHEET] State changed: \(oldValue) → \(newValue)", category: .social)
                if !newValue && oldValue {
                    AppLogger.warning("⚠️ [CHALLENGE SHEET] Sheet dismissed unexpectedly!", category: .social)
                }
            }
            .fullScreenCover(isPresented: $showingChallengeFlow) {
                if let friend = user.asFriend {
                    NavigationStack {
                        ChallengeFlowStartView(preSelectedFriend: friend)
                            .environmentObject(userManager)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingMutualsList) {
                // `primaryFriend` may be nil here when opened from a non-friend
                // profile — `MutualFriendsListView` honors the optional and
                // hides the challenge CTA when it's nil.
                MutualFriendsListView(
                    primaryFriend: user.asFriend,
                    mutuals: mutualFriends
                )
                .environmentObject(userManager)
            }
            .fullScreenCover(isPresented: $showingUserFriendsList) {
                UserFriendsListView(targetUser: user)
                    .environmentObject(userManager)
            }
            .sheet(isPresented: $showingChallengeDetail) {
                if let challenge = selectedChallenge {
                    NavigationStack {
                        ChallengeDetailView(challenge: challenge)
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button("Close") {
                                        showingChallengeDetail = false
                                    }
                                }
                            }
                    }
                }
            }
            .alert("Unfriend \(user.displayName)?", isPresented: $showingUnfriendConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Unfriend", role: .destructive) {
                    unfriend()
                }
            } message: {
                Text("You will no longer be able to share workouts with each other.")
            }
            .alert("Block \(user.displayName)?", isPresented: $showingBlockConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Block", role: .destructive) {
                    blockUser()
                }
            } message: {
                Text("They won't be able to find you, send you requests, or see your activity. You will also be unfriended.")
            }
            .onAppear {
                AppLogger.debug("📱 [PROFILE] View appeared for \(user.name ?? user.username ?? "user")", category: .social)
                // Sprint 2026-04-24 Phase 4 (N1): pause intelligence phases
                // while user is in this detail view — see UserFocusSentinel doc.
                UserFocusSentinel.shared.beginFocus("FriendProfile")
                if user.isFriend {
                    loadData()
                }
                // Always fetch mutuals so the quick-add section can seed a
                // group challenge (friend case) or just inform context
                // (non-friend case).
                Task {
                    mutualFriends = await FriendService.shared.fetchMutualFriends(for: user.userId)
                }

                // 2026-05-04 — Path to 33: load this friend's stackable
                // Olympian seasons (RLS-protected; only readable when
                // accepted friends).
                Task {
                    await loadFriendOlympianSeasons()
                }
            }
            .onDisappear {
                UserFocusSentinel.shared.endFocus("FriendProfile")
            }
        }
    }
    
    // MARK: - Load Data
    
    private func loadData() {
        activeChallengesWithFriend = ChallengeService.shared.activeChallenges.filter { $0.opponentId == user.userId }
        sentWorkoutsToFriend = FriendService.shared.sentWorkouts.filter { $0.toUserId == user.userId }
        
        Task {
            friendChallenges = await ChallengeService.shared.getChallengesWithFriend(friendId: user.userId)
            await FriendRankingService.shared.logInteraction(
                withFriendId: user.userId,
                type: .profileViewed
            )
        }
        
        AppLogger.debug("📱 [PROFILE] Loaded \(activeChallengesWithFriend.count) active challenges, \(sentWorkoutsToFriend.count) sent workouts", category: .social)
    }
    
    // MARK: - Active Challenge Section
    
    private func activeChallengeSection(challenge: ActiveChallenge) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Active Challenge")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, Spacing.xxs)
            
            ActiveChallengeWidget(challenge: challenge) {
                selectedChallenge = challenge
                showingChallengeDetail = true
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            LargeCachedFriendPhoto(
                friendId: user.userId.uuidString,
                photoUrl: user.profilePhotoUrl,
                name: user.name ?? user.username ?? "User",
                size: 100,
                gradientColors: [.blue, .purple.opacity(0.8)]
            )
            
            HStack(spacing: 4) {
                Text(user.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if user.isVerified || user.isGoldVerified {
                    VerifiedBadge(size: 18, isGold: user.isGoldVerified)
                }
            }
            
            if user.isFriend, let since = user.friendsSince {
                HStack(spacing: 6) {
                    Image(systemName: "person.2.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Friends since \(formatDate(since))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if let username = user.username, !username.isEmpty, user.displayName != "@\(username)" {
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        HStack(spacing: 12) {
            statCard(
                icon: "flame.fill",
                gradientColors: [.orange, .red],
                value: user.fitnessGoal ?? "Not set",
                label: "Goal"
            )
            
            statCard(
                icon: "chart.bar.fill",
                gradientColors: [.green, .mint],
                value: user.experienceLevel ?? "Not set",
                label: "Level"
            )
            
            statCard(
                icon: "arrow.left.arrow.right",
                gradientColors: [.blue, .cyan],
                value: "\(user.totalWorkoutsShared)",
                label: "Shared"
            )
        }
    }

    // MARK: - Olympian Badges (2026-05-04 — Path to 33)

    /// Stackable Olympian YYYY crowns for the friend. Self-hides when
    /// `friendOlympianSeasons` is empty (new friend, never completed a path).
    /// Read access is RLS-gated: only accepted friends see a friend's badges
    /// (mirrors `user_achievements` social-visibility pattern).
    private var friendOlympianBadgesSection: some View {
        let goldAccent = Color(red: 1.00, green: 0.84, blue: 0.00)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(LinearGradient(
                        colors: [goldAccent, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Olympian Track")
                    .font(.ds_bodySmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text("\(friendOlympianSeasons.count) season\(friendOlympianSeasons.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(friendOlympianSeasons) { badge in
                        VStack(spacing: 2) {
                            Image(systemName: "crown.fill")
                                .font(.subheadline)
                                .foregroundStyle(LinearGradient(
                                    colors: [goldAccent, badge.resolvedArchetype.accent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                            Text("'\(String(badge.seasonYear).suffix(2))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 44, height: 44)
                        .background(
                            Circle().fill(goldAccent.opacity(0.10))
                        )
                        .overlay(
                            Circle().stroke(goldAccent.opacity(0.35), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(goldAccent.opacity(0.25), lineWidth: 1)
                )
        )
    }

    @MainActor
    private func loadFriendOlympianSeasons() async {
        struct FriendSeasonsRequest: Encodable {}
        do {
            let response: [OlympianSeasonBadge] = try await SupabaseManager.shared.supabaseClient
                .from("user_olympian_seasons")
                .select("season_year, archetype, completed_at")
                .eq("user_id", value: user.userId.uuidString)
                .order("season_year", ascending: false)
                .execute()
                .value
            self.friendOlympianSeasons = response
        } catch {
            AppLogger.warning("Failed to load friend Olympian seasons: \(error.localizedDescription)", category: .social)
        }
    }

    private var nonFriendStatsSection: some View {
        HStack(spacing: 12) {
            if let goal = user.fitnessGoal, !goal.isEmpty {
                statCard(
                    icon: "flame.fill",
                    gradientColors: [.orange, .red],
                    value: goal,
                    label: "Goal"
                )
            }
            
            if let level = user.experienceLevel, !level.isEmpty {
                statCard(
                    icon: "chart.bar.fill",
                    gradientColors: [.green, .mint],
                    value: level,
                    label: "Level"
                )
            }
        }
    }
    
    // MARK: - "See friends >" CTA (non-friend case)

    /// Single-row card that opens the target user's full friend list as an
    /// Instagram-style scroller. Sits below the mutual-friends compact card
    /// on a non-friend's profile so the user can browse the wider social
    /// graph (not just the intersection).
    private var seeUserFriendsButton: some View {
        Button(action: {
            HapticManager.impact(.light)
            showingUserFriendsList = true
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 36, height: 36)
                    Image(systemName: "person.2.crop.square.stack.fill")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("See friends")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Text("Browse \(user.name?.components(separatedBy: " ").first ?? user.username ?? "their")'s full friend list")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Mutual Friends Compact Preview (shared by friend & non-friend)

    /// Compact preview row that shows the mutual count and up to 5 stacked
    /// avatars. Tapping anywhere on the card opens `MutualFriendsListView`,
    /// which owns the multi-select + group / private challenge flow.
    private var mutualFriendsCompactSection: some View {
        Button(action: {
            HapticManager.impact(.light)
            showingMutualsList = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Mutual Friends (\(mutualFriends.count))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer()

                    HStack(spacing: 4) {
                        Text("See all")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundColor(.cyan)
                }

                // Stacked rings — up to 5 mutual avatars overlapping.
                // The inset stroke matches the card background so the ring
                // gradient on each avatar reads as a clean, separated edge.
                HStack(spacing: -10) {
                    ForEach(Array(mutualFriends.prefix(5))) { mutual in
                        CachedFriendPhoto(
                            friendId: mutual.userId.uuidString,
                            photoUrl: mutual.profilePhotoUrl,
                            name: mutual.displayName,
                            size: 38,
                            showGradientRing: true,
                            gradientColors: [.green, .cyan]
                        )
                        .overlay(Circle().stroke(Color.cardBackground, lineWidth: 2))
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)

                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.clear]
                                    : [Color.white, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func statCard(icon: String, gradientColors: [Color], value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(
            ZStack {
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        Color.cardBackground
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Colored accent border
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [gradientColors[0].opacity(colorScheme == .dark ? 0.3 : 0.2), gradientColors[1].opacity(colorScheme == .dark ? 0.2 : 0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Create Workout Button
    
    private var createWorkoutButton: some View {
        Button(action: { showingCreateWorkout = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .blue.opacity(0.4), radius: 6, x: 0, y: 3)
                    
                    Image(systemName: "dumbbell.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Workout for \(user.name?.components(separatedBy: " ").first ?? "Friend")")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Build and send a custom workout")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Blue/purple accent border
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.purple.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            .shadow(color: .blue.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Create Challenge Button
    
    /// Check if there's already an active challenge with this friend
    private var hasActiveChallengeWithFriend: Bool {
        !activeChallengesWithFriend.isEmpty
    }
    
    /// The active challenge with this friend (if any)
    private var activeChallengeWithFriend: ActiveChallenge? {
        activeChallengesWithFriend.first
    }
    
    private var createChallengeButton: some View {
        Group {
            if let activeChallenge = activeChallengeWithFriend {
                // Show active challenge status instead of create button
                activeChallengeCard(challenge: activeChallenge)
            } else {
                // Show create challenge button
                Button(action: {
                    showingChallengeFlow = true
                }) {
                    createChallengeButtonContent
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var createChallengeButtonContent: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.orange, .red]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                    .shadow(color: .orange.opacity(0.4), radius: 6, x: 0, y: 3)
                
                Image(systemName: "trophy.fill")
                    .font(.ds_heading2)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Create Challenge with \(user.name?.components(separatedBy: " ").first ?? "Friend")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Steps, workouts, running & more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.ds_labelMedium)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                // Main card background with gradient
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        Color.cardBackground
                    )
                
                // Inner highlight (top edge glow)
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                
                // Orange/red accent border
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.red.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
        .shadow(color: .orange.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Active Challenge Card (shows when challenge already exists with friend)
    
    private func activeChallengeCard(challenge: ActiveChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let resolver = ChallengeProgressResolver.shared
        
        return Button(action: {
            selectedChallenge = challenge
            showingChallengeDetail = true
        }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Text(resolvedType.emoji)
                        .font(.ds_heading3)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active Challenge")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("\(challenge.displayTitle) • \(challenge.daysRemaining) days left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Live score comparison
                VStack(spacing: 2) {
                    Text(challenge.amWinning ? "🏆" : "")
                        .font(.ds_caption)
                    Text("\(resolver.formattedProgress(for: challenge)) - \(resolver.formatValue(challenge.opponentTodayProgress ?? 0, unit: challenge.targetUnit, type: resolvedType))")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(challenge.amWinning ? .green : ((challenge.opponentTodayProgress ?? 0) > (challenge.myTodayProgress ?? 0) ? .red : .primary))
                }
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(resolvedType.color)
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(colorScheme == .dark ? 0.4 : 0.3), Color.cyan.opacity(colorScheme == .dark ? 0.3 : 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            .shadow(color: .blue.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 12, x: 0, y: 0) // Even glow
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Challenge History Section
    
    private var challengeHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
                Text("Challenge History")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, Spacing.xxs)
            
            VStack(spacing: 8) {
                ForEach(friendChallenges.prefix(3)) { challenge in
                    FriendChallengeRow(challenge: challenge) {
                        // Find matching active challenge or show completed state
                        if let activeMatch = activeChallengesWithFriend.first(where: { $0.challengeId == challenge.challengeId }) {
                            selectedChallenge = activeMatch
                            showingChallengeDetail = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Shared History Section
    
    private var sharedHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
                Text("Shared History")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, Spacing.xxs)
            
            if sentWorkoutsToFriend.isEmpty {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.15), .cyan.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "arrow.left.arrow.right.circle")
                            .font(.ds_heading1)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("No workouts shared yet")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Create a workout to get started!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                Color.cardBackground
                            )
                        
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                        : [Color.white, Color.white.opacity(0.5), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2), Color.cyan.opacity(colorScheme == .dark ? 0.2 : 0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            } else {
                // Show recent shared workouts
                VStack(spacing: 0) {
                    ForEach(sentWorkoutsToFriend) { workout in
                        SharedWorkoutHistoryRow(workout: workout, colorScheme: colorScheme)
                        
                        if workout.id != sentWorkoutsToFriend.last?.id {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(
                                Color.cardBackground
                            )
                        
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                        : [Color.white, Color.white.opacity(0.5), Color.clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                        
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.blue.opacity(colorScheme == .dark ? 0.2 : 0.15), Color.cyan.opacity(colorScheme == .dark ? 0.15 : 0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            }
        }
    }
    
    // recentSharedWorkouts is now using sentWorkoutsToFriend @State variable
    
    // MARK: - Unfriend Button
    
    private var unfriendButton: some View {
        Button(action: { showingUnfriendConfirmation = true }) {
            HStack {
                if isUnfriending {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "person.badge.minus")
                    Text("Unfriend")
                }
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.red.opacity(0.1))
            )
        }
        .disabled(isUnfriending)
    }
    
    // MARK: - Block Button
    
    private var blockButton: some View {
        Button(action: { showingBlockConfirmation = true }) {
            HStack {
                if isBlocking {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "hand.raised.slash")
                    Text("Block")
                }
            }
            .font(.subheadline)
            .foregroundColor(.red.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.red.opacity(0.05))
            )
        }
        .disabled(isBlocking)
    }
    
    // MARK: - Add Friend Button (non-friend state)
    
    private var addFriendButton: some View {
        Group {
            if requestSent || user.hasOutgoingRequest {
                HStack {
                    Image(systemName: "clock.fill")
                    Text("Request Sent")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.gray.opacity(0.1))
                )
            } else if user.hasIncomingRequest {
                Button {
                    Task {
                        if let request = FriendService.shared.pendingRequests.first(where: { $0.fromUserId == user.userId }) {
                            _ = await FriendService.shared.acceptFriendRequest(requestId: request.requestId)
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.checkmark")
                        Text("Accept Friend Request")
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
            } else {
                Button(action: sendFriendRequest) {
                    HStack(spacing: 8) {
                        if isSendingRequest {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "person.badge.plus")
                            Text("Add Friend")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .disabled(isSendingRequest)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func unfriend() {
        guard let friendshipId = user.friendshipId else { return }
        isUnfriending = true
        Task {
            let success = await FriendService.shared.removeFriend(friendshipId: friendshipId)
            if success {
                dismiss()
            }
            isUnfriending = false
        }
    }
    
    private func blockUser() {
        isBlocking = true
        Task {
            let success = await FriendService.shared.blockUser(userId: user.userId)
            if success {
                dismiss()
            }
            isBlocking = false
        }
    }
    
    private func sendFriendRequest() {
        isSendingRequest = true
        Task {
            let success = await FriendService.shared.sendFriendRequest(toUserId: user.userId)
            if success {
                requestSent = true
            }
            isSendingRequest = false
        }
    }
}

// MARK: - Shared Workout History Row

struct SharedWorkoutHistoryRow: View {
    let workout: SentWorkout
    let colorScheme: ColorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [workout.statusColor.opacity(0.2), workout.statusColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)
                
                Image(systemName: workout.statusIcon)
                    .font(.ds_bodyRegular)
                    .foregroundColor(workout.statusColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.workoutName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(formatDate(workout.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(workout.status.capitalized)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(workout.statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(workout.statusColor.opacity(0.15))
                )
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 14)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Mutual Friends Full-Screen List

/// Full-screen mutuals picker reached from a friend profile's "See all >".
/// - Top: 3 featured mutuals as larger avatars (visual emphasis).
/// - Below: scrollable list of every mutual; tap a row to toggle selection.
/// - Top-right system button: "Start Challenge" (≤2 selected → group flow)
///   or "Private Challenge" (>2 selected → private challenge community flow).
/// Both flows pre-include the primary friend (the profile we navigated from)
/// in the cohort so a tap on Kayli from KC's profile creates a group of
/// {you, KC, Kayli}.
struct MutualFriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager

    /// When non-nil, the toolbar exposes a "Start Challenge" / "Private
    /// Challenge" CTA that pre-includes this friend in the cohort. When nil
    /// (e.g. opened from a non-friend's profile), the challenge button is
    /// hidden — the surface becomes a read-only mutuals browser.
    let primaryFriend: Friend?
    let mutuals: [MutualFriend]

    @State private var selectedMutualIds: Set<UUID> = []
    @State private var showingGroupChallengeFlow = false
    @State private var showingPrivateChallengeFlow = false

    /// Mutuals we still have a local Friend record for (so we can pass them
    /// into the challenge flow without stale UUIDs).
    @MainActor
    private var addableFriends: [Friend] {
        let allFriends = FriendService.shared.friends
        return mutuals.compactMap { mutual in
            allFriends.first(where: { $0.friendId == mutual.userId })
        }
    }

    private var selectedFriends: [Friend] {
        addableFriends.filter { selectedMutualIds.contains($0.friendId) }
    }

    /// >2 mutuals = total cohort of 4+ (you + primaryFriend + 3 mutuals),
    /// which exceeds the regular group-challenge cap of 3 friends.
    /// Switch to the Private Challenge community flow.
    private var ctaUsesPrivate: Bool { selectedMutualIds.count > 2 }
    private var ctaTitle: String {
        ctaUsesPrivate ? "Private Challenge" : "Start Challenge"
    }

    private var topFeaturedMutuals: [MutualFriend] {
        Array(mutuals.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        if !topFeaturedMutuals.isEmpty {
                            featuredMutualsHeader
                        }

                        mutualsList
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Mutual Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.ds_labelLarge)
                    }
                }
                // Read-only mode (no `primaryFriend`) hides the CTA — opened
                // from a non-friend profile, where there's no friend to seed
                // a challenge with.
                if primaryFriend != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: launchChallenge) {
                            Text(ctaTitle)
                                .fontWeight(.semibold)
                        }
                        .disabled(selectedMutualIds.isEmpty)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingGroupChallengeFlow) {
                if let primaryFriend {
                    NavigationStack {
                        ChallengeFlowStartView(
                            preSelectedFriends: [primaryFriend] + selectedFriends
                        )
                        .environmentObject(userManager)
                    }
                }
            }
            .fullScreenCover(isPresented: $showingPrivateChallengeFlow) {
                if let primaryFriend {
                    NavigationStack {
                        PrivateChallengeCreationFlow(
                            preSelectedFriends: [primaryFriend] + selectedFriends
                        )
                        .environmentObject(userManager)
                    }
                }
            }
        }
    }

    private func launchChallenge() {
        guard !selectedMutualIds.isEmpty else { return }
        HapticManager.impact(.medium)
        if ctaUsesPrivate {
            showingPrivateChallengeFlow = true
        } else {
            showingGroupChallengeFlow = true
        }
    }

    // MARK: - Featured (top 3)

    private var featuredMutualsHeader: some View {
        HStack(spacing: 16) {
            Spacer()
            ForEach(topFeaturedMutuals) { mutual in
                featuredMutualButton(mutual: mutual)
            }
            Spacer()
        }
    }

    private func featuredMutualButton(mutual: MutualFriend) -> some View {
        let isSelected = selectedMutualIds.contains(mutual.userId)
        let isAddable = FriendService.shared.friends.contains(where: { $0.friendId == mutual.userId })
        let firstName = mutual.name?.components(separatedBy: " ").first
            ?? mutual.username
            ?? "Friend"

        return Button(action: { toggleSelection(mutual: mutual, isAddable: isAddable) }) {
            VStack(spacing: 8) {
                CachedFriendPhoto(
                    friendId: mutual.userId.uuidString,
                    photoUrl: mutual.profilePhotoUrl,
                    name: mutual.displayName,
                    size: 70,
                    showGradientRing: true,
                    gradientColors: isSelected ? [.blue, .cyan] : [.green, .cyan]
                )
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .shadow(color: isSelected ? .cyan.opacity(0.5) : .clear, radius: 10, x: 0, y: 4)
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .background(Circle().fill(Color.cardBackground))
                            .offset(x: 4, y: -4)
                    }
                }

                Text(firstName)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundColor(isSelected ? .cyan : .primary)
                    .lineLimit(1)
            }
            .opacity(isAddable ? 1.0 : 0.5)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAddable)
    }

    // MARK: - Full list

    private var mutualsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("All Mutuals (\(mutuals.count))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                if !selectedMutualIds.isEmpty {
                    Text("\(selectedMutualIds.count) selected")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.cyan.opacity(0.15)))
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(mutuals.enumerated()), id: \.element.id) { index, mutual in
                    mutualListRow(mutual: mutual)

                    if index < mutuals.count - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
        }
    }

    private func mutualListRow(mutual: MutualFriend) -> some View {
        let isSelected = selectedMutualIds.contains(mutual.userId)
        let isAddable = FriendService.shared.friends.contains(where: { $0.friendId == mutual.userId })

        return Button(action: { toggleSelection(mutual: mutual, isAddable: isAddable) }) {
            HStack(spacing: 12) {
                CachedFriendPhoto(
                    friendId: mutual.userId.uuidString,
                    photoUrl: mutual.profilePhotoUrl,
                    name: mutual.displayName,
                    size: 40,
                    showGradientRing: isSelected,
                    gradientColors: isSelected ? [.blue, .cyan] : [.green, .green.opacity(0.6)]
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(mutual.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if let username = mutual.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3)
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.secondary)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .opacity(isAddable ? 1.0 : 0.5)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAddable)
    }

    private func toggleSelection(mutual: MutualFriend, isAddable: Bool) {
        guard isAddable else { return }
        HapticManager.impact(.light)
        if selectedMutualIds.contains(mutual.userId) {
            selectedMutualIds.remove(mutual.userId)
        } else {
            selectedMutualIds.insert(mutual.userId)
        }
    }
}

// MARK: - User Friends Full-Screen List (Instagram-style)

/// Instagram-style scrollable list of *another user's* friends. Reached from
/// the "See friends >" CTA on a non-friend's profile (`FriendProfileView`).
/// Each row renders the right per-row CTA based on the caller's relationship
/// with that friend:
///   - **Friends**          → green "Friends" pill
///   - **Pending (sent)**   → muted "Pending" pill
///   - **Pending (recv'd)** → blue "Accept" button → `acceptFriendRequest`
///   - **Stranger**         → blue "+ Add" button → `sendFriendRequest`
///
/// Backed by `FriendService.fetchUserFriendsList(for:)` → RPC
/// `get_user_friends_list` (#196). Rows that yield friend-request actions
/// optimistically toggle local state so the user gets instant feedback while
/// the network call completes.
struct UserFriendsListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager

    let targetUser: ProfileUser

    @State private var entries: [UserFriendListEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var sentRequestIds: Set<UUID> = []
    @State private var inFlightRequestIds: Set<UUID> = []
    @State private var acceptedRequestIds: Set<UUID> = []
    @State private var selectedProfile: ProfileUser?

    private var filtered: [UserFriendListEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            (entry.name?.lowercased().contains(query) ?? false)
                || (entry.username?.lowercased().contains(query) ?? false)
        }
    }

    private var headerSubtitle: String {
        let firstName = targetUser.name?.components(separatedBy: " ").first
            ?? targetUser.username
            ?? "they"
        if entries.isEmpty {
            return isLoading ? "Loading…" : "\(firstName) has no friends yet"
        }
        return "\(entries.count) friend\(entries.count == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        searchBar
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, 12)
                            .padding(.bottom, 8)

                        if isLoading && entries.isEmpty {
                            loadingState
                                .padding(.top, 60)
                        } else if filtered.isEmpty {
                            emptyState
                                .padding(.top, 60)
                        } else {
                            friendsListCard
                                .padding(.horizontal, Spacing.md)
                                .padding(.bottom, 40)
                        }
                    }
                }
            }
            .navigationTitle(targetUser.name?.components(separatedBy: " ").first.map { "\($0)'s Friends" } ?? "Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.ds_labelLarge)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(targetUser.name?.components(separatedBy: " ").first ?? targetUser.username ?? "Friends")
                            .font(.headline)
                        Text(headerSubtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .task { await loadFriends() }
            .sheet(item: $selectedProfile) { profile in
                FriendProfileView(user: profile)
                    .environmentObject(userManager)
            }
        }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.subheadline)

            TextField("Search friends", text: $searchText)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.cardBackground)
        )
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading friends…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        let firstName = targetUser.name?.components(separatedBy: " ").first
            ?? targetUser.username
            ?? "This user"
        return VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.title)
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "\(firstName) has no friends yet" : "No friends matching \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    private var friendsListCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                friendRow(entry: entry)

                if index < filtered.count - 1 {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
        )
    }

    private func friendRow(entry: UserFriendListEntry) -> some View {
        Button(action: { openProfile(for: entry) }) {
            HStack(spacing: 12) {
                CachedFriendPhoto(
                    friendId: entry.userId.uuidString,
                    photoUrl: entry.profilePhotoUrl,
                    name: entry.name ?? entry.username ?? "?",
                    size: 44,
                    showGradientRing: entry.isMyFriend,
                    gradientColors: [.green, .green.opacity(0.6)]
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.name ?? "Unknown")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if (entry.isVerified ?? false) || (entry.isGoldVerified ?? false) {
                            VerifiedBadge(size: 12, isGold: entry.isGoldVerified ?? false)
                        }
                    }

                    if let username = entry.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                rowActionPill(entry: entry)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    @ViewBuilder
    private func rowActionPill(entry: UserFriendListEntry) -> some View {
        let optimisticallySent = sentRequestIds.contains(entry.userId)
        let optimisticallyAccepted = acceptedRequestIds.contains(entry.userId)
        let isInFlight = inFlightRequestIds.contains(entry.userId)

        if entry.isMyFriend || optimisticallyAccepted {
            // Green "Friends" pill — already in our circle.
            Text("Friends")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.green.opacity(0.15)))
        } else if entry.hasOutgoingRequest || optimisticallySent {
            // Muted "Pending" pill — request already sent.
            Text("Pending")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.gray.opacity(0.15)))
        } else if entry.hasIncomingRequest {
            // Inbound request → "Accept" button.
            Button(action: { Task { await acceptIncoming(entry: entry) } }) {
                HStack(spacing: 4) {
                    if isInFlight {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text("Accept")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isInFlight)
        } else {
            // Stranger → "+ Add" button (sends a friend request).
            Button(action: { Task { await sendRequest(entry: entry) } }) {
                HStack(spacing: 4) {
                    if isInFlight {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                    }
                    Text("Add")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isInFlight)
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadFriends() async {
        isLoading = true
        let fetched = await FriendService.shared.fetchUserFriendsList(for: targetUser.userId)
        entries = fetched
        isLoading = false
    }

    @MainActor
    private func openProfile(for entry: UserFriendListEntry) {
        // Map to a ProfileUser via the existing UserSearchResult bridge.
        // Note: argument order must match the struct's memberwise init
        // (userId, name, email, username, fitnessGoal, experienceLevel,
        // profilePhotoUrl, isFriend, hasPendingRequest, hasOutgoingRequest,
        // hasIncomingRequest, isVerified, isGoldVerified).
        let pendingEither = entry.hasOutgoingRequest
            || entry.hasIncomingRequest
            || sentRequestIds.contains(entry.userId)
        let synthesizedSearch = UserSearchResult(
            userId: entry.userId,
            name: entry.name,
            email: nil,
            username: entry.username,
            fitnessGoal: nil,
            experienceLevel: nil,
            profilePhotoUrl: entry.profilePhotoUrl,
            isFriend: entry.isMyFriend || acceptedRequestIds.contains(entry.userId),
            hasPendingRequest: pendingEither,
            hasOutgoingRequest: entry.hasOutgoingRequest || sentRequestIds.contains(entry.userId),
            hasIncomingRequest: entry.hasIncomingRequest,
            isVerified: entry.isVerified,
            isGoldVerified: entry.isGoldVerified
        )
        selectedProfile = ProfileUser(searchResult: synthesizedSearch)
    }

    @MainActor
    private func sendRequest(entry: UserFriendListEntry) async {
        guard !inFlightRequestIds.contains(entry.userId) else { return }
        HapticManager.impact(.medium)
        inFlightRequestIds.insert(entry.userId)
        let success = await FriendService.shared.sendFriendRequest(toUserId: entry.userId)
        inFlightRequestIds.remove(entry.userId)
        if success {
            sentRequestIds.insert(entry.userId)
            HapticManager.notification(.success)
        }
    }

    @MainActor
    private func acceptIncoming(entry: UserFriendListEntry) async {
        guard !inFlightRequestIds.contains(entry.userId) else { return }
        HapticManager.impact(.medium)
        inFlightRequestIds.insert(entry.userId)
        // Find the matching pending-request id from the FriendService cache —
        // the list RPC doesn't carry the request UUID, so we look it up here.
        if let request = FriendService.shared.pendingRequests.first(where: { $0.fromUserId == entry.userId }) {
            let ok = await FriendService.shared.acceptFriendRequest(requestId: request.requestId)
            if ok {
                acceptedRequestIds.insert(entry.userId)
                HapticManager.notification(.success)
            }
        }
        inFlightRequestIds.remove(entry.userId)
    }
}
