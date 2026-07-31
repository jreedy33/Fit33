import SwiftUI

struct DashboardChallengesWrapper: View {
    @StateObject private var challengeService = ChallengeService.shared
    /// Subscribes to incoming dashboard battle cries so the carousel
    /// can re-sort the moment a cry lands and surface that challenge
    /// at page 0. The published `dashboardIncomingBattleCryByChallenge`
    /// dictionary is the canonical source — see
    /// `Array<ActiveChallenge>.sortedByOpponentFreshness` in
    /// ChallengeService.swift.
    @StateObject private var realtimeService = RealtimeService.shared
    @EnvironmentObject var userManager: UserManager
    @Environment(\.colorScheme) var colorScheme
    @State private var selectedWidgetPage: Int = 0
    @State private var bottomRowPage: Int = 0
    @State private var challengeGlowPhase: CGFloat = 0
    @State private var challengeToCancel: UUID?
    @AppStorage("showChallengeWidget") private var showChallengeWidget = true
    @Binding var showingChallengeCreation: Bool
    var reducedGlow: Bool = false
    var stackedMode: Bool = false
    
    // MARK: - Body
    
    var body: some View {
        if stackedMode {
            stackedChallengesBody
        } else {
            singleCarouselBody
        }
    }
    
    // MARK: - Stacked Mode (two independent carousels, sorted by type)
    
    @ViewBuilder
    private var stackedChallengesBody: some View {
        let activeIds = Set(challengeService.activeChallenges.map { $0.id })
        // Sort by opponent freshness + incoming battle cries BEFORE
        // truncating so attention-worthy challenges are guaranteed to
        // make the cut (and land on page 0). Battle-cry challenges win
        // the top slot so the user sees the `BattleCryShoutBubble`
        // overlay without a swipe. See
        // `Array<ActiveChallenge>.sortedByOpponentFreshness` in
        // ChallengeService.swift for tier definitions.
        let battleCryChallengeIds = Set(realtimeService.dashboardIncomingBattleCryByChallenge.keys)
        let activeChallenges = Array(
            challengeService.activeChallenges
                .sortedByOpponentFreshness(incomingBattleCryChallengeIds: battleCryChallengeIds)
                .prefix(8)
        )
        let groupChallenges = challengeService.activeGroupChallenges.filter { $0.iHaveAccepted }
        let activeCount = activeChallenges.count + groupChallenges.count
        
        let remainingSlots = max(0, 8 - activeCount)
        var seenPendingIds = Set<UUID>()
        let pendingSent = challengeService.pendingSentChallenges
            .filter { pending in
                guard !pending.title.isEmpty && pending.durationDays > 0 else { return false }
                guard !activeIds.contains(pending.challengeId) else { return false }
                guard !seenPendingIds.contains(pending.challengeId) else { return false }
                seenPendingIds.insert(pending.challengeId)
                return true
            }
            .prefix(remainingSlots)
        let pendingArray = Array(pendingSent)
        
        let typeSorted: [StackedChallengeItem] = (
            activeChallenges.map { StackedChallengeItem.active($0) } +
            groupChallenges.map { .group($0) } +
            pendingArray.map { .pending($0) }
        ).sorted { $0.typeKey < $1.typeKey }
        
        // The type-alphabetical sort above scatters challenges by type for
        // a clean visual grouping, but it would also push a challenge with
        // a pending battle cry off page 0 if its `typeKey` happened to
        // sort late. Hoist any active challenge whose opponent has just
        // shouted at us back to the front so the user lands on that card
        // and the `BattleCryShoutBubble` overlay paints without a swipe.
        // (Group / pending items have no battle-cry signal today.)
        //
        // Wrapped in a closure because SwiftUI's `@ViewBuilder` doesn't
        // allow `for` / `var` at the top-level of the body — the closure
        // hides the imperative work behind a single returned value.
        let allItems: [StackedChallengeItem] = {
            guard !battleCryChallengeIds.isEmpty else { return typeSorted }
            var bumped: [StackedChallengeItem] = []
            var rest: [StackedChallengeItem] = []
            for item in typeSorted {
                if case .active(let c) = item, battleCryChallengeIds.contains(c.challengeId) {
                    bumped.append(item)
                } else {
                    rest.append(item)
                }
            }
            return bumped + rest
        }()
        
        if allItems.isEmpty {
            getStartedChallengeWidget
        } else if allItems.count == 1 {
            stackedRowCarousel(items: allItems, page: $selectedWidgetPage)
        } else {
            let midpoint = (allItems.count + 1) / 2
            let topItems = Array(allItems.prefix(midpoint))
            let bottomItems = Array(allItems.suffix(from: midpoint))
            
            VStack(spacing: 10) {
                stackedRowCarousel(items: topItems, page: $selectedWidgetPage)
                stackedRowCarousel(items: bottomItems, page: $bottomRowPage)
            }
            .onChange(of: challengeService.activeChallenges.count) { _, _ in
                selectedWidgetPage = 0
                bottomRowPage = 0
            }
            .onChange(of: challengeService.activeGroupChallenges.count) { _, _ in
                selectedWidgetPage = 0
                bottomRowPage = 0
            }
            // When a fresh battle cry lands (e.g. via realtime / silent push
            // while the dashboard is visible, or on app foreground hydration
            // of the sticky buffer), snap both rows back to page 0 so the
            // freshly-prioritized card is the one the user sees.
            .onChange(of: battleCryChallengeIds) { _, _ in
                selectedWidgetPage = 0
                bottomRowPage = 0
            }
        }
    }
    
    @ViewBuilder
    private func stackedRowCarousel(items: [StackedChallengeItem], page: Binding<Int>) -> some View {
        let count = items.count
        let safePage = count > 0 ? min(max(0, page.wrappedValue), count - 1) : 0
        
        if count > 1 {
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    let cardWidth = geometry.size.width
                    let spacing: CGFloat = 16
                    
                    HStack(spacing: spacing) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            stackedItemView(item)
                                .frame(width: cardWidth)
                                .opacity(safePage == index ? 1 : 0)
                        }
                    }
                    .offset(x: -CGFloat(safePage) * (cardWidth + spacing))
                }
                .frame(height: 156)
                .animation(.easeOut(duration: 0.2), value: safePage)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { value in
                            let h = value.translation.width
                            let v = abs(value.translation.height)
                            if abs(h) > v * 1.5 && abs(h) > 20 {
                                HapticManager.impact(.medium)
                                if h < 0 && page.wrappedValue < count - 1 {
                                    page.wrappedValue += 1
                                } else if h > 0 && page.wrappedValue > 0 {
                                    page.wrappedValue -= 1
                                }
                            }
                        }
                )
                
                HStack(spacing: 6) {
                    ForEach(0..<count, id: \.self) { index in
                        Capsule()
                            .fill(safePage == index ? Color.orange : Color.gray.opacity(0.3))
                            .frame(width: safePage == index ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: safePage)
                            .onTapGesture {
                                HapticManager.impact(.light)
                                page.wrappedValue = index
                            }
                    }
                }
                .padding(.vertical, Spacing.xxs)
            }
        } else if let item = items.first {
            // Pin the single-item row to the same 156pt height the
            // multi-item carousel uses so a row with one challenge
            // matches the size of a row with multiple. Without this
            // the row collapses to the widget's intrinsic height,
            // making "top vs bottom" stacked rows look mismatched.
            stackedItemView(item)
                .frame(height: 156)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 25)
                        .onEnded { _ in }
                )
        }
    }
    
    @ViewBuilder
    private func stackedItemView(_ item: StackedChallengeItem) -> some View {
        switch item {
        case .active(let c):
            activeChallengeDetailWidget(challenge: c)
        case .group(let g):
            groupChallengeWidget(challenge: g)
        case .pending(let p):
            pendingSentChallengeWidget(challenge: p)
        }
    }
    
    // MARK: - Single Carousel Mode (original)
    
    @ViewBuilder
    private var singleCarouselBody: some View {
        // PRIORITY ORDER:
        // 1. Active challenges ALWAYS show first (up to 3)
        // 2. Pending sent challenges fill remaining slots (up to 3 total cards max)
        // 3. If only pending (no active), also show "Challenge a Friend" as swipeable option
        // 4. If no active AND no pending → show default "Challenge a Friend" widget only
        
        // Get active challenges (deduplicated by ID)
        // Sort by opponent freshness + incoming battle cries BEFORE the
        // 3-card cap so a challenge where the opponent has updated today
        // (or just sent a battle cry) wins page 0 over a stale sibling
        // card (opponent at 0 with hours-old `last_progress_at`). See
        // `Array<ActiveChallenge>.sortedByOpponentFreshness` in
        // ChallengeService.swift for tier definitions.
        let activeIds = Set(challengeService.activeChallenges.map { $0.id })
        let battleCryChallengeIds = Set(realtimeService.dashboardIncomingBattleCryByChallenge.keys)
        let activeChallenges = Array(
            challengeService.activeChallenges
                .sortedByOpponentFreshness(incomingBattleCryChallengeIds: battleCryChallengeIds)
                .prefix(3)
        )
        let groupChallenges = challengeService.activeGroupChallenges.filter { $0.iHaveAccepted }
        let activeCount = activeChallenges.count + groupChallenges.count
        
        // Only show pending if we have room (max 3 total cards)
        // CRITICAL: Filter out any pending that also appears in active (duplicate IDs)
        // Also filter invalid data and deduplicate
        let remainingSlots = max(0, 3 - activeCount)
        var seenPendingIds = Set<UUID>()
        let pendingSent = challengeService.pendingSentChallenges
            .filter { pending in
                // Must have valid data
                guard !pending.title.isEmpty && pending.durationDays > 0 else { return false }
                // Must not be a duplicate of an active challenge
                guard !activeIds.contains(pending.challengeId) else { return false }
                // Must not be a duplicate within pending list
                guard !seenPendingIds.contains(pending.challengeId) else { return false }
                seenPendingIds.insert(pending.challengeId)
                return true
            }
            .prefix(remainingSlots)
        let pendingArray = Array(pendingSent)
        let pendingCount = pendingArray.count
        
        // Show "Challenge a Friend" as a swipeable card whenever total cards < 3
        let challengeCardCount = activeCount + pendingCount
        let showDefaultInCarousel = challengeCardCount < 3
        let totalWidgetCount = challengeCardCount + (showDefaultInCarousel ? 1 : 0)
        
        // Clamp the page to valid range - this ensures we always show SOMETHING
        let safePageIndex = totalWidgetCount > 0 ? min(max(0, selectedWidgetPage), totalWidgetCount - 1) : 0
        
        Group {
            if totalWidgetCount > 0 {
                VStack(spacing: 4) {
                    if totalWidgetCount > 1 {
                        // Multiple cards - swipeable (max 3 cards)
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                // Active 1v1 challenges FIRST
                                ForEach(Array(activeChallenges.enumerated()), id: \.element.id) { index, challenge in
                                    activeChallengeDetailWidget(challenge: challenge)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == index ? 1 : 0)
                                }
                                // Group challenges
                                ForEach(Array(groupChallenges.enumerated()), id: \.element.id) { index, group in
                                    groupChallengeWidget(challenge: group)
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeChallenges.count + index) ? 1 : 0)
                                }
                                // Then pending sent challenges
                                ForEach(Array(pendingArray.enumerated()), id: \.offset) { index, pending in
                                    pendingSentChallengeWidget(challenge: pending)
                                        .id("\(pending.challengeId)-\(pending.opponentId)")
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + index) ? 1 : 0)
                                }
                                // Then "Challenge a Friend" widget (if only pending, no active)
                                if showDefaultInCarousel {
                                    getStartedChallengeWidget
                                        .frame(width: cardWidth)
                                        .opacity(safePageIndex == (activeCount + pendingCount) ? 1 : 0)
                                }
                            }
                            .offset(x: -CGFloat(safePageIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: safePageIndex)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    // Use the same calculation logic as above (including group challenges)
                                    let activeIdsNow = Set(challengeService.activeChallenges.map { $0.id })
                                    let currentActiveCount = min(3, challengeService.activeChallenges.count) + challengeService.activeGroupChallenges.count
                                    var seenNow = Set<UUID>()
                                    let currentPendingCount = challengeService.pendingSentChallenges
                                        .filter { p in
                                            guard !p.title.isEmpty && p.durationDays > 0 else { return false }
                                            guard !activeIdsNow.contains(p.challengeId) else { return false }
                                            guard !seenNow.contains(p.challengeId) else { return false }
                                            seenNow.insert(p.challengeId)
                                            return true
                                        }
                                        .prefix(max(0, 3 - currentActiveCount))
                                        .count
                                    let currentCardCount = currentActiveCount + currentPendingCount
                                    let hasDefaultWidget = currentCardCount < 3
                                    let currentTotal = currentCardCount + (hasDefaultWidget ? 1 : 0)
                                    
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 && currentTotal > 0 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && selectedWidgetPage < currentTotal - 1 {
                                            selectedWidgetPage += 1
                                        } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                            selectedWidgetPage -= 1
                                        }
                                    }
                                }
                        )
                        
                        // Page indicators (dash and dot style)
                        HStack(spacing: 6) {
                            ForEach(0..<totalWidgetCount, id: \.self) { index in
                                Capsule()
                                    .fill(safePageIndex == index ? Color.blue : Color.gray.opacity(0.3))
                                    .frame(width: safePageIndex == index ? 20 : 8, height: 6)
                                    .animation(.easeOut(duration: 0.2), value: safePageIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        selectedWidgetPage = index
                                    }
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    } else if let activeChallenge = activeChallenges.first {
                        activeChallengeDetailWidget(challenge: activeChallenge)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 25)
                                    .onEnded { _ in }
                            )
                    } else if let groupChallenge = groupChallenges.first {
                        groupChallengeWidget(challenge: groupChallenge)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 25)
                                    .onEnded { _ in }
                            )
                    } else if challengeCardCount == 0 && showDefaultInCarousel {
                        // No challenges — show the "Challenge a Friend" entry widget.
                        // (Previously this case fell through to an empty VStack because
                        // totalWidgetCount is always >= 1 whenever showDefaultInCarousel
                        // is true, making the outer `else` branch unreachable.)
                        getStartedChallengeWidget
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 25)
                                    .onEnded { _ in }
                            )
                    } else if let firstPending = pendingArray.first {
                        // Single pending (show with default widget as carousel)
                        // When single pending exists, show it + default widget
                        let singlePendingCount = 2 // pending + default
                        let singleSafeIndex = min(max(0, selectedWidgetPage), singlePendingCount - 1)
                        
                        GeometryReader { geometry in
                            let cardWidth = geometry.size.width
                            let spacing: CGFloat = 16
                            
                            HStack(spacing: spacing) {
                                pendingSentChallengeWidget(challenge: firstPending)
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 0 ? 1 : 0)
                                
                                getStartedChallengeWidget
                                    .frame(width: cardWidth)
                                    .opacity(singleSafeIndex == 1 ? 1 : 0)
                            }
                            .offset(x: -CGFloat(singleSafeIndex) * (cardWidth + spacing))
                        }
                        .frame(height: 156)
                        .animation(.easeOut(duration: 0.2), value: selectedWidgetPage)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 25)
                                .onEnded { value in
                                    let horizontalAmount = value.translation.width
                                    let verticalAmount = abs(value.translation.height)
                                    
                                    if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                        HapticManager.impact(.medium)
                                        if horizontalAmount < 0 && selectedWidgetPage < 1 {
                                            selectedWidgetPage = 1
                                        } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                            selectedWidgetPage = 0
                                        }
                                    }
                                }
                        )
                        
                        // Page indicators for single pending
                        HStack(spacing: 6) {
                            ForEach(0..<2, id: \.self) { index in
                                Circle()
                                    .fill(singleSafeIndex == index ? Color.orange : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(singleSafeIndex == index ? 1.0 : 0.8)
                                    .animation(.easeOut(duration: 0.2), value: singleSafeIndex)
                                    .onTapGesture {
                                        HapticManager.impact(.light)
                                        selectedWidgetPage = index
                                    }
                            }
                        }
                        .padding(.vertical, Spacing.xxs)
                    }
                }
                .onChange(of: challengeService.activeChallenges.count) { _, newCount in
                    let total = newCount + challengeService.pendingSentChallenges.count + (newCount + challengeService.pendingSentChallenges.count < 3 ? 1 : 0)
                    if selectedWidgetPage >= total {
                        selectedWidgetPage = max(0, total - 1)
                    }
                }
                .onChange(of: challengeService.pendingSentChallenges.count) { _, newCount in
                    let total = challengeService.activeChallenges.count + newCount + (challengeService.activeChallenges.count + newCount < 3 ? 1 : 0)
                    if selectedWidgetPage >= total {
                        selectedWidgetPage = max(0, total - 1)
                    }
                }
                // When a fresh battle cry lands (realtime / silent push /
                // app-foreground hydration of the sticky buffer), snap to
                // page 0 so the freshly-prioritized card — the one carrying
                // the `BattleCryShoutBubble` overlay — is what the user
                // sees, even if they were sitting on a later page.
                .onChange(of: battleCryChallengeIds) { _, _ in
                    selectedWidgetPage = 0
                }
            } else {
                // Fallback: no cards at all (shouldn't happen since showDefaultInCarousel covers < 3)
                getStartedChallengeWidget
            }
        }
    }
    
    // MARK: - Pending Sent Challenge Widget
    
    
    
    func pendingSentChallengeWidget(challenge: PendingSentChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let challengeType = resolvedType
        let isShowingCancelForThis = Binding(
            get: { challengeToCancel == challenge.challengeId },
            set: { if !$0 { challengeToCancel = nil } }
        )
        
        return VStack(spacing: 0) {
            // Top row: Emoji + Title/Status + PENDING badge
            HStack(alignment: .center, spacing: 12) {
                CachedFriendPhoto(
                    friendId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName ?? "Friend",
                    size: 48,
                    showGradientRing: true,
                    gradientColors: [.orange, .yellow]
                )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(challenge.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(challengeType.emoji)
                            .font(.ds_bodySmall)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "paperplane.fill")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                        Text("Sent to \(challenge.opponentName?.components(separatedBy: " ").first ?? "friend")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            // Bottom row: accent bar + details + Cancel button (matches "Challenge a Friend" inner card)
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.orange)
                    .frame(width: 4, height: 36)
                
                VStack(alignment: .leading, spacing: 3) {
                    let target = challenge.dailyTarget ?? 0
                    let formatted = target >= 1000 ? "\(target / 1000)K" : "\(target)"
                    HStack(spacing: 6) {
                        Text("\(formatted) \(challenge.targetUnit)/day")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("PENDING")
                            .font(.ds_caption).fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.85))
                            )
                    }
                    
                    HStack(spacing: 4) {
                        Text("\(challenge.durationDays) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Waiting to accept")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                Button(action: {
                    HapticManager.impact(.medium)
                    challengeToCancel = challenge.challengeId
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.ds_caption)
                        Text("Cancel")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.85))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(colorScheme == .dark ? 0.35 : 0.25), Color.orange.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
        .confirmationDialog(
            "Cancel Challenge?",
            isPresented: isShowingCancelForThis,
            titleVisibility: .visible
        ) {
            Button("Cancel Challenge", role: .destructive) {
                Task {
                    AppLogger.debug("[DASHBOARD] Cancel challenge button tapped in confirmation dialog", category: .ui)
                    let success = await ChallengeService.shared.cancelPendingChallenge(challengeId: challenge.challengeId)
                    if success {
                        AppLogger.info("[DASHBOARD] Challenge cancelled successfully", category: .ui)
                        HapticManager.notification(.success)
                    } else {
                        AppLogger.error("[DASHBOARD] Cancel failed - refreshing to check if challenge is now active", category: .ui)
                        // Challenge might have just been accepted - refresh all lists
                        await ChallengeService.shared.fetchPendingSentChallenges()
                        await ChallengeService.shared.fetchActiveChallenges()
                        HapticManager.notification(.error)
                    }
                    challengeToCancel = nil
                }
            }
            Button("Keep Challenge", role: .cancel) {
                challengeToCancel = nil
            }
        } message: {
            Text("This will cancel the challenge request. \(challenge.opponentName?.components(separatedBy: " ").first ?? "Your friend") will be notified.")
        }
    }
    
    func activeChallengeDetailWidget(challenge: ActiveChallenge) -> some View {
        let isAccountability = challenge.mode == .accountability
        let resolvedType = challenge.resolvedType
        // Type-aware colors — each challenge type gets its own visual identity
        let typeColor: Color = resolvedType.color
        let typeGradient: [Color] = resolvedType.gradientColors
        
        return VStack(spacing: 0) {
            // Header row owns its own state for the battle-cry sheet so
            // the smiley shortcut works from any embedding (single
            // carousel, stacked carousel, future surfaces). See
            // `ActiveChallengeHeaderRow.swift`.
            ActiveChallengeHeaderRow(challenge: challenge)
            
            // Bottom section — different layout per mode, type-aware colors + live data
            HStack(spacing: 0) {
                // Left accent bar — type-colored
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: typeGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, Spacing.xxs)
                
                if isAccountability {
                    accountabilityProgressSection(challenge: challenge, challengeColor: typeColor, typeGradient: typeGradient)
                } else {
                    competitionProgressSection(challenge: challenge, challengeColor: typeColor, typeGradient: typeGradient)
                }
            }
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.black.opacity(0.03))
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(typeColor.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [typeColor.opacity(colorScheme == .dark ? 0.35 : 0.25), typeColor.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
    }
    
    // MARK: - Accountability Progress (buddy check-in)
    
    func accountabilityProgressSection(challenge: ActiveChallenge, challengeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let myLiveProgress = resolver.liveProgress(for: challenge)
        // Use today's progress only — 0 means the opponent hasn't started today (correct after midnight reset)
        let oppProgress = challenge.opponentTodayProgress ?? 0
        let myDone = challenge.dailyTarget.map { myLiveProgress >= $0 } ?? false
        let oppDone = challenge.dailyTarget.map { oppProgress >= $0 } ?? false
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Buddy"
        let livePercent = resolver.progressPercentage(for: challenge)
        let resolvedType = challenge.resolvedType
        
        return HStack(spacing: 12) {
            // Both avatars together with status
            HStack(spacing: -8) {
                challengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: myDone,
                    gradientColors: typeGradient
                )
                challengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: oppDone,
                    gradientColors: typeGradient
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Live progress value for "my" side
                HStack(spacing: 4) {
                    Text(myDone ? "✅" : "⬜")
                        .font(.ds_bodySmall)
                    Text(resolver.formattedProgress(for: challenge))
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(myDone ? .green : challengeColor)
                    
                    Text("·")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(oppDone ? "✅" : "⬜")
                        .font(.ds_bodySmall)
                    Text(opponentFirst)
                        .font(.caption2)
                        .foregroundColor(oppDone ? .green : .secondary)
                        .lineLimit(1)
                }
                
                // Shared streak
                HStack(spacing: 4) {
                    if challenge.myCurrentStreak > 0 {
                        Image(systemName: "flame.fill")
                            .font(.ds_caption)
                            .foregroundColor(.orange)
                        Text("\(challenge.myCurrentStreak)-day streak together")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing))
                    } else {
                        // Type-specific encouragement
                        Text(accountabilityEncouragement(for: resolvedType))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 4)
            
            // Daily progress ring — type-colored with live percentage
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 2.5)
                    .frame(width: 28, height: 28)
                Circle()
                    .trim(from: 0, to: livePercent)
                    .stroke(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                
                if myDone && oppDone {
                    Image(systemName: "checkmark")
                        .font(.ds_bodySmall).fontWeight(.bold)
                        .foregroundColor(.green)
                } else {
                    Text("\(Int(livePercent * 100))%")
                        .font(.ds_caption).fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    /// Returns a type-specific encouragement string for accountability challenges
    func accountabilityEncouragement(for type: ChallengeType) -> String {
        switch type {
        case .hydrate: return "Drink up together today!"
        case .protein: return "Hit your protein today!"
        case .calories: return "Burn it together!"
        case .steps: return "Start stepping today!"
        case .walk: return "Get walking today!"
        case .run: return "Lace up and go!"
        case .lift: return "Hit the weights today!"
        case .activeMinutes: return "Get moving today!"
        case .workoutStreak: return "Start your streak today!"
        // Wearable Personalization Phase 5 — new wearable-sourced types.
        case .sleepHours: return "Rest up tonight!"
        case .readinessAverage: return "Keep the green days coming!"
        case .strainBudget: return "Train smart today!"
        // Sprint 20260811 — new ChallengeType cases.
        case .cycling: return "Saddle up and ride today!"
        case .swim: return "Hit the pool together!"
        case .stairsClimbed: return "Take the stairs today!"
        case .totalVolumeLifted: return "Move some weight today!"
        case .mindBodyMinutes: return "Roll out the mat together!"
        }
    }
    
    // MARK: - Competition Progress (head-to-head battle)
    
    func competitionProgressSection(challenge: ActiveChallenge, challengeColor: Color, typeGradient: [Color]) -> some View {
        let resolver = ChallengeProgressResolver.shared
        let resolvedType = challenge.resolvedType
        // Use live data for my progress, server data for opponent
        // Use today's progress only — 0 means opponent hasn't started today (correct after midnight reset)
        let myLiveToday = resolver.liveProgress(for: challenge)
        let oppToday = challenge.opponentTodayProgress ?? 0
        // Realtime Widget Server Pull, Phase 6b (2026-04-26, rev
        // 2026-04-26 evening):
        // When the server's `opponent_last_progress_at` is older than
        // 24h (or null) we suppress the opponent's raw value instead
        // of letting it render as a misleading "0 steps". Anything
        // inside the last 24h is today's known total (possibly
        // trailing reality by a couple hours) and is shown alongside
        // an age suffix so the user has the freshness context.
        // Mirrors the widget's `CompetitionRow` so the dashboard card
        // and the home-screen widget tell the same story.
        let oppShowsRaw = ProgressFreshnessKit.shouldShowRawValue(for: challenge.opponentLastProgressAt)
        let oppFreshness = ProgressFreshnessKit.freshness(for: challenge.opponentLastProgressAt)
        let oppAgeLabel = ProgressFreshnessKit.ageLabel(for: challenge.opponentLastProgressAt)
        // Winning state is only claimed when both sides have a real
        // today number. `oppShowsRaw` is true whenever we have a
        // last-progress timestamp inside the last 24h (today's data,
        // possibly trailing reality by a couple hours). When it's
        // false (`.unknown`: ≥24h or never logged) we leave both
        // crowns dark — celebrating a lead over a missing/yesterday
        // residue would be lying.
        let amWinningNow = oppShowsRaw && myLiveToday > oppToday
        let oppLeads = oppShowsRaw && oppToday > myLiveToday && oppToday > 0
        
        return HStack(spacing: 10) {
            // Your side
            HStack(spacing: 10) {
                ZStack(alignment: .top) {
                    challengeAvatar(
                        isUser: true,
                        photoUrl: nil,
                        name: userManager.currentUser?.name,
                        done: amWinningNow,
                        gradientColors: typeGradient,
                        size: 44
                    )
                    if amWinningNow {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                            .offset(y: -12)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("You")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(resolver.formatValue(myLiveToday, unit: challenge.targetUnit, type: resolvedType))
                        .font(.ds_heading2).fontDesign(.rounded)
                        .foregroundColor(amWinningNow ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: 100, alignment: .leading)
            }
            
            Spacer(minLength: 4)
            
            // VS divider with score diff
            VStack(spacing: 2) {
                Text("⚔️")
                    .font(.ds_bodySmall)
                
                // Hide the +/- delta entirely when the opponent's
                // value is stale — comparing against an unknown
                // number would mislead the user about their lead.
                if oppShowsRaw && myLiveToday != oppToday {
                    let diff = abs(myLiveToday - oppToday)
                    let diffStr = resolver.formatValue(diff, unit: challenge.targetUnit, type: resolvedType)
                    Text(amWinningNow ? "+\(diffStr)" : "-\(diffStr)")
                        .font(.ds_caption).fontWeight(.bold)
                        .foregroundColor(amWinningNow ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: 30)
            
            Spacer(minLength: 4)
            
            // Opponent side — renders raw value when fresh, "—" + age
            // suffix when stale (Phase 6b). The opponent name row also
            // grows a tiny age suffix in the `.recent` window so users
            // see the data is a bit behind without losing the value.
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Friend")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if challenge.opponentIsVerified == true || challenge.opponentIsGoldVerified == true {
                            VerifiedBadge(size: 10, isGold: challenge.opponentIsGoldVerified == true)
                        }
                    }

                    Text(oppShowsRaw
                         ? resolver.formatValue(oppToday, unit: challenge.targetUnit, type: resolvedType)
                         : "—")
                        .font(.ds_heading2).fontDesign(.rounded)
                        .foregroundColor(oppLeads ? .green : (oppShowsRaw ? .primary : .secondary))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    // Age annotation: show nothing when fresh, and a
                    // subtle "47m" / "4h" suffix for any non-`.fresh`
                    // reading inside the last 24h (`.recent` or
                    // `.stale`). The `!oppShowsRaw` branch covers the
                    // `.unknown` case where the value collapses to `—`.
                    if !oppShowsRaw, let age = oppAgeLabel {
                        Text(age)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if (oppFreshness == .recent || oppFreshness == .stale),
                              let age = oppAgeLabel {
                        Text(age)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: 100, alignment: .trailing)

                ZStack(alignment: .top) {
                    challengeAvatar(
                        isUser: false,
                        userId: challenge.opponentId.uuidString,
                        photoUrl: challenge.opponentPhotoUrl,
                        name: challenge.opponentName,
                        done: oppLeads,
                        gradientColors: [.orange, .red],
                        size: 44
                    )
                    if oppLeads {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                            .offset(y: -12)
                    }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    // MARK: - Challenge Avatar Helper
    
    func challengeAvatar(isUser: Bool, userId: String? = nil, photoUrl: String?, name: String?, done: Bool, gradientColors: [Color], size: CGFloat = 30) -> some View {
        Group {
            if isUser {
                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5))
                } else {
                    CachedFriendPhoto(
                        friendId: SupabaseManager.shared.currentUser?.id.uuidString ?? "me",
                        photoUrl: nil,
                        name: name ?? "You",
                        size: size,
                        showGradientRing: false,
                        gradientColors: gradientColors
                    )
                    .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5))
                }
            } else {
                CachedFriendPhoto(
                    friendId: userId ?? UUID().uuidString,
                    photoUrl: photoUrl,
                    name: name ?? "Friend",
                    size: size,
                    showGradientRing: false,
                    gradientColors: gradientColors
                )
                .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5))
            }
        }
    }
    
    // MARK: - Group Member Avatar Helper
    
    @ViewBuilder
    func groupMemberAvatar(member: GroupChallengeMember, currentUserId: UUID?, size: CGFloat, accentGradient: [Color]) -> some View {
        if member.userId == currentUserId, let cachedImage = ProfilePhotoCache.shared.cachedImage {
            Image(uiImage: cachedImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            CachedFriendPhoto(
                friendId: member.userId.uuidString,
                photoUrl: member.profilePhotoUrl,
                name: member.name ?? member.username ?? "?",
                size: size,
                showGradientRing: false,
                gradientColors: accentGradient
            )
        }
    }
    
    // MARK: - Group Challenge Widget (3-person)
    
    func groupChallengeWidget(challenge: ActiveGroupChallenge) -> some View {
        let resolvedType = challenge.resolvedType
        let isAccountability = challenge.challengeMode == .accountability
        let accentColor: Color = resolvedType.color
        let accentGradient: [Color] = resolvedType.gradientColors
        let allMembers = challenge.members ?? []
        let acceptedMembers = challenge.acceptedMembers
        let pendingMembers = challenge.pendingMembers
        let isPending = challenge.isPending
        let challengeColor = resolvedType.color
        
        let cardHeight: CGFloat = 156
        
        return VStack(spacing: 0) {
            // Header
            NavigationLink(value: challenge) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                            .frame(width: 48, height: 48)
                        Text(resolvedType.emoji)
                            .font(.ds_heading2)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(challenge.displayTitle)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            if isPending {
                                Text("PENDING")
                                    .font(.ds_caption).fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.teal.opacity(0.7)))
                                
                                let pendingNames = pendingMembers.map { $0.firstName }.prefix(2)
                                Text("• Waiting for \(pendingNames.joined(separator: " & "))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            } else {
                                Text("\(acceptedMembers.count) friends")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if pendingMembers.count > 0 {
                                    Text("• \(pendingMembers.count) pending")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                Text("• \(challenge.daysRemaining)d left")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(accentColor)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Text(isAccountability ? "🤝" : "⚔️")
                        .font(.ds_bodyRegular)
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Head-to-head battle row — User1 vs User2 vs User3
            HStack(spacing: 0) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: isPending ? [challengeColor, .teal] : accentGradient, startPoint: .top, endPoint: .bottom))
                    .frame(width: 4)
                    .padding(.vertical, Spacing.xxs)
                
                if isPending {
                    HStack(spacing: 0) {
                        let currentUserId = SupabaseManager.shared.currentUser?.id
                        let membersArray = Array(allMembers.prefix(4))
                        ForEach(Array(membersArray.enumerated()), id: \.element.id) { index, member in
                            if index > 0 {
                                Text("vs")
                                    .font(.ds_caption).fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 20)
                            }
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    groupMemberAvatar(member: member, currentUserId: currentUserId, size: 28, accentGradient: [challengeColor, .teal])
                                        .opacity(member.isPending ? 0.5 : 1)

                                    if member.isPending && member.userId != currentUserId {
                                        let nudgeKey = "nudge_\(challenge.challengeId.uuidString)_\(member.userId.uuidString)"
                                        if UserDefaults.standard.bool(forKey: nudgeKey) {
                                            Text("Sent")
                                                .font(.ds_caption).fontWeight(.bold)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Color.orange))
                                                .offset(x: 28, y: -4)
                                                .allowsHitTesting(false)
                                        } else {
                                            Button {
                                                nudgePendingMember(challengeId: challenge.challengeId, memberId: member.userId)
                                            } label: {
                                                Text("Nudge")
                                                    .font(.ds_caption).fontWeight(.bold)
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Capsule().fill(Color.orange))
                                                    .contentShape(Capsule())
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .offset(x: 28, y: -4)
                                            .zIndex(1)
                                        }
                                    }
                                }

                                HStack(spacing: 3) {
                                    Text(member.userId == currentUserId ? "You" : String(member.firstName.prefix(8)))
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if member.isVerified == true || member.isGoldVerified == true {
                                        VerifiedBadge(size: 10, isGold: member.isGoldVerified == true)
                                    }
                                    if member.isAccepted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(.green)
                                    } else if member.isPending && member.userId == currentUserId {
                                        Image(systemName: "clock.fill")
                                            .font(.ds_caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                                
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, Spacing.sm)
                } else {
                    // ACTIVE: Head-to-head battle layout
                    let currentUserId = SupabaseManager.shared.currentUser?.id
                    let resolver = ChallengeProgressResolver.shared
                    // Use live HealthKit data for "my" progress, DB data for others
                    let myLiveProgress = resolver.liveProgress(for: challenge, serverValue: acceptedMembers.first(where: { $0.userId == currentUserId })?.todayProgress ?? 0)
                    let sorted = acceptedMembers.sorted { m1, m2 in
                        let p1 = m1.userId == currentUserId ? myLiveProgress : m1.todayProgress
                        let p2 = m2.userId == currentUserId ? myLiveProgress : m2.todayProgress
                        return p1 > p2
                    }
                    let leaderId = sorted.first?.userId
                    
                    HStack(spacing: 0) {
                        ForEach(Array(sorted.prefix(4).enumerated()), id: \.element.id) { index, member in
                            if index > 0 {
                                Text("vs")
                                    .font(.ds_caption).fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 20)
                            }
                            
                            let isMe = member.userId == currentUserId
                            let displayProgress = isMe ? myLiveProgress : member.todayProgress
                            let isLeader = member.userId == leaderId
                            let done = challenge.dailyTarget.map { displayProgress >= $0 } ?? false
                            
                            HStack(spacing: 6) {
                                ZStack(alignment: .top) {
                                    groupMemberAvatar(member: member, currentUserId: currentUserId, size: 32, accentGradient: accentGradient)
                                        .overlay(
                                            Circle()
                                                .stroke(done ? Color.green : (isLeader ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3)), lineWidth: 2)
                                        )
                                    if isLeader {
                                        Image(systemName: "crown.fill")
                                            .font(.ds_caption)
                                            .foregroundColor(.yellow)
                                            .offset(y: -13)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(isMe ? "You" : String(member.firstName.prefix(6)))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        if member.isVerified == true || member.isGoldVerified == true {
                                            VerifiedBadge(size: 10, isGold: member.isGoldVerified == true)
                                        }
                                    }
                                    
                                    Text(formatChallengeProgress(displayProgress, unit: challenge.targetUnit))
                                        .font(.ds_bodySmall).fontWeight(.bold).fontDesign(.rounded)
                                        .foregroundColor(isLeader ? .green : .primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .frame(height: cardHeight)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4, style: .continuous)
                    .fill(challengeColor.opacity(colorScheme == .dark ? (reducedGlow ? 0.15 : 0.12) : (reducedGlow ? 0.08 : 0.06)))
                    .offset(y: 6)
                    .blur(radius: reducedGlow ? 4 : 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: reducedGlow ? 3 : 4)
                
                AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [challengeColor.opacity(colorScheme == .dark ? (reducedGlow ? 0.4 : 0.35) : (reducedGlow ? 0.3 : 0.25)), Color.teal.opacity(colorScheme == .dark ? (reducedGlow ? 0.3 : 0.25) : (reducedGlow ? 0.2 : 0.15))],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: reducedGlow ? .black.opacity(colorScheme == .dark ? 0.3 : 0.08) : challengeColor.opacity(0.15), radius: reducedGlow ? 12 : 15, x: 0, y: reducedGlow ? 6 : 0)
        .shadow(color: reducedGlow ? challengeColor.opacity(colorScheme == .dark ? 0.2 : 0.12) : challengeColor.opacity(0.08), radius: reducedGlow ? 20 : 25, x: 0, y: reducedGlow ? 10 : 4)
        .frame(height: 156)
        // Battle-cry shout bubble (2026-05-02). Pinned to the top of
        // the group widget; the bubble self-aligns to the LEFT for
        // outgoing (I sent it) and to the RIGHT for incoming (they
        // sent it). Mirrors the 1v1 hookup in
        // `ActiveChallengeHeaderRow`.
        .overlay(alignment: .top) {
            BattleCryShoutBubble(challengeId: challenge.challengeId)
                .padding(.horizontal, Spacing.md)
                .offset(y: Spacing.sm + 35)
                .allowsHitTesting(true)
                .zIndex(20)
        }
    }

    func nudgePendingMember(challengeId: UUID, memberId: UUID) {
        HapticManager.impact(.medium)
        let nudgeKey = "nudge_\(challengeId.uuidString)_\(memberId.uuidString)"
        
        Task {
            let sent = await ChallengeService.shared.nudgeGroupChallengeMember(
                challengeId: challengeId,
                recipientId: memberId
            )
            if sent {
                UserDefaults.standard.set(true, forKey: nudgeKey)
                HapticManager.notification(.success)
                PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "challenge_nudge")
                await ChallengeService.shared.fetchActiveGroupChallenges()
            }
        }
    }
    
    func formatChallengeProgress(_ value: Int, unit: String) -> String {
        // Type-aware formatting based on unit
        switch unit.lowercased() {
        case "ml":
            if value >= 1000 {
                return String(format: "%.1fL", Double(value) / 1000)
            }
            return "\(value) ml"
        case "oz":
            return "\(value) oz"
        case "grams", "g":
            return "\(value)g"
        case "cal", "calories", "kcal":
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return "\(value) cal"
        default:
            if value >= 10000 {
                return String(format: "%.1fk", Double(value) / 1000)
            }
            return value.formatted()
        }
    }
    

    // MARK: - Get Started Challenge Widget - "Challenge a Friend!" entry point
    
    var getStartedChallengeWidget: some View {
        let challengeColor = Color.orange
        
        return Button { showingChallengeCreation = true } label: {
            VStack(spacing: 0) {
                // Top row: Trophy + Title + Chevron
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .stroke(challengeColor.opacity(0.3), lineWidth: 4)
                            .frame(width: 48, height: 48)
                        
                        Text("🏆")
                            .font(.ds_heading2)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Challenge a Friend!")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        Text("Compete head-to-head on fitness goals")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                // Bottom row: Activity info + Challenge button (inner card)
                HStack(spacing: 10) {
                    // Green accent bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(challengeColor)
                        .frame(width: 4, height: 36)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Steps, Workouts & More")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 4) {
                            Text("7-30 days")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Daily goals")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(challengeColor)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.ds_caption)
                        Text("Challenge")
                            .font(.caption)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, Color(red: 1.0, green: 0.6, blue: 0.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.94))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(.plain)
        .frame(height: 156)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl + 4)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.12 : 0.06))
                    .offset(y: 6)
                    .blur(radius: 3)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl + 2)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                    .offset(y: 4)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(colorScheme == .dark ? 0.35 : 0.25), Color.yellow.opacity(colorScheme == .dark ? 0.25 : 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(colorScheme == .dark ? 0.1 : 0.06), radius: 12, x: 0, y: 3)
    }
    
    // MARK: - Challenge Type Button Helper
    
    func challengeTypeButton(emoji: String, title: String, subtitle: String, gradient: [Color]) -> some View {
        VStack(spacing: 6) {
            Text(emoji)
                .font(.ds_heading2)
            
            Text(title)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Text(subtitle)
                .font(.ds_caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            AdaptiveCardSurface(cornerRadius: CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(
                            LinearGradient(colors: [gradient[0].opacity(0.4), gradient[1].opacity(0.2)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                )
        )
    }
    
}

// MARK: - Stacked Challenge Item

private enum StackedChallengeItem {
    case active(ActiveChallenge)
    case group(ActiveGroupChallenge)
    case pending(PendingSentChallenge)
    
    var typeKey: String {
        switch self {
        case .active(let c): return c.resolvedType.rawValue
        case .group(let c): return c.resolvedType.rawValue
        case .pending(let c): return c.resolvedType.rawValue
        }
    }
}

// MARK: - Dashboard Challenge Section Header
//
// Mirrors `FriendsChallengeHeaderWrapper` (FriendsTabView.swift) so the
// dashboard's challenge section gets the same "Active Challenges" /
// "Start a Challenge" header treatment as the Friends tab. Lives in its
// own wrapper struct (with its own `@StateObject`) so the parent
// DashboardView body doesn't re-render when challenge data changes —
// per the widget isolation rule.
struct DashboardChallengeHeaderWrapper: View {
    @StateObject private var challengeService = ChallengeService.shared
    @Binding var showingChallengeCreation: Bool
    
    var body: some View {
        if !challengeService.activeChallenges.isEmpty || !challengeService.activeGroupChallenges.isEmpty || !challengeService.pendingSentChallenges.isEmpty {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .font(.title3)
                Text("Active Challenges")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    HapticManager.impact(.light)
                    showingChallengeCreation = true
                } label: {
                    HStack(spacing: 2) {
                        Text("Start a Challenge")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(
                        LinearGradient(colors: [.orange, Color(red: 1.0, green: 0.4, blue: 0.1)], startPoint: .leading, endPoint: .trailing)
                    )
                }
                .accessibilityLabel("Start a Challenge")
                .accessibilityHint("Opens the challenge creation flow")
            }
        }
    }
}
