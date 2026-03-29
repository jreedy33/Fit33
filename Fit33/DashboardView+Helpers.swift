import SwiftUI

extension DashboardView {
    // MARK: - Load Personalized Recommendation
    func loadPersonalizedRecommendation() async {
        guard !isLoadingRecommendation else { return }
        
        // Get user ID from Supabase auth
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.debug("[DASHBOARD] No user ID for recommendation", category: .ui)
            return
        }
        
        isLoadingRecommendation = true
        let streak = userManager.currentUser?.currentStreak ?? 0
        
        let recommendation = await AdvancedIntelligenceService.shared.getPersonalizedRecommendation(
            userId: userId,
            streak: Int(streak)
        )
        
        self.personalizedRecommendation = recommendation
        self.isLoadingRecommendation = false
        AppLogger.debug("[DASHBOARD] Loaded recommendation: \(recommendation.message)", category: .ui)
    }
    
    // ⚡️ PERFORMANCE: Throttle cardio fetches — multiple triggers (HealthKit, Strava, notifications)
    // can fire simultaneously, causing 10+ redundant network requests that flood the dashboard.
    static let cardioFetchCooldown: TimeInterval = 10 // Max once per 10 seconds
    
    func loadRecentCardioWorkouts() async {
        // Throttle: skip if we just fetched within cooldown
        if let lastFetch = lastCardioFetchTime,
           Date().timeIntervalSince(lastFetch) < Self.cardioFetchCooldown {
            return
        }
        lastCardioFetchTime = Date()
        
        do {
            // Fetch recent for display (limited to 5)
            let cardioWorkouts = try await SupabaseManager.shared.fetchRecentCardioWorkouts(limit: 5)
            
            // Fetch total count for "Your Progress" stats (all-time)
            let allTimeCount = try await SupabaseManager.shared.fetchCardioWorkoutCount()
            
            await MainActor.run {
                self.recentCardioWorkouts = cardioWorkouts
                self.totalCardioWorkoutCount = allTimeCount
                AppLogger.debug("[DASHBOARD] Loaded \(cardioWorkouts.count) recent cardio workouts (\(allTimeCount) total all-time)", category: .ui)
            }
        } catch {
            if !Task.isCancelled {
                AppLogger.warning("[DASHBOARD] Failed to load cardio workouts: \(error.localizedDescription)", category: .ui)
            }
        }
    }
    
    func loadProfilePhoto() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Show cached image immediately for fast UX (but don't trust it - verify with database)
        let hasCachedImage = ProfilePhotoCache.shared.cachedImage != nil
        if hasCachedImage {
            await MainActor.run {
                self.profilePhotoURL = "cached"
            }
        }
        
        // ALWAYS fetch fresh from database to ensure correct photo for current user
        do {
            struct ProfilePhotoResult: Codable {
                let profile_photo_url: String?
            }
            
            let result: [ProfilePhotoResult] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("profile_photo_url")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            if let photoUrl = result.first?.profile_photo_url {
                // Download fresh from database and update cache
                if let url = URL(string: photoUrl) {
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        if let image = UIImage(data: data) {
                            ProfilePhotoCache.shared.cacheImage(image)
                            await MainActor.run {
                                self.profilePhotoURL = photoUrl
                            }
                        }
                    } catch {
                        AppLogger.warning("[DASHBOARD] Failed to download profile photo: \(error.localizedDescription)", category: .ui)
                    }
                }
            } else {
                // User has no profile photo - clear any stale cache
                ProfilePhotoCache.shared.clearCache()
                await MainActor.run {
                    self.profilePhotoURL = nil
                }
            }
        } catch {
            AppLogger.warning("[DASHBOARD] Failed to load profile photo: \(error.localizedDescription)", category: .ui)
        }
    }

    func generateMotivationalMessage() async -> String {
        let streak = userManager.currentUser?.currentStreak ?? 0
        let hour = Calendar.current.component(.hour, from: Date())
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let firstName = getFirstName()
        
        // 👤 Gender-aware terms – "queen"/"king", etc.
        let isFemale = userManager.currentUser?.gender?.lowercased().contains("female") == true
        let crown = isFemale ? "queen" : "king"
        let Royal = isFemale ? "Queen" : "King"
        let legend = isFemale ? "goddess" : "legend"
        
        var messages: [String] = []
        
        // ─────────────────────────────────────────────
        // 🧠 CONTEXT-AWARE SUGGESTION (recovery + program)
        // ─────────────────────────────────────────────
        if let contextual = await WorkoutSuggestionEngine.shared.contextualMotivationalMessageAsync(firstName: firstName, crown: crown) {
            messages.append(contextual)
            messages.append(contextual)
        }
        
        // ─────────────────────────────────────────────
        // 🏆 CHALLENGE-PERSONALIZED MESSAGES
        // ─────────────────────────────────────────────
        if let challenge = challengeService.activeChallenges.first {
            let oppName = challenge.opponentName?.components(separatedBy: " ").first ?? "your opponent"
            let resolvedType = challenge.resolvedType
            let myProgress = challenge.myTodayProgress ?? 0
            let dailyTarget = challenge.dailyTarget ?? 0
            let remaining = max(0, dailyTarget - myProgress)
            let unit = challenge.targetUnit.lowercased()
            
            // Winning vs. behind messages
            if challenge.amWinning {
                messages.append(contentsOf: [
                    "You're ahead of \(oppName)! Don't let up, \(crown)! 👑",
                    "Leading the battle vs \(oppName)! Keep that crown! 🏆",
                    "\(oppName) is watching your lead – stay locked in! 🔥",
                    "You're winning, \(firstName)! Make \(oppName) sweat! 💪"
                ])
            } else {
                messages.append(contentsOf: [
                    "\(oppName) is ahead – time to close the gap! 🔥",
                    "Behind \(oppName)? Not for long. Let's go, \(crown)! 👑",
                    "\(oppName) thinks they've got this – prove them wrong! 💪",
                    "Comeback energy! \(oppName) won't see you coming! ⚡"
                ])
            }
            
            // Type-specific actionable tips with real numbers
            if remaining > 0 {
                switch resolvedType {
                case .protein:
                    messages.append(contentsOf: [
                        "\(remaining)g protein to go! A chicken breast gets you closer! 🍗",
                        "Need \(remaining)g more protein – Greek yogurt + chicken = easy! 💪",
                        "\(remaining)g left to crush your protein goal, \(crown)! 🥚"
                    ])
                case .hydrate:
                    let unitLabel = unit.contains("oz") ? "oz" : "ml"
                    messages.append(contentsOf: [
                        "\(remaining)\(unitLabel) of water left! Grab that bottle, \(crown)! 💧",
                        "Stay hydrated! \(remaining)\(unitLabel) more to hit your goal! 🌊",
                        "Water check! \(remaining)\(unitLabel) to go – almost there! 💦"
                    ])
                case .steps:
                    messages.append(contentsOf: [
                        "\(remaining.formatted()) steps to go! A quick walk does it! 👟",
                        "\(remaining.formatted()) more steps to beat \(oppName)! 🚶",
                        "So close! \(remaining.formatted()) steps left, \(crown)! 🔥"
                    ])
                case .calories:
                    messages.append(contentsOf: [
                        "\(remaining) calories to go! Get moving, \(crown)! 🔥",
                        "\(remaining) cals left – a solid workout crushes that! 💪"
                    ])
                case .activeMinutes:
                    messages.append(contentsOf: [
                        "\(remaining) active minutes left! Any movement counts! ⏱️",
                        "\(remaining) more minutes to hit your goal, \(crown)! 💪"
                    ])
                case .walk, .run:
                    messages.append(contentsOf: [
                        "Lace up! A little more distance to beat \(oppName)! 🏃",
                        "Almost there! Keep moving, \(crown)! 👟"
                    ])
                case .lift, .workoutStreak:
                    messages.append(contentsOf: [
                        "Time to hit the weights, \(crown)! 🏋️",
                        "One workout closer to winning – let's get it! 💪"
                    ])
                }
            } else if dailyTarget > 0 {
                // Already hit daily target
                messages.append(contentsOf: [
                    "Daily challenge goal CRUSHED! You're a \(legend)! 🎉",
                    "\(firstName), you hit your daily target! \(Royal) behavior! 👑",
                    "Challenge goal: DONE. \(oppName) can't keep up! 🏆"
                ])
            }
        }
        
        // ─────────────────────────────────────────────
        // 🏋️ WORKOUT-PERSONALIZED MESSAGES
        // ─────────────────────────────────────────────
        if let lastWorkout = recentWorkouts.first {
            let workoutName = lastWorkout.name ?? "your workout"
            let daysSince = Calendar.current.dateComponents([.day], from: lastWorkout.date ?? Date(), to: Date()).day ?? 0
            
            if daysSince == 0 {
                messages.append(contentsOf: [
                    "You crushed \(workoutName) today! Amazing, \(crown)! 🔥",
                    "\(workoutName) ✅ – you're on fire, \(firstName)! 🌟",
                    "That \(workoutName) was pure \(Royal) energy! 👑"
                ])
            } else if daysSince == 1 {
                messages.append(contentsOf: [
                    "\(workoutName) yesterday was 🔥! Ready for round two?",
                    "Great \(workoutName) session yesterday, \(crown)! 💪",
                    "Your body is still thanking you for that \(workoutName)! 🌟"
                ])
            } else if daysSince <= 3 {
                messages.append(contentsOf: [
                    "Muscles are rested from \(workoutName) – time to go! 💪",
                    "\(daysSince) days since \(workoutName)? Fresh and ready, \(crown)! 🚀"
                ])
            }
            
            // Workout-type specific fun messages
            let type = (lastWorkout.workoutType ?? workoutName).lowercased()
            if type.contains("leg") || type.contains("lower") || type.contains("squat") {
                messages.append("Those legs are powerful! Walk tall, \(crown)! 🦵👑")
            } else if type.contains("chest") || type.contains("push") || type.contains("bench") {
                messages.append("Chest day champion! Stand proud, \(crown)! 💪✨")
            } else if type.contains("back") || type.contains("pull") {
                messages.append("Back gains loading! Posture on point, \(crown)! 🎯")
            } else if type.contains("arm") || type.contains("bicep") || type.contains("tricep") {
                messages.append("Arms looking toned! Flex on 'em, \(crown)! 💪✨")
            } else if type.contains("shoulder") || type.contains("delt") {
                messages.append("Shoulders looking strong! Go off, \(crown)! 🏋️")
            } else if type.contains("core") || type.contains("ab") {
                messages.append("Core work pays off every day! Love that, \(crown)! 🎯")
            } else if type.contains("cardio") || type.contains("run") || type.contains("hiit") {
                messages.append(isFemale ? "Cardio queen energy! You're glowing! ✨🏃‍♀️" : "Cardio beast mode! Keep that engine running! 🏃‍♂️🔥")
            } else if type.contains("yoga") || type.contains("stretch") || type.contains("flex") {
                messages.append("Flexibility is a superpower! Namaste, \(crown)! 🧘✨")
            } else if type.contains("dance") {
                messages.append(isFemale ? "Dancing queen! You're glowing, keep it going! 💃✨" : "Dance moves AND gains? Unstoppable! 🕺🔥")
            } else if type.contains("full body") || type.contains("total body") {
                messages.append("Full body work = full \(crown) energy! 👑🔥")
            }
        }
        
        // ─────────────────────────────────────────────
        // 🔥 STREAK-BASED MESSAGES (gender-aware)
        // ─────────────────────────────────────────────
        if streak == 0 {
            messages.append(contentsOf: [
                "Today's the day to start something great, \(firstName)! 💪",
                "Every champion started with day one. Let's go! 🚀",
                "Fresh start energy! Let's get it, \(crown)! 🌟",
                "Day one? You're about to surprise yourself! 🔥"
            ])
        } else if streak == 1 {
            messages.append(contentsOf: [
                "Day 1 in the books! The hardest part is done! 🔥",
                "You showed up, \(firstName)! That's \(Royal) behavior! 💪",
                "One day down, so many wins to come! 🚀",
                "First step taken! Momentum starts here, \(crown)! ⚡"
            ])
        } else if streak <= 3 {
            messages.append(contentsOf: [
                "\(streak) days in! You're building something real! 🔥",
                "\(streak) days of showing up – so proud of you! 💪",
                "Keep stacking those days, \(crown)! 🚀",
                "\(streak)-day streak – your future self is cheering! ⭐"
            ])
        } else if streak <= 7 {
            messages.append(contentsOf: [
                "\(streak) days strong! Unstoppable, \(crown)! 🔥",
                "Almost a full week! Champions are made right here! 💪",
                "Discipline AND heart – you've got both, \(firstName)! 🚀",
                "\(streak) days of proving you're the real deal! ⚡"
            ])
        } else if streak <= 14 {
            messages.append(contentsOf: [
                "Over a week! This is becoming who you are! 🔥",
                "\(streak) days – you're an inspiration, \(firstName)! 💪",
                "\(streak)-day streak! Absolutely elite, \(crown)! 🌟",
                "Double digits! Your dedication is beautiful! 🚀"
            ])
        } else if streak <= 30 {
            messages.append(contentsOf: [
                "\(streak) days! Fitness is non-negotiable for you! 👑",
                "\(streak)-day \(legend)! Elite consistency! 🏆",
                "\(streak) days of pure dedication – respect, \(firstName)! 💎",
                "\(streak) days strong! Nothing can stop you, \(crown)! 🔥"
            ])
        } else {
            messages.append(contentsOf: [
                "\(streak) DAYS! Top 1% energy, \(crown)! 👑",
                "\(streak)-day \(legend)! You ARE fitness goals! 🏆",
                "\(streak) days of mastered consistency, \(firstName)! 💎",
                "\(streak) days! Your discipline is legendary! 🔥",
                "\(streak) days! Rewriting what's possible! ⭐"
            ])
        }
        
        // ─────────────────────────────────────────────
        // ⏰ TIME-OF-DAY MESSAGES
        // ─────────────────────────────────────────────
        if hour < 9 {
            messages.append(contentsOf: [
                "Early bird energy! Morning \(crown)s win the day! ☀️",
                "Rise and shine, \(firstName)! Best time to invest in you! 🌅",
                "Morning check-in! You're already ahead! ⚡"
            ])
        } else if hour >= 12 && hour < 14 {
            messages.append(contentsOf: [
                "Lunch break? Perfect time for a protein-packed meal! 🥗",
                "Midday \(crown) energy! Stay fueled, stay strong! 💪"
            ])
        } else if hour >= 17 && hour < 21 {
            messages.append(contentsOf: [
                "Evening power! Perfect time to get it in, \(crown)! 🌙",
                "End the day strong! Your body is ready! 💪",
                "Evening workout = better sleep tonight! Win-win! 🔥"
            ])
        } else if hour >= 21 {
            messages.append(contentsOf: [
                "Winding down? You earned tonight's rest, \(crown)! 🌙",
                "Great day, \(firstName)! Sleep well – gains happen at rest! 😴"
            ])
        }
        
        // ─────────────────────────────────────────────
        // 📅 DAY-OF-WEEK MESSAGES
        // ─────────────────────────────────────────────
        if dayOfWeek == 2 { // Monday
            messages.append(contentsOf: [
                "Monday momentum! Set the tone, \(crown)! 💪",
                "New week, new energy! Let's go, \(firstName)! 🚀",
                "Monday \(crown)s build championship weeks! 🔥"
            ])
        } else if dayOfWeek == 4 { // Wednesday
            messages.append("Halfway through the week! Keep that energy, \(crown)! ⚡")
        } else if dayOfWeek == 6 { // Friday
            messages.append(contentsOf: [
                "Friday vibes! End the week on a high note! 🎉",
                "Weekend \(crown) mode: activated! 💪",
                "Friday flex! You earned this week, \(firstName)! 🏆"
            ])
        } else if dayOfWeek == 1 || dayOfWeek == 7 { // Weekend
            messages.append(contentsOf: [
                "Weekend dedication = next-level results! 🌴",
                "Weekends count too! Stay locked in, \(crown)! 💪",
                "Weekend work builds real results! ⚡"
            ])
        }
        
        // ─────────────────────────────────────────────
        // 🌿 WELLNESS REMINDERS (recovery-aware, never suggest fatigued muscles)
        // ─────────────────────────────────────────────
        let recoveredMuscles = await Set(WorkoutSuggestionEngine.shared.recoveredMusclesAsync())
        
        messages.append(contentsOf: [
            "Hydration check! Grab that water bottle, \(crown)! 💧",
            "Hit your step goal yet? Every step counts! 👟",
            "Protein fuels progress! Hitting your macros? 🥩",
            "Stretch it out! Flexibility is a superpower! 🧘",
            "Sleep is where the magic happens – 7-8 hours tonight? 😴",
            "Get that heart rate up today! Your heart loves you! ❤️",
            "Posture check! Stand tall, \(crown)! 👑",
            "Meal prep = future you saying 'thank you!' 🥗",
            "Water before coffee! Your body will thank you! ☕",
            "Walking counts! 10K steps for the win! 🚶",
            "You're doing amazing, \(firstName)! Keep going! ✨",
            isFemale ? "Strong is beautiful – and you're proof! 💪✨" : "Putting in the work every day! Respect, \(crown)! 💪🔥"
        ])
        
        if recoveredMuscles.contains(.core) {
            messages.append("Core work today? Your whole body will thank you! 🎯")
            messages.append("Strong core = strong everything! 🎯")
        }
        if recoveredMuscles.contains(.quads) || recoveredMuscles.contains(.glutes) {
            messages.append("Leg day is \(crown) behavior! 🦵👑")
            messages.append("Glutes are the powerhouse! Show them love today! 🍑")
        }
        if recoveredMuscles.contains(.shoulders) {
            messages.append("Shoulder day builds confidence! Go get it! 🏋️")
        }
        if recoveredMuscles.isEmpty || !recoveredMuscles.contains(.quads) {
            messages.append("Recovery day? Active rest still counts, \(crown)! 🌿")
            messages.append("Rest days build strength too! Listen to your body! 🛏️")
        }
        
        // ─────────────────────────────────────────────
        // 🧠 SMART INSIGHTS (prioritized when available)
        // ─────────────────────────────────────────────
        if !insightsService.activeInsights.isEmpty && Int.random(in: 0...9) < 4 {
            if let insight = insightsService.activeInsights.randomElement() {
                return insight.message
            }
        }
        
        // 🔥 STREAK INSIGHTS from tracking
        if !insightsService.streaks.isEmpty {
            if let proteinStreak = insightsService.streaks.first(where: { $0.streakType == "protein_goal" }),
               proteinStreak.currentStreak >= 3 {
                messages.append("\(proteinStreak.currentStreak)-day protein streak! Keep fueling those gains! 🍗")
            }
            if let hydrationStreak = insightsService.streaks.first(where: { $0.streakType == "hydration" }),
               hydrationStreak.currentStreak >= 3 {
                messages.append("\(hydrationStreak.currentStreak) days hydrated! Your body loves you, \(crown)! 💧")
            }
            if let weightStreak = insightsService.streaks.first(where: { $0.streakType == "weight_log" }),
               weightStreak.currentStreak >= 5 {
                messages.append("\(weightStreak.currentStreak)-day weight logging streak! Data drives results! ⚖️")
            }
            if let loggingStreak = insightsService.streaks.first(where: { $0.streakType == "logging" }),
               loggingStreak.currentStreak >= 7 {
                messages.append("\(loggingStreak.currentStreak) days tracking! Consistency is your superpower, \(crown)! 📊")
            }
        }
        
        return messages.randomElement() ?? "Let's make today amazing, \(firstName)! 💪"
    }

    // MARK: - Swipeable Workout Carousel
    // Page 0: Custom + Auto workout buttons
    // Page 1: Active Program widget (if available)
    
    var swipeableWorkoutCarousel: some View {
        let hasActiveProgram = activeSmartProgramForWidget != nil
        let hasRecommendedProgram = topRecommendedSmartProgram != nil || isFirstTimeUser
        let showSecondPage = hasActiveProgram || hasRecommendedProgram
        let pageCount = showSecondPage ? 2 : 1
        
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                let cardWidth = geometry.size.width
                let spacing: CGFloat = 16
                
                HStack(spacing: spacing) {
                    // Page 0: Workout Buttons
                    startWorkoutButton
                        .frame(width: cardWidth)
                    
                    // Page 1: Active Program (if available)
                    if showSecondPage {
                        unifiedProgramWidgetWithGlow(isVisible: selectedWorkoutPage == 1)
                            .frame(width: cardWidth)
                    }
                }
                .offset(x: -CGFloat(selectedWorkoutPage) * (cardWidth + spacing))
            }
            .frame(height: 160)
            .animation(.easeOut(duration: 0.25), value: selectedWorkoutPage)
            .highPriorityGesture(
                DragGesture(minimumDistance: 25)
                    .onEnded { value in
                        let horizontalAmount = value.translation.width
                        let verticalAmount = abs(value.translation.height)
                        
                        if abs(horizontalAmount) > verticalAmount * 1.5 && abs(horizontalAmount) > 20 {
                            HapticManager.impact(.medium)
                            if horizontalAmount < 0 && selectedWorkoutPage < pageCount - 1 {
                                selectedWorkoutPage += 1
                            } else if horizontalAmount > 0 && selectedWorkoutPage > 0 {
                                selectedWorkoutPage -= 1
                            }
                        }
                    }
            )
            
            if pageCount > 1 {
                HStack(spacing: 8) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        Capsule()
                            .fill(selectedWorkoutPage == index ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: selectedWorkoutPage == index ? 20 : 8, height: 6)
                            .animation(.easeOut(duration: 0.2), value: selectedWorkoutPage)
                            .onTapGesture {
                                HapticManager.impact(.light)
                                selectedWorkoutPage = index
                            }
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 2)
            }
        }
        .onAppear {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if activeSmartProgramForWidget != nil {
                    selectedWorkoutPage = 1
                } else {
                    selectedWorkoutPage = 0
                }
            }
        }
    }
    
    // MARK: - Daily Quests Section
    
    var dailyQuestsSection: some View {
        DailyQuestsWidget(questService: dailyQuestService)
    }

    // MARK: - Phone Verification Prompt Sheet
    
    @ViewBuilder
    var phoneVerificationPromptSheet: some View {
        ExistingUserPhonePrompt(
            onComplete: { [self] phoneNumber in
                handlePhoneVerificationComplete(phoneNumber)
            },
            onSkip: { [self] in
                handlePhoneVerificationSkip()
            }
        )
        .interactiveDismissDisabled()
    }
    
    func handlePhoneVerificationComplete(_ phoneNumber: String) {
        Task {
            do {
                try await SupabaseManager.shared.updatePhoneNumber(phoneNumber)
                await MainActor.run {
                    userHasVerifiedPhone = true
                    hasSeenPhonePrompt = true
                }
                if let user = userManager.currentUser {
                    user.phoneNumber = phoneNumber
                    try? viewContext.save()
                }
                AppLogger.info("[PHONE PROMPT] Phone saved successfully: \(phoneNumber)", category: .ui)
            } catch {
                AppLogger.error("[PHONE PROMPT] Failed to save phone: \(error.localizedDescription)", category: .ui)
            }
        }
    }
    
    func handlePhoneVerificationSkip() {
        hasSeenPhonePrompt = true
        AppLogger.debug("[PHONE PROMPT] User skipped phone verification", category: .ui)
    }
    
}

// MARK: - Isolated Wrapper Views (prevent parent body recomputation)

struct DashboardQuestsWrapper: View {
    @StateObject private var questService = DailyQuestService.shared
    
    var body: some View {
        DailyQuestsWidget(questService: questService)
    }
}

struct DashboardQuestCelebrationWrapper: View {
    @StateObject private var questService = DailyQuestService.shared
    
    var body: some View {
        VStack(spacing: 8) {
            if let quest = questService.lastCompletedQuest {
                QuestCompletionCelebration(
                    quest: quest,
                    isShowing: $questService.showQuestCompletionCelebration
                )
            }
            QuestBonusCelebration(
                isShowing: $questService.showBonusCelebration
            )
        }
    }
}

struct DashboardNotificationBannerWrapper: View {
    @StateObject private var notificationManager = NotificationManager.shared
    @AppStorage("notification_banner_dismissed") private var dismissedNotificationBanner = false
    
    var body: some View {
        if notificationManager.hasCheckedAuthStatus &&
           !notificationManager.isAuthorized &&
           !dismissedNotificationBanner {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
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
                
                Button(action: {
                    HapticManager.impact(.medium)
                    Task {
                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                        if settings.authorizationStatus == .notDetermined {
                            let granted = await NotificationManager.shared.requestAuthorization()
                            if granted {
                                await MainActor.run {
                                    withAnimation {
                                        dismissedNotificationBanner = true
                                    }
                                }
                            }
                        } else {
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
            .padding(.bottom, 16)
        }
    }
}
