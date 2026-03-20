//
//  FriendSelectionSheet.swift
//  Fit33
//
//  Quick friend selection for challenge creation
//

import SwiftUI

struct FriendSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    
    let onSelect: (Friend) -> Void
    
    @State private var searchText = ""
    @State private var isLoading = true
    
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
                Color(colorScheme == .dark ? .black : UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if isLoading {
                    ProgressView("Loading friends...")
                        .tint(.blue)
                } else if friendService.friends.isEmpty {
                    emptyStateView
                } else {
                    friendListView
                }
            }
            .navigationTitle("Select Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                print("📋 [FRIEND SELECTION] Sheet appeared")
                // Give cached data a moment to load
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                isLoading = false
                print("📋 [FRIEND SELECTION] Showing \(friendService.friends.count) friends")
            }
        }
        // NavigationStack doesn't need .navigationViewStyle
    }
    
    private var friendListView: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search friends...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
                )
                .padding(.horizontal, Spacing.md)
                .padding(.top, 16)
                
                // Friend list
                LazyVStack(spacing: 12) {
                    ForEach(filteredFriends) { friend in
                        FriendRowButton(friend: friend, onSelect: onSelect)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 8)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Friends Yet")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Add friends to start challenging them!")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct FriendRowButton: View {
    let friend: Friend
    let onSelect: (Friend) -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            print("👤 [FRIEND SELECTION] Selected friend: \(friend.displayName)")
            HapticManager.impact(.light)
            onSelect(friend)
        }) {
            HStack(spacing: 12) {
                // Friend photo
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 50,
                    showGradientRing: false,
                    gradientColors: []
                )
                
                // Friend info
                VStack(alignment: .leading, spacing: 4) {
                    if let name = friend.friendName {
                        Text(name)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    if let username = friend.friendUsername {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.cardBackground : Color.white)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
