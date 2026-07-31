import SwiftUI
import CoreData

extension DashboardView {
    // MARK: - Pinned Top Header (Logo + Actions + Welcome Row)
    //
    // Layout (pinned at the very top, above the ScrollView):
    //   [ status bar (time / signal) ]
    //   [ Fit33 logo + ... + profile ]
    //   [ WELCOME BACK, NAME + Silver ]
    //   [ scrollable dashboard content ]
    //
    // Uses `PinnedTabHeader` for consistent horizontal inset only — no
    // divider, no background (`AnimatedOrbBackground` fills the ZStack).
    // Tight vertical rhythm — no top padding on the logo so the
    // wordmark sits right under the status bar.
    var pinnedTopHeader: some View {
        PinnedTabHeader {
            // 12pt gap between the Fit33 wordmark row and the WELCOME BACK
            // row so the welcome line drops a touch lower and breathes.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                customHeaderView
                pinnedWelcomeRow
                pinnedShareBetaRow
            }
        }
    }

    // MARK: - Share Beta Link Row
    //
    // TestFlight invite affordance shown directly under the "Welcome
    // back, NAME" line so power users / Joe can hand the beta link to
    // a friend with two taps. Tapping opens `ShareBetaLinkSheet` which
    // exposes the canonical TestFlight URL + a copy button.
    var pinnedShareBetaRow: some View {
        Button(action: {
            HapticManager.tap()
            showShareBetaLink = true
        }) {
            HStack(spacing: 6) {
                Text("Share Beta Link")
                    .font(.ds_labelMedium)
                    .foregroundColor(.blue)
                Image(systemName: "doc.on.doc")
                    .font(.ds_labelMedium)
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Share beta link")
        .accessibilityHint("Opens a dialog to copy the Fit33 TestFlight invite link")
        .padding(.leading, 8)
    }

    // MARK: - Pinned Welcome Row
    //
    // "WELCOME BACK, NAME" + verified badge on the left, weekly
    // league badge ("Silver", placement copy, etc.) on the right.
    // Extracted from `headerView` so it can live in the pinned top
    // strip above the scrollable dashboard. The welcome card below
    // (flame + daily brief) keeps its own card chrome but no longer
    // duplicates this row.
    var pinnedWelcomeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            HStack(spacing: 4) {
                // 2026-05-02 — Phase 8 (New User Onboarding Brief).
                // First-visit banner reads "WELCOME TO FIT33, NAME"
                // so a brand-new user's very first dashboard load
                // doesn't say "Welcome BACK" (false-by-construction —
                // they've never been here before). UserDefaults flag
                // `has_been_welcomed_<userId>` is set with a 2s delay
                // by `DashboardView.onAppear` (see comment at the
                // flag write site), so the next dashboard mount
                // flips to "WELCOME BACK". Helper + flag wiring
                // already existed; this just routes the rendered
                // Text through `getWelcomeMessage()` instead of the
                // hardcoded "WELCOME BACK, ".
                Text("\(getWelcomeMessage().replacingOccurrences(of: ",", with: "").uppercased()), \(getFirstName().uppercased())")
                    .font(.ds_labelLarge)
                    .tracking(1.4)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if userManager.isVerified || userManager.isGoldVerified {
                    VerifiedBadge(size: 12, isGold: userManager.isGoldVerified)
                }
            }

            Spacer(minLength: 0)
        }
        // Match `customHeaderView`'s internal horizontal padding so the
        // "W" in WELCOME aligns with the "F" in Fit33. Trailing keeps
        // `Spacing.xxs`; leading is nudged to 8pt because the wordmark
        // PNG has a touch of transparent padding before the "F".
        .padding(.leading, 8)
        .padding(.trailing, Spacing.xxs)
    }

    // MARK: - Custom Header View
    var customHeaderView: some View {
        HStack(alignment: .center) {
            Image("fit33-logo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 55)
                .clipped()
                .accessibilityHidden(true)
            
            Spacer()
            
            // Timer, league badge, and profile icon grouped together.
            // 2026-05-08 — Header simplification (lead-designer call).
            // The widget-settings ellipsis moved into the ProfileView
            // toolbar (next to the settings cog) and the weekly league
            // tier badge moved up into this slot. One identity element
            // ("you, your tier") sits next to the avatar instead of two
            // controls competing with the wordmark.
            HStack(spacing: 8) {
                // Active workout timer (only shows when workout is active)
                if workoutManager.isWorkoutActive {
                    Text(workoutManager.formattedDuration)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .adaptiveMaterialBackground(cornerRadius: CornerRadius.sm)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                // Weekly league tier badge ("Gold", "Silver", trend
                // chip) — promoted from the welcome row to the avatar
                // row so it reads as part of the user's identity strip.
                DashboardLeagueBadge(navigationPath: $dashboardNavPath)

                // 4pt breathing room between the tier badge and the avatar.
                Spacer()
                    .frame(width: 4)

                // Profile button with hollow blue gradient ring and photo/person icon
                NavigationLink(value: DashboardRoute.profile) {
                    ZStack(alignment: .topTrailing) {
                        ZStack {
                            // Hollow ring with blue gradient
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 36, height: 36)
                                .shadow(color: .blue.opacity(0.4), radius: 4, x: 0, y: 2)
                            
                            // Show profile photo if available (from cache or URL), otherwise person icon
                            if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                                Image(uiImage: cachedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 28, height: 28)
                                    .clipShape(Circle())
                            } else if let photoURL = profilePhotoURL, photoURL != "cached", let url = URL(string: photoURL) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 28, height: 28)
                                            .clipShape(Circle())
                                    case .failure(_), .empty:
                                        Image(systemName: "person.fill")
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.white)
                                    @unknown default:
                                        Image(systemName: "person.fill")
                                            .font(.ds_labelLarge)
                                            .foregroundColor(.white)
                                    }
                                }
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.ds_labelLarge)
                                    .foregroundColor(.white)
                            }
                        }
                        
                        // Red indicator dot - isolated component to prevent DashboardView re-renders
                        FriendNotificationBadge()
                            .offset(x: 3, y: -3)
                    }
                }
                .accessibilityLabel("Profile")
                .accessibilityHint("View your profile and settings")
                .offset(y: 2)
            }
            .animation(.easeInOut(duration: 0.2), value: workoutManager.isWorkoutActive)
        }
        .padding(.horizontal, Spacing.xxs)
    }
    
    // MARK: - Notification Permission Banner
    // Persist dismissed state so it doesn't flicker on view recreation
    
    var notificationPermissionBanner: some View {
        // All conditions are checked in the parent - this just renders the content
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Bell icon with animation
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.orange, Color.red.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "bell.badge.fill")
                        .font(.ds_heading3).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Stay on Track!")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Enable notifications to get workout reminders & celebrate your wins")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Dismiss button
                Button(action: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dismissedNotificationBanner = true
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(Spacing.xs)
                }
            }
            
            // Enable button
            Button(action: {
                HapticManager.impact(.medium)
                // Check if we need to request permission or open settings
                Task {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    if settings.authorizationStatus == .notDetermined {
                        // First time - request permission
                        let granted = await NotificationManager.shared.requestAuthorization()
                        if granted {
                            await MainActor.run {
                                withAnimation {
                                    dismissedNotificationBanner = true
                                }
                            }
                        }
                    } else {
                        // Already denied - open settings
                        await MainActor.run {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "bell.fill")
                        .font(.ds_labelMedium)
                    Text("Enable Notifications")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(
                    LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(CornerRadius.md)
            }
        }
        .padding(Spacing.md)
        .onboardingCardStyle(accentColor: .orange, secondaryColor: .red, isSelected: true, cornerRadius: CornerRadius.lg)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // Get the user's first name only (remove last name)
    func getFirstName() -> String {
        let fullName = userManager.currentUser?.name ?? "there"
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        return firstName.isEmpty ? "there" : firstName
    }
    
    // Check if this is the user's first time seeing the dashboard after account creation
    func checkIsFirstVisit() -> Bool {
        guard let userId = userManager.currentUser?.id else { return true }
        return !UserDefaults.standard.bool(forKey: "has_been_welcomed_\(userId.uuidString)")
    }
    
    // Welcome message based on first visit. Banner copy is the
    // formal app-name greeting on Day 0 ("Welcome to Fit33,") so
    // it pairs with the warmer "Welcome to the club." card
    // headline below — banner = identity, card = community.
    // Subsequent loads flip to "Welcome back" via the
    // `has_been_welcomed_<userId>` UserDefaults flag set by
    // `DashboardView.onAppear` (2s delay after first paint).
    func getWelcomeMessage() -> String {
        checkIsFirstVisit() ? "Welcome to Fit33," : "Welcome back,"
    }
    
    // 2026-05-01 — Welcome card redesign (lead-designer spec).
    // Five stacked card-chrome layers were collapsed to canonical
    // `.sleekCard()`; flame medallion shrunk 58→48 with
    // proportionally scaled SF Symbol + hole-filler; streak number
    // moved to the canonical `.ds_statSmall` token; HStack gap +
    // padding moved to `Spacing.md` so the card no longer reads as
    // "smashed". Headline bumped `.ds_heading3` → `.ds_heading2`
    // inside `WelcomeBriefRow` to give the hero card its proper
    // weight now that there's room for it.
    var headerView: some View {
        HStack(spacing: Spacing.md) {
            streakFlameMedallion

            // Daily Brief — fused multi-source insight (replaces
            // the old single-line motivational subtitle, 2026-04-27).
            // Engine: `DailyBriefEngine.compose()`; widget isolation
            // in `DashboardWelcomeBriefWrapper` (PE invariant 9).
            DashboardWelcomeBriefWrapper(navigationPath: $dashboardNavPath)
                .environmentObject(workoutManager)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: .blue)
    }

    /// Streak flame badge — the whole 58pt medallion is the tap
    /// target for `showStreakInfo`. Internal sizes (58pt frame, 56pt
    /// SF Symbol, 42pt hole-filler) are component-internal canonical
    /// constants matching the original welcome-card flame size;
    /// they are NOT `Spacing.*` tokens because they describe a
    /// component's intrinsic size, not layout padding.
    /// Hole-filler bumped 32→42pt on 2026-05-08 so the streak number
    /// always sits on solid orange/red — at 32pt the SF Symbol's
    /// inner bulb showed dark gaps around the digits.
    private var streakFlameMedallion: some View {
        Button(action: {
            HapticManager.impact(.light)
            showStreakInfo = true
        }) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red.opacity(0.9)]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 42, height: 42)
                    .offset(y: 6)

                Image(systemName: "flame.fill")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.orange, Color.red]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 8, x: 0, y: 2)

                Text("\(userManager.currentUser?.currentStreak ?? 0)")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(y: 4)
            }
            .frame(width: 58, height: 58)
        }
        .accessibilityLabel("Current streak: \(userManager.currentUser?.currentStreak ?? 0) days")
        .accessibilityHint("Tap for streak details")
        .buttonStyle(.plain)
    }
    
    var startWorkoutButton: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                DashboardStyleWorkoutQuickStartTile(
                    title: "Custom Workout",
                    subtitle: "Build your own",
                    icon: "plus.circle.fill",
                    circleGradient: [Color.blue, Color.cyan],
                    cardGlowBase: .blue,
                    borderGradient: [Color.blue, Color.cyan],
                    outerGlowColor: .blue,
                    outerGlowOpacityDark: 0.2,
                    outerGlowOpacityLight: 0.12,
                    accessibilityLabelText: "Start custom workout",
                    accessibilityHintText: "Build your own workout from scratch",
                    action: { handleWorkoutSelection(type: .custom) }
                )

                DashboardStyleWorkoutQuickStartTile(
                    title: "Auto Workout",
                    subtitle: "Auto-generated routine",
                    icon: "dumbbell.fill",
                    circleGradient: [Color.purple, Color.pink],
                    cardGlowBase: .purple,
                    borderGradient: [Color.purple, Color.pink],
                    outerGlowColor: .purple,
                    outerGlowOpacityDark: 0.12,
                    outerGlowOpacityLight: 0.12,
                    accessibilityLabelText: "Start auto workout",
                    accessibilityHintText: "Generate a workout based on your history",
                    action: { handleWorkoutSelection(type: .auto) }
                )
            }
        }
    }
    
    // MARK: - Dashboard Widgets Row
    var dashboardWidgetsRow: some View {
        let showBoth = showWeightTrackerWidget && showHydrationWidget
        
        return Group {
            if showBoth {
                // Two widgets side by side
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    if showWeightTrackerWidget {
                        DashboardWeightWidget(isCompact: true)
                    }
                    if showHydrationWidget {
                        DashboardHydrationWidget(isCompact: true)
                    }
                }
            } else {
                // Single widget expanded
                if showWeightTrackerWidget {
                    DashboardWeightWidget(isCompact: false)
                }
                if showHydrationWidget {
                    DashboardHydrationWidget(isCompact: false)
                }
            }
        }
    }
    
    var destinationForTodaysWorkout: some View {
        Group {
            if let program = generatedProgramService.activeProgram,
               let currentDay = generatedProgramService.currentDay {
                SmartWorkoutPreviewView(
                    day: currentDay,
                    program: program
                )
                .environmentObject(workoutManager)
                .environmentObject(generatedProgramService)
            } else {
                EmptyView()
            }
        }
    }

    func handleWorkoutSelection(type: PendingWorkoutType) {
        // 🔧 Debounce: Prevent double-taps
        guard !isNavigating else { return }
        isNavigating = true
        
        Task { @MainActor in try? await Task.sleep(for: .seconds(0.5)); isNavigating = false }
        
        if generatedProgramService.activeProgram != nil {
            // Show alert if there's an active program
            pendingWorkoutType = type
            showingProgramConflictAlert = true
        } else {
            // Proceed directly if no active program
            pendingWorkoutType = type
            if type == .custom {
                navigateToCustomWorkout = true
            } else if type == .auto {
                // 🔧 Redirect to Workout tab's auto-gen flow
                // This prevents cross-tab navigation issues when starting workout
                workoutManager.shouldNavigateToAutoGen = true
            }
        }
    }
}

// MARK: - Dashboard League Badge (replaces the old "Legendary Master N" XP badge)

/// Floating tappable league badge in the welcome card's top-right
/// corner. Source-of-truth: `WeeklyLeagueService.shared.standing`.
/// Tapping pushes `WeeklyLeagueDetailView` onto the dashboard's
/// existing NavigationStack — same surface as the FriendsTab
/// `LeagueDetail` deep link (full page, not a sheet). The detail
/// view sets its own `.navigationBarHidden(true)` so it draws its
/// own header inside the parent stack (no nested NavigationStack
/// — PE invariant 6).
///
/// Fallback hierarchy when no league standing yet:
///   1. `notPlaced == true` → "Earn XP to enter" placement copy.
///   2. `standing == nil` AND not placed → temporarily renders the
///      legacy XP-level title ("Legendary Master 148") so the slot
///      is never blank during the cold-start fetch.
///
/// Widget isolation (PE invariant 9): owns its own
/// `@StateObject WeeklyLeagueService.shared` so league fetches
/// (which run on weekly placement events + foreground refresh) do
/// not recompute the parent `DashboardView` body.
struct DashboardLeagueBadge: View {
    @Binding var navigationPath: NavigationPath
    @StateObject private var league = WeeklyLeagueService.shared

    init(navigationPath: Binding<NavigationPath>) {
        self._navigationPath = navigationPath
    }

    var body: some View {
        Button {
            HapticManager.impact(.light)
            navigationPath.append(DashboardRoute.weeklyLeague)
        } label: {
            badgeContent
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Tap to view this week's league leaderboard")
        .task {
            // Fetch on first paint if standing isn't already loaded.
            // The service throttles internally so a tab-return won't
            // hammer the RPC.
            if league.standing == nil && !league.hasJoined && !league.notPlaced {
                await league.fetchOrJoinLeague()
            }
        }
    }

    @ViewBuilder
    private var badgeContent: some View {
        if let standing = league.standing {
            HStack(spacing: 4) {
                // 2026-05-08 — Stripped tier emoji + Crown-of-the-Week flair
                // per design call. The gradient-tinted tier name carries
                // the visual identity on its own; the trend chip remains
                // as the only adjacent affordance.
                Text(standing.tierName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: standing.tierGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                trendIndicator(for: standing)
            }
        } else if league.notPlaced {
            HStack(spacing: 4) {
                Image(systemName: "trophy")
                    .font(.ds_caption)
                    .foregroundColor(.orange)
                // 2026-04-29 — League Redesign Plan §B3. Replaces the legacy
                // "Earn XP to enter" copy. New users tap the badge to land
                // on the educational "How leagues work" page; "Placement
                // Monday" is what's actually true between Tue-Sun.
                Text("Placement Monday")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.orange)
            }
        } else {
            // Cold-start fallback while the league fetch is in flight.
            // 2026-04-29 — League Redesign Plan §B3. Replaces the legacy
            // "Legendary Master 148" XP-level title. Tier is now identity;
            // when no standing has loaded yet we render a quiet trophy +
            // "Loading..." placeholder so the slot is never empty.
            HStack(spacing: 4) {
                Image(systemName: "trophy")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
                Text("Loading…")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Tiny up/down/flat trend chip rendered next to the tier name.
    /// Encodes whether the user is currently in the promotion zone
    /// (advance), relegation zone (drop), or holding their tier.
    @ViewBuilder
    private func trendIndicator(for standing: LeagueStanding) -> some View {
        if standing.isInPromotionZone {
            Image(systemName: "arrow.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
                .accessibilityLabel("On track to advance")
        } else if standing.isInRelegationZone {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.red)
                .accessibilityLabel("At risk of dropping")
        } else {
            Image(systemName: "minus")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .accessibilityLabel("Holding tier")
        }
    }

    private var accessibilityLabel: String {
        if let standing = league.standing {
            let trend: String
            if standing.isInPromotionZone {
                trend = ", on track to advance"
            } else if standing.isInRelegationZone {
                trend = ", at risk of dropping"
            } else {
                trend = ", holding tier"
            }
            return "\(standing.tierName) League, rank \(standing.myRank) of \(standing.groupSize)\(trend)"
        }
        if league.notPlaced {
            return "Not yet placed in a league. Placement runs on Monday."
        }
        return "League standing loading"
    }
}

// MARK: - Dashboard / Workout tab — Custom + Auto entry tiles (shared)
//
// Pixel-parity with `DashboardView.startWorkoutButton` (home tab).
// `WorkoutTabView` uses the same component for the first quick-action row.
struct DashboardStyleWorkoutQuickStartTile: View {
    let title: String
    let subtitle: String
    let icon: String
    let circleGradient: [Color]
    let cardGlowBase: Color
    let borderGradient: [Color]
    let outerGlowColor: Color
    let outerGlowOpacityDark: Double
    let outerGlowOpacityLight: Double
    let accessibilityLabelText: String
    let accessibilityHintText: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            HapticManager.impact(.medium)
            action()
        }) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: circleGradient),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: circleGradient[0].opacity(0.4), radius: 8, x: 0, y: 4)

                    Image(systemName: icon)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(cardGlowBase.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)

                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)

                    AdaptiveCardSurface(cornerRadius: 24)

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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

                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    borderGradient[0].opacity(colorScheme == .dark ? 0.4 : 0.3),
                                    borderGradient[1].opacity(colorScheme == .dark ? 0.3 : 0.2)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(
                color: outerGlowColor.opacity(colorScheme == .dark ? outerGlowOpacityDark : outerGlowOpacityLight),
                radius: 20,
                x: 0,
                y: 10
            )
        }
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityHint(accessibilityHintText)
        .buttonStyle(PlainButtonStyle())
    }
}
