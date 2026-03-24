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

// MARK: - Group Challenge Invites Section (Isolated to prevent ChallengeService re-renders from reaching DashboardView)
struct GroupChallengeInvitesSection: View {
    @ObservedObject private var challengeService = ChallengeService.shared
    
    var body: some View {
        ForEach(challengeService.activeGroupChallenges.filter(\.isMyInvitePending)) { group in
            GroupChallengeInviteWidget(challenge: group)
                .padding(.bottom, 16)
        }
    }
}

// MARK: - Friend Notification Badge (Isolated to prevent parent re-renders)
/// Small isolated view that observes FriendService for notification badges
/// This prevents the entire DashboardView from re-rendering when friend data changes
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
