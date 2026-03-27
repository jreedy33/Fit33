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
    @Environment(\.colorScheme) var colorScheme
    
    @State private var currentPage: Int = 0
    @State private var selectedWorkout: ReceivedWorkoutDTO?
    @State private var navigateToDetail = false
    
    // MARK: - Notification Item Enum
    
    private enum NotificationItem: Identifiable {
        case friendRequest(FriendRequest)
        case receivedWorkout(ReceivedWorkoutDTO)
        case challengeInvite(ChallengeInvite)
        case groupChallenge(ActiveGroupChallenge)
        case privateChallenge(PrivateChallengeInvite)
        
        var id: String {
            switch self {
            case .friendRequest(let r): return "fr-\(r.requestId)"
            case .receivedWorkout(let w): return "rw-\(w.id)"
            case .challengeInvite(let i): return "ci-\(i.challengeId)"
            case .groupChallenge(let g): return "gc-\(g.challengeId)"
            case .privateChallenge(let p): return "pc-\(p.inviteId)"
            }
        }
        
        var date: Date {
            switch self {
            case .friendRequest(let r): return r.createdAt
            case .receivedWorkout(let w): return w.createdAt
            case .challengeInvite(let i): return i.invitedAt
            case .groupChallenge(let g): return g.startDate
            case .privateChallenge(let p): return p.createdAt ?? .distantPast
            }
        }
        
        var isFriendRequest: Bool {
            if case .friendRequest = self { return true }
            return false
        }
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
        
        // Friend requests always first, then oldest-first for the rest
        let friendRequests = items.filter(\.isFriendRequest).sorted { $0.date < $1.date }
        let others = items.filter { !$0.isFriendRequest }.sorted { $0.date < $1.date }
        return friendRequests + others
    }
    
    private var totalCards: Int { notifications.count }
    private var safePage: Int { totalCards > 0 ? min(currentPage, totalCards - 1) : 0 }
    
    // MARK: - Body
    
    var body: some View {
        if totalCards > 0 {
            VStack(spacing: 8) {
                ZStack {
                    ForEach(Array(notifications.enumerated()), id: \.element.id) { index, item in
                        if safePage == index {
                            notificationCard(for: item)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: safePage)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            let hAmount = value.translation.width
                            let vAmount = abs(value.translation.height)
                            guard abs(hAmount) > vAmount * 1.5 && abs(hAmount) > 20 && totalCards > 1 else { return }
                            HapticManager.impact(.medium)
                            if hAmount < 0 && currentPage < totalCards - 1 {
                                currentPage += 1
                            } else if hAmount > 0 && currentPage > 0 {
                                currentPage -= 1
                            }
                        }
                )
                
                HStack(spacing: 6) {
                    ForEach(0..<max(totalCards, 1), id: \.self) { index in
                        Capsule()
                            .fill(safePage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: safePage == index ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: safePage)
                            .onTapGesture {
                                guard totalCards > 1 else { return }
                                HapticManager.impact(.light)
                                currentPage = index
                            }
                    }
                }
                .padding(.vertical, Spacing.xxs)
                .opacity(totalCards > 1 ? 1 : 0)
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
            .onChange(of: totalCards) { oldValue, newValue in
                if newValue < oldValue {
                    currentPage = min(currentPage, max(0, newValue - 1))
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
        }
    }
}
