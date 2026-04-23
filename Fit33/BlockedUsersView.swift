//
//  BlockedUsersView.swift
//  Fit33
//
//  Settings → Privacy & Security → Blocked Users.
//  App Review requires a social app to expose this list with an unblock
//  affordance (Sprint 2 Q2-7).
//

import SwiftUI

struct BlockedUsersView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var friendService = FriendService.shared

    @State private var blockedUsers: [BlockedUser] = []
    @State private var isLoading = false
    @State private var pendingUnblockUserId: UUID?
    @State private var unblockTargetUser: BlockedUser?

    var body: some View {
        ZStack {
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)

            ScrollView {
                VStack(spacing: Spacing.md) {
                    headerCard

                    if isLoading && blockedUsers.isEmpty {
                        loadingState
                    } else if blockedUsers.isEmpty {
                        emptyState
                    } else {
                        blockedList
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)
                .padding(.bottom, Spacing.xl)
            }
            .refreshable {
                await loadBlockedUsers()
            }
        }
        .navigationTitle("Blocked Users")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadBlockedUsers()
        }
        .confirmationDialog(
            "Unblock \(unblockTargetUser?.displayName ?? "this user")?",
            isPresented: Binding(
                get: { unblockTargetUser != nil },
                set: { if !$0 { unblockTargetUser = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = unblockTargetUser {
                Button("Unblock", role: .destructive) {
                    Task { await performUnblock(target) }
                }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("They will be able to see your public profile, add you as a friend, and see your shared activity again.")
        }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "hand.raised.fill")
                    .font(.title3)
                    .foregroundColor(.red)
                Text("Blocked Users")
                    .font(.ds_heading3)
            }
            Text("Blocked users can't see your profile, add you as a friend, react to your posts, or message you. You can unblock someone at any time.")
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    private var loadingState: some View {
        VStack {
            ProgressView()
                .padding(.top, Spacing.xl)
            Text("Loading…")
                .font(.ds_caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        // Q2-91 (Sprint 9 2026-04-28): migrated to shared EmptyStateView so
        // all empty surfaces share typography + spacing.
        EmptyStateView(
            icon: "person.2.slash",
            title: "No one blocked",
            subtitle: "Users you block will appear here. Long-press a message or open a profile to block someone."
        )
        .frame(maxWidth: .infinity)
    }

    private var blockedList: some View {
        VStack(spacing: 0) {
            ForEach(Array(blockedUsers.enumerated()), id: \.element.id) { index, user in
                blockedRow(user: user)
                if index < blockedUsers.count - 1 {
                    Divider().padding(.leading, 68)
                }
            }
        }
        .background(Color.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    private func blockedRow(user: BlockedUser) -> some View {
        HStack(spacing: Spacing.sm) {
            CachedFriendPhoto(
                friendId: user.userId.uuidString,
                photoUrl: user.profilePhotoUrl,
                name: user.displayName,
                size: 44
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.ds_bodyMedium)
                    .foregroundColor(.primary)
                if let username = user.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                unblockTargetUser = user
            } label: {
                if pendingUnblockUserId == user.userId {
                    ProgressView()
                        .frame(width: 80, height: 30)
                } else {
                    Text("Unblock")
                        .font(.ds_caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(Color.primary.opacity(0.08))
                        )
                }
            }
            .disabled(pendingUnblockUserId == user.userId)
            .accessibilityLabel("Unblock \(user.displayName)")
            .accessibilityHint("Removes the block so they can interact with your profile again")
        }
        .padding(Spacing.md)
    }

    // MARK: - Actions

    private func loadBlockedUsers() async {
        isLoading = true
        defer { isLoading = false }
        blockedUsers = await friendService.fetchBlockedUsers()
    }

    private func performUnblock(_ user: BlockedUser) async {
        pendingUnblockUserId = user.userId
        let ok = await friendService.unblockUser(userId: user.userId)
        pendingUnblockUserId = nil
        if ok {
            blockedUsers.removeAll { $0.userId == user.userId }
            HapticManager.notification(.success)
        } else {
            HapticManager.notification(.error)
        }
        unblockTargetUser = nil
    }
}

