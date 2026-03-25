import SwiftUI

extension DashboardView {
    // MARK: - Challenge Cards Section (kept together)
    
    var challengeCardsSection: some View {
        // PRIORITY ORDER:
        // 1. Active challenges ALWAYS show first (up to 3)
        // 2. Pending sent challenges fill remaining slots (up to 3 total cards max)
        // 3. If only pending (no active), also show "Challenge a Friend" as swipeable option
        // 4. If no active AND no pending → show default "Challenge a Friend" widget only
        
        // Get active challenges (deduplicated by ID)
        let activeIds = Set(challengeService.activeChallenges.map { $0.id })
        let activeChallenges = Array(challengeService.activeChallenges.prefix(3))
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
        
        // If we only have pending (no active), add the default widget as an option
        let showDefaultInCarousel = activeCount == 0 && pendingCount > 0 && pendingCount < 3
        let totalWidgetCount = activeCount + pendingCount + (showDefaultInCarousel ? 1 : 0)
        
        // Clamp the page to valid range - this ensures we always show SOMETHING
        let safePageIndex = totalWidgetCount > 0 ? min(max(0, selectedWidgetPage), totalWidgetCount - 1) : 0
        
        return Group {
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
                        .simultaneousGesture(
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
                                    let hasDefaultWidget = currentActiveCount == 0 && currentPendingCount > 0 && currentPendingCount < 3
                                    let currentTotal = currentActiveCount + currentPendingCount + (hasDefaultWidget ? 1 : 0)
                                    
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
                        // Single active 1v1 challenge (no swiping needed)
                        activeChallengeDetailWidget(challenge: activeChallenge)
                    } else if let groupChallenge = groupChallenges.first {
                        // Single group challenge (pending or active)
                        groupChallengeWidget(challenge: groupChallenge)
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
                        .simultaneousGesture(
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
                // Reset to first page when data changes
                .onChange(of: challengeService.activeChallenges.count) { _, _ in
                    selectedWidgetPage = 0
                }
                .onChange(of: challengeService.pendingSentChallenges.count) { _, _ in
                    // Reset page when pending count changes to avoid out of bounds
                    selectedWidgetPage = 0
                }
                .onAppear {
                    // Default to page 0 when section appears
                    selectedWidgetPage = 0
                }
            } else {
                // NO active challenges AND NO pending sent → show default widget only
                if !PremiumManager.shared.isPremiumUser || showChallengeWidget {
                    getStartedChallengeWidget
                }
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
                            .font(.system(size: 9, weight: .bold))
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
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
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
    
    // Legacy - kept for compatibility
    var widgetsToDisplay: [AnyView] {
        var widgets: [AnyView] = []
        
        // Add challenge widgets (up to 3)
        for challenge in challengeService.activeChallenges.prefix(3) {
            widgets.append(AnyView(activeChallengeDetailWidget(challenge: challenge)))
        }
        
        // Add program widget if available
        if activeSmartProgramForWidget != nil || topRecommendedSmartProgram != nil || isFirstTimeUser {
            widgets.append(AnyView(unifiedProgramWidget))
        }
        
        return widgets
    }
    
    var swipeableProgramChallengeWidget: some View {
        let widgets = widgetsToDisplay
        let widgetCount = widgets.count
        
        // If multiple widgets exist, show swipeable container
        if widgetCount > 1 {
            return AnyView(
                VStack(spacing: 4) {
                    GeometryReader { geometry in
                        let cardWidth = geometry.size.width
                        let spacing: CGFloat = 16 // Space between cards
                        
                        HStack(spacing: spacing) {
                            ForEach(0..<widgetCount, id: \.self) { index in
                                widgets[index]
                                    .frame(width: cardWidth)
                                    .opacity(selectedWidgetPage == index ? 1 : 0)
                            }
                        }
                        .offset(x: -CGFloat(selectedWidgetPage) * (cardWidth + spacing))
                    }
                    .frame(height: 156)
                    // No .clipped() - allows glow to render naturally
                    .animation(.easeOut(duration: 0.2), value: selectedWidgetPage) // Snappy animation
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 25)
                            .onEnded { value in
                                let horizontalAmount = value.translation.width
                                let verticalAmount = abs(value.translation.height)
                                
                                // Only trigger if movement is primarily horizontal
                                if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                                    HapticManager.impact(.medium)
                                    if horizontalAmount < 0 && selectedWidgetPage < widgetCount - 1 {
                                        // Swipe left - go to next
                                        selectedWidgetPage += 1
                                    } else if horizontalAmount > 0 && selectedWidgetPage > 0 {
                                        // Swipe right - go to previous
                                        selectedWidgetPage -= 1
                                    }
                                }
                            }
                    )
                    
                    // Custom page indicators (tappable to switch)
                    HStack(spacing: 6) {
                        ForEach(0..<widgetCount, id: \.self) { index in
                            Circle()
                                .fill(selectedWidgetPage == index ? Color.primary : Color.gray.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .scaleEffect(selectedWidgetPage == index ? 1.0 : 0.8)
                                .animation(.easeOut(duration: 0.2), value: selectedWidgetPage)
                                .onTapGesture {
                                    HapticManager.impact(.light)
                                    selectedWidgetPage = index
                                }
                        }
                    }
                    .padding(.vertical, Spacing.xxs)
                }
                .onChange(of: widgetCount) { oldCount, newCount in
                    // Reset to valid page if widgets were removed
                    if selectedWidgetPage >= newCount {
                        selectedWidgetPage = max(0, newCount - 1)
                    }
                }
            )
        } else if widgetCount == 1 {
            // Single widget - no pagination needed
            return AnyView(widgets[0])
        } else {
            // No widgets - show program recommendation
            return AnyView(unifiedProgramWidget)
        }
    }
    
    // MARK: - Active Challenge Widget (Legacy - kept for single challenge scenarios)
    
    var activeChallengeWidget: some View {
        Group {
            if let challenge = challengeService.activeChallenges.first {
                activeChallengeDetailWidget(challenge: challenge)
            } else {
                EmptyView()
            }
        }
    }
    
    func activeChallengeDetailWidget(challenge: ActiveChallenge) -> some View {
        let isAccountability = challenge.mode == .accountability
        let resolvedType = challenge.resolvedType
        // Type-aware colors — each challenge type gets its own visual identity
        let typeColor: Color = resolvedType.color
        let typeGradient: [Color] = resolvedType.gradientColors
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "Friend"
        
        return VStack(spacing: 0) {
            // Header — shared shape, type-aware content
            NavigationLink(value: challenge) {
                HStack(alignment: .center, spacing: 10) {
                    // Type-specific icon with gradient ring
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: typeGradient, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                            .frame(width: 36, height: 36)
                        Text(resolvedType.emoji)
                            .font(.ds_heading3)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.displayTitle)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text(isAccountability ? "with \(opponentFirst)" : "vs \(opponentFirst)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(challenge.daysRemaining)d left")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(typeColor)
                        }
                    }
                    
                    Spacer()
                    
                    // Mode badge
                    Text(isAccountability ? "🤝" : "⚔️")
                        .font(.ds_bodyRegular)
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
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
                // Animated glowing border — type-colored
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                typeColor.opacity(0.7),
                                typeGradient.last?.opacity(0.5) ?? typeColor.opacity(0.5),
                                typeColor.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                typeColor.opacity(0.2),
                                typeGradient.last?.opacity(0.4) ?? typeColor.opacity(0.4),
                                typeColor.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [typeColor.opacity(0.5), typeGradient.last?.opacity(0.3) ?? typeColor.opacity(0.3), typeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: typeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: typeColor.opacity(0.08), radius: 25, x: 0, y: 4)
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
                        .font(.system(size: 9, weight: .bold, design: .rounded))
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
        let amWinningNow = myLiveToday > oppToday
        
        return HStack(spacing: 8) {
            // Your side
            HStack(spacing: 8) {
                challengeAvatar(
                    isUser: true,
                    photoUrl: nil,
                    name: userManager.currentUser?.name,
                    done: amWinningNow,
                    gradientColors: typeGradient
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text("You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        if amWinningNow {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                    }
                    
                    Text(resolver.formatValue(myLiveToday, unit: challenge.targetUnit, type: resolvedType))
                        .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(amWinningNow ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .leading)
            }
            
            Spacer(minLength: 4)
            
            // VS divider with score diff
            VStack(spacing: 2) {
                Text("⚔️")
                    .font(.ds_bodySmall)
                
                if myLiveToday != oppToday {
                    let diff = abs(myLiveToday - oppToday)
                    let diffStr = resolver.formatValue(diff, unit: challenge.targetUnit, type: resolvedType)
                    Text(amWinningNow ? "+\(diffStr)" : "-\(diffStr)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(amWinningNow ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(minWidth: 30)
            
            Spacer(minLength: 4)
            
            // Opponent side
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 3) {
                        if !amWinningNow && oppToday > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.yellow)
                        }
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Friend")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(resolver.formatValue(oppToday, unit: challenge.targetUnit, type: resolvedType))
                        .font(.ds_bodyRegular).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(!amWinningNow && oppToday > 0 ? .green : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: 85, alignment: .trailing)
                
                challengeAvatar(
                    isUser: false,
                    userId: challenge.opponentId.uuidString,
                    photoUrl: challenge.opponentPhotoUrl,
                    name: challenge.opponentName,
                    done: !amWinningNow && oppToday > 0,
                    gradientColors: [.orange, .red]
                )
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
    }
    
    // MARK: - Challenge Avatar Helper
    
    func challengeAvatar(isUser: Bool, userId: String? = nil, photoUrl: String?, name: String?, done: Bool, gradientColors: [Color]) -> some View {
        Group {
            if isUser {
                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 30, height: 30)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(done ? Color.green : Color.gray.opacity(0.3), lineWidth: 1.5))
                } else {
                    CachedFriendPhoto(
                        friendId: SupabaseManager.shared.currentUser?.id.uuidString ?? "me",
                        photoUrl: nil,
                        name: name ?? "You",
                        size: 30,
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
                    size: 30,
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
        
        return VStack(spacing: 0) {
            // Header
            NavigationLink(value: challenge) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(LinearGradient(colors: resolvedType.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2.5)
                            .frame(width: 36, height: 36)
                        Text(resolvedType.emoji)
                            .font(.ds_heading3)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(challenge.displayTitle)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if isPending {
                                Text("PENDING")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.teal.opacity(0.7)))
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text("\(allMembers.count) buddies")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            if isPending {
                                let pendingNames = pendingMembers.map { $0.firstName }.prefix(2)
                                Text("• Waiting for \(pendingNames.joined(separator: " & "))")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .lineLimit(1)
                            } else {
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
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
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
                    // PENDING: Show acceptance status + nudge buttons with "vs" between
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
                                groupMemberAvatar(member: member, currentUserId: currentUserId, size: 28, accentGradient: [challengeColor, .teal])
                                    .opacity(member.isPending ? 0.5 : 1)
                                
                                if member.isAccepted {
                                    Text("✅")
                                        .font(.ds_bodySmall)
                                } else if member.isPending && member.userId != currentUserId {
                                    // Nudge button for pending members (not yourself)
                                    let nudgeKey = "nudge_\(challenge.challengeId.uuidString)_\(member.userId.uuidString)"
                                    if UserDefaults.standard.bool(forKey: nudgeKey) {
                                        Text("⏳")
                                            .font(.ds_bodySmall)
                                    } else {
                                        Button {
                                            nudgePendingMember(challengeId: challenge.challengeId, memberId: member.userId)
                                        } label: {
                                            Text("Nudge")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, Spacing.xs)
                                                .padding(.vertical, Spacing.xxs)
                                                .background(Capsule().fill(Color.teal.opacity(0.7)))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                } else {
                                    Text("⏳")
                                        .font(.ds_bodySmall)
                                }
                                
                                Text(member.userId == currentUserId ? "You" : String(member.firstName.prefix(6)))
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
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
                                // VS divider
                                Text("⚔️")
                                    .font(.ds_labelSmall)
                                    .frame(minWidth: 20)
                            }
                            
                            let isMe = member.userId == currentUserId
                            let displayProgress = isMe ? myLiveProgress : member.todayProgress
                            let isLeader = member.userId == leaderId
                            let done = challenge.dailyTarget.map { displayProgress >= $0 } ?? false
                            
                            HStack(spacing: 6) {
                                groupMemberAvatar(member: member, currentUserId: currentUserId, size: 32, accentGradient: accentGradient)
                                    .overlay(
                                        Circle()
                                            .stroke(done ? Color.green : (isLeader ? Color.yellow.opacity(0.6) : Color.gray.opacity(0.3)), lineWidth: 2)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 3) {
                                        Text(isMe ? "You" : String(member.firstName.prefix(6)))
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        if isLeader {
                                            Image(systemName: "crown.fill")
                                                .font(.system(size: 7))
                                                .foregroundColor(.yellow)
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
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
            )
            .padding(.horizontal, Spacing.sm)
            .padding(.bottom, 12)
        }
        .background(
            ZStack {
                // Animated glowing border (always on — teal glow for consistency)
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [
                                challengeColor.opacity(0.7),
                                Color.teal.opacity(0.5),
                                challengeColor.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                challengeColor.opacity(0.2),
                                Color.mint.opacity(0.4),
                                challengeColor.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
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
                            colors: [challengeColor.opacity(0.5), Color.teal.opacity(0.3), challengeColor.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: challengeColor.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: challengeColor.opacity(0.08), radius: 25, x: 0, y: 4)
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
                // Force UI refresh
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
        .background(
            ZStack {
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
                        AngularGradient(
                            gradient: Gradient(colors: [
                                Color.orange.opacity(0.7),
                                Color.orange.opacity(0.5),
                                Color.orange.opacity(0.3),
                                Color.clear,
                                Color.clear,
                                Color.orange.opacity(0.2),
                                Color.yellow.opacity(0.4),
                                Color.orange.opacity(0.6)
                            ]),
                            center: .center,
                            angle: .degrees(challengeGlowPhase)
                        ),
                        lineWidth: 2
                    )
                    .blur(radius: 2)
                
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.5), Color.orange.opacity(0.3), Color.orange.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .shadow(color: Color.orange.opacity(0.15), radius: 15, x: 0, y: 0)
        .shadow(color: Color.orange.opacity(0.08), radius: 25, x: 0, y: 4)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                challengeGlowPhase = 360
            }
        }
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
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.cardBackground : Color(white: 0.96))
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
