import SwiftUI

// MARK: - Friends List View
/// Main hub for managing friends - view friends, requests, and search for new friends

struct FriendsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    // Use ObservedObject for singletons to observe without owning lifecycle
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var contactsService = ContactsService.shared
    
    // Initial tab can be set via deep link (0: Friends, 1: Requests, 2: Search)
    var initialTab: Int = 0
    
    @State private var selectedTab = 0 // 0: Friends, 1: Requests, 2: Search
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingFriendProfile: Friend?
    @State private var showingReceivedWorkouts = false
    @State private var hasLoadedInitialData = false // Prevent navigation reset from data reloading
    @State private var isRefreshingRequests = false // For pull-to-refresh on requests tab
    
    // Adaptive colors
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            AdaptiveGradient.stats(for: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Selector
                tabSelector
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                
                // Content based on selected tab
                TabView(selection: $selectedTab) {
                    friendsListContent
                        .tag(0)
                    
                    requestsContent
                        .tag(1)
                    
                    searchContent
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                        
                        if friendService.unreadWorkoutCount > 0 {
                            Text("\(friendService.unreadWorkoutCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Circle().fill(Color.red))
                                .offset(x: 8, y: -8)
                        }
                    }
                }
            }
        }
        .sheet(item: $showingFriendProfile) { friend in
            NavigationView {
                FriendProfileView(friend: friend)
            }
        }
        .sheet(isPresented: $showingReceivedWorkouts) {
            NavigationView {
                ReceivedWorkoutsView()
            }
        }
        .onAppear {
            // Set initial tab from deep link if specified
            if initialTab != 0 {
                selectedTab = initialTab
            }
            
            // ALWAYS refresh pending requests when coming from a deep link (notification tap)
            // This ensures the request is fetched and displayed even if there's a race condition
            if initialTab == 1 {
                print("👥 [FRIENDS] Opened from notification - forcing refresh of pending requests")
                Task {
                    await friendService.fetchPendingRequests()
                    await friendService.fetchSentRequests()
                }
            }
            
            // Only load ALL data on first appear to prevent navigation disruption
            // Subsequent appears (e.g., returning from detail view) skip the full load
            guard !hasLoadedInitialData else { return }
            hasLoadedInitialData = true
            
            Task {
                await friendService.loadAllData()
                // Preload friend photos for fast display
                preloadFriendPhotos()
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            // Refresh friends when switching to Friends tab (tab 0)
            // This ensures new friends appear immediately after accepting a request
            if newTab == 0 {
                Task {
                    await friendService.fetchFriends()
                    preloadFriendPhotos()
                }
            }
            // Load contact suggestions when switching to Search tab (tab 2)
            if newTab == 2 && contactsService.canAccessContacts && !contactsService.hasCheckedContacts {
                Task {
                    await contactsService.fetchContactsAndFindFriends()
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
                                    .font(.system(size: 10, weight: .bold))
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
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground.opacity(0.5))
        )
    }
    
    // MARK: - Friends List Content
    
    private var friendsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendService.isLoading {
                    ProgressView("Loading friends...")
                        .padding(.top, 50)
                } else if friendService.friends.isEmpty {
                    emptyFriendsState
                        .padding(.top, 50)
                } else {
                    ForEach(friendService.friends) { friend in
                        FriendCard(friend: friend) {
                            showingFriendProfile = friend
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
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
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
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
            print("👥 [FRIENDS] Pull-to-refresh on requests tab")
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
    
    private var searchContent: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search by @username...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.twitter) // Good for @mentions
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 20)
            
            // Results
            ScrollView {
                LazyVStack(spacing: 12) {
                    if isSearching {
                        ProgressView("Searching...")
                            .padding(.top, 30)
                    } else if friendService.searchResults.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("No users found")
                                .font(.headline)
                            
                            Text("Try a different username")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 50)
                    } else if searchText.isEmpty {
                        // Show contact suggestions or permission prompt
                        contactSuggestionsSection
                    } else {
                        ForEach(friendService.searchResults) { user in
                            UserSearchResultCard(user: user, onRespondToRequest: {
                                // Switch to Requests tab when user taps "Respond"
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedTab = 1
                                }
                            })
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .onChange(of: searchText) { newValue in
            // Debounce search
            if newValue.count >= 3 {
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                    if searchText == newValue { // Still the same
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
                // Normal flow - show search header first
                VStack(spacing: 8) {
                    Image(systemName: "at")
                        .font(.system(size: 40))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("Find Friends")
                        .font(.headline)
                    
                    Text("Search by username above")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 30)
                
                // Then show contact suggestions or states
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
                                .font(.system(size: 30))
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
                        .font(.system(size: 18))
                    Text("Connect Contacts")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.green, .teal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
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
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(cardBackground)
                .shadow(color: .green.opacity(0.12), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [.green.opacity(0.4), .teal.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .padding(.horizontal, 16)
    }
    
    private var suggestedFriendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            
            // Suggested friends list
            ForEach(contactsService.suggestedFriends) { friend in
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
    
    private var contactPermissionDeniedView: some View {
        VStack(spacing: 12) {
            HStack {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
                Text("or")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 30))
                    .foregroundColor(.secondary.opacity(0.5))
                
                Text("Contact Access Disabled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Button(action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Open Settings")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .padding(.top, 10)
        }
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
                // Username
                if let username = friend.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                // Name
                if let name = friend.name, !name.isEmpty {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                
                // "From contacts" label
                HStack(spacing: 4) {
                    Image(systemName: "person.crop.rectangle.stack")
                        .font(.system(size: 10))
                    Text("In your contacts")
                        .font(.caption2)
                }
                .foregroundColor(.green)
            }
            
            Spacer()
            
            // Action button
            actionButton
        }
        .padding(16)
        .background(PremiumCardBackground(accentColor: .green))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 10, x: 0, y: 5)
        .shadow(color: .green.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 16, x: 0, y: 8)
    }
    
    private var avatarView: some View {
        Group {
            if let photoUrl = friend.profilePhotoUrl, let url = URL(string: photoUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    case .failure(_), .empty:
                        defaultAvatar
                    @unknown default:
                        defaultAvatar
                    }
                }
            } else {
                defaultAvatar
            }
        }
        .frame(width: 50, height: 50)
    }
    
    private var defaultAvatar: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.green, Color.teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            Text(friend.initials)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if friend.isFriend {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.orange, lineWidth: 1)
                )
        } else if friend.hasIncomingRequest {
            Button(action: { onRespondToRequest?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12))
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            Button(action: { sendRequest() }) {
                HStack(spacing: 4) {
                    if isProcessing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                    }
                    Text("Add")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
            }
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(16)
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
                gradientColors: [.green, .cyan]
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
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.red.opacity(0.15)))
                }
                .disabled(isProcessing)
                
                Button(action: { acceptRequest() }) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.green)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.green.opacity(0.15)))
                }
                .disabled(isProcessing)
            }
        }
        .padding(16)
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
                        colors: [Color.green, Color.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
            
            Text(initials)
                .font(.system(size: 18, weight: .bold))
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
                        .font(.system(size: 14, weight: .medium))
                    Text("Unsend")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.12))
                )
            }
            .disabled(isProcessing)
            .opacity(isProcessing ? 0.5 : 1)
        }
        .padding(16)
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
            // Avatar with profile photo
            ZStack {
                if let photoUrl = user.profilePhotoUrl, let url = URL(string: photoUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(Circle())
                        case .failure(_), .empty:
                            defaultAvatar
                        @unknown default:
                            defaultAvatar
                        }
                    }
                } else {
                    defaultAvatar
                }
            }
            .frame(width: 50, height: 50)
            
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
        .padding(16)
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
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    @ViewBuilder
    private var actionButton: some View {
        if user.isFriend {
            // Already friends
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.orange, lineWidth: 1)
                )
        } else if user.hasIncomingRequest == true {
            // THEY sent ME a request - I need to respond
            Button(action: { onRespondToRequest?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 12))
                    Text("Respond")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
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
            Button(action: { sendRequest() }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12))
                    Text("Add")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.blue, Color.purple.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                )
            }
            .disabled(isProcessing)
        }
    }
    
    private func sendRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            print("📤 Sending friend request to user: \(user.userId)")
            let success = await friendService.sendFriendRequest(toUserId: user.userId)
            await MainActor.run {
                if success {
                    requestSent = true
                    HapticManager.notification(.success)
                    print("✅ Friend request sent successfully!")
                } else {
                    HapticManager.notification(.error)
                    print("❌ Failed to send friend request")
                }
                isProcessing = false
            }
        }
    }
}

#Preview {
    NavigationView {
        FriendsListView()
    }
}
