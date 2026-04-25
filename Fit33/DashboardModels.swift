import SwiftUI

// MARK: - Dashboard Navigation Route

enum DashboardRoute: Hashable {
    case profile
    case mealPlan
    case workoutHistory
    case programDetailsPlaceholder
    case generatedProgramsList
    case personalizedPrograms
    case smartWorkoutPreview  // uses GeneratedProgramService.shared
    case smartProgramOverview(programId: String)
    case smartProgramDayPreview(programId: String, dayNumber: Int)
    case stravaSettings
    case whoopSettings
}

enum WorkoutCreationType {
    case custom
    case generated
}

enum PendingWorkoutType {
    case custom
    case auto
}

// MARK: - Program Stat Pill Component
struct ProgramStatPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.xs)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    }
}

// MARK: - Friend Notification Badge (Isolated to prevent parent re-renders)

struct FriendNotificationBadge: View {
    @ObservedObject private var friendService = FriendService.shared
    
    var body: some View {
        if friendService.pendingRequests.count > 0 || friendService.unreadWorkoutCount > 0 {
            Circle()
                .fill(Color.red)
                .frame(width: 14, height: 14)
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

// MARK: - Unified Notification Carousel

/// Combines all dashboard notification types into a single swipeable carousel.
/// Friend requests always appear first, then other notifications sorted oldest-first.
/// Isolated View struct per widget isolation rule — owns all service subscriptions.
struct DashboardNotificationCarousel: View {
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var challengeService = ChallengeService.shared
    @ObservedObject private var privateChallengeService = PrivateChallengeService.shared
    @ObservedObject private var stravaService = StravaService.shared
    @Environment(\.colorScheme) var colorScheme
    
    @State private var selectedWorkout: ReceivedWorkoutDTO?
    @State private var navigateToDetail = false
    @State private var selectedStravaActivity: StravaActivity?
    @State private var showingStravaRecap = false
    /// Activities the user has already swiped away — persisted across launches
    /// so we don't re-surface the same recap card after every dashboard refresh.
    @AppStorage("dismissed_strava_recap_ids") private var dismissedStravaIDsCSV: String = ""

    /// Window for surfacing a fresh Strava activity in the carousel.
    /// Shorter than the dashboard widget's 36h window — once a user has had
    /// the chance to glance at the recap card we move on.
    private static let stravaRecapWindow: TimeInterval = 6 * 60 * 60
    
    // MARK: - Notification Item Enum
    
    private enum NotificationItem: Identifiable {
        case friendRequest(FriendRequest)
        case receivedWorkout(ReceivedWorkoutDTO)
        case challengeInvite(ChallengeInvite)
        case groupChallenge(ActiveGroupChallenge)
        case privateChallenge(PrivateChallengeInvite)
        case stravaRecap(StravaActivity)

        var id: String {
            switch self {
            case .friendRequest(let r): return "fr-\(r.requestId)"
            case .receivedWorkout(let w): return "rw-\(w.id)"
            case .challengeInvite(let i): return "ci-\(i.challengeId)"
            case .groupChallenge(let g): return "gc-\(g.challengeId)"
            case .privateChallenge(let p): return "pc-\(p.inviteId)"
            case .stravaRecap(let a): return "sr-\(a.id)"
            }
        }
        
        var date: Date {
            switch self {
            case .friendRequest(let r): return r.createdAt
            case .receivedWorkout(let w): return w.createdAt
            case .challengeInvite(let i): return i.invitedAt
            case .groupChallenge(let g): return g.startDate
            case .privateChallenge(let p): return p.createdAt ?? .distantPast
            case .stravaRecap(let a): return a.startDate
            }
        }
        
        var isFriendRequest: Bool {
            if case .friendRequest = self { return true }
            return false
        }
    }

    private var dismissedStravaIDs: Set<String> {
        Set(dismissedStravaIDsCSV.split(separator: ",").map(String.init))
    }

    private var freshStravaActivity: StravaActivity? {
        guard stravaService.isConnected else { return nil }
        let cutoff = Date().addingTimeInterval(-Self.stravaRecapWindow)
        let dismissed = dismissedStravaIDs
        return stravaService.recentActivities
            .filter { $0.startDate >= cutoff && !dismissed.contains(String($0.id)) }
            .sorted { $0.startDate > $1.startDate }
            .first
    }

    private func dismissStravaRecap(activityId: Int64) {
        var ids = dismissedStravaIDs
        ids.insert(String(activityId))
        // Cap the persisted set so it doesn't grow forever; we only need the
        // last ~50 activity ids to suppress repeats.
        let trimmed = Array(ids).suffix(50)
        dismissedStravaIDsCSV = trimmed.joined(separator: ",")
    }
    
    // MARK: - Data
    
    private var notifications: [NotificationItem] {
        var items: [NotificationItem] = []
        
        for r in friendService.pendingRequests {
            items.append(.friendRequest(r))
        }
        for w in friendService.receivedWorkouts where w.isPending {
            items.append(.receivedWorkout(w))
        }
        for i in challengeService.pendingInvites {
            items.append(.challengeInvite(i))
        }
        for g in challengeService.activeGroupChallenges where g.isMyInvitePending {
            items.append(.groupChallenge(g))
        }
        for p in privateChallengeService.pendingInvites {
            items.append(.privateChallenge(p))
        }
        if let stravaActivity = freshStravaActivity {
            items.append(.stravaRecap(stravaActivity))
        }
        
        // Friend requests always first, then oldest-first for the rest
        let friendRequests = items.filter(\.isFriendRequest).sorted { $0.date < $1.date }
        let others = items.filter { !$0.isFriendRequest }.sorted { $0.date < $1.date }
        return friendRequests + others
    }
    
    private var totalCards: Int { notifications.count }
    @State private var scrolledID: String?
    
    private var activeIndex: Int {
        guard let scrolledID, totalCards > 0 else { return 0 }
        return notifications.firstIndex(where: { $0.id == scrolledID }) ?? 0
    }
    
    // MARK: - Body
    
    var body: some View {
        if totalCards > 0 {
            VStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(notifications) { item in
                            notificationCard(for: item)
                                .containerRelativeFrame(.horizontal, count: 1, spacing: 0)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledID)
                .scrollClipDisabled()
                
                if totalCards > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<totalCards, id: \.self) { index in
                            Capsule()
                                .fill(activeIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                .frame(width: activeIndex == index ? 20 : 8, height: 6)
                                .animation(.easeOut(duration: 0.2), value: activeIndex)
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
            }
            .onChange(of: scrolledID) { _, _ in
                HapticManager.impact(.light)
            }
            .background(
                NavigationLink(
                    destination: Group {
                        if let workout = selectedWorkout {
                            ReceivedWorkoutDetailView(workout: workout)
                        }
                    },
                    isActive: $navigateToDetail
                ) {
                    EmptyView()
                }
                .hidden()
            )
            .sheet(isPresented: $showingStravaRecap) {
                if let selectedStravaActivity {
                    StravaActivityRecapSheet(activity: selectedStravaActivity)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    // MARK: - Card Rendering
    
    @ViewBuilder
    private func notificationCard(for item: NotificationItem) -> some View {
        switch item {
        case .friendRequest(let request):
            FriendRequestPreviewWidget(
                request: request,
                onAccept: {},
                onDecline: {}
            )
            
        case .receivedWorkout(let workout):
            ReceivedWorkoutPreviewWidget(
                workout: workout,
                onStart: {
                    selectedWorkout = workout
                    navigateToDetail = true
                    Task {
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        await friendService.markWorkoutStarted(workoutId: workout.id)
                    }
                },
                onDismiss: {}
            )
            
        case .challengeInvite(let invite):
            ChallengePreviewWidget(
                invite: invite,
                onAccept: {},
                onDecline: {}
            )
            
        case .groupChallenge(let challenge):
            GroupChallengeInviteWidget(challenge: challenge)
            
        case .privateChallenge(let invite):
            PrivateChallengeInviteWidget(invite: invite)

        case .stravaRecap(let activity):
            StravaRecapNotificationCard(
                activity: activity,
                onTap: {
                    HapticManager.tap()
                    selectedStravaActivity = activity
                    showingStravaRecap = true
                },
                onDismiss: {
                    HapticManager.impact(.light)
                    dismissStravaRecap(activityId: activity.id)
                }
            )
        }
    }
}

// MARK: - Strava Recap Notification Card

/// Small carousel card surfaced on the dashboard the first few hours after a
/// Strava activity is detected. Tap → opens the full recap sheet. Dismiss →
/// hides the card permanently for that activity id.
struct StravaRecapNotificationCard: View {
    let activity: StravaActivity
    let onTap: () -> Void
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Color.stravaOrange.opacity(colorScheme == .dark ? 0.22 : 0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: activity.activityIcon)
                        .font(.title3)
                        .foregroundColor(Color.stravaOrange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("New Strava \(activity.type)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(summaryLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Dismiss Strava recap")
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.stravaOrange.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityHint("Tap to see splits and effort details")
    }

    private var summaryLine: String {
        var parts: [String] = [activity.distanceFormatted, activity.durationFormatted]
        if let pace = activity.paceFormatted { parts.append(pace) }
        return parts.joined(separator: " • ")
    }
}
