//
//  ChallengeDetailView.swift
//  Fit33
//
//  Detailed view of an active challenge with progress visualization
//  Shows head-to-head comparison, daily breakdown, and streak info
//

import SwiftUI

struct ChallengeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    
    @ObservedObject private var challengeService = ChallengeService.shared
    @ObservedObject private var healthKitService = HealthKitService.shared
    @ObservedObject private var realtimeService = RealtimeService.shared
    
    let challenge: ActiveChallenge
    
    @State private var details: ChallengeDetails?
    @State private var isLoading = true
    @State private var showingCancelConfirmation = false
    @State private var isCancelling = false
    @State private var notifyOnOpponentComplete = true
    @State private var isTogglingNotification = false
    @State private var lastSyncedSteps = 0
    @State private var showingReactionPicker = false
    
    
    private var challengeType: ChallengeType {
        challenge.resolvedType
    }
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with challenge flow)
            AnimatedOrbBackground.home(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 24) {
                        // Epic head-to-head display
                        headToHeadSection
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // 🗣️ Battle Cry / 💪 Power Up send button
                        if challenge.status == "active" {
                            reactionSendSection
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Progress bars comparison
                        progressComparisonSection
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // 🗣️ Reaction Feed (Battle Log / Hype Feed)
                        if challenge.status == "active" {
                            ReactionFeedView(challenge: challenge)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        // Stats grid
                        statsGridSection
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Daily breakdown calendar
                        dailyBreakdownSection
                            .fixedSize(horizontal: false, vertical: true)
                        
                        // Cancel challenge button
                        if challenge.status == "active" || challenge.status == "pending" {
                            cancelChallengeButton
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
                .scrollDisabled(false)
            }
        }
        .navigationTitle(challenge.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadDetails()
            lastSyncedSteps = healthKitService.todaySteps
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Refresh when app returns from background
            if oldPhase == .background && newPhase == .active {
                Task {
                    await refreshProgressIfNeeded()
                }
            }
        }
        .onChange(of: healthKitService.todaySteps) { oldValue, newValue in
            // Auto-refresh when steps update and crosses the daily target
            if challenge.challengeType == "steps" && newValue != lastSyncedSteps {
                let dailyTarget = challenge.dailyTarget ?? 1000
                
                // If we just crossed the threshold, refresh immediately
                if (lastSyncedSteps < dailyTarget && newValue >= dailyTarget) ||
                   (newValue > lastSyncedSteps + 100) { // Or significant change
                    lastSyncedSteps = newValue
                    Task {
                        await syncMyProgressInBackground()
                    }
                }
            }
        }
        .task(id: challenge.challengeId) {
            // Subscribe to real-time opponent progress updates (battery-efficient WebSocket)
            // This replaces the old 30-second polling
            RealtimeService.shared.onOpponentDailyProgressUpdated = { payload in
                // Only refresh if it's for THIS challenge
                if payload.challengeId == challenge.challengeId {
                    print("⚡️ [CHALLENGE] Real-time opponent update received!")
                    Task {
                        details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                        
                        // Haptic feedback when opponent hits their target
                        if payload.targetHit {
                            HapticManager.notification(.warning) // Alert them!
                        }
                    }
                }
            }
            
            // Fallback: Still refresh every 2 minutes as a safety net
            // (in case WebSocket disconnects temporarily)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000) // 2 minutes (was 30 seconds)
                if !isLoading {
                    details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                }
            }
        }
        .onDisappear {
            // Clean up callback when leaving view
            RealtimeService.shared.onOpponentDailyProgressUpdated = nil
        }
        .alert("Cancel Challenge?", isPresented: $showingCancelConfirmation) {
            Button("Keep Challenge", role: .cancel) { }
            Button("Cancel Challenge", role: .destructive) {
                cancelChallenge()
            }
        } message: {
            Text("This will end the challenge for both you and \(challenge.opponentName?.components(separatedBy: " ").first ?? "your friend"). They will be notified that you cancelled.")
        }
        .sheet(isPresented: $showingReactionPicker) {
            ReactionPickerSheet(challenge: challenge, onSend: { _ in })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Cancel Challenge Button
    
    private var cancelChallengeButton: some View {
        Button(action: { showingCancelConfirmation = true }) {
            HStack(spacing: 10) {
                if isCancelling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ds_heading3)
                }
                
                Text(isCancelling ? "Cancelling..." : "Cancel Challenge")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.1 : 0.05))
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCancelling)
        .padding(.top, 8)
    }
    
    private func cancelChallenge() {
        isCancelling = true
        HapticManager.impact(.medium)
        
        Task {
            let success = await challengeService.cancelChallenge(challengeId: challenge.challengeId)
            await MainActor.run {
                isCancelling = false
                if success {
                    HapticManager.notification(.success)
                    // Dismiss after a brief moment so user sees the action completed
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismiss()
                    }
                } else {
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    // MARK: - Head to Head Section
    
    private var headToHeadSection: some View {
        VStack(spacing: 20) {
            // Challenge type badge with emoji
            HStack(spacing: 6) {
                Text(challengeType.emoji)
                    .font(.ds_bodyRegular)
                Text(challengeType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }
            
            // VS Battle Display
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                
                // Me
                VStack(spacing: 12) {
                    // Avatar with actual profile photo
                    ZStack {
                        if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                            // Use actual profile photo
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 70)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(
                                            LinearGradient(
                                                colors: challenge.amWinning ? [.green, .mint] : [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ),
                                            lineWidth: 3
                                        )
                                )
                        } else {
                            // Fallback gradient circle
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 70, height: 70)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.ds_heading1)
                                        .foregroundColor(.white)
                                )
                        }
                        
                        // Winning crown
                        if challenge.amWinning && challenge.myTotalProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.yellow)
                                .offset(y: -40)
                        }
                    }
                    
                    Text("You")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Score
                    Text(formatProgress(challenge.myTotalProgress))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: challenge.amWinning ? [.green, .mint] : [.primary.opacity(0.8), .primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(maxWidth: .infinity)
                
                // VS
                VStack(spacing: 4) {
                    Text("VS")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    // Lead indicator
                    if challenge.myTotalProgress != challenge.opponentTotalProgress {
                        let diff = abs(challenge.myTotalProgress - challenge.opponentTotalProgress)
                        Text(challenge.amWinning ? "+\(formatProgress(diff))" : "-\(formatProgress(diff))")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(challenge.amWinning ? .green : .red)
                    }
                }
                .frame(width: 60)
                
                // Opponent
                VStack(spacing: 12) {
                    // Avatar
                    ZStack {
                        CachedFriendPhoto(
                            friendId: challenge.opponentId.uuidString,
                            photoUrl: challenge.opponentPhotoUrl,
                            name: challenge.opponentName ?? "Opponent",
                            size: 70,
                            showGradientRing: true,
                            gradientColors: !challenge.amWinning && challenge.opponentTotalProgress > 0 ? [.green, .mint] : [.orange, .red]
                        )
                        
                        // Winning crown
                        if !challenge.amWinning && challenge.opponentTotalProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.ds_heading3)
                                .foregroundColor(.yellow)
                                .offset(y: -40)
                        }
                    }
                    
                    Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Score
                    Text(formatProgress(challenge.opponentTotalProgress))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: !challenge.amWinning ? [.green, .mint] : [.primary.opacity(0.8), .primary],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(maxWidth: .infinity)
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            
            // Time remaining
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.caption)
                
                if challenge.daysRemaining > 0 {
                    Text("\(challenge.daysRemaining) day\(challenge.daysRemaining == 1 ? "" : "s") remaining")
                } else {
                    Text("Challenge Complete!")
                }
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            // Notification toggle (show for both active and pending challenges)
            if challenge.status == "active" || challenge.status == "pending" {
                Divider()
                    .padding(.vertical, Spacing.xs)
                
                HStack(spacing: 12) {
                    Image(systemName: notifyOnOpponentComplete ? "bell.fill" : "bell.slash")
                        .font(.ds_bodyRegular)
                        .foregroundColor(notifyOnOpponentComplete ? challengeType.color : .secondary)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Opponent completion alerts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Get notified when \(challenge.opponentName?.components(separatedBy: " ").first ?? "opponent") hits their daily goal")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    if isTogglingNotification {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: $notifyOnOpponentComplete)
                            .labelsHidden()
                            .tint(challengeType.color)
                            .onChange(of: notifyOnOpponentComplete) { _, newValue in
                                toggleNotificationPreference(newValue)
                            }
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .sleekCard(cornerRadius: 24, accentColor: challengeType.color)
    }
    
    // MARK: - Reaction Send Section
    
    private var reactionSendSection: some View {
        let isCompetition = challenge.mode == .competition
        let themeGradient: [Color] = isCompetition ? [.orange, .red] : [.blue, .cyan]
        let opponentFirst = challenge.opponentName?.components(separatedBy: " ").first ?? "them"
        
        return Button {
            HapticManager.impact(.medium)
            showingReactionPicker = true
        } label: {
            HStack(spacing: 12) {
                // Animated icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: themeGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 42, height: 42)
                    
                    Text(isCompetition ? "🗣️" : "⚡")
                        .font(.ds_heading3)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(isCompetition ? "Send a Battle Cry" : "Send a Power Up")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(isCompetition
                         ? "Talk smack to \(opponentFirst) 😈"
                         : "Hype up \(opponentFirst) 💪")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelMedium)
                    .foregroundStyle(
                        LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing)
                    )
            }
            .padding(Spacing.md)
            .sleekCard(cornerRadius: 16, accentColor: themeGradient[0])
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Progress Comparison Section
    
    private var progressComparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.xxs)
            
            VStack(spacing: 16) {
                // My progress bar — type-colored with live data
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("You")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(challenge.myDaysCompleted)/\(challenge.daysElapsed > 0 ? challenge.daysElapsed : 1) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geometry in
                        let livePercent = ChallengeProgressResolver.shared.progressPercentage(for: challenge)
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                            
                            // Progress — type-colored
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(
                                    LinearGradient(
                                        colors: challengeType.gradientColors,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * livePercent, height: 12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: livePercent)
                        }
                    }
                    .frame(height: 12)
                }
                
                // Opponent progress bar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(challenge.opponentDaysCompleted)/\(challenge.daysElapsed > 0 ? challenge.daysElapsed : 1) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(
                                    LinearGradient(
                                        colors: [.orange, .red],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * challenge.opponentProgressPercentage, height: 12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: challenge.opponentProgressPercentage)
                        }
                    }
                    .frame(height: 12)
                }
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
            )
        }
    }
    
    // MARK: - Stats Grid Section
    
    private var statsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.xxs)
            
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ChallengeStatCard(
                    title: "Daily Target",
                    value: formatProgress(challenge.dailyTarget ?? 0),
                    unit: challenge.targetUnit,
                    icon: "target",
                    color: .blue
                )
                
                ChallengeStatCard(
                    title: "Your Streak",
                    value: "\(challenge.myCurrentStreak)",
                    unit: "days",
                    icon: "flame.fill",
                    color: .orange
                )
                
                ChallengeStatCard(
                    title: "Days Left",
                    value: "\(challenge.daysRemaining)",
                    unit: "days",
                    icon: "calendar",
                    color: .purple
                )
                
                ChallengeStatCard(
                    title: "Completion",
                    value: "\(Int(challenge.progressPercentage * 100))",
                    unit: "%",
                    icon: "chart.pie.fill",
                    color: .green
                )
            }
        }
    }
    
    // MARK: - Daily Breakdown Section
    
    private var dailyBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Progress")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.xxs)
            
            if let details = details, let participants = details.participants {
                let myProgress = participants.first { $0.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString }
                let opponentProgress = participants.first { $0.userId.uuidString != SupabaseManager.shared.currentUser?.id.uuidString }
                
                // Generate all 7 days of the challenge using UTC calendar
                let calendar = createUTCCalendar()
                let allDays = generateDays(from: challenge.startDate, to: challenge.endDate)
                
                // Debug: Show what days we're generating
                let _ = {
                    print("📅 [DAILY PROGRESS] Generating days from \(challenge.startDate) to \(challenge.endDate)")
                    print("📅 [DAILY PROGRESS] Generated \(allDays.count) days")
                    if !allDays.isEmpty {
                        print("📅 [DAILY PROGRESS] First day: \(allDays[0])")
                    }
                }()
                
                VStack(spacing: 6) {
                    // Header
                    HStack(spacing: 0) {
                        Text("Day")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        Spacer()
                        
                        Text("You")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .frame(width: 50)
                        
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    
                    Divider()
                    
                    // Daily rows - show all 7 days (using UTC calendar)
                    ForEach(Array(allDays.enumerated()), id: \.offset) { index, date in
                        // date is already start of day in UTC from generateDays()
                        
                        let myProgressEntry = myProgress?.dailyProgress?.first { entry in
                            let entryStartOfDay = calendar.startOfDay(for: entry.date)
                            return entryStartOfDay == date
                        }
                        let oppProgressEntry = opponentProgress?.dailyProgress?.first { entry in
                            let entryStartOfDay = calendar.startOfDay(for: entry.date)
                            return entryStartOfDay == date
                        }
                        
                        let myValue = myProgressEntry?.value ?? 0
                        let oppValue = oppProgressEntry?.value ?? 0
                        let target = challenge.dailyTarget ?? 1
                        
                        // Debug: Show date matching
                        let _ = {
                            if index == 0 {
                                print("🔍 [DATE MATCH] Day \(index + 1) (UTC calendar)")
                                print("  Challenge day (UTC): \(date)")
                                if let myDailyProgress = myProgress?.dailyProgress {
                                    print("  Available MY dates (UTC): \(myDailyProgress.map { calendar.startOfDay(for: $0.date) })")
                                }
                                if let myEntry = myProgressEntry {
                                    print("  ✅ Found MY progress: \(calendar.startOfDay(for: myEntry.date)) = \(myEntry.value)")
                                } else {
                                    print("  ❌ No MY progress for this date")
                                }
                                if let oppEntry = oppProgressEntry {
                                    print("  ✅ Found OPP progress: \(calendar.startOfDay(for: oppEntry.date)) = \(oppEntry.value)")
                                } else {
                                    print("  ❌ No OPP progress for this date")
                                }
                                print("  Target: \(target), MY: \(myValue), OPP: \(oppValue)")
                                print("  Should show ✅ for MY: \(myValue >= target), OPP: \(oppValue >= target)")
                            }
                        }()
                        
                        DailyProgressRow(
                            dayNumber: index + 1,
                            date: date,
                            myValue: myValue,
                            opponentValue: oppValue,
                            target: target,
                            targetUnit: challenge.targetUnit
                        )
                        
                        if index < allDays.count - 1 {
                            Divider()
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                )
            } else {
                // Loading state
                VStack(spacing: 12) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 44)
                    }
                }
                .padding(Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color.cardBackground)
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadDetails() {
        Task {
            // Fetch challenge details immediately for fast display
            print("🔄 [CHALLENGE DETAIL] Fetching details for challenge: \(challenge.challengeId)")
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
            
            if let fetchedDetails = details {
                print("✅ [CHALLENGE DETAIL] Details loaded - \(fetchedDetails.participants?.count ?? 0) participants")
                
                // Debug: Print daily progress data
                if let participants = fetchedDetails.participants {
                    for participant in participants {
                        print("👤 [CHALLENGE DETAIL] \(participant.displayName): \(participant.totalProgress), days completed: \(participant.daysCompleted)")
                        if let dailyProgress = participant.dailyProgress {
                            print("📊 [CHALLENGE DETAIL] Daily progress entries: \(dailyProgress.count)")
                            for entry in dailyProgress {
                                print("  📅 \(entry.date): \(entry.value) \(challenge.targetUnit)")
                            }
                        } else {
                            print("⚠️ [CHALLENGE DETAIL] No daily progress data for \(participant.displayName)")
                        }
                    }
                }
                
                await MainActor.run {
                    notifyOnOpponentComplete = fetchedDetails.shouldNotifyOnOpponentComplete
                }
            } else {
                print("❌ [CHALLENGE DETAIL] Failed to load details")
            }
            
            isLoading = false
            
            // After displaying, sync latest progress in background (non-blocking)
            // This ensures the data is fresh but doesn't block the initial view
            await syncMyProgressInBackground()
        }
    }
    
    /// Sync progress in background after view loads (non-blocking)
    private func syncMyProgressInBackground() async {
        guard challenge.status == "active" || challenge.status == "pending" else { return }
        
        // Only sync for step/active minute challenges
        let challengeType = challenge.challengeType
        guard challengeType == "steps" || challengeType == "active_minutes" else { return }
        
        // Get current HealthKit value (no force refresh - use cached)
        let progressValue: Int
        if challengeType == "steps" {
            progressValue = HealthKitService.shared.todaySteps
        } else {
            progressValue = HealthKitService.shared.todayActiveMinutes
        }
        
        if progressValue > 0 {
            await challengeService.logProgress(
                challengeId: challenge.challengeId,
                progressValue: progressValue,
                source: "healthkit"
            )
            
            // Immediately refresh details to show updated progress (including checkmarks)
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
        }
    }
    
    /// Called when app returns from background to refresh progress
    private func refreshProgressIfNeeded() async {
        // Quick sync using cached HealthKit data
        await syncMyProgressInBackground()
    }
    
    /// Toggle notification preference for opponent completing daily challenge
    private func toggleNotificationPreference(_ notify: Bool) {
        isTogglingNotification = true
        HapticManager.impact(.light)
        
        Task {
            let success = await challengeService.toggleChallengeNotificationPreference(
                challengeId: challenge.challengeId,
                notify: notify
            )
            
            await MainActor.run {
                isTogglingNotification = false
                
                if success {
                    HapticManager.notification(.success)
                    print("✅ [CHALLENGES] Notification preference set to: \(notify ? "ON" : "OFF")")
                } else {
                    // Revert toggle on failure
                    notifyOnOpponentComplete = !notify
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func formatProgress(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
    
    private func createUTCCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }
    
    private func generateDays(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []
        let calendar = createUTCCalendar()
        
        var current = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        
        while current <= endDay {
            dates.append(current)
            current = calendar.date(byAdding: .day, value: 1, to: current) ?? current
        }
        
        return dates
    }
}

// MARK: - Challenge Stat Card

private struct ChallengeStatCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.ds_bodySmall)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(unit)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.cardBackground)
        )
    }
}

// MARK: - Daily Progress Row

struct DailyProgressRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let dayNumber: Int
    let date: Date
    let myValue: Int
    let opponentValue: Int
    let target: Int
    let targetUnit: String
    
    private var isToday: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.isDateInToday(date)
    }
    
    private var isFuture: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let today = calendar.startOfDay(for: Date())
        return date > today
    }
    
    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var myCompleted: Bool {
        let completed = myValue >= target
        if !isFuture && myValue > 0 {
            print("🔍 [DAILY ROW] Day \(dayNumber): myValue=\(myValue), target=\(target), completed=\(completed)")
        }
        return completed
    }
    
    private var opponentCompleted: Bool {
        let completed = opponentValue >= target
        if !isFuture && opponentValue > 0 {
            print("🔍 [DAILY ROW] Day \(dayNumber): oppValue=\(opponentValue), target=\(target), completed=\(completed)")
        }
        return completed
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Day number and label
            VStack(spacing: 2) {
                Text("Day \(dayNumber)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(isToday ? .blue : .secondary)
                
                Text(dayLabel)
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50, alignment: .leading)
            
            Spacer()
            
            // My completion status
            HStack(spacing: 6) {
                if isFuture {
                    Image(systemName: "circle")
                        .font(.ds_heading3)
                        .foregroundColor(.gray.opacity(0.3))
                } else if myCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.green)
                } else if myValue > 0 {
                    // Partial progress
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        
                        Circle()
                            .trim(from: 0, to: min(1.0, Double(myValue) / Double(target)))
                            .stroke(Color.orange, lineWidth: 2)
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(-90))
                    }
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.ds_heading2)
                        .foregroundColor(.red.opacity(0.6))
                }
            }
            .frame(width: 50)
            
            // Opponent completion status
            HStack(spacing: 6) {
                if isFuture {
                    Image(systemName: "circle")
                        .font(.ds_heading3)
                        .foregroundColor(.gray.opacity(0.3))
                } else if opponentCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading2)
                        .foregroundColor(.green)
                } else if opponentValue > 0 {
                    // Partial progress
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        
                        Circle()
                            .trim(from: 0, to: min(1.0, Double(opponentValue) / Double(target)))
                            .stroke(Color.orange, lineWidth: 2)
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(-90))
                    }
                } else {
                    Image(systemName: "xmark.circle")
                        .font(.ds_heading2)
                        .foregroundColor(.red.opacity(0.6))
                }
            }
            .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday ? (colorScheme == .dark ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08)) : Color.clear)
        )
    }
}

// MARK: - Preview

#Preview {
    ChallengeDetailView(challenge: ActiveChallenge(
        challengeId: UUID(),
        challengeType: "steps",
        title: "10K Steps Daily",
        description: "Hit 10,000 steps every day",
        dailyTarget: 10000,
        totalTarget: nil,
        targetUnit: "steps",
        startDate: Date().addingTimeInterval(-86400 * 3),
        endDate: Date().addingTimeInterval(86400 * 4),
        durationDays: 7,
        daysElapsed: 3,
        daysRemaining: 4,
        status: "active",
        myTotalProgress: 28500,
        myDaysCompleted: 2,
        myCurrentStreak: 2,
        opponentId: UUID(),
        opponentName: "Leo Smith",
        opponentUsername: "leosmith",
        opponentPhotoUrl: nil,
        opponentTotalProgress: 25000,
        opponentDaysCompleted: 2,
        amWinning: true
    ))
}
