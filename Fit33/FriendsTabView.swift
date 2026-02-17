import SwiftUI
import CoreData

// MARK: - Friends Tab View
/// The main social hub — friend circles, active challenges, recommended challenges,
/// community challenges, and quick friend search. High-energy, engaging design.

struct FriendsTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    @StateObject private var friendService = FriendService.shared
    @StateObject private var rankingService = FriendRankingService.shared
    @StateObject private var challengeService = ChallengeService.shared
    @StateObject private var communityService = CommunityChallengeService.shared
    @StateObject private var contactsService = ContactsService.shared
    
    @State private var showingFriendsList = false
    @State private var showingFriendProfile: Friend?
    @State private var showingCommunityHub = false
    @State private var showingChallengeCreation = false
    @State private var activeChallengePageIndex = 0
    @State private var sentRecommendedChallenge = false
    @State private var showingSentConfirmation = false
    @State private var navigationPath = NavigationPath()
    @State private var sentRequestIds: Set<UUID> = [] // Track sent friend requests for instant UI
    
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
                        
                        // Active Challenges carousel
                        activeChallengesCarousel
                        
                        // Recommended Challenge for You
                        recommendedChallengeWidget
                        
                        // Join Community Challenge
                        communityChallengeWidget
                        
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
        }
        .task {
            // ⚡️ INSTANT DISPLAY: FriendService and FriendRankingService load cached
            // data in their init(), so the Friends tab shows populated data immediately.
            // This .task just refreshes from the server in the background.
            
            // Small debounce to avoid competing with Dashboard's initial load
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            guard !Task.isCancelled else { return }
            
            // Refresh friend data (services have internal caching — if data is fresh, these are no-ops)
            await rankingService.fetchRankedFriends()
            await friendService.fetchFriends()
            
            // Refresh contact suggestions (non-friends from contacts) every time tab loads
            if contactsService.canAccessContacts {
                await contactsService.fetchContactsAndFindFriends()
            }
            
            // Only fetch challenges if Dashboard hasn't already loaded them
            if challengeService.activeChallenges.isEmpty {
                await challengeService.fetchActiveChallenges()
                await challengeService.fetchActiveGroupChallenges()
            }
            
            // Community challenges last (lowest priority)
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await communityService.fetchFeaturedChallenges()
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
        .sheet(isPresented: $showingCommunityHub) {
            CommunityChallengesHubView()
        }
        .sheet(isPresented: $showingChallengeCreation) {
            ChallengeFlowStartView()
                .environmentObject(userManager)
        }
        .overlay(
            sentConfirmationOverlay
        )
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
            
            // Add Friend button
            Button(action: {
                HapticManager.selectionChanged()
                showingFriendsList = true
            }) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .padding(10)
                    .background(
                        Circle()
                            .fill(.ultraThinMaterial)
                            .shadow(color: Color.cyan.opacity(0.2), radius: 8, x: 0, y: 2)
                    )
            }
        }
        .padding(.leading, 4)
    }
    
    // MARK: - Add Friends Bar (Non-Friends from Contacts)
    
    private var friendStoriesBar: some View {
        // Show non-friend contact suggestions with quick-add "+" button
        // CRITICAL: Cross-reference against actual FriendService.friends to exclude existing friends
        // The isFriend flag from ContactsService can be stale/incorrect
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let suggestions = contactsService.suggestedFriends
            .filter { suggestion in
                // Exclude: already friends (by ID check against live friend list)
                guard !existingFriendIds.contains(suggestion.userId) else { return false }
                // Exclude: already flagged as friend by contacts service
                guard !suggestion.isFriend else { return false }
                // Exclude: already sent a request (from contacts service or this session)
                guard !suggestion.hasOutgoingRequest && !sentRequestIds.contains(suggestion.userId) else { return false }
                return true
            }
            .sorted { a, b in
                // Prioritize users with profile photos
                let aHasPhoto = a.profilePhotoUrl != nil && !(a.profilePhotoUrl?.isEmpty ?? true)
                let bHasPhoto = b.profilePhotoUrl != nil && !(b.profilePhotoUrl?.isEmpty ?? true)
                if aHasPhoto != bHasPhoto { return aHasPhoto }
                let aHasUsername = a.username != nil && !(a.username?.isEmpty ?? true)
                let bHasUsername = b.username != nil && !(b.username?.isEmpty ?? true)
                if aHasUsername != bHasUsername { return aHasUsername }
                return (a.name ?? "") < (b.name ?? "")
            }
        
        return Group {
            if !suggestions.isEmpty || contactsService.canAccessContacts {
                VStack(alignment: .leading, spacing: 12) {
                    // Header
                    HStack {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .font(.title3)
                        Text("Add Friends")
                            .font(.title3)
                            .fontWeight(.bold)
                        Spacer()
                        
                        Button(action: {
                            HapticManager.selectionChanged()
                            showingFriendsList = true
                        }) {
                            Text("See All")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            // "Find" search circle as first item
                            Button(action: {
                                HapticManager.selectionChanged()
                                showingFriendsList = true
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
                                        
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 22, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            )
                                    }
                                    .frame(width: 64, height: 64)
                                    
                                    Text("Find")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 72)
                            }
                            .buttonStyle(.plain)
                            
                            // Contact suggestions
                            ForEach(suggestions.prefix(12)) { suggestion in
                                contactSuggestionCircle(suggestion: suggestion)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                    }
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
        Button(action: {
            HapticManager.impact(.medium)
            // Send friend request
            sentRequestIds.insert(suggestion.userId)
            Task {
                let success = await friendService.sendFriendRequest(toUserId: suggestion.userId)
                if !success {
                    // Revert if failed
                    sentRequestIds.remove(suggestion.userId)
                }
            }
        }) {
            VStack(spacing: 5) {
                ZStack(alignment: .bottomTrailing) {
                    // Profile photo or initials
                    if let photoUrl = suggestion.profilePhotoUrl, let url = URL(string: photoUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 58, height: 58)
                                    .clipShape(Circle())
                            default:
                                suggestionInitialsCircle(suggestion: suggestion)
                            }
                        }
                    } else {
                        suggestionInitialsCircle(suggestion: suggestion)
                    }
                    
                    // "+" badge overlay
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 22, height: 22)
                            .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 1)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .offset(x: 2, y: 2)
                }
                .frame(width: 64, height: 64)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(colors: [.blue.opacity(0.5), .cyan.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 2.5
                        )
                        .frame(width: 66, height: 66)
                )
                
                Text(suggestion.name?.components(separatedBy: " ").first ?? suggestion.username ?? "Add")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
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
        
        return Group {
            if totalCards > 0 {
                VStack(alignment: .leading, spacing: 12) {
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
                    
                    // Card with carousel inside
                    TabView(selection: $activeChallengePageIndex) {
                        ForEach(Array(activeChallenges.enumerated()), id: \.element.id) { index, challenge in
                            activeChallengeCard(challenge: challenge)
                                .tag(index)
                        }
                        
                        ForEach(Array(groupChallenges.enumerated()), id: \.element.id) { index, group in
                            groupChallengeCard(challenge: group)
                                .tag(activeChallenges.count + index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: totalCards > 1 ? .automatic : .never))
                    .frame(height: 175)
                }
            } else {
                noChallengesCard
            }
        }
    }
    
    private func activeChallengeCard(challenge: ActiveChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let typeGradient = resolvedType.gradientColors
        let resolver = ChallengeProgressResolver.shared
        let myProgress = resolver.liveProgress(for: challenge)
        let oppProgress = (challenge.opponentTodayProgress ?? 0) > 0
            ? (challenge.opponentTodayProgress ?? 0)
            : challenge.opponentTotalProgress
        let amWinning = myProgress > oppProgress
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        
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
                    Text(challenge.displayTitle)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text("vs \(opponentFirst)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if amWinning {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                        Text("Winning!")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                } else {
                    Text("Behind")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                }
            }
            .padding(16)
            
            // Progress comparison bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("You")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(resolver.formatValue(myProgress, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(amWinning ? .green : .primary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(opponentFirst)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(resolver.formatValue(oppProgress, unit: challenge.targetUnit, type: resolvedType))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(!amWinning ? .red : .primary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .sleekCard(cornerRadius: 20, accentColor: resolvedType.color)
        .padding(.horizontal, 4)
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
        VStack(alignment: .leading, spacing: 12) {
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
    
    private var communityChallengeWidget: some View {
        let featured = communityService.featuredChallenges.filter { !$0.alreadyJoined }.prefix(2)
        
        return VStack(alignment: .leading, spacing: 12) {
            // Header OUTSIDE the card
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
                    Text("Browse All")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
            
            if featured.isEmpty {
                // Loading or empty state
                VStack(spacing: 12) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 36))
                        .foregroundColor(.green.opacity(0.4))
                    
                    Text("Discover community challenges")
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
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(featured)) { challenge in
                        communityChallengeRow(challenge: challenge)
                    }
                }
            }
        }
    }
    
    private func communityChallengeRow(challenge: FeaturedCommunityChallenge) -> some View {
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

// MARK: - Preview

#Preview {
    FriendsTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
        .environmentObject(UserManager())
        .environmentObject(WorkoutManager.shared)
}
