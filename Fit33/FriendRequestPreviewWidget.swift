import SwiftUI

// MARK: - Friend Request Preview Widget
/// Shows pending friend requests on the home screen
/// Appears until user accepts or denies the request

struct FriendRequestPreviewWidget: View {
    @Environment(\.colorScheme) private var colorScheme
    
    @ObservedObject private var friendService = FriendService.shared
    
    let request: FriendRequest
    let onAccept: () -> Void
    let onDecline: () -> Void
    
    @State private var isAccepting = false
    @State private var isDeclining = false
    @State private var showingDeclineConfirmation = false
    
    // Theme colors (green/teal for friend requests)
    private let themeColor: Color = .green
    private let secondaryThemeColor: Color = .teal
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            VStack(spacing: 0) {
                // Header - Request info
                headerSection
                
                Divider()
                    .padding(.horizontal, Spacing.md)
                
                // Action buttons
                actionButtonsSection
            }
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.cardBackground)
                    .shadow(color: themeColor.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [themeColor.opacity(0.4), secondaryThemeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .confirmationDialog(
            "Decline friend request?",
            isPresented: $showingDeclineConfirmation,
            titleVisibility: .visible
        ) {
            Button("Decline", role: .destructive) {
                declineRequest()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the friend request from \(request.displayName).")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack(spacing: 12) {
            // Sender avatar with gradient ring
            senderAvatarView
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Friend Request")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themeColor)
                    
                    // NEW badge
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(themeColor))
                }
                
                Text(request.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Username if available
                if let username = request.fromUserUsername, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Message if available
                if let message = request.message, !message.isEmpty {
                    Text("\"\(message)\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
            
            Spacer()
            
            // Time ago
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatSmartDate(request.createdAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Spacing.md)
    }
    
    // MARK: - Sender Avatar View
    
    private var senderAvatarView: some View {
        ZStack(alignment: .topTrailing) {
            CachedFriendPhoto(
                friendId: request.fromUserId.uuidString,
                photoUrl: request.profilePhotoUrl,
                name: request.displayName,
                size: 52,
                showGradientRing: true,
                gradientColors: [themeColor, secondaryThemeColor]
            )
            
            // Pulsing red dot for new friend requests
            PulsingRedDot()
                .offset(x: 2, y: -2)
        }
    }
    
    // MARK: - Action Buttons Section
    
    private var actionButtonsSection: some View {
        HStack(spacing: 12) {
            // Decline button
            Button(action: {
                HapticManager.impact(.light)
                showingDeclineConfirmation = true
            }) {
                HStack(spacing: 6) {
                    if isDeclining {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.primary)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Decline")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.15))
                )
            }
            .disabled(isAccepting || isDeclining)
            
            // Accept button
            Button(action: acceptRequest) {
                HStack(spacing: 6) {
                    if isAccepting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text("Accept")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [themeColor, secondaryThemeColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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
    
    private func formatSmartDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Container View for Friend Requests
/// Shows pending friend requests on the home screen

struct FriendRequestPreviewContainer: View {
    @ObservedObject private var friendService = FriendService.shared
    
    var body: some View {
        // Show only the first pending request (most recent)
        if let firstRequest = friendService.pendingRequests.first {
            VStack(spacing: 12) {
                // Show the friend request widget
                FriendRequestPreviewWidget(
                    request: firstRequest,
                    onAccept: {
                        // Request accepted - friend will appear in friends list
                        // Widget auto-removes via FriendService state
                    },
                    onDecline: {
                        // Request declined - widget disappears
                        // Widget auto-removes via FriendService state
                    }
                )
                
                // If there are more pending requests, show count
                if friendService.pendingRequests.count > 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text("\(friendService.pendingRequests.count - 1) more request\(friendService.pendingRequests.count > 2 ? "s" : "") waiting")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}

#Preview {
    FriendRequestPreviewContainer()
        .padding()
}
