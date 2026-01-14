import SwiftUI

// MARK: - Friends List View
/// Main hub for managing friends - view friends, requests, and search for new friends

struct FriendsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared
    
    @State private var selectedTab = 0 // 0: Friends, 1: Requests, 2: Search
    @State private var searchText = ""
    @State private var searchResults: [UserSearchResultDTO] = []
    @State private var isSearching = false
    @State private var showingFriendProfile: FriendDTO?
    @State private var showingReceivedWorkouts = false
    
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
            Task {
                await friendService.loadAllData()
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
                            FriendRequestCard(request: request, isIncoming: true)
                        }
                    }
                }
                
                // Sent Requests
                if !friendService.sentRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SENT REQUESTS")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                        
                        ForEach(friendService.sentRequests) { request in
                            FriendRequestCard(request: request, isIncoming: false)
                        }
                    }
                }
                
                // Empty state
                if friendService.pendingRequests.isEmpty && friendService.sentRequests.isEmpty {
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
            
            Text("Friend requests you send and receive\nwill appear here")
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
                
                TextField("Search by email...", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = []
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
                    } else if searchResults.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 50))
                                .foregroundColor(.gray.opacity(0.5))
                            
                            Text("No users found")
                                .font(.headline)
                            
                            Text("Try a different email address")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 50)
                    } else if searchText.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "envelope.badge.person.crop")
                                .font(.system(size: 50))
                                .foregroundColor(.blue.opacity(0.5))
                            
                            Text("Find Friends")
                                .font(.headline)
                            
                            Text("Enter an email address to find\nand add friends")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 50)
                    } else {
                        ForEach(searchResults) { user in
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
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        Task {
            searchResults = await friendService.searchUsers(email: searchText)
            isSearching = false
        }
    }
}

// MARK: - Friend Card

struct FriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: FriendDTO
    let onTap: () -> Void
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Text(friend.initials)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(friend.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(friend.email)
                        .font(.caption)
                        .foregroundColor(.secondary)
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
    let request: FriendRequestDTO
    let isIncoming: Bool
    
    @State private var isProcessing = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isIncoming ? [Color.green, Color.cyan] : [Color.orange, Color.yellow],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)
                
                Text(request.initials)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(request.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(request.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(timeAgoString(from: request.requestedAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isIncoming {
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
            } else {
                // Cancel button
                Button(action: { cancelRequest() }) {
                    Text("Cancel")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .stroke(Color.orange, lineWidth: 1)
                        )
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
                .stroke(isIncoming ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func acceptRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            do {
                try await friendService.acceptFriendRequest(requestId: request.id)
                HapticManager.notificationOccurred(.success)
            } catch {
                print("❌ Error accepting request: \(error)")
            }
            isProcessing = false
        }
    }
    
    private func declineRequest() {
        isProcessing = true
        HapticManager.impact(.light)
        Task {
            do {
                try await friendService.declineFriendRequest(requestId: request.id)
            } catch {
                print("❌ Error declining request: \(error)")
            }
            isProcessing = false
        }
    }
    
    private func cancelRequest() {
        isProcessing = true
        HapticManager.impact(.light)
        Task {
            do {
                try await friendService.cancelFriendRequest(requestId: request.id)
            } catch {
                print("❌ Error cancelling request: \(error)")
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
    @StateObject private var friendService = FriendService.shared
    let user: UserSearchResultDTO
    
    @State private var isProcessing = false
    @State private var localStatus: FriendshipStatus
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    init(user: UserSearchResultDTO) {
        self.user = user
        self._localStatus = State(initialValue: user.friendshipStatus)
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Avatar
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
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    
    @ViewBuilder
    private var actionButton: some View {
        switch localStatus {
        case .none:
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
            
        case .requestSent:
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
            
        case .requestReceived:
            Text("Accept?")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .stroke(Color.green, lineWidth: 1)
                )
            
        case .friends:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Friends")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.green)
            
        case .blocked:
            Text("Blocked")
                .font(.caption)
                .foregroundColor(.gray)
        }
    }
    
    private func sendRequest() {
        isProcessing = true
        HapticManager.impact(.medium)
        Task {
            do {
                try await friendService.sendFriendRequest(to: user.id)
                localStatus = .requestSent
                HapticManager.notificationOccurred(.success)
            } catch {
                print("❌ Error sending request: \(error)")
            }
            isProcessing = false
        }
    }
}

#Preview {
    NavigationView {
        FriendsListView()
    }
}
