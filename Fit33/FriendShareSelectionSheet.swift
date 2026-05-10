import SwiftUI

// MARK: - Friend Share Selection Sheet
//
// Multi-select friend picker (up to 3) used by the share-workout flows
// (`WorkoutCompletionView` "Send Workout to Friend" + `ShareWorkoutSheet`
// "Send to Friend"). Mirrors the "Who do you want to challenge?" page in
// `ChallengeFlowStartView` exactly — same 3-bubble top row that swaps
// selected friends into the leftmost slots, same inline search bar, same
// scrollable frosted `ChallengeFlowFriendCard` rows, same
// `AnimatedOrbBackground.home` blue/cyan orb behind everything.
//
// Returns the chosen friends to the caller via `onConfirm` (then dismisses)
// — does NOT auto-send the workout, so the caller can still surface the
// "add a message" composer + fan out the send through its existing
// pipeline (`FriendService.sendWorkoutToFriend` per friend).
//
// Usage contract:
//   FriendShareSelectionSheet(initialSelection: currentlySelected) { picked in
//       selectedFriends = picked   // dismissal is automatic
//   }
//
// Reuses `TopFriendBubble` + `ChallengeFlowFriendCard` from
// `ChallengeFlowStartView.swift` so the visuals never drift.
//
// See PE invariant in `PRODUCT_ENGINEER_AGENT.md` ("Canonical components
// to REUSE") — NEVER reuse `FriendsListView` for selection (that's the
// friends-management hub, taps route to `FriendProfileView` and dead-end
// the share flow).

struct FriendShareSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared

    let initialSelection: [Friend]
    let maxSelection: Int
    let onConfirm: ([Friend]) -> Void

    @State private var selectedFriends: [Friend] = []
    @State private var searchText: String = ""

    init(
        initialSelection: [Friend] = [],
        maxSelection: Int = 3,
        onConfirm: @escaping ([Friend]) -> Void
    ) {
        self.initialSelection = initialSelection
        self.maxSelection = maxSelection
        self.onConfirm = onConfirm
    }

    // MARK: Derived state

    private var filteredFriends: [Friend] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return friendService.friends
        }
        return friendService.friends.filter { friend in
            let name = friend.friendName ?? ""
            let username = friend.friendUsername ?? ""
            return name.localizedCaseInsensitiveContains(trimmed)
                || username.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Top 3 bubble row. Selected friends always occupy the leftmost slots
    /// — the moment a friend is tapped in the scroll list, they jump up
    /// into the bubble row and push the lowest-priority suggestion out
    /// (matches `ChallengeFlowStartView.friendSelectionContainer`).
    private var topThreeFriends: [Friend] {
        let rankedPool = Array(rankingService.rankedFriends.prefix(8))
        let mostEngaged: [Friend] = rankedPool.compactMap { ranked in
            friendService.friends.first { $0.friendId == ranked.friendId }
        }
        let engagedFallback: [Friend] = mostEngaged.isEmpty
            ? friendService.friends
            : mostEngaged

        var result: [Friend] = Array(selectedFriends.prefix(3))
        var seen = Set(result.map(\.friendId))
        for friend in engagedFallback where result.count < 3 {
            if !seen.contains(friend.friendId) {
                result.append(friend)
                seen.insert(friend.friendId)
            }
        }
        for friend in friendService.friends where result.count < 3 {
            if !seen.contains(friend.friendId) {
                result.append(friend)
                seen.insert(friend.friendId)
            }
        }
        return result
    }

    /// Scrollable list excludes the friends already shown as bubbles to
    /// avoid duplicates (matches the parent challenge-flow behavior).
    private var listFriends: [Friend] {
        let topIds = Set(topThreeFriends.map(\.friendId))
        return filteredFriends.filter { !topIds.contains($0.friendId) }
    }

    private var subtitleText: String {
        switch selectedFriends.count {
        case 0:                  return "Pick up to \(maxSelection) friends"
        case maxSelection:       return "\(maxSelection) selected"
        default:                 return "\(selectedFriends.count) selected — add more?"
        }
    }

    private var ctaTitle: String {
        switch selectedFriends.count {
        case 0:  return "Send Workout"
        case 1:  return "Send to 1 Friend"
        default: return "Send to \(selectedFriends.count) Friends"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.home(colorScheme: colorScheme)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    pinnedTopSection

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    scrollableFriendList
                }

                VStack(spacing: 0) {
                    Spacer()
                    bottomCTA
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.selectionChanged()
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .accessibilityLabel("Cancel friend selection")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .onAppear {
                if selectedFriends.isEmpty && !initialSelection.isEmpty {
                    selectedFriends = Array(initialSelection.prefix(maxSelection))
                }
            }
            .task {
                if friendService.friends.isEmpty {
                    await friendService.fetchFriends()
                }
                if rankingService.rankedFriends.isEmpty {
                    await rankingService.fetchRankedFriends()
                }
            }
        }
    }

    // MARK: - Pinned Top Section (title + subtitle + 3 bubbles + search)

    private var pinnedTopSection: some View {
        VStack(spacing: 16) {
            Text("Who do you want to send this to?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text(subtitleText)
                .font(.caption)
                .foregroundColor(selectedFriends.isEmpty ? .white.opacity(0.6) : .cyan)

            HStack(spacing: 12) {
                let topThree = topThreeFriends
                ForEach(topThree) { friend in
                    TopFriendBubble(
                        friend: friend,
                        isSelected: isFriendSelected(friend)
                    ) {
                        toggleFriendSelection(friend)
                    }
                }
                if topThree.count < 3 {
                    ForEach(0..<(3 - topThree.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }

            inlineFriendSearchBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private var inlineFriendSearchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.5))
                .font(.ds_bodyRegular)

            TextField("Search friends", text: $searchText)
                .font(.body)
                .foregroundColor(.white)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search friends")

            if !searchText.isEmpty {
                Button(action: {
                    HapticManager.impact(.light)
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.5))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.1))
        .cornerRadius(CornerRadius.md)
    }

    // MARK: - Scrollable Friend List

    private var scrollableFriendList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if friendService.friends.isEmpty {
                    emptyFriendsState
                        .padding(.top, Spacing.xl)
                } else if listFriends.isEmpty && !searchText.isEmpty {
                    noMatchesState
                        .padding(.top, Spacing.lg)
                } else {
                    ForEach(listFriends) { friend in
                        ChallengeFlowFriendCard(
                            friend: friend,
                            isSelected: isFriendSelected(friend),
                            onSelect: { toggleFriendSelection($0) }
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 140)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .frame(maxHeight: .infinity)
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 50))
                .foregroundColor(.white.opacity(0.4))
            Text("No friends yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Add friends from the Friends tab to share workouts in-app")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.ds_heading2)
                .foregroundColor(.white.opacity(0.4))
            Text("No friends matching \"\(searchText)\"")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.lg)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom CTA

    private var bottomCTA: some View {
        VStack(spacing: 0) {
            Button(action: confirmSelection) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "paperplane.fill")
                        .font(.ds_labelLarge)
                    Text(ctaTitle)
                        .font(.ds_labelLarge)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(
                            selectedFriends.isEmpty
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.gray.opacity(0.5), Color.gray.opacity(0.4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                  ))
                                : AnyShapeStyle(LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                  ))
                        )
                )
            }
            .scaleButtonStyle(.standard)
            .disabled(selectedFriends.isEmpty)
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.md)
            .accessibilityLabel(ctaTitle)
            .accessibilityHint(
                selectedFriends.isEmpty
                    ? "Select at least one friend first"
                    : "Continues to the message and send step"
            )
        }
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.white.opacity(0.12)),
                    alignment: .top
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Selection Logic

    private func isFriendSelected(_ friend: Friend) -> Bool {
        selectedFriends.contains(where: { $0.friendId == friend.friendId })
    }

    private func toggleFriendSelection(_ friend: Friend) {
        HapticManager.impact(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let idx = selectedFriends.firstIndex(where: { $0.friendId == friend.friendId }) {
                selectedFriends.remove(at: idx)
            } else if selectedFriends.count < maxSelection {
                selectedFriends.append(friend)
            } else {
                // At cap — replace the oldest pick (FIFO) so a tap is never
                // a no-op (matches the challenge-flow behavior).
                selectedFriends.removeFirst()
                selectedFriends.append(friend)
            }
        }
    }

    private func confirmSelection() {
        guard !selectedFriends.isEmpty else { return }
        HapticManager.impact(.medium)
        AppLogger.debug(
            "📤 [SHARE PICKER] Confirmed \(selectedFriends.count) friend(s)",
            category: .social
        )
        let picked = selectedFriends
        onConfirm(picked)
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    FriendShareSelectionSheet { _ in }
}
