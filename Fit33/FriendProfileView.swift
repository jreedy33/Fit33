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

    init(searchResult: UserSearchResult) {
        self.userId = searchResult.userId
        self.name = searchResult.name
        self.username = searchResult.username
        self.email = searchResult.email
        self.fitnessGoal = searchResult.fitnessGoal
        self.experienceLevel = searchResult.experienceLevel
        self.profilePhotoUrl = searchResult.profilePhotoUrl
        self.isFriend = searchResult.isFriend
        self.hasOutgoingRequest = searchResult.hasOutgoingRequest ?? searchResult.hasPendingRequest
        self.hasIncomingRequest = searchResult.hasIncomingRequest ?? false
        self.friendshipId = nil
        self.friendsSince = nil
        self.totalWorkoutsShared = 0
        self.isVerified = searchResult.isVerified ?? false
        self.isGoldVerified = searchResult.isGoldVerified ?? false
        self.mutualFriendCount = nil
    }

    init(suggested: SuggestedFriend) {
        self.userId = suggested.userId
        self.name = suggested.name
        self.username = suggested.username
        self.email = suggested.email
        self.fitnessGoal = suggested.fitnessGoal
        self.experienceLevel = nil
        self.profilePhotoUrl = suggested.profilePhotoUrl
        self.isFriend = suggested.isFriend
        self.hasOutgoingRequest = suggested.hasOutgoingRequest
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
                            statsSection

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

                            if !mutualFriends.isEmpty {
                                mutualFriendsSection
                            }

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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCreateWorkout) {
                if let friend = user.asFriend {
                    CreateWorkoutForFriendView(friend: friend)
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
                if user.isFriend {
                    loadData()
                } else {
                    Task {
                        mutualFriends = await FriendService.shared.fetchMutualFriends(for: user.userId)
                    }
                }
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
    
    private var mutualFriendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("\(mutualFriends.count) Mutual Friend\(mutualFriends.count == 1 ? "" : "s")")
                    .font(.ds_bodySmall)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(mutualFriends.enumerated()), id: \.element.id) { index, mutual in
                    HStack(spacing: 12) {
                        CachedFriendPhoto(
                            friendId: mutual.userId.uuidString,
                            photoUrl: mutual.profilePhotoUrl,
                            name: mutual.displayName,
                            size: 36,
                            showGradientRing: true,
                            gradientColors: [.green, .green.opacity(0.6)]
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

                        Text("Friends")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if index < mutualFriends.count - 1 {
                        Divider()
                            .padding(.leading, 60)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
        }
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

// MARK: - Create Workout For Friend View

struct CreateWorkoutForFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    
    let friend: Friend
    
    @State private var workoutName = ""
    @State private var workoutDescription = ""
    @State private var personalMessage = ""
    @State private var selectedExercises: [Exercise] = []
    @State private var exerciseConfigs: [UUID: ExerciseConfig] = [:]
    @State private var estimatedDuration: Int = 45
    @State private var difficulty: String = "Custom"
    
    @State private var showingExercisePicker = false
    @State private var showingPreview = false
    @State private var isSending = false
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with friends tab)
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Recipient Header
                        recipientHeader
                        
                        // Workout Details
                        workoutDetailsSection
                        
                        // Exercise List
                        exerciseListSection
                        
                        // Personal Message
                        personalMessageSection
                        
                        // Duration & Difficulty
                        metadataSection
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 16)
                    .padding(.bottom, 100)
                }
                
                // Bottom Bar
                VStack {
                    Spacer()
                    bottomBar
                }
            }
            .navigationTitle("Create Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(selectedExercises: $selectedExercises)
            }
            .sheet(isPresented: $showingPreview) {
                SharedWorkoutPreviewView(
                    friend: friend,
                    workoutName: workoutName,
                    workoutDescription: workoutDescription,
                    exercises: buildSelectedExercises(),
                    message: personalMessage,
                    onSent: { dismiss() }
                )
            }
        }
    }
    
    // MARK: - Recipient Header
    
    private var recipientHeader: some View {
        HStack(spacing: 14) {
            CachedFriendPhoto(
                friendId: friend.friendId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                size: 50,
                showGradientRing: false,
                gradientColors: [.blue.opacity(0.6), .purple.opacity(0.6)]
            )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Creating for")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(friend.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            Image(systemName: "paperplane.fill")
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 16, accentColor: .cyan)
    }
    
    // MARK: - Workout Details Section
    
    private var workoutDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workout Details")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.leading, 4)
            
            VStack(spacing: 16) {
                // Name
                VStack(alignment: .leading, spacing: 8) {
                    Text("Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., Full Body Blast", text: $workoutName)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                }
                
                // Description
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("What's this workout about?", text: $workoutDescription, axis: .vertical)
                        .textFieldStyle(PlainTextFieldStyle())
                        .lineLimit(2...4)
                        .padding(Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                        )
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
        }
    }
    
    // MARK: - Exercise List Section
    
    private var exerciseListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Exercises")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { showingExercisePicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add")
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, Spacing.xxs)
            
            if selectedExercises.isEmpty {
                emptyExercisesView
            } else {
                VStack(spacing: 0) {
                    ForEach(selectedExercises, id: \.objectID) { exercise in
                        ExerciseConfigRow(
                            exercise: exercise,
                            config: binding(for: exercise),
                            onRemove: { removeExercise(exercise) }
                        )
                        
                        if exercise.objectID != selectedExercises.last?.objectID {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                )
            }
        }
    }
    
    private var emptyExercisesView: some View {
        VStack(spacing: 16) {
            Image(systemName: "dumbbell")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("No exercises added")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: { showingExercisePicker = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercises")
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, Spacing.sm)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
        )
    }
    
    // MARK: - Personal Message Section
    
    private var personalMessageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Message")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.leading, 4)
            
            VStack(spacing: 8) {
                Text("Optional note for \(friend.friendName?.components(separatedBy: " ").first ?? "your friend")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                TextEditor(text: $personalMessage)
                    .frame(height: 80)
                    .padding(Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                    )
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
        }
    }
    
    // MARK: - Metadata Section
    
    private var metadataSection: some View {
        HStack(spacing: 12) {
            // Duration
            VStack(alignment: .leading, spacing: 8) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.blue)
                    
                    Picker("Duration", selection: $estimatedDuration) {
                        ForEach([15, 30, 45, 60, 75, 90], id: \.self) { mins in
                            Text("\(mins) min").tag(mins)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.cardBackground)
            )
            
            // Difficulty
            VStack(alignment: .leading, spacing: 8) {
                Text("Difficulty")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: "flame")
                        .foregroundColor(.orange)
                    
                    Picker("Difficulty", selection: $difficulty) {
                        Text("Beginner").tag("Beginner")
                        Text("Intermediate").tag("Intermediate")
                        Text("Advanced").tag("Advanced")
                        Text("Custom").tag("Custom")
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color.cardBackground)
            )
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Exercise count
            VStack(alignment: .leading, spacing: 2) {
                Text("\(selectedExercises.count) exercises")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("~\(estimatedDuration) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Preview Button
            Button(action: { showingPreview = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                    Text("Preview & Send")
                }
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: canSend ? [.blue, .purple] : [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, Spacing.md)
        .background(
            Rectangle()
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: -5)
        )
    }
    
    // MARK: - Helpers
    
    private var canSend: Bool {
        !workoutName.isEmpty && !selectedExercises.isEmpty
    }
    
    private func binding(for exercise: Exercise) -> Binding<ExerciseConfig> {
        Binding(
            get: {
                exerciseConfigs[exercise.id ?? UUID()] ?? ExerciseConfig()
            },
            set: { newValue in
                exerciseConfigs[exercise.id ?? UUID()] = newValue
            }
        )
    }
    
    private func removeExercise(_ exercise: Exercise) {
        selectedExercises.removeAll { $0.objectID == exercise.objectID }
        if let id = exercise.id {
            exerciseConfigs.removeValue(forKey: id)
        }
    }
    
    private func buildSelectedExercises() -> [SelectedExerciseForFriend] {
        selectedExercises.map { exercise in
            let config = exerciseConfigs[exercise.id ?? UUID()] ?? ExerciseConfig()
            return SelectedExerciseForFriend(
                exerciseId: exercise.id?.uuidString,
                name: exercise.name ?? "Unknown",
                category: exercise.category,
                sets: config.sets,
                reps: config.reps,
                restSeconds: config.restSeconds ?? 90,
                notes: config.notes ?? ""
            )
        }
    }
}

// MARK: - Exercise Config

struct ExerciseConfig {
    var sets: Int = 3
    var reps: String = "8-12"
    var restSeconds: Int? = 90
    var notes: String? = nil
}

// MARK: - Exercise Config Row

struct ExerciseConfigRow: View {
    let exercise: Exercise
    @Binding var config: ExerciseConfig
    let onRemove: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(config.sets) sets × \(config.reps) reps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Expand button
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Remove button
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.6))
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            
            // Expanded config
            if isExpanded {
                VStack(spacing: 16) {
                    Divider()
                    
                    HStack(spacing: 16) {
                        // Sets
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Stepper("\(config.sets)", value: $config.sets, in: 1...10)
                                .labelsHidden()
                        }
                        
                        // Reps
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reps")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("8-12", text: $config.reps)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 80)
                        }
                        
                        // Rest
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rest (sec)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("90", value: $config.restSeconds, format: .number)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 60)
                        }
                    }
                    
                    // Notes
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        TextField("Optional instructions...", text: Binding(
                            get: { config.notes ?? "" },
                            set: { config.notes = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK: - Exercise Picker View

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var selectedExercises: [Exercise]
    
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var localSelection: Set<NSManagedObjectID> = []
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Exercise.name, ascending: true)],
        animation: .default)
    private var allExercises: FetchedResults<Exercise>
    
    private let categories = ["All", "Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
    
    
    private var filteredExercises: [Exercise] {
        var exercises = Array(allExercises)
        
        if selectedCategory != "All" {
            exercises = exercises.filter { $0.category == selectedCategory }
        }
        
        if !searchText.isEmpty {
            exercises = exercises.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return exercises
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.exercises(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search exercises", text: $searchText)
                    }
                    .padding(Spacing.sm)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.cardBackground))
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 8)
                    
                    // Categories
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(categories, id: \.self) { category in
                                Button(action: { selectedCategory = category }) {
                                    Text(category)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(selectedCategory == category ? .white : .primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, Spacing.xs)
                                        .background(
                                            Capsule()
                                                .fill(selectedCategory == category
                                                    ? LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)
                                                    : LinearGradient(colors: [Color.cardBackground, Color.cardBackground], startPoint: .leading, endPoint: .trailing))
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                    }
                    
                    // Exercise List
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredExercises, id: \.objectID) { exercise in
                                ExercisePickerRow(
                                    exercise: exercise,
                                    isSelected: localSelection.contains(exercise.objectID),
                                    onToggle: {
                                        if localSelection.contains(exercise.objectID) {
                                            localSelection.remove(exercise.objectID)
                                        } else {
                                            localSelection.insert(exercise.objectID)
                                        }
                                    }
                                )
                                
                                if exercise.objectID != filteredExercises.last?.objectID {
                                    Divider().padding(.leading, 50)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(Color.cardBackground)
                        )
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Add Exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add \(localSelection.count)") {
                        addSelectedExercises()
                    }
                    .fontWeight(.semibold)
                    .disabled(localSelection.isEmpty)
                }
            }
            .onAppear {
                // Initialize with already selected exercises
                localSelection = Set(selectedExercises.map { $0.objectID })
            }
        }
    }
    
    private func addSelectedExercises() {
        let newExercises = allExercises.filter { localSelection.contains($0.objectID) }
        selectedExercises = newExercises.sorted { ($0.name ?? "") < ($1.name ?? "") }
        dismiss()
    }
}

// MARK: - Exercise Picker Row

struct ExercisePickerRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 14) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 16, height: 16)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name ?? "Unknown")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(exercise.category ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.clear)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
