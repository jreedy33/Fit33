import SwiftUI

// MARK: - Friends List View
/// Main hub for managing friends - view friends, requests, and search for new friends

struct FriendsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    // Use ObservedObject for singletons to observe without owning lifecycle
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var contactsService = ContactsService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared
    
    // Initial tab can be set via deep link (0: Friends, 1: Requests, 2: Search)
    var initialTab: Int = 0
    
    @State private var selectedTab = 0 // 0: Friends, 1: Requests, 2: Search
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingFriendProfile: Friend?
    @State private var showingReceivedWorkouts = false
    @State private var hasLoadedInitialData = false // Prevent navigation reset from data reloading
    @State private var isRefreshingRequests = false // For pull-to-refresh on requests tab
    @State private var wasInBackground = false // Track if user went to Settings
    @State private var showRankedView = true // Toggle between ranked/alphabetical
    @State private var showingQRScanner = false // QR code scanner sheet
    @State private var showingMyQRCode = false // My QR code sheet
    @State private var topFriendsPage = 0 // 0: Most engaged, 1: Newest added
    @State private var friendSwipeDragOffset: CGFloat = 0
    
    // Adaptive colors
    
    var body: some View {
        ZStack {
            // Animated blue/cyan orb background
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                // Content based on selected tab
                Group {
                    switch selectedTab {
                    case 0:
                        friendsListContent
                    case 1:
                        requestsContent
                    case 2:
                        searchContent
                    default:
                        friendsListContent
                    }
                }
                .animation(.easeOut(duration: 0.2), value: selectedTab)
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Received Workouts Badge Button
                Button(action: { showingReceivedWorkouts = true }) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "tray.full.fill")
                            .font(.ds_heading3)
                            .foregroundColor(.blue)
                        
                        if friendService.unreadWorkoutCount > 0 {
                            Text("\(friendService.unreadWorkoutCount)")
                                .font(.ds_caption)
                                .foregroundColor(.white)
                                .padding(Spacing.xxs)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
        }
        .sheet(item: $showingFriendProfile) { friend in
            NavigationStack {
                FriendProfileView(friend: friend)
            }
        }
        .sheet(isPresented: $showingReceivedWorkouts) {
            NavigationStack {
                ReceivedWorkoutsView()
            }
        }
        .sheet(isPresented: $showingMyQRCode) {
            MyQRCodeView()
        }
        .fullScreenCover(isPresented: $showingQRScanner) {
            QRCodeScannerView()
        }
        .onAppear {
            // Set initial tab from deep link if specified
            if initialTab != 0 {
                selectedTab = initialTab
            }
            
            // ALWAYS refresh pending requests when coming from a deep link (notification tap)
            // This ensures the request is fetched and displayed even if there's a race condition
            if initialTab == 1 {
                AppLogger.debug("👥 [FRIENDS] Opened from notification - forcing refresh of pending requests", category: .social)
                Task {
                    await friendService.fetchPendingRequests()
                    await friendService.fetchSentRequests()
                }
            }
            
            // Only load ALL data on first appear to prevent navigation disruption
            // Subsequent appears (e.g., returning from detail view) skip the full load
            guard !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            
            // ⚡️ INSTANT LOAD: Use already-cached friends data (loaded at app startup)
            // Only do background refresh if data is empty or stale
            if !friendService.friends.isEmpty {
                AppLogger.debug("👥 [FRIENDS] Using cached friends data (\(friendService.friends.count) friends) - instant display!", category: .social)
                // Preload photos in background for fast display
                preloadFriendPhotos()
                
                // Background refresh for freshness (non-blocking, low priority)
                Task(priority: .low) {
                    await rankingService.fetchRankedFriends()
                    await rankingService.fetchFriendsFromContacts()
                }
            } else {
                // No cached data - need to fetch
                AppLogger.debug("👥 [FRIENDS] No cached data, fetching from server...", category: .social)
                Task {
                    await friendService.loadAllData()
                    await rankingService.fetchRankedFriends()
                    await rankingService.fetchFriendsFromContacts()
                    preloadFriendPhotos()
                }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Refresh friends when switching to Friends tab (tab 0)
            // This ensures new friends appear immediately after accepting a request
            if newTab == 0 {
                // ⚡️ Background refresh - don't block the UI
                preloadFriendPhotos()
                Task(priority: .low) {
                    await friendService.fetchFriends()
                    await rankingService.fetchRankedFriends()
                    await rankingService.fetchFriendsFromContacts()
                }
            }
            // Load contact suggestions when switching to Search tab (tab 2)
            if newTab == 2 && contactsService.canAccessContacts && !contactsService.hasCheckedContacts {
                Task {
                    await contactsService.fetchContactsAndFindFriends()
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Track when user goes to background (likely to Settings)
            if newPhase == .background {
                wasInBackground = true
            }
            
            // When returning from background, check if contacts were enabled
            if newPhase == .active && wasInBackground {
                wasInBackground = false
                
                // Re-check authorization status
                contactsService.checkAuthorizationStatus()
                
                // If contacts are now accessible and we're on Search tab, fetch immediately
                if contactsService.canAccessContacts && selectedTab == 2 {
                    AppLogger.info("✅ [CONTACTS] User returned from Settings - contacts now enabled!", category: .social)
                    HapticManager.notification(.success)
                    Task {
                        await contactsService.fetchContactsAndFindFriends()
                    }
                }
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(["Friends", "Requests", "Search"], id: \.self) { tab in
                let index = ["Friends", "Requests", "Search"].firstIndex(of: tab) ?? 0
                let isSelected = selectedTab == index
                let badgeCount = index == 1 ? friendService.pendingRequests.count : 0
                
                Button(action: {
                    AppLogger.debug("🔴 [TAB] Tapped \(tab) tab (index: \(index))", category: .social)
                    HapticManager.selectionChanged()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedTab = index
                    }
                }) {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Text(tab)
                                .font(.subheadline)
                                .fontWeight(isSelected ? .bold : .medium)
                            
                            if badgeCount > 0 {
                                Text("\(badgeCount)")
                                    .font(.ds_caption)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                        .foregroundColor(isSelected ? .primary : .secondary)
                        
                        // Underline indicator
                        Rectangle()
                            .fill(isSelected ? Color.blue : Color.clear)
                            .frame(height: 3)
                            .cornerRadius(1.5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.cardBackground.opacity(0.5))
        )
    }
    
    // MARK: - Friends List Content
    
    private var friendsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendService.isLoading || rankingService.isLoading {
                    ProgressView("Loading friends...")
                        .padding(.top, 50)
                } else if friendService.friends.isEmpty {
                    emptyFriendsState
                        .padding(.top, 50)
                } else {
                    // View toggle (Ranked vs Alphabetical)
                    friendsViewToggle
                        .padding(.bottom, 8)
                    
                    // From Your Contacts section (if any friends are from contacts)
                    if !rankingService.friendsFromContacts.isEmpty {
                        fromContactsSection
                    }
                    
                    // Main friends list
                    if showRankedView && !rankingService.rankedFriends.isEmpty {
                        // Ranked friends view
                        rankedFriendsSection
                    } else {
                        // Original alphabetical view
                        ForEach(friendService.friends) { friend in
                            FriendCard(friend: friend) {
                                showingFriendProfile = friend
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .refreshable {
            // Pull to refresh rankings
            await rankingService.fetchRankedFriends(forceRefresh: true)
            await rankingService.fetchFriendsFromContacts()
            await friendService.fetchFriends()
            preloadFriendPhotos()
        }
    }
    
    // MARK: - Friends Count Header
    
    private var friendsViewToggle: some View {
        HStack {
            Text("\(friendService.friends.count) Friends")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding(.horizontal, Spacing.xxs)
    }
    
    // MARK: - From Your Contacts Section
    
    private var fromContactsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle.stack.fill")
                    .font(.ds_bodySmall)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("FROM YOUR CONTACTS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(rankingService.friendsFromContacts.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
            }
            .padding(.leading, 4)
            
            // Horizontal scroll of contact friends
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rankingService.friendsFromContacts) { contactFriend in
                        ContactFriendChip(
                            friend: contactFriend,
                            onTap: {
                                // Find the matching Friend object to show profile
                                if let friend = friendService.friends.first(where: { $0.friendId == contactFriend.friendId }) {
                                    showingFriendProfile = friend
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, Spacing.xxs)
            }
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Ranked Friends Section
    
    private var rankedFriendsSection: some View {
        let showFloatingHeads = rankingService.rankedFriends.count >= 3
        let mostEngaged = Array(rankingService.rankedFriends.prefix(3))
        let mostEngagedIds = Set(mostEngaged.map(\.friendId))
        
        // Newest added — skip anyone already on page 0, backfill from remaining
        let newestAdded: [Friend] = {
            let sorted = friendService.friends.sorted(by: { $0.friendsSince > $1.friendsSince })
            return Array(sorted.filter { !mostEngagedIds.contains($0.friendId) }.prefix(3))
        }()
        
        // Collect all IDs shown in floating heads (both pages)
        let floatingHeadIds: Set<UUID> = showFloatingHeads
            ? Set(mostEngaged.map(\.friendId) + newestAdded.map(\.friendId))
            : []
        
        // Filter out friends already shown in floating heads
        let remainingFriends = rankingService.rankedFriends.filter { !floatingHeadIds.contains($0.friendId) }
        
        return VStack(alignment: .leading, spacing: 12) {
            // Top Friends (ranked 1-3)
            if showFloatingHeads {
                topFriendsHighlight
                    .padding(.bottom, 8)
            }
            
            // Remaining friends (excluding floating heads)
            ForEach(remainingFriends) { rankedFriend in
                if let friend = friendService.friends.first(where: { $0.friendId == rankedFriend.friendId }) {
                    RankedFriendCard(
                        friend: friend,
                        rankedFriend: rankedFriend,
                        isFromContacts: rankingService.isFromContacts(friendId: friend.friendId)
                    ) {
                        showingFriendProfile = friend
                    }
                }
            }
        }
    }
    
    // MARK: - Top Friends (Top 3)
    
    private var topFriendsHighlight: some View {
        let mostEngaged = Array(rankingService.rankedFriends.prefix(3))
        let mostEngagedIds = Set(mostEngaged.map(\.friendId))
        let newestAdded: [Friend] = {
            let sorted = friendService.friends.sorted(by: { $0.friendsSince > $1.friendsSince })
            return Array(sorted.filter { !mostEngagedIds.contains($0.friendId) }.prefix(3))
        }()
        
        return VStack(alignment: .leading, spacing: 12) {
            // Swipeable top 3 friends
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                
                HStack(spacing: 0) {
                    // Page 0: Most Engaged
                    HStack(spacing: 12) {
                        ForEach(mostEngaged) { rankedFriend in
                            if let friend = friendService.friends.first(where: { $0.friendId == rankedFriend.friendId }) {
                                TopFriendCard(
                                    friend: friend,
                                    rankedFriend: rankedFriend
                                ) {
                                    showingFriendProfile = friend
                                }
                            }
                        }
                    }
                    .frame(width: cardWidth)
                    
                    // Page 1: Newest Added
                    HStack(spacing: 12) {
                        ForEach(Array(newestAdded.enumerated()), id: \.element.id) { index, friend in
                            TopFriendCard(
                                friend: friend,
                                rankedFriend: RankedFriend(
                                    friendId: friend.friendId,
                                    friendName: friend.friendName,
                                    friendUsername: friend.friendUsername,
                                    profilePhotoUrl: friend.profilePhotoUrl,
                                    fitnessGoal: friend.fitnessGoal,
                                    relationshipScore: 0,
                                    interactionCount: 0,
                                    workoutsShared: 0,
                                    workoutsCompleted: 0,
                                    challengesTogether: 0,
                                    lastInteraction: nil,
                                    friendshipStarted: friend.friendsSince,
                                    rank: index + 1
                                )
                            ) {
                                showingFriendProfile = friend
                            }
                        }
                    }
                    .frame(width: cardWidth)
                }
                .offset(x: -CGFloat(topFriendsPage) * cardWidth + friendSwipeDragOffset)
                .animation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1), value: topFriendsPage)
            }
            .frame(height: 90)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        friendSwipeDragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let velocity = value.predictedEndTranslation.width - value.translation.width
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)) {
                            friendSwipeDragOffset = 0
                            if (horizontalAmount < -30 || velocity < -100) && topFriendsPage == 0 {
                                topFriendsPage = 1
                            } else if (horizontalAmount > 30 || velocity > 100) && topFriendsPage == 1 {
                                topFriendsPage = 0
                            }
                        }
                        HapticManager.impact(.light)
                    }
            )
            
            // Page indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(topFriendsPage == 0 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
                Circle()
                    .fill(topFriendsPage == 1 ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Empty Friends State
    
    private var emptyFriendsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text("No Friends Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Search for friends by email to start\nsharing workouts and staying motivated!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                withAnimation { selectedTab = 2 }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("Find Friends")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.purple.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(25)
            }
        }
        .padding(30)
    }
    
    // MARK: - Requests Content
    
    private var requestsContent: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Loading indicator when refreshing
                if isRefreshingRequests {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Refreshing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                }
                
                // Incoming Requests Section
                if !friendService.pendingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.green)
                            Text("INCOMING REQUESTS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 4)
                        
                        ForEach(friendService.pendingRequests) { request in
                            FriendRequestCard(request: request)
                        }
                    }
                }
                
                // Sent Requests Section (Outgoing)
                if !friendService.sentRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.blue)
                            Text("SENT REQUESTS")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 4)
                        
                        ForEach(friendService.sentRequests) { request in
                            SentFriendRequestCard(request: request)
                        }
                    }
                }
                
                // Empty state - only show if both incoming and sent are empty AND not loading
                if friendService.pendingRequests.isEmpty && friendService.sentRequests.isEmpty && !isRefreshingRequests {
                    emptyRequestsState
                        .padding(.top, 50)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
        .refreshable {
            // Pull-to-refresh to force reload requests
            AppLogger.debug("👥 [FRIENDS] Pull-to-refresh on requests tab", category: .social)
            await friendService.fetchPendingRequests()
            await friendService.fetchSentRequests()
        }
        .task {
            // Fetch requests when tab is shown
            isRefreshingRequests = true
            await friendService.fetchPendingRequests()
            await friendService.fetchSentRequests()
            isRefreshingRequests = false
        }
    }
    
    private var emptyRequestsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Pending Requests")
                .font(.headline)
            
            Text("Friend requests you send or receive\nwill appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Search Content
    
    @State private var showingQROptions = false
    
    private var searchContent: some View {
        VStack(spacing: 12) {
            // Search bar with QR button inline
            HStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search by @username...", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.twitter)
                        .onSubmit { performSearch() }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(Color.cardBackground)
                .cornerRadius(CornerRadius.md)
                
                // QR Code button (replaces separate Scan QR / My Code buttons)
                Button(action: { showingQROptions = true }) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.ds_heading3)
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(CornerRadius.md)
                }
                .confirmationDialog("QR Code", isPresented: $showingQROptions) {
                    Button("Scan QR Code") { showingQRScanner = true }
                    Button("Share My QR Code") { showingMyQRCode = true }
                    Button("Cancel", role: .cancel) { }
                }
            }
            .padding(.horizontal, 20)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    if searchText.isEmpty {
                        contactSuggestionsSection
                    } else {
                        // Always show filtered contact suggestions first
                        let query = searchText.lowercased()
                        let filteredContacts = contactsService.suggestedFriends.filter { contact in
                            let name = (contact.name ?? "").lowercased()
                            let user = (contact.username ?? "").lowercased()
                            return name.contains(query) || user.contains(query)
                        }
                        
                        if !filteredContacts.isEmpty {
                            Section {
                                ForEach(filteredContacts) { contact in
                                    SuggestedFriendCard(friend: contact)
                                }
                            } header: {
                                Text("From Your Contacts")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        
                        let usernameResults = friendService.searchResults.filter { user in
                            !user.isFriend
                        }
                        
                        if isSearching {
                            ProgressView("Looking up username...")
                                .padding(.top, filteredContacts.isEmpty ? 30 : 12)
                        } else if !usernameResults.isEmpty {
                            Section {
                                ForEach(usernameResults) { user in
                                    UserSearchResultCard(user: user, onRespondToRequest: {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            selectedTab = 1
                                        }
                                    })
                                }
                            } header: {
                                Text("Username Match")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else if filteredContacts.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 50))
                                    .foregroundColor(.gray.opacity(0.5))
                                
                                Text("No one found")
                                    .font(.headline)
                                
                                Text("Try an exact @username")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 50)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .onChange(of: searchText) { newValue in
            if newValue.count >= 3 {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if searchText == newValue {
                        performSearch()
                    }
                }
            }
        }
    }
    
    /// Preload friend profile photos for fast display
    private func preloadFriendPhotos() {
        let friendsWithPhotos = friendService.friends.map { friend in
            (id: friend.friendId.uuidString, url: friend.profilePhotoUrl)
        }
        FriendPhotoCache.shared.preloadPhotos(for: friendsWithPhotos)
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        Task {
            await friendService.searchUsers(query: searchText)
            isSearching = false
        }
    }
    
    // MARK: - Contact Suggestions Section
    
    @ViewBuilder
    private var contactSuggestionsSection: some View {
        VStack(spacing: 20) {
            // Show contact permission prompt FIRST if not yet granted
            if contactsService.shouldShowPermissionPrompt {
                // Prominent permission prompt at the top
                contactPermissionPromptHero
                    .padding(.top, 20)
                
                // Then show search instruction below
                VStack(spacing: 8) {
                    HStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                        Text("or search by username")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 10)
            } else {
                // Show contact suggestions directly (no filler header)
                if contactsService.canAccessContacts {
                    if contactsService.isLoading {
                        ProgressView("Finding friends from contacts...")
                            .padding(.top, 20)
                    } else if !contactsService.suggestedFriends.isEmpty {
                        suggestedFriendsSection
                    } else if contactsService.hasCheckedContacts {
                        // Checked but no suggestions found
                        VStack(spacing: 8) {
                            Image(systemName: "person.2.slash")
                                .font(.ds_heading1)
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("No contacts on Fit33 yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Invite your friends to join!")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.top, 20)
                    }
                } else if contactsService.permissionDenied {
                    contactPermissionDeniedView
                }
            }
        }
    }
    
    // MARK: - Hero Contact Permission Prompt (shown first time)
    
    private var contactPermissionPromptHero: some View {
        VStack(spacing: 16) {
            // Icon with animation hint
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.15), .teal.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Find Friends from Contacts")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("See which of your contacts are already on Fit33 and add them as friends instantly!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            Button(action: {
                HapticManager.impact(.medium)
                Task {
                    await contactsService.requestAccess()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.ds_heading3)
                    Text("Connect Contacts")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.lg)
                .shadow(color: .green.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 30)
            .padding(.top, 8)
            
            // Privacy note
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption2)
                Text("Your contacts stay private and are never shared")
                    .font(.caption2)
            }
            .foregroundColor(.secondary.opacity(0.7))
            .padding(.top, 4)
        }
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.md)
        .sleekCard(cornerRadius: 24, accentColor: .green)
        .padding(.horizontal, Spacing.md)
    }
    
    private var suggestedFriendsSection: some View {
        let existingFriendIds = Set(friendService.friends.map { $0.friendId })
        let filteredSuggestions = contactsService.suggestedFriends.filter { suggestion in
            !existingFriendIds.contains(suggestion.userId) &&
            !suggestion.isFriend
        }
        
        return VStack(alignment: .leading, spacing: 12) {
            if !filteredSuggestions.isEmpty {
                // Divider with label
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                    Text("From Your Contacts")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.top, 10)
                
                // Suggested friends list (excluding existing friends)
                ForEach(filteredSuggestions) { friend in
                    SuggestedFriendCard(
                        friend: friend,
                        onRespondToRequest: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTab = 1
                            }
                        },
                        onActionCompleted: {
                            // Refresh suggestions and sent requests after sending
                            Task {
                                await contactsService.refreshSuggestions()
                                await friendService.fetchSentRequests()
                            }
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Sync Contacts Button (Permission Denied State)
    /// Prominent button shown when user previously denied contacts - allows re-enabling
    
    private var contactPermissionDeniedView: some View {
        VStack(spacing: 16) {
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                Text("Find Friends Faster")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, 20)
            
            // Sync Contacts Card
            VStack(spacing: 14) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.15), .teal.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.ds_heading2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .teal],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(spacing: 4) {
                    Text("Sync Contacts")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("Find friends already on Fit33")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Enable Contacts Button
                Button(action: {
                    HapticManager.impact(.medium)
                    // Open Settings to Fit33's contact permissions
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "gear.badge")
                            .font(.ds_labelLarge)
                        Text("Enable in Settings")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.md)
                }
                .padding(.horizontal, Spacing.md)
                
                // Privacy note
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.caption2)
                    Text("Your contacts are never shared")
                        .font(.caption2)
                }
                .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.vertical, 20)
            .padding(.horizontal, Spacing.md)
            .sleekCard(cornerRadius: 20, accentColor: .green)
            .padding(.horizontal, Spacing.md)
        }
        .padding(.top, 10)
    }
}

// MARK: - Suggested Friend Card

struct SuggestedFriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    let friend: SuggestedFriend
    var onRespondToRequest: (() -> Void)?
    var onActionCompleted: (() -> Void)?
    
    @State private var isProcessing = false
    @State private var requestSent = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            avatarView
            
            VStack(alignment: .leading, spacing: 4) {
                // Name — bold white, primary
                if let name = friend.name, !name.isEmpty {
                    Text(name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                
                // Username — small grey
                if let username = friend.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // "In your contacts" label — blue
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.ds_caption)
                    Text("In your contacts")
                        .font(.caption2)
                }
                .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Action button
            actionButton
        }
        .padding(Spacing.md)
        .background(PremiumCardBackground(accentColor: .blue))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .blue.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
    }
    
    private var avatarView: some View {
        CachedFriendPhoto(
            friendId: friend.userId.uuidString,
            photoUrl: friend.profilePhotoUrl,
            name: friend.name ?? friend.username ?? "?",
            size: 50,
            showGradientRing: true,
            gradientColors: [.blue, .cyan]
        )
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            Text(friend.initials)
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if friend.isFriend {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ds_bodySmall)
                Text("Friends")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
        } else if friend.hasOutgoingRequest || requestSent {
            Text("Pending")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .stroke(Color.orange, lineWidth: 1)
                )
        } else if friend.hasIncomingRequest {
            Button(action: { onRespondToRequest?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.ds_bodySmall)
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
            }
        } else {
            Button(action: { 
                AppLogger.debug("🔴 [ADD BUTTON] Tapped! Sending request to \(friend.displayName)", category: .social)
                sendRequest()
            }) {
                HStack(spacing: 4) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.ds_bodySmall)
                    }
                    Text("Add")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(minWidth: 60, minHeight: 32)
                .background(
                    Capsule()
                        .fill(Color.blue)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }
    
    private func sendRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            let success = await friendService.sendFriendRequest(toUserId: friend.userId)
            await MainActor.run {
                if success {
                    requestSent = true
                    HapticManager.notification(.success)
                    onActionCompleted?()
                } else {
                    HapticManager.notification(.error)
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Premium Card Background (matches exercise cards)

struct PremiumCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var accentColor: Color = .blue
    
    var body: some View {
        ZStack {
            // Bottom shadow layer (deepest) - color glow
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(accentColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                .offset(y: 5)
                .blur(radius: 3)
            
            // Middle shadow layer
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03))
                .offset(y: 3)
            
            // Main card background with gradient
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.16), Color(white: 0.11)]
                            : [Color.white, Color.white.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Inner highlight (top edge glow)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                            : [Color.white, Color.white.opacity(0.4), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            
            // Colored accent border
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accentColor.opacity(colorScheme == .dark ? 0.35 : 0.25), accentColor.opacity(colorScheme == .dark ? 0.2 : 0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
}

// MARK: - Friend Card

struct FriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: Friend
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar with cached profile photo
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 50,
                    showGradientRing: false,
                    gradientColors: [.blue, .purple.opacity(0.8)]
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    // Username (primary)
                    if let username = friend.friendUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    // Name (secondary)
                    if let name = friend.friendName, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(Spacing.md)
            .background(PremiumCardBackground(accentColor: .blue))
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .blue.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Friend Request Card

struct FriendRequestCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    let request: FriendRequest
    
    @State private var isProcessing = false
    
    private var initials: String {
        guard let name = request.fromUserName, !name.isEmpty else { return "?" }
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with cached profile photo
            CachedFriendPhoto(
                friendId: request.fromUserId.uuidString,
                photoUrl: request.profilePhotoUrl,
                name: request.fromUserName ?? request.fromUserUsername ?? "User",
                size: 50,
                showGradientRing: false,
                gradientColors: [.blue, .cyan]
            )
            
            VStack(alignment: .leading, spacing: 4) {
                // Name
                Text(request.displayName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Username
                if let username = request.fromUserUsername {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                // Time ago
                Text(timeAgoString(from: request.createdAt))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Accept/Decline buttons
            HStack(spacing: 8) {
                Button(action: { declineRequest() }) {
                    Image(systemName: "xmark")
                        .font(.ds_bodySmall).fontWeight(.bold)
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
                .disabled(isProcessing)
                
                Button(action: { acceptRequest() }) {
                    Image(systemName: "checkmark")
                        .font(.ds_bodySmall).fontWeight(.bold)
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.green.opacity(0.15)))
                }
                .disabled(isProcessing)
            }
        }
        .padding(Spacing.md)
        .background(PremiumCardBackground(accentColor: .green))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .green.opacity(colorScheme == .dark ? 0.15 : 0.08), radius: 16, x: 0, y: 8)
    }
    
    // Keeping for backwards compatibility with initials property
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            Text(initials)
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
    }
    
    private func acceptRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            let success = await friendService.acceptFriendRequest(requestId: request.requestId)
            if success {
                HapticManager.notification(.success)
            }
            isProcessing = false
        }
    }
    
    private func declineRequest() {
        isProcessing = true
        HapticManager.impact(.light)
        Task {
            _ = await friendService.declineFriendRequest(requestId: request.requestId)
            isProcessing = false
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Sent Friend Request Card (Outgoing)

struct SentFriendRequestCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    let request: SentFriendRequest
    
    @State private var isProcessing = false
    @State private var showCancelConfirmation = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with cached profile photo
            CachedFriendPhoto(
                friendId: request.toUserId.uuidString,
                photoUrl: request.profilePhotoUrl,
                name: request.toUserName ?? request.toUserUsername ?? "User",
                size: 50,
                showGradientRing: false,
                gradientColors: [.blue, .cyan]
            )
            
            VStack(alignment: .leading, spacing: 4) {
                // Username first (primary)
                if let username = request.toUserUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                // Name (secondary)
                if let name = request.toUserName, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                // Time ago + pending status
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Pending • \(timeAgoString(from: request.createdAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Cancel/Unsend button
            Button(action: { showCancelConfirmation = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle")
                        .font(.ds_bodySmall).fontWeight(.medium)
                    Text("Unsend")
                        .font(.ds_bodySmall)
                }
                .foregroundColor(.red)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.12))
                )
            }
            .disabled(isProcessing)
            .opacity(isProcessing ? 0.5 : 1)
        }
        .padding(Spacing.md)
        .background(PremiumCardBackground(accentColor: .orange))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .orange.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
        .confirmationDialog(
            "Cancel Friend Request?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel Request", role: .destructive) {
                cancelRequest()
            }
            Button("Keep Request", role: .cancel) {}
        } message: {
            Text("This will unsend your friend request to \(request.displayName).")
        }
    }
    
    private func cancelRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            let success = await friendService.cancelSentRequest(requestId: request.requestId)
            if success {
                HapticManager.notification(.success)
            }
            isProcessing = false
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - User Search Result Card

struct UserSearchResultCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    let user: UserSearchResult
    var onRespondToRequest: (() -> Void)?  // Called when they sent us a request and we tap "Respond"
    
    @State private var isProcessing = false
    @State private var requestSent = false
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar with cached profile photo
            CachedFriendPhoto(
                friendId: user.userId.uuidString,
                photoUrl: user.profilePhotoUrl,
                name: user.name ?? user.username ?? "?",
                size: 50,
                showGradientRing: false,
                gradientColors: [.indigo, .purple]
            )
            
            VStack(alignment: .leading, spacing: 4) {
                // Username (primary)
                if let username = user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                // Name (secondary)
                if let name = user.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
            }
            
            Spacer()
            
            // Action button based on status
            actionButton
        }
        .padding(Spacing.md)
        .background(PremiumCardBackground(accentColor: .purple))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .purple.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.indigo, Color.purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            Text(user.initials)
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if user.isFriend {
            // Already friends
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ds_bodySmall)
                Text("Friends")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
        } else if user.hasOutgoingRequest == true || requestSent {
            // I sent THEM a request - waiting for their response
            Text("Pending")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.orange)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .stroke(Color.orange, lineWidth: 1)
                )
        } else if user.hasIncomingRequest == true {
            // THEY sent ME a request - I need to respond
            Button(action: { onRespondToRequest?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.ds_bodySmall)
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.green, Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
            }
        } else {
            // No relationship - can add as friend
            Button(action: { 
                AppLogger.debug("🔴 [ADD BUTTON] Tapped! Sending request to \(user.username ?? "unknown")", category: .social)
                sendRequest()
            }) {
                HStack(spacing: 4) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.ds_bodySmall)
                        Text("Add")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(minWidth: 60, minHeight: 32)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: isProcessing ? [Color.gray.opacity(0.5), Color.gray] : [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
        }
    }
    
    private func sendRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            AppLogger.debug("📤 Sending friend request to user: \(user.userId)", category: .social)
            let success = await friendService.sendFriendRequest(toUserId: user.userId)
            await MainActor.run {
                if success {
                    requestSent = true
                    HapticManager.notification(.success)
                    AppLogger.info("✅ Friend request sent successfully!", category: .social)
                } else {
                    HapticManager.notification(.error)
                    AppLogger.error("❌ Failed to send friend request", category: .social)
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Contact Friend Chip (Horizontal scroll item)

struct ContactFriendChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: ContactFriend
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                // Avatar (cached)
                ZStack {
                    CachedFriendPhoto(
                        friendId: friend.friendId.uuidString,
                        photoUrl: friend.profilePhotoUrl,
                        name: friend.friendName ?? friend.friendUsername ?? "?",
                        size: 56,
                        showGradientRing: false,
                        gradientColors: [.green, .teal]
                    )
                    
                    // Contact badge
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.ds_caption)
                        .foregroundColor(.white)
                        .padding(Spacing.xxs)
                        .background(Circle().fill(Color.green))
                        .offset(x: 20, y: 20)
                }
                .frame(width: 56, height: 56)
                
                // Name
                Text(friend.displayName.components(separatedBy: " ").first ?? friend.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }
    
    private var defaultContactAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
            
            Text(friend.initials)
                .font(.ds_heading3)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Ranked Friend Card (Main list item with interaction stats)

struct RankedFriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: Friend
    let rankedFriend: RankedFriend
    let isFromContacts: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar with cached profile photo
                ZStack(alignment: .bottomTrailing) {
                    CachedFriendPhoto(
                        friendId: friend.friendId.uuidString,
                        photoUrl: friend.profilePhotoUrl,
                        name: friend.friendName ?? friend.friendUsername ?? "Friend",
                        size: 50,
                        showGradientRing: rankedFriend.rank <= 3,
                        gradientColors: rankGradientColors
                    )
                    
                    // Contact badge if from contacts
                    if isFromContacts {
                        Image(systemName: "person.crop.rectangle.stack.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Circle().fill(Color.green))
                            .offset(x: 2, y: 2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    // Username (primary)
                    if let username = friend.friendUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    
                    // Name (secondary)
                    if let name = friend.friendName, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(Spacing.md)
            .background(PremiumCardBackground(accentColor: rankedFriend.relationshipTier.color))
        }
        .buttonStyle(PlainButtonStyle())
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: rankedFriend.relationshipTier.color.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
    }
    
    private var rankGradientColors: [Color] {
        [.blue, .cyan]
    }
}

// MARK: - Top Friend Card

struct TopFriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: Friend
    let rankedFriend: RankedFriend
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Avatar
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 60,
                    showGradientRing: true,
                    gradientColors: [.blue, .cyan]
                )
                
                // Name
                Text(firstName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
    
    private var firstName: String {
        let name = friend.friendName ?? friend.friendUsername ?? "Friend"
        return name.components(separatedBy: " ").first ?? name
    }
}

#Preview {
    NavigationStack {
        FriendsListView()
    }
}
