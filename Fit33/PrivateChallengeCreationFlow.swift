//
//  PrivateChallengeCreationFlow.swift
//  Fit33
//
//  Creation flow for Private Challenges — invite-only challenge communities.
//  Reuses existing ChallengeActivityType, ChallengeOption, and card components.
//

import SwiftUI
import PhotosUI

struct PrivateChallengeCreationFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared
    
    enum FlowStep: CaseIterable {
        case naming          // Name + emoji
        case activityType    // What are we tracking?
        case goalSetting     // Daily target (reuse ChallengeOption cards)
        case settings        // Admin settings (leaderboard, member invites, etc.)
        case inviteFriends   // Invite friends to the challenge
        case review          // Summary before creating
    }
    
    @State private var currentStep: FlowStep = .naming
    @State private var challengeTitle = ""
    @State private var challengeDescription = ""
    @State private var selectedEmoji = "🔒"
    @State private var selectedActivity: ChallengeActivityType?
    @State private var selectedOption: ChallengeOption?
    @State private var customTarget: Int = 10000
    @State private var hydrationUnit: HydrationUnit = .ml
    
    // Admin settings
    @State private var allowMemberInvites = false
    @State private var showLeaderboard = true
    @State private var maxMembers = 50
    
    // Friend invitation
    @State private var selectedFriends: [Friend]
    @State private var searchText = ""

    /// Optional pre-selected friends to invite. When non-empty, the invite
    /// step opens with these friends already chipped — useful for the
    /// "mutual friends quick-add" flow from `FriendProfileView`.
    init(preSelectedFriends: [Friend] = []) {
        _selectedFriends = State(initialValue: preSelectedFriends)
    }
    
    // Challenge icon photo
    @State private var iconPhotoItem: PhotosPickerItem?
    @State private var iconImageData: Data?
    @State private var iconImage: Image?
    
    // State
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var createdChallengeId: UUID?
    @State private var showingError = false
    
    // Emoji options for quick pick
    private let emojiOptions = ["🔒", "🏃", "💪", "👣", "🏆", "⚡", "🔥", "💧", "🎯", "🏋️", "🧘", "🥇", "💎", "🌟", "🚀", "🎪"]
    
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
    
    // MARK: - Top friends highlight (mirrors FriendsListView.topFriendsHighlight)
    
    /// Top 3 most engaged friends sourced from FriendRankingService.
    private var highlightMostEngaged: [Friend] {
        let rankedTop = rankingService.rankedFriends.prefix(3)
        return rankedTop.compactMap { ranked in
            friendService.friends.first { $0.friendId == ranked.friendId }
        }
    }
    
    /// Top 3 newest-added friends, excluding any already shown in row 1.
    private var highlightNewestAdded: [Friend] {
        let engagedIds = Set(highlightMostEngaged.map(\.friendId))
        let sorted = friendService.friends.sorted(by: { $0.friendsSince > $1.friendsSince })
        return Array(sorted.filter { !engagedIds.contains($0.friendId) }.prefix(3))
    }
    
    /// Whether to show the 3×2 highlight at all — match FriendsListView's
    /// "only when at least 3 friends" gate.
    private var showFloatingHeads: Bool {
        friendService.friends.count >= 3 && !highlightMostEngaged.isEmpty
    }
    
    /// Friends to render in the scrollable list below the highlight, with
    /// search applied. Excludes the 6 highlighted friends so they aren't
    /// duplicated.
    private var inviteListFriends: [Friend] {
        let highlightIds: Set<UUID> = showFloatingHeads
            ? Set(highlightMostEngaged.map(\.friendId) + highlightNewestAdded.map(\.friendId))
            : []
        let base = filteredFriends.filter { !highlightIds.contains($0.friendId) }
        return base
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress bar
                    progressHeader
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                    
                    // Main content
                    ScrollView {
                        VStack(spacing: 24) {
                            switch currentStep {
                            case .naming:
                                namingCard
                            case .activityType:
                                activityTypeCard
                            case .goalSetting:
                                goalSettingCard
                            case .settings:
                                settingsCard
                            case .inviteFriends:
                                inviteFriendsCard
                            case .review:
                                reviewCard
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 120)
                    }
                    .scrollIndicators(.hidden)
                    // Sprint 5 M-9: naming step opens the keyboard immediately;
                    // let the user swipe it away while scrolling to the next
                    // step instead of having to hit Return.
                    .scrollDismissesKeyboard(.interactively)
                    
                    Spacer(minLength: 0)
                    
                    navigationBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("Private Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        if currentStep == .naming {
                            dismiss()
                        } else {
                            goBack()
                        }
                    }) {
                        Image(systemName: currentStep == .naming ? "xmark" : "chevron.left")
                            .font(.ds_labelLarge)
                    }
                }
            }
            .alert("Challenge Created! 🔒", isPresented: $showingSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Your private challenge is ready! \(selectedFriends.count > 0 ? "Invites have been sent to your friends." : "Invite friends to join from the challenge detail page.")")
            }
            .alert("Failed to Create Challenge", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text("There was an issue creating your challenge. Please try again.")
            }
            .onAppear {
                Task {
                    await friendService.fetchFriends()
                    // Powers the 3×2 "top friends" highlight on the invite step
                    // (mirrors FriendsListView).
                    await rankingService.fetchRankedFriends()
                }
            }
        }
    }
    
    // MARK: - Progress Header
    
    private var progressHeader: some View {
        let steps = FlowStep.allCases
        let stepIndex = steps.firstIndex(of: currentStep) ?? 0
        let progress = Double(stepIndex + 1) / Double(steps.count)
        
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 5)
                
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .pink],
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
            case .naming: return !challengeTitle.trimmingCharacters(in: .whitespaces).isEmpty
            case .activityType: return selectedActivity != nil
            case .goalSetting: return selectedOption != nil
            case .settings: return true
            case .inviteFriends: return true
            case .review: return true
            }
        }()
        
        let buttonTitle = currentStep == .review ? "Create Challenge" : "Continue"
        let buttonIcon = currentStep == .review ? "lock.fill" : "arrow.right"
        let buttonColors: [Color] = currentStep == .review ? [.purple, .pink] : [.purple, .blue]
        
        return HStack(spacing: 12) {
            if currentStep != .naming {
                Button(action: { goBack() }) {
                    Image(systemName: "chevron.left")
                        .font(.ds_labelLarge)
                        .foregroundColor(.gray)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(.ultraThinMaterial))
                        .overlay(Circle().stroke(Color.gray.opacity(0.5), lineWidth: 2))
                }
            }
            
            Button(action: {
                if currentStep == .review {
                    Task { await createChallenge() }
                } else {
                    goForward()
                }
            }) {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .purple))
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
                .padding(.vertical, Spacing.md)
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(
                    Capsule().stroke(
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
        .buttonStyle(.plain)
    }
    
    // MARK: - Navigation Logic
    
    private func goForward() {
        withAnimation(.spring(response: 0.3)) {
            switch currentStep {
            case .naming: currentStep = .activityType
            case .activityType: currentStep = .goalSetting
            case .goalSetting: currentStep = .settings
            case .settings: currentStep = .inviteFriends
            case .inviteFriends: currentStep = .review
            case .review: break
            }
        }
        HapticManager.impact(.medium)
    }
    
    private func goBack() {
        withAnimation(.spring(response: 0.3)) {
            switch currentStep {
            case .naming: break
            case .activityType: currentStep = .naming
            case .goalSetting: currentStep = .activityType
            case .settings: currentStep = .goalSetting
            case .inviteFriends: currentStep = .settings
            case .review: currentStep = .inviteFriends
            }
        }
        HapticManager.impact(.light)
    }
    
    // MARK: - Step 1: Naming Card
    
    private var namingCard: some View {
        VStack(spacing: 24) {
            Text("Name Your Challenge")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Give your private challenge a name that inspires your group")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            // Icon picker — emoji or uploaded photo
            VStack(spacing: 12) {
                if let iconImage {
                    iconImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3))
                } else {
                    Text(selectedEmoji)
                        .font(.system(size: 60))
                }
                
                HStack(spacing: 12) {
                    PhotosPicker(selection: $iconPhotoItem, matching: .images) {
                        Label("Upload Icon", systemImage: "photo.fill")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                            )
                    }
                    .onChange(of: iconPhotoItem) { _, newItem in
                        Task {
                            if let newItem,
                               let data = try? await newItem.loadTransferable(type: Data.self) {
                                iconImageData = data
                                if let uiImage = UIImage(data: data) {
                                    iconImage = Image(uiImage: uiImage)
                                }
                                HapticManager.impact(.medium)
                            }
                        }
                    }
                    
                    if iconImage != nil {
                        Button(action: {
                            iconPhotoItem = nil
                            iconImageData = nil
                            iconImage = nil
                            HapticManager.impact(.light)
                        }) {
                            Label("Remove", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(0.12))
                                )
                        }
                    }
                }
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            Button(action: {
                                HapticManager.impact(.light)
                                selectedEmoji = emoji
                                // Clear photo when emoji is tapped
                                if iconImage != nil {
                                    iconPhotoItem = nil
                                    iconImageData = nil
                                    iconImage = nil
                                }
                            }) {
                                Text(emoji)
                                    .font(.ds_heading1)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle()
                                            .fill(selectedEmoji == emoji && iconImage == nil ? Color.purple.opacity(0.3) : Color.white.opacity(0.1))
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                selectedEmoji == emoji && iconImage == nil
                                                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                                    : AnyShapeStyle(Color.clear),
                                                lineWidth: 2
                                            )
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xxs)
                }
            }
            
            // Title field
            VStack(alignment: .leading, spacing: 8) {
                Text("Challenge Name")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
                
                TextField("e.g. Office Step Challenge", text: $challengeTitle)
                    .font(.body)
                    .foregroundColor(.white)
                    .padding(Spacing.md)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .autocorrectionDisabled()
            }
            
            // Description field (optional)
            VStack(alignment: .leading, spacing: 8) {
                Text("Description (optional)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white.opacity(0.7))
                
                TextField("What's this challenge about?", text: $challengeDescription, axis: .vertical)
                    .font(.body)
                    .foregroundColor(.white)
                    .lineLimit(3...5)
                    .padding(Spacing.md)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Step 2: Activity Type
    
    private var activityTypeCard: some View {
        VStack(spacing: 24) {
            Text("What will your group track?")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(ChallengeActivityType.allCases, id: \.self) { activity in
                    ActivityTypeCard(
                        activity: activity,
                        isSelected: selectedActivity == activity,
                        onSelect: {
                            selectedActivity = activity
                            customTarget = getDefaultCustomTarget(activity)
                            hydrationUnit = .ml
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
    
    // MARK: - Step 3: Goal Setting
    
    private var goalSettingCard: some View {
        VStack(spacing: 16) {
            if let activity = selectedActivity {
                Text("Set the \(activity.emoji) Daily Goal")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text("Everyone in the group works toward this target each day")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 10) {
                    // Custom Goal
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
                    
                    HStack(spacing: 12) {
                        Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                        Text("OR").font(.caption).fontWeight(.semibold).foregroundColor(.white.opacity(0.6))
                        Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1)
                    }
                    .padding(.vertical, 2)
                    
                    // Presets
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
    
    
    // MARK: - Step 5: Admin Settings
    
    private var settingsCard: some View {
        VStack(spacing: 24) {
            Text("Challenge Settings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Configure how your private challenge works")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
            
            VStack(spacing: 14) {
                // Leaderboard toggle
                settingsToggleRow(
                    icon: "trophy.fill",
                    iconColor: .yellow,
                    title: "Show Leaderboard",
                    subtitle: "Rank members by daily progress",
                    isOn: $showLeaderboard
                )
                
                // Member invites toggle
                settingsToggleRow(
                    icon: "person.badge.plus",
                    iconColor: .blue,
                    title: "Allow Member Invites",
                    subtitle: "Let any member invite others (not just admins)",
                    isOn: $allowMemberInvites
                )
                
                // Max members stepper
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 40, height: 40)
                            Image(systemName: "person.3.fill")
                                .font(.ds_bodyRegular)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Max Members")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("Limit how many people can join")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                if maxMembers > 5 { maxMembers -= 5 }
                                HapticManager.impact(.light)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.ds_heading2)
                                    .foregroundColor(.white.opacity(0.5))
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                            
                            Text("\(maxMembers)")
                                .font(.ds_statSmall)
                                .foregroundColor(.white)
                                .frame(width: 40)
                            
                            Button(action: {
                                if maxMembers < 200 { maxMembers += 5 }
                                HapticManager.impact(.light)
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.ds_heading2)
                                    .foregroundColor(.purple)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Circle())
                            }
                        }
                    }
                    .padding(Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
            }
            
            // Pro tip
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text("You're the admin. You can change all settings later.")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(.top, 8)
        }
    }
    
    private func settingsToggleRow(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.2))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.ds_bodyRegular)
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
            
            Spacer()
            
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.purple)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Step 5: Invite Friends
    
    private var inviteFriendsCard: some View {
        VStack(spacing: 20) {
            Text("Invite Friends")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("Add friends to invite when the challenge is created. You can always invite more later.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            
            // Selected friends chips
            if !selectedFriends.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedFriends) { friend in
                            HStack(spacing: 6) {
                                CachedFriendPhoto(
                                    friendId: friend.friendId.uuidString,
                                    photoUrl: friend.profilePhotoUrl,
                                    name: friend.friendName ?? "Friend",
                                    size: 24,
                                    showGradientRing: false,
                                    gradientColors: [.purple, .pink]
                                )
                                
                                Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                
                                Button(action: { toggleFriend(friend) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.ds_bodySmall)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.purple.opacity(0.25))
                                    .overlay(Capsule().stroke(Color.purple.opacity(0.4), lineWidth: 1))
                            )
                        }
                    }
                }
                
                Text("\(selectedFriends.count) friend\(selectedFriends.count == 1 ? "" : "s") will be invited")
                    .font(.caption)
                    .foregroundColor(.purple)
            }
            
            // Empty state — keeps "no friends yet" copy in place.
            if friendService.friends.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.ds_heading1)
                        .foregroundColor(.white.opacity(0.4))
                    Text("No friends yet")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                    Text("You can invite friends later from the challenge page")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, Spacing.lg)
            } else {
                // 3×2 top friends highlight — mirrors FriendsListView.
                if showFloatingHeads {
                    topFriendsInviteHighlight
                }
                
                // Search bar
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.ds_bodyRegular)
                    
                    TextField("Search friends", text: $searchText)
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
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(Color.white.opacity(0.1))
                .cornerRadius(CornerRadius.md)
                
                // Scrollable friends list (excludes the 6 already highlighted).
                if !inviteListFriends.isEmpty {
                    LazyVStack(spacing: 10) {
                        ForEach(inviteListFriends) { friend in
                            friendInviteRow(friend: friend)
                        }
                    }
                } else if !searchText.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.ds_heading2)
                            .foregroundColor(.white.opacity(0.4))
                        Text("No friends matching \"\(searchText)\"")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                }
            }
        }
    }
    
    /// 3×2 grid of top friends. Tapping a bubble toggles invite selection.
    private var topFriendsInviteHighlight: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ForEach(highlightMostEngaged) { friend in
                    inviteFriendBubble(friend: friend)
                }
                if highlightMostEngaged.count < 3 {
                    ForEach(0..<(3 - highlightMostEngaged.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            
            if !highlightNewestAdded.isEmpty {
                HStack(spacing: 12) {
                    ForEach(highlightNewestAdded) { friend in
                        inviteFriendBubble(friend: friend)
                    }
                    if highlightNewestAdded.count < 3 {
                        ForEach(0..<(3 - highlightNewestAdded.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }
    
    /// Single bubble used in the 3×2 highlight. Mirrors FriendsListView's
    /// `TopFriendCard` look but adds tap-to-toggle invite behavior.
    private func inviteFriendBubble(friend: Friend) -> some View {
        let isSelected = selectedFriends.contains(where: { $0.friendId == friend.friendId })
        return Button(action: { toggleFriend(friend) }) {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    CachedFriendPhoto(
                        friendId: friend.friendId.uuidString,
                        photoUrl: friend.profilePhotoUrl,
                        name: friend.friendName ?? friend.friendUsername ?? "Friend",
                        size: 60,
                        showGradientRing: isSelected,
                        gradientColors: [.purple, .pink]
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    
                    if isSelected {
                        ZStack {
                            Circle()
                                .fill(Color(white: 0.1))
                                .frame(width: 22, height: 22)
                            Image(systemName: "checkmark.circle.fill")
                                .font(.ds_bodyRegular)
                                .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .offset(x: 4, y: 4)
                    }
                }
                
                Text(friend.friendName?.components(separatedBy: " ").first ?? friend.friendUsername ?? "Friend")
                    .font(.subheadline)
                    .fontWeight(isSelected ? .bold : .semibold)
                    .foregroundColor(isSelected ? .purple : .white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
    
    private func friendInviteRow(friend: Friend) -> some View {
        let isSelected = selectedFriends.contains(where: { $0.friendId == friend.friendId })
        
        return Button(action: { toggleFriend(friend) }) {
            HStack(spacing: 14) {
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 44,
                    showGradientRing: isSelected,
                    gradientColors: [.purple, .pink]
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    if let name = friend.friendName, !name.isEmpty {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    if let username = friend.friendUsername, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Image(systemName: "plus.circle")
                        .font(.ds_heading2)
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? Color.purple.opacity(0.12) : Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isSelected
                                    ? AnyShapeStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    : AnyShapeStyle(Color.white.opacity(0.08)),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func toggleFriend(_ friend: Friend) {
        HapticManager.impact(.medium)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let idx = selectedFriends.firstIndex(where: { $0.friendId == friend.friendId }) {
                selectedFriends.remove(at: idx)
            } else {
                selectedFriends.append(friend)
            }
        }
    }
    
    // MARK: - Step 6: Review Card
    
    private var reviewCard: some View {
        VStack(spacing: 24) {
            Text("Review Your Challenge")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            // Challenge preview card
            VStack(spacing: 16) {
                // Challenge icon + title
                VStack(spacing: 8) {
                    if let iconImage {
                        iconImage
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
                    } else {
                        Text(selectedEmoji)
                            .font(.system(size: 48))
                    }
                    
                    Text(challengeTitle)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    if !challengeDescription.isEmpty {
                        Text(challengeDescription)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    
                    // "Private" badge
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.ds_caption)
                        Text("Private Challenge")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule().fill(Color.purple.opacity(0.15))
                    )
                }
                
                // Details
                VStack(spacing: 12) {
                    if let activity = selectedActivity {
                        reviewRow(title: "Activity", value: "\(activity.emoji) \(activity.rawValue)")
                    }
                    if let option = selectedOption {
                        reviewRow(title: "Daily Goal", value: "\(option.dailyTarget) \(option.unit)")
                    }
                    reviewRow(title: "Leaderboard", value: showLeaderboard ? "Visible" : "Hidden")
                    reviewRow(title: "Member Invites", value: allowMemberInvites ? "Anyone can invite" : "Admin only")
                    reviewRow(title: "Max Members", value: "\(maxMembers)")
                    
                    if !selectedFriends.isEmpty {
                        reviewRow(
                            title: "Inviting",
                            value: "\(selectedFriends.count) friend\(selectedFriends.count == 1 ? "" : "s")"
                        )
                        
                        // Show invited friend avatars
                        HStack(spacing: -8) {
                            ForEach(Array(selectedFriends.prefix(5))) { friend in
                                CachedFriendPhoto(
                                    friendId: friend.friendId.uuidString,
                                    photoUrl: friend.profilePhotoUrl,
                                    name: friend.friendName ?? "Friend",
                                    size: 32,
                                    showGradientRing: false,
                                    gradientColors: [.purple, .pink]
                                )
                                .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                            }
                            if selectedFriends.count > 5 {
                                Circle()
                                    .fill(Color.purple.opacity(0.3))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Text("+\(selectedFriends.count - 5)")
                                            .font(.ds_caption)
                                            .foregroundColor(.white)
                                    )
                                    .overlay(Circle().stroke(Color(white: 0.1), lineWidth: 2))
                            }
                        }
                        .padding(.top, 4)
                    }
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
                                    colors: [Color(white: 0.18), Color.cardBackground],
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
                    }
                )
            }
            
            // You are the admin badge
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                Text("You'll be the admin of this challenge")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }
    
    private func reviewRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Create Challenge
    
    private func createChallenge() async {
        guard let activity = selectedActivity,
              let option = selectedOption else { return }
        
        isCreating = true
        
        let challengeType = activity.rawValue.lowercased()
            .replacingOccurrences(of: " ", with: "_")
        
        // Convert hydration to ml
        var finalDailyTarget = option.dailyTarget
        var finalUnit = option.unit
        if activity == .hydrate && option.unit == "oz" {
            finalDailyTarget = HydrationUnit.oz.convert(value: option.dailyTarget, to: .ml)
            finalUnit = "ml"
        }
        
        let challengeId = await privateChallengeService.createChallenge(
            challengeType: challengeType,
            title: challengeTitle.trimmingCharacters(in: .whitespaces),
            description: challengeDescription.isEmpty ? nil : challengeDescription,
            emoji: selectedEmoji,
            dailyTarget: finalDailyTarget,
            targetUnit: finalUnit,
            isRecurring: true,
            maxMembers: maxMembers,
            allowMemberInvites: allowMemberInvites,
            showLeaderboard: showLeaderboard
        )
        
        if let id = challengeId {
            createdChallengeId = id
            
            // Upload challenge icon if user selected a photo
            if let imageData = iconImageData {
                if let compressed = UIImage(data: imageData)?.jpegData(compressionQuality: 0.8) {
                    do {
                        let _ = try await privateChallengeService.uploadChallengeIcon(
                            challengeId: id,
                            imageData: compressed
                        )
                    } catch {
                        AppLogger.warning("Failed to upload challenge icon: \(error.localizedDescription)", category: .social)
                    }
                }
            }
            
            // Send invites to selected friends
            for friend in selectedFriends {
                let _ = await privateChallengeService.inviteUser(
                    challengeId: id,
                    userId: friend.friendId
                )
            }
            
            isCreating = false
            showingSuccess = true
        } else {
            isCreating = false
            showingError = true
        }
    }
    
    // MARK: - Helpers (same as ChallengeFlowStartView)
    
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
                ChallengeOption(title: "🏋️ Gym Rat", description: "5 sessions per week", dailyTarget: 5, unit: "workouts", isPreset: true, isCustom: false)
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
                ChallengeOption(title: "🥚 Protein Basics", description: "100g daily", dailyTarget: 100, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🍗 Muscle Fuel", description: "150g daily", dailyTarget: 150, unit: "grams", isPreset: true, isCustom: false),
                ChallengeOption(title: "🥩 Gains Machine", description: "200g daily", dailyTarget: 200, unit: "grams", isPreset: true, isCustom: false)
            ]
        case .activeMinutes:
            return [
                ChallengeOption(title: "🧘 Gentle Movement", description: "15 active minutes daily", dailyTarget: 15, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "⏱️ WHO Standard", description: "30 active minutes daily", dailyTarget: 30, unit: "minutes", isPreset: true, isCustom: false),
                ChallengeOption(title: "🔋 Power Hour", description: "60 active minutes daily", dailyTarget: 60, unit: "minutes", isPreset: true, isCustom: false)
            ]
        case .workoutStreak:
            return [
                ChallengeOption(title: "🎯 Daily Grinder", description: "1 workout every day", dailyTarget: 1, unit: "workouts", isPreset: true, isCustom: false)
            ]
        case .sleep:
            return [
                ChallengeOption(title: "💤 Early Bird", description: "6 hours of sleep", dailyTarget: 6, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "😴 Sleep Well", description: "7 hours — science-backed", dailyTarget: 7, unit: "hours", isPreset: true, isCustom: false),
                ChallengeOption(title: "🛏️ Recovery King", description: "8+ hours for peak performance", dailyTarget: 8, unit: "hours", isPreset: true, isCustom: false)
            ]
        }
    }
}

