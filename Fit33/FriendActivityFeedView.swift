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

struct ActivityExerciseInfo: Codable {
    let name: String
    let sets: Int
    let maxWeight: Double?
    let maxReps: Int?
    
    enum CodingKeys: String, CodingKey {
        case name, sets
        case maxWeight = "max_weight"
        case maxReps = "max_reps"
    }
}

struct ActivityMetadata: Codable {
    let workoutName: String?
    let durationSeconds: Int?
    let exerciseCount: Int?
    let totalSets: Int?
    let xpEarned: Int?
    let muscleGroups: [String]?
    let exercises: [ActivityExerciseInfo]?
    
    enum CodingKeys: String, CodingKey {
        case workoutName = "workout_name"
        case durationSeconds = "duration_seconds"
        case exerciseCount = "exercise_count"
        case totalSets = "total_sets"
        case xpEarned = "xp_earned"
        case muscleGroups = "muscle_groups"
        case exercises
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

    /// Sprint 2 Q2-46 — called from `RealtimeService` when a `friend_activity_feed`
    /// row flips to `is_hidden = true` (moderation webhook). Removes the row
    /// from the in-memory feed so the sender no longer sees their own
    /// flagged post.
    func applyModerationHide(activityId: UUID) {
        activities.removeAll { $0.activityId == activityId }
    }
    
    func fetchFeed() async {
        guard SupabaseManager.shared.isAuthenticated else { return }
        // Sprint 5 M-8: coalesce concurrent feed fetches. The dashboard
        // wrapper + `.task(id: tab)` in `FriendActivityFeedView` + realtime
        // refresh can all fire within a few hundred ms of each other on app
        // resume. Without this, three `get_friend_activity_feed` RPCs run in
        // parallel with three JSON decodes and three `@Published` broadcasts.
        await RequestCoalescer.shared.coalesceVoid(key: "ActivityFeedService.fetchFeed") { [weak self] in
            await self?._fetchFeedBody()
        }
    }

    private func _fetchFeedBody() async {
        await MainActor.run { isLoading = true }

        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                struct FeedParams: Encodable {
                    let p_limit: Int
                    let p_offset: Int
                }
                let result: [FriendActivity] = try await SupabaseManager.shared.supabaseClient
                    .rpc("get_friend_activity_feed", params: FeedParams(p_limit: 20, p_offset: 0))
                    .execute()
                    .value

                // Sprint 2 Q2-7 — defensive client-side filter against stale
                // server responses that predate a block.
                let blocked = await MainActor.run { FriendService.shared.blockedUserIds }
                let filtered = result.filter { !blocked.contains($0.userId) }

                await MainActor.run {
                    self.activities = filtered
                    self.isLoading = false
                }
                return
            } catch is CancellationError {
                AppLogger.debug("🔕 Activity feed fetch cancelled (tab switch)", category: .social)
                await MainActor.run { self.isLoading = false }
                return
            } catch let error as URLError where error.code == .cancelled {
                AppLogger.debug("🔕 Activity feed fetch cancelled (tab switch)", category: .social)
                await MainActor.run { self.isLoading = false }
                return
            } catch {
                if Task.isCancelled { await MainActor.run { self.isLoading = false }; return }
                let nsError = error as NSError
                let isTimeout = nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorTimedOut
                if isTimeout && attempt < maxAttempts {
                    AppLogger.warning("fetchFeed timeout (attempt \(attempt)/\(maxAttempts)), retrying...", category: .social)
                    try? await Task.sleep(for: .seconds(pow(2.0, Double(attempt))))
                } else if isTimeout {
                    AppLogger.warning("❌ Failed to fetch activity feed: \(error)", category: .social)
                } else {
                    AppLogger.error("❌ Failed to fetch activity feed: \(error)", category: .social)
                }
            }
        }
        await MainActor.run { self.isLoading = false }
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
            // Sprint 2 Q2-35 — flush push queue so the activity owner gets a
            // push about the reaction (previously only the in-app badge updated).
            await MainActor.run {
                PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "activity_reaction")
            }
            await fetchFeed()
            return true
        } catch {
            AppLogger.error("❌ Failed to send reaction: \(error)", category: .social)
            return false
        }
    }
    
    func postWorkoutActivity(workoutId: String, name: String, duration: Int, exercises: Int, sets: Int, xp: Int, muscles: [String], exerciseDetails: [[String: Any]] = []) async {
        // Cluster F: guard against posting before auth is ready so we stop
        // emitting 401 fingerprints on this hot path. The RPC is also
        // SECURITY DEFINER — if auth.uid() is NULL it RAISEs, which wraps
        // into a PGRSTxxx error without auth info.
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug(
                "Skipping postWorkoutActivity — not authenticated",
                category: .social,
                context: DiagnosticContext(op: "social.post_workout_activity", endpoint: "rpc/post_workout_activity")
            )
            return
        }
        let startedAt = Date()
        do {
            struct PostParams: Encodable {
                let p_workout_id: String
                let p_workout_name: String
                let p_duration_seconds: Int
                let p_exercise_count: Int
                let p_total_sets: Int
                let p_xp_earned: Int
                let p_muscle_groups: [String]
                let p_exercises_json: String
            }
            
            var exercisesJSON = "[]"
            if !exerciseDetails.isEmpty, JSONSerialization.isValidJSONObject(exerciseDetails) {
                if let data = try? JSONSerialization.data(withJSONObject: exerciseDetails) {
                    exercisesJSON = String(data: data, encoding: .utf8) ?? "[]"
                }
            }
            
            try await SupabaseManager.shared.supabaseClient
                .rpc("post_workout_activity", params: PostParams(
                    p_workout_id: workoutId,
                    p_workout_name: name,
                    p_duration_seconds: duration,
                    p_exercise_count: exercises,
                    p_total_sets: sets,
                    p_xp_earned: xp,
                    p_muscle_groups: muscles,
                    p_exercises_json: exercisesJSON
                ))
                .execute()
        } catch {
            // Captures pg_code (42883 / PGRST202 overload-ambiguity / 42501 RLS)
            // + http_status + elapsed_ms — critical for verifying the
            // 20260513 overload-collapse migration actually fixed this class.
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to post workout activity",
                category: .social,
                op: "social.post_workout_activity",
                endpoint: "rpc/post_workout_activity",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
        }
    }

    /// Sprint 2 Q2-5 — post a cardio_completed row to friend_activity_feed so
    /// cardio workouts show up in friends' feeds the same way strength does.
    func postCardioActivity(
        workoutId: String,
        activityType: String,
        durationSeconds: Int,
        distanceMeters: Double,
        caloriesBurned: Int,
        averageHeartRate: Int?,
        xpEarned: Int
    ) async {
        // Cluster G auth guard — called from workout-completion flow which
        // can fire before session refresh on cold-start networks.
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug(
                "Skipping postCardioActivity — not authenticated",
                category: .social,
                context: DiagnosticContext(op: "social.post_cardio_activity", endpoint: "rpc/post_cardio_activity")
            )
            return
        }
        let startedAt = Date()
        let userId = SupabaseManager.shared.currentUser?.id
        do {
            struct Params: Encodable {
                let p_workout_id: String
                let p_activity_type: String
                let p_duration_seconds: Int
                let p_distance_meters: Double
                let p_calories_burned: Int
                let p_average_heart_rate: Int?
                let p_xp_earned: Int
            }
            try await SupabaseManager.shared.supabaseClient
                .rpc("post_cardio_activity", params: Params(
                    p_workout_id: workoutId,
                    p_activity_type: activityType,
                    p_duration_seconds: durationSeconds,
                    p_distance_meters: distanceMeters,
                    p_calories_burned: caloriesBurned,
                    p_average_heart_rate: averageHeartRate,
                    p_xp_earned: xpEarned
                ))
                .execute()
        } catch {
            // Route through NetworkErrorClassifier so a residual 23514 CHECK
            // violation (fingerprint b66f6c07 pre-20260515) lands with
            // pg_code + http_status + elapsed_ms in the bug_intelligence
            // payload instead of collapsing into "Failed to post cardio
            // activity". Migration 20260515 widened the check constraint
            // to include 'cardio_completed', so we expect this catch to be
            // quiet going forward; if a new invalid value appears, it
            // fingerprints by pg_code.
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to post cardio activity",
                category: .social,
                op: "social.post_cardio_activity",
                endpoint: "rpc/post_cardio_activity",
                startedAt: startedAt,
                userId: userId
            )
        }
    }

    func fetchMyReactions() async {
        // Cluster G: auth guard — this is called from DashboardView.onAppear
        // which fires before auth has had a chance to refresh on cold start.
        guard SupabaseManager.shared.isAuthenticated else {
            AppLogger.debug(
                "Skipping fetchMyReactions — not authenticated",
                category: .social,
                context: DiagnosticContext(op: "activity_feed.my_reactions", endpoint: "rpc/get_my_activity_reactions")
            )
            return
        }
        let startedAt = Date()
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
            // Phase 12c — `transientLevel: .debug` because this is a
            // retry-covered, non-critical read (reactions populate a
            // UI accent; absence = no annotations shown, no user-
            // visible error). Without the demotion, a Cloudflare 502
            // during a deploy window wrote a `.warning` session log
            // that the Phase 10 noise filter eventually caught — but
            // bumping to .debug means it never round-trips at all,
            // saving server noise-filter regex cycles. Matches the
            // pattern used by `CrashReportingService.uploadCrashReport`
            // catch block (Phase 11B).
            _ = NetworkErrorClassifier.log(
                error,
                context: "Failed to fetch my reactions",
                category: .social,
                transientLevel: .debug,
                op: "activity_feed.my_reactions",
                endpoint: "rpc/get_my_activity_reactions",
                startedAt: startedAt,
                userId: SupabaseManager.shared.currentUser?.id
            )
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
        // Sprint 5 M-24 — use the canonical `EmptyStateView` from
        // `DesignSystem.swift` so typography and spacing stay in lock-step
        // with other empty surfaces.
        EmptyStateView(
            icon: "person.2.wave.2.fill",
            title: "No Friend Activity Yet",
            subtitle: "When your friends complete workouts, they'll show up here!"
        )
        .frame(maxWidth: .infinity)
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
    @State private var showReportConfirmation = false
    
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
            // Header — Profile photo + name + level + time + chevron
            headerSection

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
        .contentShape(Rectangle())
        .onTapGesture {
            if activity.workoutId != nil {
                HapticManager.impact(.light)
                showWorkoutPreview = true
            }
        }
        .sleekCard(cornerRadius: CornerRadius.xl, accentColor: muscleGradient.first ?? .cyan)
        .contextMenu {
            // Sprint 2 Q2-7 — long-press Report & Block on feed activities
            Button(role: .destructive) {
                showReportConfirmation = true
            } label: {
                Label("Report & Block", systemImage: "flag.fill")
            }
        }
        .confirmationDialog(
            "Report this post?",
            isPresented: $showReportConfirmation,
            titleVisibility: .visible
        ) {
            Button("Report & Block", role: .destructive) {
                Task {
                    let snippet = (activity.metadata.muscleGroups?.joined(separator: ",") ?? "") +
                        " | type=\(activity.activityType)"
                    _ = await FriendService.shared.reportContent(
                        tableName: "friend_activity_feed",
                        recordId: activity.activityId.uuidString,
                        reportedUserId: activity.userId,
                        contentSnippet: snippet,
                        reason: "Reported from activity feed"
                    )
                    _ = await FriendService.shared.blockUser(userId: activity.userId)
                    HapticManager.notification(.success)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll hide this post, flag it for review, and block \(activity.displayName). You can manage blocks in Settings → Privacy & Security → Blocked Users.")
        }
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
                    .accessibilityHidden(true)
            }
        }
    }
    
    private var profilePhoto: some View {
        CachedFriendPhoto(
            friendId: activity.userId.uuidString,
            photoUrl: activity.userProfilePhotoUrl,
            name: activity.displayName,
            size: 48,
            showGradientRing: true,
            gradientColors: muscleGradient
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
