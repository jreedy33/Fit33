//
//  PrivateChallengeInviteView.swift
//  Fit33
//
//  Invite friends to an existing private challenge.
//  Shows your friends list with invite status per person.
//

import SwiftUI

struct PrivateChallengeInviteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var service = PrivateChallengeService.shared
    
    let challengeId: UUID
    
    @State private var searchText = ""
    @State private var invitingFriends: Set<UUID> = []
    @State private var invitedFriends: Set<UUID> = []
    @State private var inviteErrors: Set<UUID> = []
    
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
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 32))
                            .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                        
                        Text("Invite Friends")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("They'll receive a notification and can accept to join")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                        
                        if !invitedFriends.isEmpty {
                            Text("\(invitedFriends.count) invite\(invitedFriends.count == 1 ? "" : "s") sent ✓")
                                .font(.caption)
                                .foregroundColor(.green)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.green.opacity(0.15)))
                        }
                    }
                    .padding(.top, 8)
                    
                    // Search bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.white.opacity(0.5))
                            .font(.system(size: 16))
                        
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
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    
                    // Friends list
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredFriends) { friend in
                                inviteRow(friend: friend)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                Task { await friendService.fetchFriends() }
            }
        }
    }
    
    private func inviteRow(friend: Friend) -> some View {
        let isInviting = invitingFriends.contains(friend.friendId)
        let isInvited = invitedFriends.contains(friend.friendId)
        let hasError = inviteErrors.contains(friend.friendId)
        
        return HStack(spacing: 14) {
            CachedFriendPhoto(
                friendId: friend.friendId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                size: 44,
                showGradientRing: isInvited,
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
            
            // Invite button
            Button(action: {
                guard !isInvited && !isInviting else { return }
                invitingFriends.insert(friend.friendId)
                inviteErrors.remove(friend.friendId)
                HapticManager.impact(.medium)
                
                Task {
                    let inviteId = await service.inviteUser(
                        challengeId: challengeId,
                        userId: friend.friendId
                    )
                    
                    await MainActor.run {
                        invitingFriends.remove(friend.friendId)
                        if inviteId != nil {
                            invitedFriends.insert(friend.friendId)
                        } else {
                            inviteErrors.insert(friend.friendId)
                        }
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if isInviting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: isInvited ? "checkmark" : (hasError ? "exclamationmark.triangle" : "plus"))
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(isInvited ? "Sent" : (hasError ? "Error" : "Invite"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isInvited ? .green : (hasError ? .orange : .white))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Group {
                        if isInvited {
                            Color.green.opacity(0.15)
                        } else if hasError {
                            Color.orange.opacity(0.15)
                        } else {
                            LinearGradient(colors: [.purple, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .cornerRadius(20)
            }
            .disabled(isInvited || isInviting)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            isInvited ? Color.green.opacity(0.3) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }
}
