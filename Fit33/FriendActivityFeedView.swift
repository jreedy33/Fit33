import SwiftUI

// MARK: - Activity Feed Models

struct FriendActivity: Codable, Identifiable {
    let activityId: UUID
    let userId: UUID
    let userName: String?
    let userUsername: String?
    let userProfilePhotoUrl: String?
    let userLevel: Int
    let activityType: String
    let workoutId: String?
    let metadata: ActivityMetadata
    let createdAt: String
    let reactions: [ActivityReaction]
    let isVerified: Bool?
    let isGoldVerified: Bool?

    var id: UUID { activityId }
    
    var displayName: String {
        if let name = userName, !name.isEmpty { return name }
        if let username = userUsername, !username.isEmpty { return "@\(username)" }
        return "Friend"
    }
    
    var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }
    
    var relativeTime: String {
        guard let date = ISO8601Parser.parse(createdAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        return "\(Int(interval / 604800))w ago"
    }
    
    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case userId = "user_id"
        case userName = "user_name"
        case userUsername = "user_username"
        case userProfilePhotoUrl = "user_profile_photo_url"
        case userLevel = "user_level"
        case activityType = "activity_type"
        case workoutId = "workout_id"
        case metadata
        case createdAt = "created_at"
        case reactions
        case isVerified = "is_verified"
        case isGoldVerified = "is_gold_verified"
    }
}

struct ActivityMetadata: Codable {
    let workoutName: String?
    let durationSeconds: Int?
    let exerciseCount: Int?
    let totalSets: Int?
    let xpEarned: Int?
    let muscleGroups: [String]?
    
    enum CodingKeys: String, CodingKey {
        case workoutName = "workout_name"
        case durationSeconds = "duration_seconds"
        case exerciseCount = "exercise_count"
        case totalSets = "total_sets"
        case xpEarned = "xp_earned"
        case muscleGroups = "muscle_groups"
    }
}

struct ActivityReaction: Codable {
    let senderId: UUID
    let senderName: String?
    let emoji: String
    
    enum CodingKeys: String, CodingKey {
        case senderId = "sender_id"
        case senderName = "sender_name"
        case emoji
    }
}

// MARK: - My Activity Reaction (for home tab stickers)

struct MyActivityReaction: Codable, Identifiable {
    let activityId: UUID
    let workoutId: String?
    let senderId: UUID
    let senderName: String
    let emoji: String
    let reactedAt: String
    
    var id: UUID { activityId }
    
    var senderFirstName: String {
        senderName.split(separator: " ").first.map(String.init) ?? senderName
    }
    
    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case workoutId = "workout_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case emoji
        case reactedAt = "reacted_at"
    }
}

// MARK: - Activity Feed Service

class ActivityFeedService: ObservableObject {
    static let shared = ActivityFeedService()
    
    @Published var activities: [FriendActivity] = []
    @Published var myReactions: [MyActivityReaction] = []
    @Published var isLoading = false
    @Published var lastRealtimeUpdate: Date?
    
    private init() {}
    
    @MainActor
    func removeBlockedUser(_ userId: UUID) {
        activities.removeAll { $0.userId == userId }
    }
    
    func fetchFeed() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        await MainActor.run { isLoading = true }
        
        do {
            struct FeedParams: Encodable {
                let p_limit: Int
                let p_offset: Int
            }
            let result: [FriendActivity] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_friend_activity_feed", params: FeedParams(p_limit: 20, p_offset: 0))
                .execute()
                .value
            
            await MainActor.run {
                self.activities = result
                self.isLoading = false
            }
        } catch is CancellationError {
            AppLogger.debug("🔕 Activity feed fetch cancelled (tab switch)", category: .social)
            await MainActor.run { self.isLoading = false }
        } catch let error as URLError where error.code == .cancelled {
            AppLogger.debug("🔕 Activity feed fetch cancelled (tab switch)", category: .social)
            await MainActor.run { self.isLoading = false }
        } catch {
            AppLogger.error("❌ Failed to fetch activity feed: \(error)", category: .social)
            await MainActor.run { self.isLoading = false }
        }
    }
    
    func sendReaction(activityId: UUID, emoji: String) async -> Bool {
        do {
            struct ReactionParams: Encodable {
                let p_activity_id: String
                let p_emoji: String
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("send_activity_reaction", params: ReactionParams(
                    p_activity_id: activityId.uuidString,
                    p_emoji: emoji
                ))
                .execute()
            
            HapticManager.notification(.success)
            await fetchFeed()
            return true
        } catch {
            AppLogger.error("❌ Failed to send reaction: \(error)", category: .social)
            return false
        }
    }
    
    func postWorkoutActivity(workoutId: String, name: String, duration: Int, exercises: Int, sets: Int, xp: Int, muscles: [String]) async {
        do {
            struct PostParams: Encodable {
                let p_workout_id: String
                let p_workout_name: String
                let p_duration_seconds: Int
                let p_exercise_count: Int
                let p_total_sets: Int
                let p_xp_earned: Int
                let p_muscle_groups: [String]
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("post_workout_activity", params: PostParams(
                    p_workout_id: workoutId,
                    p_workout_name: name,
                    p_duration_seconds: duration,
                    p_exercise_count: exercises,
                    p_total_sets: sets,
                    p_xp_earned: xp,
                    p_muscle_groups: muscles
                ))
                .execute()
        } catch {
            AppLogger.error("❌ Failed to post workout activity: \(error)", category: .social)
        }
    }
    
    func fetchMyReactions() async {
        do {
            struct Params: Encodable {
                let p_limit: Int
            }
            let result: [MyActivityReaction] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_my_activity_reactions", params: Params(p_limit: 10))
                .execute()
                .value
            
            await MainActor.run {
                self.myReactions = result
            }
        } catch {
            AppLogger.error("❌ Failed to fetch my reactions: \(error)", category: .social)
        }
    }
}

// MARK: - Friend Activity Feed Section

struct FriendActivityFeedSection: View {
    @StateObject private var feedService = ActivityFeedService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFullLog = false
    
    private let previewLimit = 3
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(
                    title: "Friend Activity",
                    icon: "person.2.wave.2.fill",
                    iconColor: .cyan
                )
                
                Spacer()
                
                if feedService.activities.count > previewLimit {
                    Button {
                        showFullLog = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("See More")
                                .font(.ds_labelMedium)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.cyan)
                    }
                    .accessibilityLabel("See more friend activity")
                    .accessibilityHint("Opens the full activity log")
                }
            }
            
            if feedService.isLoading && feedService.activities.isEmpty {
                loadingState
            } else if feedService.activities.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(feedService.activities.prefix(previewLimit)) { activity in
                        FriendActivityCard(activity: activity)
                    }
                }
            }
        }
        .task {
            await feedService.fetchFeed()
        }
        .sheet(isPresented: $showFullLog) {
            FriendActivityLogView()
        }
    }
    
    private var loadingState: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
            Text("Loading friend activity...")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
    }
    
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.ds_heading1)
                .foregroundColor(.secondary)
            Text("No Friend Activity Yet")
                .font(.ds_heading3)
                .foregroundColor(.primary)
            Text("When your friends complete workouts, they'll show up here!")
                .font(.ds_bodyMedium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - Full Activity Log View

struct FriendActivityLogView: View {
    @StateObject private var feedService = ActivityFeedService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.friends(colorScheme: colorScheme)
                
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: Spacing.sm) {
                        ForEach(feedService.activities.prefix(20)) { activity in
                            FriendActivityCard(activity: activity)
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await feedService.fetchFeed()
                }
            }
            .navigationTitle("Friend Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.ds_labelLarge)
                        .foregroundColor(.cyan)
                }
            }
        }
    }
}

// MARK: - Friend Activity Card

struct FriendActivityCard: View {
    let activity: FriendActivity
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEmojiPicker = false
    @State private var isSendingReaction = false
    @State private var showWorkoutPreview = false
    @State private var showingProfile: ProfileUser?
    
    private let quickEmojis = ["🔥", "💪", "🙌", "🏆", "👏", "🎯"]
    
    private var muscleGradient: [Color] {
        let primary = activity.metadata.muscleGroups?.first?.lowercased() ?? ""
        switch primary {
        case "chest": return [.red, .orange]
        case "back": return [.blue, .cyan]
        case "legs", "quads", "hamstrings", "glutes": return [.green, .teal]
        case "shoulders": return [.orange, .yellow]
        case "biceps", "triceps", "arms": return [.purple, .pink]
        case "core", "abs": return [.yellow, .orange]
        default: return [.cyan, .blue]
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — Profile photo + name + level + time
            Button {
                if activity.workoutId != nil {
                    showWorkoutPreview = true
                }
            } label: {
                headerSection
            }
            .buttonStyle(.plain)
            
            Divider()
                .padding(.vertical, Spacing.sm)
            
            // Stats row
            statsRow
            
            // Bottom — muscle tags + emoji button
            HStack {
                // Muscle tags
                if let muscles = activity.metadata.muscleGroups, !muscles.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(muscles.prefix(3), id: \.self) { muscle in
                            Text(muscle.capitalized)
                                .font(.ds_caption)
                                .foregroundColor(muscleGradient.first ?? .blue)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(muscleGradient.first?.opacity(0.12) ?? Color.blue.opacity(0.12))
                                )
                        }
                    }
                }
                
                Spacer()
                
                // Emoji reaction button
                emojiButton
            }
            .padding(.top, Spacing.xs)
            
            // Inline emoji picker
            if showEmojiPicker {
                emojiPickerRow
                    .transition(.scale.combined(with: .opacity))
            }
            
            // Show existing reactions
            if !activity.reactions.isEmpty {
                reactionsDisplay
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: muscleGradient.first ?? .cyan)
        .sheet(isPresented: $showWorkoutPreview) {
            if let workoutId = activity.workoutId {
                FriendWorkoutPreviewView(
                    workoutId: workoutId,
                    friendName: activity.displayName,
                    metadata: activity.metadata
                )
                .environmentObject(WorkoutManager.shared)
            }
        }
        .sheet(item: $showingProfile) { profileUser in
            NavigationStack {
                FriendProfileView(user: profileUser)
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Button {
                showingProfile = ProfileUser(activity: activity)
            } label: {
                profilePhoto
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Spacing.xxs) {
                    Button {
                        showingProfile = ProfileUser(activity: activity)
                    } label: {
                        HStack(spacing: 4) {
                            Text(activity.displayName)
                                .font(.ds_heading3)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if activity.isVerified == true || activity.isGoldVerified == true {
                                VerifiedBadge(size: 13, isGold: activity.isGoldVerified == true)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    levelBadge
                }
                
                HStack(spacing: Spacing.xxs) {
                    Text(activity.metadata.workoutName ?? "Workout")
                        .font(.ds_bodyMedium)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text("·")
                        .foregroundColor(.secondary)
                    
                    Text(activity.relativeTime)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if activity.workoutId != nil {
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
    }
    
    private var profilePhoto: some View {
        ZStack {
            if let urlString = activity.userProfilePhotoUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initialsCircle
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            } else {
                initialsCircle
            }
            
            // Gradient ring
            Circle()
                .stroke(
                    LinearGradient(colors: muscleGradient, startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2.5
                )
                .frame(width: 52, height: 52)
        }
    }
    
    private var initialsCircle: some View {
        Circle()
            .fill(
                LinearGradient(colors: muscleGradient.map { $0.opacity(0.3) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: 48, height: 48)
            .overlay(
                Text(String(activity.displayName.prefix(2)).uppercased())
                    .font(.ds_labelLarge)
                    .foregroundColor(muscleGradient.first ?? .blue)
            )
    }
    
    private var levelBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: levelIcon(for: activity.userLevel))
                .font(.system(size: 9))
            Text("Lv.\(activity.userLevel)")
                .font(.ds_caption)
        }
        .foregroundColor(levelColor(for: activity.userLevel))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(levelColor(for: activity.userLevel).opacity(0.12))
        )
    }
    
    private func levelIcon(for level: Int) -> String {
        if level <= 10 { return "bolt.fill" }
        else if level <= 20 { return "star.fill" }
        else if level <= 30 { return "crown.fill" }
        else if level <= 40 { return "diamond.fill" }
        else { return "sparkles" }
    }
    
    private func levelColor(for level: Int) -> Color {
        if level <= 10 { return .cyan }
        else if level <= 20 { return .blue }
        else if level <= 30 { return .purple }
        else if level <= 40 { return .pink }
        else { return .orange }
    }
    
    // MARK: - Stats Row
    
    private var statsRow: some View {
        HStack(spacing: 0) {
            statCell(icon: "clock.fill", value: formatDuration(activity.metadata.durationSeconds ?? 0), label: "Duration")
            statDivider
            statCell(icon: "figure.strengthtraining.traditional", value: "\(activity.metadata.exerciseCount ?? 0)", label: "Exercises")
            statDivider
            statCell(icon: "repeat", value: "\(activity.metadata.totalSets ?? 0)", label: "Sets")
            statDivider
            statCell(icon: "star.fill", iconColor: .orange, value: "+\(activity.metadata.xpEarned ?? 0)", label: "XP")
        }
    }
    
    private func statCell(icon: String, iconColor: Color? = nil, value: String, label: String) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.ds_caption)
                    .foregroundColor(iconColor ?? muscleGradient.first ?? .blue)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }
            Text(label)
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var statDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 30)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let mins = seconds / 60
        if mins < 60 { return "\(mins)m" }
        return "\(mins / 60)h \(mins % 60)m"
    }
    
    // MARK: - Emoji Reaction
    
    private var emojiButton: some View {
        Button {
            HapticManager.impact(.light)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showEmojiPicker.toggle()
            }
        } label: {
            Image(systemName: showEmojiPicker ? "xmark.circle.fill" : "face.smiling")
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        }
        .buttonStyle(.plain)
    }
    
    private var emojiPickerRow: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(quickEmojis, id: \.self) { emoji in
                Button {
                    Task {
                        isSendingReaction = true
                        withAnimation { showEmojiPicker = false }
                        await ActivityFeedService.shared.sendReaction(activityId: activity.activityId, emoji: emoji)
                        isSendingReaction = false
                    }
                } label: {
                    Text(emoji)
                        .font(.ds_heading2)
                }
                .buttonStyle(.plain)
                .scaleEffect(isSendingReaction ? 0.8 : 1.0)
                .animation(.spring(response: 0.2), value: isSendingReaction)
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(maxWidth: .infinity)
    }
    
    private var reactionsDisplay: some View {
        HStack(spacing: 4) {
            ForEach(Array(activity.reactions.enumerated()), id: \.offset) { _, reaction in
                HStack(spacing: 2) {
                    Text(reaction.emoji)
                        .font(.ds_bodySmall)
                    Text(reaction.senderName?.split(separator: " ").first.map(String.init) ?? "Friend")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.1))
                )
            }
        }
    }
}
