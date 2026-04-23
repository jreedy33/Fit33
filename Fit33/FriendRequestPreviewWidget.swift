import SwiftUI

// MARK: - Friend Request Preview Widget
/// Shows pending friend requests on the home screen
/// Styled to match GroupChallengeInviteWidget for unified notification carousel

struct FriendRequestPreviewWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject private var friendService = FriendService.shared
    
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var showingDeclineConfirmation = false
    
    private let themeColor: Color = .green
    private let secondaryThemeColor: Color = .teal
    
    var body: some View {
        VStack(spacing: 0) {
            headerSection
            
            Divider().padding(.horizontal, Spacing.md)
            
            detailsSection
            
            Divider().padding(.horizontal, Spacing.md)
            
            actionButtonsSection
        }
        .background(staticCardBackground(accentColor: themeColor, secondaryColor: secondaryThemeColor))
        .shadow(color: themeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: themeColor.opacity(0.08), radius: 25, x: 0, y: 4)
        .confirmationDialog(
            "Decline friend request?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) { declineRequest() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the friend request from \(request.displayName).")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            CachedFriendPhoto(
                friendId: request.fromUserId.uuidString,
                photoUrl: request.profilePhotoUrl,
                name: request.displayName,
                size: 48,
                showGradientRing: true,
                gradientColors: [themeColor, secondaryThemeColor]
            )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Friend Request")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeColor)
                    
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(themeColor))
                }
                
                HStack(spacing: 4) {
                    Text(request.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if request.isVerified == true || request.isGoldVerified == true {
                        VerifiedBadge(size: 13, isGold: request.isGoldVerified == true)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "person.badge.plus")
                .font(.ds_heading1)
                .foregroundStyle(
                    LinearGradient(colors: [themeColor, secondaryThemeColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Details Section
    
    private var detailsSection: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("wants to be your friend")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                if let username = request.fromUserUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text(formatSmartDate(request.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            if let message = request.message, !message.isEmpty {
                Text("\"\(message)\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            Button(action: {
                HapticManager.impact(.light)
                showingDeclineConfirmation = true
            }) {
                HStack(spacing: 4) {
                    if isDeclining {
                        ProgressView().scaleEffect(0.7).tint(.secondary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.gray.opacity(0.12))
                )
            }
            .disabled(isAccepting || isDeclining)
            
            Button(action: acceptRequest) {
                HStack(spacing: 4) {
                    if isAccepting {
                        ProgressView().scaleEffect(0.7).tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.ds_labelMedium)
                    }
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(colors: [themeColor, secondaryThemeColor], startPoint: .leading, endPoint: .trailing))
                )
            }
            .disabled(isAccepting || isDeclining)
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Actions
    
    private func acceptRequest() {
        HapticManager.impact(.medium)
        isAccepting = true
        
        Task {
            let success = await friendService.acceptFriendRequest(requestId: request.requestId)
            if success {
                HapticManager.notification(.success)
                onAccept()
            } else {
                HapticManager.notification(.error)
            }
            isAccepting = false
        }
    }
    
    private func declineRequest() {
        HapticManager.impact(.medium)
        isDeclining = true
        
        Task {
            let success = await friendService.declineFriendRequest(requestId: request.requestId)
            if success {
                HapticManager.notification(.success)
                onDecline()
            } else {
                HapticManager.notification(.error)
            }
            isDeclining = false
        }
    }
    
    // MARK: - Helpers
    
    // Q2-78 (Sprint 8): hoist per-call formatters to `static let` so the smart
    // date label doesn't allocate a `DateFormatter` on every render pass.
    private static let dayOfWeekFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()
    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            return Self.dayOfWeekFormatter.string(from: date)
        } else {
            return Self.monthDayFormatter.string(from: date)
        }
    }
}

// MARK: - Container (kept for backward compat, carousel replaces this on dashboard)

struct FriendRequestPreviewContainer: View {
    @ObservedObject private var friendService = FriendService.shared
    
    var body: some View {
        if let firstRequest = friendService.pendingRequests.first {
            FriendRequestPreviewWidget(
                request: firstRequest,
                onAccept: {},
                onDecline: {}
            )
        }
    }
}

#Preview {
    FriendRequestPreviewContainer()
        .padding()
}
