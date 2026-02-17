//
//  ChallengeFlowStartView.swift
//  Fit33
//
//  Challenge creation flow matching auto-gen workout style
//  Tab bar stays visible, cards rotate through inside container
//

import SwiftUI

struct ChallengeFlowStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var contactsService = ContactsService.shared
    
    enum FlowStep {
        case contactSync       // Shown first when user has no friends
        case friendSelection
        case groupOrSeparate   // NEW: choose group challenge vs separate challenges
        case modeSelection
        case activityType
        case challengeOptions
        case duration
        case review
    }
    
    @State private var currentStep: FlowStep = .friendSelection
    @State private var selectedFriend: Friend? // Legacy single-select (still used for 1 friend)
    @State private var selectedFriends: [Friend] = [] // Multi-select (up to 2)
    @State private var isGroupChallenge: Bool = true // true = one group, false = separate 1v1s
    @State private var selectedMode: ChallengeMode?
    @State private var selectedActivity: ChallengeActivityType?
    @State private var selectedOption: ChallengeOption?
    @State private var customTarget: Int = 10000
    @State private var hydrationUnit: HydrationUnit = .ml
    @State private var selectedDuration: Int = 7
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var isCustomDuration = false
    @State private var customDurationText = ""
    @FocusState private var durationFieldFocused: Bool
    @State private var searchText = ""
    @State private var topFriendsPage = 0 // 0: Most engaged, 1: Newest added
    @State private var friendSwipeDragOffset: CGFloat = 0
    @State private var loadingFriendRequests: Set<UUID> = []
    @State private var sentFriendRequests: Set<UUID> = []
    @State private var showingQRScanner = false
    @State private var showCommunityHub = false
    
    private var filteredFriends: [Friend] {
        if searchText.isEmpty {
            return friendService.friends
        }
        return friendService.friends.filter { friend in
            let name = friend.friendName ?? ""
            let username = friend.friendUsername ?? ""
            return name.localizedCaseInsensitiveContains(searchText) ||
                   username.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredSuggestedContacts: [SuggestedFriend] {
        guard !searchText.isEmpty else {
            return contactsService.suggestedFriends
        }
        
        let searchLower = searchText.lowercased()
        return contactsService.suggestedFriends.filter { friend in
            let name = (friend.name ?? "").lowercased()
            let username = (friend.username ?? "").lowercased()
            return name.contains(searchLower) || username.contains(searchLower)
        }
    }
    
    private var successAlertTitle: String {
        if selectedFriends.count > 1 && !isGroupChallenge {
            return "Challenges Sent! 🎯"
        }
        return "Challenge Sent! 🎯"
    }
    
    // MARK: - Pinned Invite Header
    private var inviteHeader: some View {
        VStack(spacing: 12) {
            Text("Invite Friends to Challenge")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Add them as friends first, then you can create challenges together!")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            
            // Search bar with QR scanner
            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 16))
                    
                    TextField("Search", text: $searchText)
                        .font(.body)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                
                Button(action: {
                    HapticManager.impact(.medium)
                    showingQRScanner = true
                }) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
    
    private var mainContent: some View {
        ZStack {
            // Blue orbs background
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator at top (hidden in invite mode)
                if !isInviteMode {
                    progressHeader
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                }
                
                // Pinned header (invite mode only)
                if isInviteMode && currentStep == .friendSelection {
                    inviteHeader
                        .padding(.horizontal, 20)
                }
                
                // Main content (card rotates through)
                ScrollView {
                    VStack(spacing: 24) {
                        switch currentStep {
                        case .contactSync:
                            contactSyncCard
                        case .friendSelection:
                            friendSelectionCard
                        case .groupOrSeparate:
                            groupOrSeparateCard
                        case .modeSelection:
                            modeSelectionCard
                        case .activityType:
                            activityTypeCard
                        case .challengeOptions:
                            challengeOptionsCard
                        case .duration:
                            durationCard
                        case .review:
                            reviewCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .scrollIndicators(.hidden)
                
                Spacer(minLength: 0)
                
                // Bottom button container
                navigationBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }
    
    private var successAlertMessage: String {
        var names: [String] = []
        for friend in selectedFriends {
            if let name = friend.friendName {
                let firstName = name.components(separatedBy: " ").first ?? name
                names.append(firstName)
            } else if let username = friend.friendUsername {
                names.append(username)
            } else {
                names.append("Friend")
            }
        }
        
        let friendCount = selectedFriends.count
        let nameList = names.joined(separator: " & ")
        
        if friendCount > 1 && isGroupChallenge {
            return "\(nameList) will receive a notification to join the group challenge!"
        } else if friendCount > 1 {
            return "\(nameList) will each receive a challenge notification!"
        } else {
            let firstName = names.first ?? "Your friend"
            return "\(firstName) will receive a notification to accept your challenge!"
        }
    }
    
    private var toolbarIcon: String {
        (currentStep == .friendSelection || currentStep == .contactSync) ? "xmark" : "chevron.left"
    }
    
    private func handleToolbarTap() {
        if currentStep == .friendSelection || currentStep == .contactSync {
            dismiss()
        } else {
            goBack()
        }
    }
    
    private var isInviteMode: Bool {
        // Invite mode when user has no friends AND either:
        // - has suggested contacts to show, OR
        // - has contacts access (contacts are loading/will load)
        // This prevents a flash of "Who do you want to challenge?" while contacts load
        friendService.friends.isEmpty && (contactsService.canAccessContacts || !contactsService.suggestedFriends.isEmpty)
    }
    
    var body: some View {
        mainContent
            .navigationTitle(isInviteMode ? "" : "Create Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: handleToolbarTap) {
                        Image(systemName: toolbarIcon)
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
            }
            .alert(successAlertTitle, isPresented: $showingSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text(successAlertMessage)
            }
            .alert("Failed to Send Challenge", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text("There was an issue sending your challenge. Please try again.")
            }
            .sheet(isPresented: $showingQRScanner) {
                QRCodeScannerView()
            }
            .onAppear {
            print("🏆 [CHALLENGE FLOW] View appeared")
            print("   └─ friends.count: \(friendService.friends.count)")
            print("   └─ suggestedFriends.count: \(contactsService.suggestedFriends.count)")
            print("   └─ hasCheckedContacts: \(contactsService.hasCheckedContacts)")
            print("   └─ canAccessContacts: \(contactsService.canAccessContacts)")
            
            // If user has friends OR has suggested friends from contacts → go to friend selection
            // Only show contact sync if no friends AND no suggested friends AND hasn't synced
            if friendService.friends.isEmpty && contactsService.suggestedFriends.isEmpty && !contactsService.canAccessContacts {
                currentStep = .contactSync
            } else {
                currentStep = .friendSelection
                
                // If contacts were already synced but suggestedFriends is empty (app restart), re-fetch
                if contactsService.canAccessContacts && contactsService.suggestedFriends.isEmpty {
                    Task {
                        await contactsService.fetchContactsAndFindFriends()
                    }
                }
            }
            
            // Always refresh friends list
            Task {
                await friendService.fetchFriends()
            }
        }
        .onChange(of: customTarget) { _, newValue in
            // Keep selectedOption in sync when user adjusts the custom stepper
            if let activity = selectedActivity, selectedOption?.isCustom == true {
                let unit = activity == .hydrate ? hydrationUnit.rawValue : getUnitForActivity(activity)
                selectedOption = ChallengeOption(
                    title: "\(newValue) \(unit) Daily \(activity.rawValue)",
                    description: "Daily target: \(newValue) \(unit)",
                    dailyTarget: newValue,
                    unit: unit,
                    isPreset: false,
                    isCustom: true
                )
            }
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        let hasContactSyncStep = currentStep == .contactSync || friendService.friends.isEmpty
        let stepNumber: Int = {
            switch currentStep {
            case .contactSync: return 1
            case .friendSelection: return hasContactSyncStep ? 2 : 1
            case .groupOrSeparate: return hasContactSyncStep ? 3 : 2
            case .modeSelection: return hasContactSyncStep ? 4 : 3
            case .activityType: return hasContactSyncStep ? 5 : 4
            case .challengeOptions: return hasContactSyncStep ? 6 : 5
            case .duration: return hasContactSyncStep ? 7 : 6
            case .review: return hasContactSyncStep ? 8 : 7
            }
        }()
        
        let baseSteps = selectedFriends.count > 1 ? 7 : 6
        let totalSteps = hasContactSyncStep ? baseSteps + 1 : baseSteps
        let progress = Double(stepNumber) / Double(totalSteps)
        
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 5)
                
                // Gradient fill
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: 5)
        .padding(.horizontal, 40)
    }
    
    // MARK: - Navigation Bar
    
    private var navigationBar: some View {
        let canProgress: Bool = {
            switch currentStep {
            case .contactSync: return true
            case .friendSelection:
                // Can only continue if they have accepted friends selected
                // If showing suggested contacts, Continue is disabled (need to add friends first)
                return !selectedFriends.isEmpty && !friendService.friends.isEmpty
            case .groupOrSeparate: return true
            case .modeSelection: return selectedMode != nil
            case .activityType: return selectedActivity != nil
            case .challengeOptions: return selectedOption != nil
            case .duration: return true
            case .review: return true
            }
        }()
        
        let isMultiChallenge = selectedFriends.count > 1 && !isGroupChallenge
        let sendTitle = isMultiChallenge ? "Send \(selectedFriends.count) Challenges" : "Send Challenge"
        
        // Special case: if showing invite friends screen (contacts but no accepted friends)
        let isInviteMode = friendService.friends.isEmpty && (contactsService.canAccessContacts || !contactsService.suggestedFriends.isEmpty)
        let buttonTitle: String = {
            if currentStep == .review { return sendTitle }
            if currentStep == .friendSelection && isInviteMode { return "Add Friends to Continue" }
            return "Continue"
        }()
        let buttonIcon: String = currentStep == .review ? "paperplane.fill" : "arrow.right"
        let buttonColors: [Color] = currentStep == .review ? [.green, .mint] : [.blue, .cyan]
        
        return HStack(spacing: 12) {
            // Back button (grey circular) — matches auto-gen & onboarding
            if currentStep != .friendSelection && currentStep != .contactSync {
                Button(action: {
                    goBack()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 52, height: 52)
                        .background(
                            Circle()
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.gray.opacity(0.5), lineWidth: 2)
                        )
                }
            }
            
            // Continue / Send button (hidden in invite mode since they can't continue)
            if !(currentStep == .friendSelection && isInviteMode) {
                Button(action: {
                    if currentStep == .review {
                        print("📤 [CHALLENGE FLOW] Send button tapped")
                        Task {
                            await sendChallenge()
                        }
                    } else {
                        print("➡️ [CHALLENGE FLOW] Continue from \(currentStep)")
                        goForward()
                    }
                }) {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: buttonColors[0]))
                            .scaleEffect(0.9)
                    } else {
                        Text(buttonTitle)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(
                    canProgress
                        ? AnyShapeStyle(LinearGradient(colors: buttonColors, startPoint: .leading, endPoint: .trailing))
                        : AnyShapeStyle(Color.gray)
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule()
                        .stroke(
                            canProgress
                                ? AnyShapeStyle(LinearGradient(colors: buttonColors, startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray.opacity(0.3)),
                            lineWidth: 2
                        )
                )
                .opacity(canProgress ? 1 : 0.6)
            }
            .disabled(!canProgress || isCreating)
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Navigation Logic
    
    private func goForward() {
        withAnimation(.spring(response: 0.3)) {
            switch currentStep {
            case .contactSync:
                currentStep = .friendSelection
            case .friendSelection:
                // If multiple friends selected, show group/separate choice
                if selectedFriends.count > 1 {
                    currentStep = .groupOrSeparate
                } else {
                    // Single friend — set legacy selectedFriend and skip group screen
                    selectedFriend = selectedFriends.first
                    currentStep = .modeSelection
                }
            case .groupOrSeparate:
                currentStep = .modeSelection
            case .modeSelection:
                currentStep = .activityType
            case .activityType:
                currentStep = .challengeOptions
            case .challengeOptions:
                currentStep = .duration
            case .duration:
                // Dismiss keyboard and commit custom duration before navigating
                durationFieldFocused = false
                if isCustomDuration, let val = Int(customDurationText), val >= 1, val <= 365 {
                    selectedDuration = val
                }
                currentStep = .review
            case .review:
                break
            }
        }
        HapticManager.impact(.medium)
    }
    
    private func goBack() {
        withAnimation(.spring(response: 0.3)) {
            switch currentStep {
            case .contactSync:
                break
            case .friendSelection:
                break
            case .groupOrSeparate:
                currentStep = .friendSelection
            case .modeSelection:
                if selectedFriends.count > 1 {
                    currentStep = .groupOrSeparate
                } else {
                    currentStep = .friendSelection
                }
            case .activityType:
                currentStep = .modeSelection
            case .challengeOptions:
                currentStep = .activityType
            case .duration:
                currentStep = .challengeOptions
            case .review:
                currentStep = .duration
            }
        }
        HapticManager.impact(.light)
    }
    
    // MARK: - Card Views (same content as ChallengeCreationFlow, but in card style)
    
    /// Toggle a friend in/out of the multi-select list (max 2)
    private func toggleFriendSelection(_ friend: Friend) {
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let idx = selectedFriends.firstIndex(where: { $0.friendId == friend.friendId }) {
                selectedFriends.remove(at: idx)
            } else if selectedFriends.count < 2 {
                selectedFriends.append(friend)
            } else {
                // Already 2 selected — replace the oldest selection
                selectedFriends.removeFirst()
                selectedFriends.append(friend)
            }
            // Keep legacy single-select in sync
            selectedFriend = selectedFriends.first
        }
    }
    
    private func isFriendSelected(_ friend: Friend) -> Bool {
        selectedFriends.contains(where: { $0.friendId == friend.friendId })
    }
    
    // MARK: - Contact Sync Card (shown when user has no friends)
    
    private var contactSyncCard: some View {
        VStack(spacing: 20) {
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
            
            Text("Find Friends to Challenge")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("Sync your contacts to see who's already on Fit33 — then challenge them!")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
            
            // Sync Contacts Button
            Button(action: {
                HapticManager.impact(.medium)
                Task {
                    if contactsService.permissionDenied {
                        // Already denied — open Settings
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            await UIApplication.shared.open(url)
                        }
                    } else {
                        // Request permission (first time or not determined)
                        let granted = await contactsService.requestAccess()
                        if granted {
                            // Sync contacts and find matching Fit33 users
                            await contactsService.fetchContactsAndFindFriends()
                            // Also refresh friends list
                            await friendService.fetchFriends()
                            
                            // Advance to friend selection after sync completes
                            await MainActor.run {
                                withAnimation {
                                    currentStep = .friendSelection
                                }
                            }
                        }
                    }
                }
            }) {
                HStack(spacing: 10) {
                    if contactsService.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Image(systemName: contactsService.permissionDenied ? "gear.badge" : "person.crop.rectangle.stack.fill")
                            .font(.system(size: 18))
                        Text(contactsService.permissionDenied ? "Enable in Settings" : "Sync Contacts")
                            .font(.headline)
                    }
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
            .padding(.horizontal, 10)
            
            // Suggested friends (if contacts already synced and found matches)
            if contactsService.canAccessContacts && !contactsService.suggestedFriends.isEmpty {
                VStack(spacing: 8) {
                    HStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                        Text("Friends Found!")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.6))
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                    }
                    
                    Text("\(contactsService.suggestedFriends.count) of your contacts are on Fit33")
                        .font(.subheadline)
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }
                .padding(.top, 4)
            }
            
            // Privacy note
            HStack(spacing: 4) {
                Image(systemName: "lock.shield")
                    .font(.caption2)
                Text("Your contacts stay private and are never shared")
                    .font(.caption2)
            }
            .foregroundColor(.white.opacity(0.4))
        }
        .padding(.vertical, 8)
    }
    
    private var friendSelectionCard: some View {
        // Page 0: Top 3 most interacted with
        let mostEngaged = Array(friendService.friends.sorted(by: { $0.totalWorkoutsShared > $1.totalWorkoutsShared }).prefix(3))
        let mostEngagedIds = Set(mostEngaged.map(\.friendId))
        
        // Page 1: Newest added — skip anyone already on page 0
        let newestAdded: [Friend] = {
            let sorted = friendService.friends.sorted(by: { $0.friendsSince > $1.friendsSince })
            return Array(sorted.filter { !mostEngagedIds.contains($0.friendId) }.prefix(3))
        }()
        
        let floatingHeadIds = Set(mostEngaged.map(\.friendId) + newestAdded.map(\.friendId))
        let listFriends = filteredFriends.filter { !floatingHeadIds.contains($0.friendId) }
        
        // Check if we're in invite mode (showing suggested contacts, not accepted friends)
        let isInviteMode = friendService.friends.isEmpty && (contactsService.canAccessContacts || !contactsService.suggestedFriends.isEmpty)
        
        return VStack(spacing: 16) {
            // Header (only shown when NOT in invite mode - invite mode uses pinned header)
            if !isInviteMode {
                Text("Who do you want to challenge?")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(selectedFriends.isEmpty ? "Pick a buddy (or two!)" : selectedFriends.count == 1 ? "1 buddy selected — add another?" : "\(selectedFriends.count) buddies selected")
                    .font(.caption)
                    .foregroundColor(selectedFriends.isEmpty ? .white.opacity(0.6) : .cyan)
            }
            
            // Selected friends preview chips
            if !selectedFriends.isEmpty {
                HStack(spacing: 8) {
                    ForEach(selectedFriends) { friend in
                        HStack(spacing: 6) {
                            CachedFriendPhoto(
                                friendId: friend.friendId.uuidString,
                                photoUrl: friend.profilePhotoUrl,
                                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                                size: 24,
                                showGradientRing: false,
                                gradientColors: [.blue, .cyan]
                            )
                            
                            Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Button(action: { toggleFriendSelection(friend) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.25))
                                .overlay(Capsule().stroke(Color.cyan.opacity(0.4), lineWidth: 1))
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            // Show suggested friends from contacts if no accepted friends yet
            if friendService.friends.isEmpty && !contactsService.suggestedFriends.isEmpty {
                // Friends list - fills available space
                VStack(spacing: 12) {
                    ForEach(filteredSuggestedContacts) { suggestedFriend in
                        suggestedFriendRow(friend: suggestedFriend)
                    }
                }
                
                // Sent requests badge
                if !sentFriendRequests.isEmpty {
                    Text("\(sentFriendRequests.count) request\(sentFriendRequests.count == 1 ? "" : "s") sent ✓")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .padding(.top, 4)
                }
            } else if friendService.friends.isEmpty {
                Text("No friends yet")
                    .foregroundColor(.white.opacity(0.7))
            } else {
                VStack(spacing: 16) {
                    // Swipeable top friends
                    GeometryReader { geometry in
                        let cardWidth = geometry.size.width
                        
                        HStack(spacing: 0) {
                            HStack(spacing: 12) {
                                ForEach(mostEngaged) { friend in
                                    TopFriendBubble(friend: friend, isSelected: isFriendSelected(friend)) {
                                        toggleFriendSelection(friend)
                                    }
                                }
                            }
                            .frame(width: cardWidth)
                            
                            HStack(spacing: 12) {
                                ForEach(newestAdded) { friend in
                                    TopFriendBubble(friend: friend, isSelected: isFriendSelected(friend)) {
                                        toggleFriendSelection(friend)
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
                    
                    // Page indicator (dash and dot style)
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(topFriendsPage == 0 ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: topFriendsPage == 0 ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: topFriendsPage)
                        Capsule()
                            .fill(topFriendsPage == 1 ? Color.blue : Color.white.opacity(0.3))
                            .frame(width: topFriendsPage == 1 ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: topFriendsPage)
                    }
                    
                    // Friends list
                    if !listFriends.isEmpty {
                        LazyVStack(spacing: 12) {
                            ForEach(listFriends) { friend in
                                ChallengeFlowFriendCard(
                                    friend: friend,
                                    isSelected: isFriendSelected(friend),
                                    onSelect: { selected in
                                        toggleFriendSelection(selected)
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Group vs Separate Screen
    
    private var groupOrSeparateCard: some View {
        let friendNames = selectedFriends.map { $0.friendName?.components(separatedBy: " ").first ?? $0.friendUsername ?? "Friend" }
        let userName = userManager.currentUser?.name?.components(separatedBy: " ").first ?? "You"
        
        return VStack(spacing: 20) {
            Text("How should this work?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            Text("You selected \(friendNames.joined(separator: " & "))")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 14) {
                // Option 1: Group Challenge (all in one)
                Button(action: {
                    HapticManager.impact(.medium)
                    withAnimation(.spring(response: 0.3)) {
                        isGroupChallenge = true
                    }
                }) {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Group Challenge")
                                .font(.headline)
                                .fontWeight(isGroupChallenge ? .bold : .semibold)
                                .foregroundColor(.white)
                            Spacer()
                            if isGroupChallenge {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        
                        // Visual: all 3 together
                        HStack(spacing: 0) {
                            Spacer()
                            HStack(spacing: -10) {
                                // User avatar with profile photo
                                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                    Image(uiImage: cachedImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
                                } else {
                                    Circle()
                                        .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 40, height: 40)
                                        .overlay(Text(String(userName.prefix(1)).uppercased()).font(.system(size: 14, weight: .bold)).foregroundColor(.white))
                                        .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
                                }
                                
                                ForEach(selectedFriends) { friend in
                                    CachedFriendPhoto(
                                        friendId: friend.friendId.uuidString,
                                        photoUrl: friend.profilePhotoUrl,
                                        name: friend.friendName ?? "F",
                                        size: 40,
                                        showGradientRing: false,
                                        gradientColors: [.blue, .cyan]
                                    )
                                    .overlay(Circle().stroke(Color.darkBackground, lineWidth: 2))
                                }
                            }
                            Spacer()
                        }
                        
                        Text("One challenge. Everyone's in it together.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                                .offset(y: 4)
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.18), Color(white: 0.12)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    isGroupChallenge
                                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.blue.opacity(0.15)),
                                    lineWidth: isGroupChallenge ? 2 : 1
                                )
                        }
                    )
                    .shadow(color: isGroupChallenge ? Color.blue.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                
                // ---- or ---- divider
                HStack(spacing: 12) {
                    Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                    Text("OR").font(.caption).fontWeight(.semibold).foregroundColor(.white.opacity(0.6))
                    Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                }
                
                // Option 2: Separate Challenges (individual 1v1s)
                Button(action: {
                    HapticManager.impact(.medium)
                    withAnimation(.spring(response: 0.3)) {
                        isGroupChallenge = false
                    }
                }) {
                    VStack(spacing: 14) {
                        HStack {
                            Text("Separate Challenges")
                                .font(.headline)
                                .fontWeight(!isGroupChallenge ? .bold : .semibold)
                                .foregroundColor(.white)
                            Spacer()
                            if !isGroupChallenge {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                        }
                        
                        // Visual: separate 1v1 lines
                        VStack(spacing: 8) {
                            ForEach(selectedFriends) { friend in
                                HStack(spacing: 8) {
                                    // User avatar with profile photo
                                    if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                        Image(uiImage: cachedImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 28, height: 28)
                                            .overlay(Text(String(userName.prefix(1)).uppercased()).font(.system(size: 10, weight: .bold)).foregroundColor(.white))
                                    }
                                    
                                    Rectangle()
                                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                        .frame(height: 2)
                                        .frame(maxWidth: 60)
                                    
                                    Text("vs")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                    
                                    Rectangle()
                                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                                        .frame(height: 2)
                                        .frame(maxWidth: 60)
                                    
                                    CachedFriendPhoto(
                                        friendId: friend.friendId.uuidString,
                                        photoUrl: friend.profilePhotoUrl,
                                        name: friend.friendName ?? "F",
                                        size: 28,
                                        showGradientRing: false,
                                        gradientColors: [.orange, .red]
                                    )
                                    
                                    Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                        }
                        
                        Text("Creates \(selectedFriends.count) separate 1-on-1 challenges.")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(18)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                                .offset(y: 4)
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.18), Color(white: 0.12)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                            
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    !isGroupChallenge
                                        ? AnyShapeStyle(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.orange.opacity(0.15)),
                                    lineWidth: !isGroupChallenge ? 2 : 1
                                )
                        }
                    )
                    .shadow(color: !isGroupChallenge ? Color.orange.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var modeSelectionCard: some View {
        let buddyText = selectedFriends.count > 1 ? "your buddies" : (selectedFriends.first?.friendName?.components(separatedBy: " ").first ?? "your buddy")
        
        return VStack(spacing: 24) {
            Text("How will you challenge \(buddyText)?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 16) {
                ForEach(ChallengeMode.allCases, id: \.self) { mode in
                    ModeSelectionCard(
                        mode: mode,
                        isSelected: selectedMode == mode,
                        onSelect: {
                            print("✅ [CHALLENGE FLOW] Selected mode: \(mode.title)")
                            selectedMode = mode
                        }
                    )
                }
                
                // Community Challenges option
                Button(action: {
                    HapticManager.impact(.medium)
                    showCommunityHub = true
                }) {
                    HStack(spacing: 14) {
                        Text("🌍")
                            .font(.system(size: 32))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Community Challenges")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text("Join global leaderboards — unlimited players")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                        Spacer()
                        
                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(
                                        LinearGradient(colors: [.purple.opacity(0.5), .blue.opacity(0.3)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 1.5
                                    )
                            )
                    )
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showCommunityHub) {
                    CommunityChallengesHubView()
                }
            }
        }
    }
    
    private var activityTypeCard: some View {
        VStack(spacing: 24) {
            Text("What will you compete on?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(ChallengeActivityType.allCases, id: \.self) { activity in
                    ActivityTypeCard(
                        activity: activity,
                        isSelected: selectedActivity == activity,
                        onSelect: {
                            print("✅ [CHALLENGE FLOW] Selected activity: \(activity.rawValue)")
                            selectedActivity = activity
                            customTarget = getDefaultCustomTarget(activity)
                            hydrationUnit = .ml
                            // Auto-select custom option by default
                            let unit = activity == .hydrate ? HydrationUnit.ml.rawValue : getUnitForActivity(activity)
                            selectedOption = ChallengeOption(
                                title: "\(getDefaultCustomTarget(activity)) \(unit) Daily \(activity.rawValue)",
                                description: "Daily target: \(getDefaultCustomTarget(activity)) \(unit)",
                                dailyTarget: getDefaultCustomTarget(activity),
                                unit: unit,
                                isPreset: false,
                                isCustom: true
                            )
                        }
                    )
                }
            }
        }
    }
    
    private var challengeOptionsCard: some View {
        VStack(spacing: 16) {
            if let activity = selectedActivity {
                Text("Choose Your \(activity.emoji) \(activity.rawValue) Goal")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(customGoalSubtitle(for: activity))
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 10) {
                    // Custom Goal Creator (unique per activity)
                    CustomTargetCard(
                        activity: activity,
                        customTarget: $customTarget,
                        hydrationUnit: $hydrationUnit,
                        isSelected: selectedOption?.isCustom == true,
                        gradientColors: activity.gradientColors,
                        onSelect: {
                            HapticManager.impact(.medium)
                            let unit = activity == .hydrate ? hydrationUnit.rawValue : getUnitForActivity(activity)
                            withAnimation(.spring(response: 0.3)) {
                                selectedOption = ChallengeOption(
                                    title: "\(customTarget) \(unit) Daily \(activity.rawValue)",
                                    description: "Daily target: \(customTarget) \(unit)",
                                    dailyTarget: customTarget,
                                    unit: unit,
                                    isPreset: false,
                                    isCustom: true
                                )
                            }
                        }
                    )
                    
                    // ---- or ---- divider
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                        
                        Text("OR")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white.opacity(0.6))
                        
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 2)
                    
                    // Preset Options
                    ForEach(getOptionsForActivity(activity)) { option in
                        ChallengeOptionCard(
                            option: option,
                            isSelected: selectedOption?.id == option.id && selectedOption?.isCustom == false,
                            gradientColors: activity.gradientColors,
                            onSelect: {
                                HapticManager.impact(.medium)
                                withAnimation(.spring(response: 0.3)) {
                                    selectedOption = option
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    private var durationCard: some View {
        VStack(spacing: 16) {
            Text("How long should the challenge last?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            VStack(spacing: 10) {
                // Custom duration input
                Button(action: {
                    HapticManager.impact(.medium)
                    isCustomDuration = true
                    customDurationText = "\(selectedDuration)"
                    durationFieldFocused = true
                }) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 46, height: 46)
                                .shadow(color: isCustomDuration ? Color.blue.opacity(0.3) : .clear, radius: 6, x: 0, y: 3)
                            
                            Text("✏️")
                                .font(.system(size: 22))
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Custom Duration")
                                .font(.body)
                                .fontWeight(isCustomDuration ? .bold : .semibold)
                                .foregroundColor(.white)
                            
                            Text("Set your own number of days")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        if isCustomDuration {
                            HStack(spacing: 6) {
                                TextField("", text: $customDurationText)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 50)
                                    .focused($durationFieldFocused)
                                    .onChange(of: customDurationText) { _, newValue in
                                        if let val = Int(newValue), val >= 1, val <= 365 {
                                            selectedDuration = val
                                        }
                                    }
                                
                                Text("days")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 17, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                                .offset(y: 4)
                            
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.18), Color(white: 0.12)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                            
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    isCustomDuration
                                        ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Color.blue.opacity(0.15)),
                                    lineWidth: isCustomDuration ? 2 : 1
                                )
                        }
                    )
                    .shadow(color: isCustomDuration ? Color.blue.opacity(0.3) : .clear, radius: 12, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                
                // ---- or ---- divider
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                    Text("OR")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.6))
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 1)
                }
                .padding(.vertical, 2)
                
                // Preset duration options
                ForEach([3, 7, 14, 30], id: \.self) { days in
                    ChallengeDurationCard(
                        days: days,
                        isSelected: selectedDuration == days && !isCustomDuration,
                        onSelect: {
                            isCustomDuration = false
                            durationFieldFocused = false
                            selectedDuration = days
                        }
                    )
                }
            }
        }
    }
    
    private var reviewCard: some View {
        let userName = userManager.currentUser?.name?.components(separatedBy: " ").first ?? "You"
        let isMultiple = selectedFriends.count > 1
        let friendNames = selectedFriends.map { $0.friendName?.components(separatedBy: " ").first ?? $0.friendUsername ?? "Friend" }
        
        return VStack(spacing: 24) {
            Text("Review Your Challenge")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            if let mode = selectedMode,
               let activity = selectedActivity,
               let option = selectedOption {
                VStack(spacing: 16) {
                    
                    // MARK: Participants Visual
                    if isMultiple && isGroupChallenge {
                        // GROUP CHALLENGE: All together
                        VStack(spacing: 10) {
                            Text("Group Challenge")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                            
                            // Overlapping avatars (you + all friends)
                            HStack(spacing: 0) {
                                Spacer()
                                HStack(spacing: -12) {
                                    // Your avatar
                                    if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                        Image(uiImage: cachedImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(Circle())
                                            .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                                    } else {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 50, height: 50)
                                            .overlay(Text(String(userName.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                                            .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                                    }
                                    
                                    ForEach(selectedFriends) { friend in
                                        CachedFriendPhoto(
                                            friendId: friend.friendId.uuidString,
                                            photoUrl: friend.profilePhotoUrl,
                                            name: friend.friendName ?? "Friend",
                                            size: 50,
                                            showGradientRing: false,
                                            gradientColors: [.blue, .cyan]
                                        )
                                        .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                                    }
                                }
                                Spacer()
                            }
                            
                            Text("\(userName), \(friendNames.joined(separator: " & "))")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }
                        
                    } else if isMultiple && !isGroupChallenge {
                        // SEPARATE 1v1 CHALLENGES: Show each matchup
                        VStack(spacing: 10) {
                            Text("\(selectedFriends.count) Separate Challenges")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                            
                            ForEach(selectedFriends) { friend in
                                HStack(spacing: 10) {
                                    // Your avatar (small)
                                    if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                        Image(uiImage: cachedImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 36, height: 36)
                                            .clipShape(Circle())
                                    } else {
                                        Circle()
                                            .fill(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 36, height: 36)
                                            .overlay(Text(String(userName.prefix(1)).uppercased()).font(.system(size: 12, weight: .bold)).foregroundColor(.white))
                                    }
                                    
                                    Text("vs")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(.orange)
                                    
                                    CachedFriendPhoto(
                                        friendId: friend.friendId.uuidString,
                                        photoUrl: friend.profilePhotoUrl,
                                        name: friend.friendName ?? "Friend",
                                        size: 36,
                                        showGradientRing: false,
                                        gradientColors: [.orange, .red]
                                    )
                                    
                                    Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                        
                    } else {
                        // SINGLE 1v1: You vs Friend
                        HStack(spacing: 12) {
                            if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                Image(uiImage: cachedImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .frame(width: 50, height: 50)
                                    .overlay(Text(String(userName.prefix(1)).uppercased()).font(.system(size: 16, weight: .bold)).foregroundColor(.white))
                            }
                            
                            Text("VS")
                                .font(.title3)
                                .fontWeight(.black)
                                .foregroundColor(.white)
                            
                            if let friend = selectedFriends.first {
                                CachedFriendPhoto(
                                    friendId: friend.friendId.uuidString,
                                    photoUrl: friend.profilePhotoUrl,
                                    name: friend.friendName ?? "Friend",
                                    size: 50,
                                    showGradientRing: true,
                                    gradientColors: [.orange, .red]
                                )
                            }
                        }
                    }
                    
                    // MARK: Details Card
                    VStack(spacing: 12) {
                        if isMultiple {
                            ReviewRow(title: "Type", value: isGroupChallenge ? "Group Challenge" : "Separate Challenges")
                            ReviewRow(title: "Buddies", value: friendNames.joined(separator: ", "))
                        } else {
                            ReviewRow(title: "Opponent", value: friendNames.first ?? "Friend")
                        }
                        ReviewRow(title: "Mode", value: "\(mode.emoji) \(mode.title)")
                        ReviewRow(title: "Activity", value: "\(activity.emoji) \(activity.rawValue)")
                        ReviewRow(title: "Goal", value: option.title)
                        ReviewRow(title: "Duration", value: "\(selectedDuration) days")
                    }
                    .padding(20)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .fill(Color.black.opacity(0.2))
                                .offset(y: 4)
                            
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(white: 0.18), Color(white: 0.12)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1.5
                                )
                            
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        }
                    )
                }
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func getDefaultCustomTarget(_ activity: ChallengeActivityType) -> Int {
        switch activity {
        case .walk: return 30
        case .run: return 20
        case .lift: return 5
        case .hydrate: return 2000
        case .steps: return 10000
        case .calories: return 500
        case .protein: return 150
        case .activeMinutes: return 30
        case .workoutStreak: return 1
        case .sleep: return 7
        }
    }
    
    private func getUnitForActivity(_ activity: ChallengeActivityType) -> String {
        switch activity {
        case .walk, .run: return "minutes"
        case .lift: return "workouts"
        case .hydrate: return "ml"
        case .steps: return "steps"
        case .calories: return "calories"
        case .protein: return "grams"
        case .activeMinutes: return "minutes"
        case .workoutStreak: return "workouts"
        case .sleep: return "hours"
        }
    }
    
    private func customGoalSubtitle(for activity: ChallengeActivityType) -> String {
        switch activity {
        case .steps: return "Set your daily step target or pick a preset below"
        case .walk: return "Choose how many minutes you'll walk each day"
        case .run: return "Set your daily running goal in minutes"
        case .lift: return "How many workouts per week can you commit to?"
        case .hydrate: return "Track your daily water intake goal"
        case .calories: return "Set your daily active calorie burn target"
        case .protein: return "Hit your daily protein intake goal"
        case .activeMinutes: return "Total active minutes from any workout"
        case .workoutStreak: return "Complete at least one workout per day"
        case .sleep: return "Get enough sleep every night"
        }
    }
    
    private func getOptionsForActivity(_ activity: ChallengeActivityType) -> [ChallengeOption] {
        switch activity {
        case .steps:
            return [
                ChallengeOption(title: "🌤️ Morning Walker", description: "Get moving with a light daily goal", dailyTarget: 5000, unit: "steps", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏆 10K Club", description: "The classic daily step goal", dailyTarget: 10000, unit: "steps", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔥 Step Machine", description: "Push your limits every day", dailyTarget: 15000, unit: "steps", isPreset: true, isCustom: false)
            ]
        case .walk:
            return [
                ChallengeOption(title: "☕ Coffee Walk", description: "A quick 15-min stroll daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🎧 Podcast Walk", description: "30 minutes of fresh air", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🌅 Golden Hour", description: "A full 60-min walk each day", dailyTarget: 60, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .run:
            return [
                ChallengeOption(title: "🐣 Easy Jog", description: "Start with 15 mins daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏃 Steady Runner", description: "Build up to 30 mins daily", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "⚡ Speed Demon", description: "45 mins of running every day", dailyTarget: 45, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .lift:
            return [
                ChallengeOption(title: "💪 Starter Strength", description: "3 sessions per week", dailyTarget: 3, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "🏋️ Gym Rat", description: "5 sessions per week", dailyTarget: 5, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "🦾 Iron Addict", description: "6 sessions — rest only once", dailyTarget: 6, unit: "workouts", isPreset: true, isCustom: false)
            ]
        case .hydrate:
            return [
                ChallengeOption(title: "💦 Stay Sipping", description: "6 cups — build the habit", dailyTarget: 1500, unit: "ml", isPreset: true, isCustom: false),
                ChallengeOption(title: "🥤 Hydro Homie", description: "8 cups — the gold standard", dailyTarget: 2000, unit: "ml", isPreset: true, isCustom: false),
                ChallengeOption(title: "🌊 Water Warrior", description: "3 liters — max hydration", dailyTarget: 3000, unit: "ml", isPreset: true, isCustom: false)
            ]
        case .calories:
            return [
                ChallengeOption(title: "🕯️ Slow Burn", description: "300 active calories daily", dailyTarget: 300, unit: "calories", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔥 Torch Mode", description: "500 active calories daily", dailyTarget: 500, unit: "calories", isPreset: true, isCustom: false),
                ChallengeOption(title: "☄️ Inferno", description: "1000 active calories daily", dailyTarget: 1000, unit: "calories", isPreset: true, isCustom: false)
            ]
        case .protein:
            return [
                ChallengeOption(title: "🥚 Protein Basics", description: "100g daily — maintenance mode", dailyTarget: 100, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🍗 Muscle Fuel", description: "150g daily — building phase", dailyTarget: 150, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🥩 Gains Machine", description: "200g daily — max protein", dailyTarget: 200, unit: "grams", isPreset: true, isCustom: false)
            ]
        case .activeMinutes:
            return [
                ChallengeOption(title: "🧘 Gentle Movement", description: "15 active minutes daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "⏱️ WHO Standard", description: "30 active minutes daily", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔋 Power Hour", description: "60 active minutes daily", dailyTarget: 60, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .workoutStreak:
            return [
                ChallengeOption(title: "🎯 Daily Grinder", description: "1 workout every day — no excuses", dailyTarget: 1, unit: "workouts", isPreset: true, isCustom: false),
                ChallengeOption(title: "💪 Double Down", description: "2 sessions a day — morning & evening", dailyTarget: 2, unit: "workouts", isPreset: true, isCustom: false)
            ]
        case .sleep:
            return [
                ChallengeOption(title: "💤 Early Bird", description: "Get at least 6 hours of sleep", dailyTarget: 6, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "😴 Sleep Well", description: "7 hours — the science-backed sweet spot", dailyTarget: 7, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "🛏️ Recovery King", description: "8+ hours for peak performance", dailyTarget: 8, unit: "hours", isPreset: true, isCustom: false)
            ]
        }
    }
    
    private func sendChallenge() async {
        guard let mode = selectedMode,
              let activity = selectedActivity,
              let option = selectedOption else {
            print("❌ [CHALLENGE FLOW] Missing required selections")
            return
        }
        
        guard !selectedFriends.isEmpty else {
            print("❌ [CHALLENGE FLOW] No friends selected")
            return
        }
        
        isCreating = true
        
        let challengeType: ChallengeType
        switch activity {
        case .walk: challengeType = .walk
        case .run: challengeType = .run
        case .lift: challengeType = .lift
        case .hydrate: challengeType = .hydrate
        case .steps: challengeType = .steps
        case .calories: challengeType = .calories
        case .protein: challengeType = .protein
        case .activeMinutes: challengeType = .activeMinutes
        case .workoutStreak: challengeType = .workoutStreak
        case .sleep: challengeType = .steps // Sleep stored as custom, resolved by unit
        }
        
        let title = "\(mode.titlePrefix) \(activity.emoji) \(option.title)"
        var success = false
        
        if selectedFriends.count > 1 && isGroupChallenge {
            // GROUP CHALLENGE: Create one group challenge with all members
            print("👥 [CHALLENGE FLOW] Creating group challenge with \(selectedFriends.count) friends")
            let groupId = await ChallengeService.shared.createGroupChallenge(
                memberIds: selectedFriends.map(\.friendId),
                type: challengeType,
                title: title,
                description: option.description,
                mode: mode.rawValue,
                dailyTarget: option.dailyTarget,
                totalTarget: option.dailyTarget * selectedDuration,
                targetUnit: option.unit,
                durationDays: selectedDuration
            )
            success = groupId != nil
        } else {
            // SEPARATE CHALLENGES: Create individual 1v1 for each friend
            print("🔀 [CHALLENGE FLOW] Creating \(selectedFriends.count) separate challenge(s)")
            var allSucceeded = true
            for friend in selectedFriends {
                print("📤 [CHALLENGE FLOW] Sending challenge to \(friend.displayName)")
                let challengeId = await ChallengeService.shared.createChallenge(
                    opponentId: friend.friendId,
                    type: challengeType,
                    title: title,
                    description: option.description,
                    dailyTarget: option.dailyTarget,
                    totalTarget: option.dailyTarget * selectedDuration,
                    targetUnit: option.unit,
                    durationDays: selectedDuration
                )
                if challengeId == nil { allSucceeded = false }
            }
            success = allSucceeded
        }
        
        isCreating = false
        
        if success {
            print("✅ [CHALLENGE FLOW] Challenge(s) created successfully")
            HapticManager.notification(.success)
            showingSuccess = true
        } else {
            print("❌ [CHALLENGE FLOW] Challenge creation failed")
            HapticManager.notification(.error)
            showingError = true
        }
    }
    
    // MARK: - Suggested Friend Row (for contacts)
    private func suggestedFriendRow(friend: SuggestedFriend) -> some View {
        let isLoading = loadingFriendRequests.contains(friend.userId)
        let isRequestSent = sentFriendRequests.contains(friend.userId) || friend.hasOutgoingRequest
        
        return HStack(spacing: 14) {
            // Profile photo or initials with blue ring
            ZStack {
                // Blue gradient ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2.5
                    )
                    .frame(width: 54, height: 54)
                
                if let photoUrl = friend.profilePhotoUrl, !photoUrl.isEmpty {
                    AsyncImage(url: URL(string: photoUrl)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Circle()
                                .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(LinearGradient(colors: [.blue.opacity(0.6), .purple.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 46, height: 46)
                        .overlay(
                            Text(friend.initials)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                if let username = friend.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Add button
            Button(action: {
                guard !isRequestSent && !isLoading else { return }
                loadingFriendRequests.insert(friend.userId)
                HapticManager.impact(.medium)
                
                Task {
                    let success = await friendService.sendFriendRequest(toUserId: friend.userId)
                    
                    await MainActor.run {
                        loadingFriendRequests.remove(friend.userId)
                        if success {
                            sentFriendRequests.insert(friend.userId)
                            HapticManager.notification(.success)
                        }
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: isRequestSent ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isRequestSent ? "Sent" : (isLoading ? "" : "Add"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isRequestSent ? .green : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isRequestSent {
                            Color.green.opacity(0.15)
                        } else {
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .cornerRadius(20)
            }
            .disabled(isRequestSent || isLoading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(14)
    }
}

// MARK: - Friend Card Component

struct TopFriendBubble: View {
    let friend: Friend
    var isSelected: Bool = false
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 10) {
                // Avatar — ring only when selected, glow behind when selected
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 60,
                    showGradientRing: isSelected,
                    gradientColors: [.blue, .cyan]
                )
                .shadow(color: isSelected ? Color.cyan.opacity(0.5) : .clear, radius: 10, x: 0, y: 4)
                .scaleEffect(isSelected ? 1.08 : 1.0)
                
                // First name only
                Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundColor(isSelected ? .cyan : .white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct ChallengeFlowFriendCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let friend: Friend
    let isSelected: Bool
    let onSelect: (Friend) -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            onSelect(friend)
        }) {
            HStack(spacing: 14) {
                // Friend photo with blue glow ring when selected
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 50,
                    showGradientRing: isSelected,
                    gradientColors: [.blue, .cyan]
                )
                
                // Friend info
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
                
                // Checkmark when selected, chevron when not
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.96)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.0)),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color.blue.opacity(0.25) : Color.black.opacity(colorScheme == .dark ? 0.15 : 0.06), radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 6 : 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
