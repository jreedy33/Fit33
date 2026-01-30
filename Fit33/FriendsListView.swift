import SwiftUI

// MARK: - Friends List View
/// Main hub for managing friends - view friends, requests, and search for new friends

struct FriendsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    // Use StateObject wrapper to prevent unnecessary re-renders during navigation
    @StateObject private var friendService = FriendService.shared
    
    // Initial tab can be set via deep link (0: Friends, 1: Requests, 2: Search)
    var initialTab: Int = 0
    
    @State private var selectedTab = 0 // 0: Friends, 1: Requests, 2: Search
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showingFriendProfile: Friend?
    @State private var showingReceivedWorkouts = false
    @State private var hasLoadedInitialData = false // Prevent navigation reset from data reloading
    
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
            
            // Only load data on first appear to prevent navigation disruption
            // Subsequent appears (e.g., returning from detail view) skip the load
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
            LazyVStack(spacing: 16) {
                // Incoming Requests
                if !friendService.pendingRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("INCOMING REQUESTS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        ForEach(friendService.pendingRequests) { request in
                            FriendRequestCard(request: request)
                        }
                    }
                }
                
                // Empty state
                if friendService.pendingRequests.isEmpty {
                    emptyRequestsState
                        .padding(.top, 50)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 100)
        }
    }
    
    private var emptyRequestsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.slash")
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))
            
            Text("No Pending Requests")
                .font(.headline)
            
            Text("Friend requests you receive\nwill appear here")
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
                        VStack(spacing: 12) {
                            Image(systemName: "at")
                                .font(.system(size: 50))
                                .foregroundColor(.blue.opacity(0.5))
                            
                            Text("Find Friends")
                                .font(.headline)
                            
                            Text("Search by username to find\nand add friends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 50)
                    } else {
                        ForEach(friendService.searchResults) { user in
                            UserSearchResultCard(user: user)
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
}

// MARK: - Friend Card

struct FriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: Friend
    let onTap: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
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
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Friend Request Card

struct FriendRequestCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var friendService = FriendService.shared
    let request: FriendRequest
    
    @State private var isProcessing = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
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

// MARK: - User Search Result Card

struct UserSearchResultCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var friendService = FriendService.shared
    let user: UserSearchResult
    
    @State private var isProcessing = false
    @State private var requestSent = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
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
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
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
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Friends")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
        } else if user.hasPendingRequest || requestSent {
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
        } else {
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
