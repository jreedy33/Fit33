//
//  ChallengeDetailView.swift
//  Fit33
//
//  Redesigned detail view for active 1v1 challenges — compact head-to-head display,
//  league-style stat bar, day-by-day battle log with actual values, and real-time updates.
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
    
    private var challengeType: ChallengeType { challenge.resolvedType }
    private var typeColor: Color { challengeType.color }
    private var typeGradient: LinearGradient {
        LinearGradient(colors: challengeType.gradientColors, startPoint: .leading, endPoint: .trailing)
    }
    private var opponentFirst: String {
        challenge.opponentName?.components(separatedBy: " ").first ?? "Opponent"
    }
    
    var body: some View {
        ZStack {
            AnimatedOrbBackground.friends(colorScheme: colorScheme)
                .ignoresSafeArea()
            
            if isLoading {
                ProgressView()
                    .scaleEffect(1.2)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Spacing.md) {
                        headToHeadCard
                        statBar
                        
                        if challenge.status == "active" {
                            reactionSendSection
                        }
                        
                        todayProgressCard
                        
                        if challenge.status == "active" {
                            ReactionFeedView(challenge: challenge)
                        }
                        
                        battleLogSection
                        
                        notificationToggleCard
                        
                        if challenge.status == "active" || challenge.status == "pending" {
                            cancelChallengeButton
                        }
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, 60)
                }
            }
        }
        // Phase 12 rage-shake fix (2026-04-24) — see PrivateChallengeDetailView.
        .trackScreen(.challengeDetail, metadata: ["challenge_id": challenge.id])
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Sprint 2026-04-24 Phase 4 (N1): pause intelligence phases while
            // user is in this detail view — see UserFocusSentinel doc.
            UserFocusSentinel.shared.beginFocus("ChallengeDetail")
            loadDetails()
            lastSyncedSteps = healthKitService.todaySteps
        }
        .onDisappear {
            UserFocusSentinel.shared.endFocus("ChallengeDetail")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if oldPhase == .background && newPhase == .active {
                Task { await refreshProgressIfNeeded() }
            }
        }
        .onChange(of: healthKitService.todaySteps) { oldValue, newValue in
            if challenge.challengeType == "steps" && newValue != lastSyncedSteps {
                let dailyTarget = challenge.dailyTarget ?? 1000
                if (lastSyncedSteps < dailyTarget && newValue >= dailyTarget) ||
                   (newValue > lastSyncedSteps + 100) {
                    lastSyncedSteps = newValue
                    Task { await syncMyProgressInBackground() }
                }
            }
        }
        .task(id: challenge.challengeId) {
            RealtimeService.shared.onOpponentDailyProgressUpdated = { payload in
                if payload.challengeId == challenge.challengeId {
                    AppLogger.debug("⚡️ [CHALLENGE] Real-time opponent update received!", category: .social)
                    Task {
                        details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                        if payload.targetHit {
                            HapticManager.notification(.warning)
                        }
                    }
                }
            }
            
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000_000)
                if !isLoading {
                    details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
                }
            }
        }
        .onDisappear {
            RealtimeService.shared.onOpponentDailyProgressUpdated = nil
        }
        .alert("Cancel Challenge?", isPresented: $showingCancelConfirmation) {
            Button("Keep Challenge", role: .cancel) { }
            Button("Cancel Challenge", role: .destructive) { cancelChallenge() }
        } message: {
            Text("This will end the challenge for both you and \(opponentFirst). They will be notified that you cancelled.")
        }
        .sheet(isPresented: $showingReactionPicker) {
            ReactionPickerSheet(challenge: challenge, onSend: { _ in })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Head-to-Head Card
    
    private var headToHeadCard: some View {
        VStack(spacing: Spacing.md) {
            // Challenge type + time badge
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(challengeType.emoji)
                        .font(.system(size: 14))
                    Text(challengeType.displayName)
                        .font(.ds_labelSmall)
                        .fontWeight(.bold)
                }
                .foregroundColor(typeColor)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxxs)
                .background(Capsule().fill(typeColor.opacity(0.12)))
                
                Spacer()
                
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    if challenge.daysRemaining > 0 {
                        Text("\(challenge.daysRemaining)d left")
                    } else {
                        Text("Complete")
                    }
                }
                .font(.ds_labelSmall)
                .foregroundColor(.secondary)
            }
            
            // VS Battle
            HStack(spacing: 0) {
                // Me
                VStack(spacing: Spacing.xs) {
                    ZStack {
                        if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                            Image(uiImage: cachedImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                                .overlay(
                                    Circle().stroke(
                                        challenge.amWinning
                                            ? LinearGradient(colors: [.green, .mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                                            : typeGradient,
                                        lineWidth: 2.5
                                    )
                                )
                        } else {
                            Circle()
                                .fill(typeGradient)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.ds_heading2)
                                        .foregroundColor(.white)
                                )
                        }
                        
                        if challenge.amWinning && challenge.myTotalProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                                .offset(y: -32)
                        }
                    }
                    
                    Text("You")
                        .font(.ds_labelSmall)
                        .foregroundColor(.primary)
                    
                    Text(formatProgress(challenge.myTotalProgress))
                        .font(.ds_stat)
                        .foregroundStyle(
                            challenge.amWinning
                                ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.primary)
                        )
                }
                .frame(maxWidth: .infinity)
                
                // VS Column
                VStack(spacing: Spacing.xxs) {
                    Text("VS")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.orange, .red], startPoint: .top, endPoint: .bottom)
                        )
                    
                    if challenge.myTotalProgress != challenge.opponentTotalProgress {
                        let diff = abs(challenge.myTotalProgress - challenge.opponentTotalProgress)
                        Text(challenge.amWinning ? "+\(formatProgress(diff))" : "-\(formatProgress(diff))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(challenge.amWinning ? .green : .red)
                    }
                }
                .frame(width: 56)
                
                // Opponent
                VStack(spacing: Spacing.xs) {
                    ZStack {
                        CachedFriendPhoto(
                            friendId: challenge.opponentId.uuidString,
                            photoUrl: challenge.opponentPhotoUrl,
                            name: challenge.opponentName ?? "Opponent",
                            size: 56,
                            showGradientRing: true,
                            gradientColors: !challenge.amWinning && challenge.opponentTotalProgress > 0
                                ? [.green, .mint] : [.orange, .red]
                        )
                        
                        if !challenge.amWinning && challenge.opponentTotalProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.yellow)
                                .offset(y: -32)
                        }
                    }
                    
                    HStack(spacing: 2) {
                        Text(opponentFirst)
                            .font(.ds_labelSmall)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if challenge.opponentIsVerified == true || challenge.opponentIsGoldVerified == true {
                            VerifiedBadge(size: 10, isGold: challenge.opponentIsGoldVerified == true)
                        }
                    }
                    
                    Text(formatProgress(challenge.opponentTotalProgress))
                        .font(.ds_stat)
                        .foregroundStyle(
                            !challenge.amWinning
                                ? AnyShapeStyle(LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.primary)
                        )
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
        .sleekCard(cornerRadius: 20, accentColor: typeColor)
    }
    
    // MARK: - Stat Bar
    
    private var statBar: some View {
        let livePercent = ChallengeProgressResolver.shared.progressPercentage(for: challenge)
        let streak = challenge.myCurrentStreak
        
        return VStack(spacing: Spacing.sm) {
            // Today's progress context
            HStack(spacing: Spacing.xs) {
                HStack(spacing: Spacing.xxs) {
                    Text(challengeType.emoji)
                        .font(.system(size: 14))
                    Text("\(Int(livePercent * 100))% of today's goal")
                        .font(.ds_labelSmall)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                let liveValue = ChallengeProgressResolver.shared.liveProgress(for: challenge)
                Text("\(liveValue)/\(challenge.dailyTarget ?? 0) \(challenge.targetUnit)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(typeColor)
            }
            
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(typeColor.opacity(colorScheme == .dark ? 0.12 : 0.08))
                        .frame(height: 6)
                    
                    Capsule()
                        .fill(typeGradient)
                        .frame(width: max(geo.size.width * livePercent, 6), height: 6)
                        .animation(.spring(response: 0.5), value: livePercent)
                }
            }
            .frame(height: 6)
            
            // Stats row with dividers
            HStack(spacing: 0) {
                statCell(
                    value: formatProgress(challenge.dailyTarget ?? 0),
                    label: "daily \(challenge.targetUnit)",
                    valueColor: typeColor
                )
                
                thinDivider
                
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        Text("\(streak)")
                            .font(.ds_statSmall)
                            .foregroundColor(.primary)
                    }
                    Text("streak")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                thinDivider
                
                statCell(
                    value: "\(challenge.daysRemaining)",
                    label: challenge.daysRemaining == 1 ? "day left" : "days left",
                    valueColor: challenge.daysRemaining <= 1 ? .red : .primary
                )
                
                thinDivider
                
                statCell(
                    value: "\(challenge.myDaysCompleted)/\(max(challenge.daysElapsed, 1))",
                    label: "days hit",
                    valueColor: .green
                )
            }
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .fill(typeColor.opacity(colorScheme == .dark ? 0.06 : 0.04))
            )
        }
        .padding(Spacing.sm)
        .sleekCardSubtle(cornerRadius: 16)
    }
    
    private func statCell(value: String, label: String, valueColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.ds_statSmall)
                .foregroundColor(valueColor)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var thinDivider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(width: 1, height: 28)
    }
    
    // MARK: - Reaction Send
    
    private var reactionSendSection: some View {
        let isCompetition = challenge.mode == .competition
        let themeGradient: [Color] = isCompetition ? [.orange, .red] : [.blue, .cyan]
        
        return Button {
            HapticManager.impact(.medium)
            showingReactionPicker = true
        } label: {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: themeGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 38, height: 38)
                    
                    Text(isCompetition ? "🗣️" : "⚡")
                        .font(.ds_bodyMedium)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(isCompetition ? "Send a Battle Cry" : "Send a Power Up")
                        .font(.ds_bodySmall)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(isCompetition ? "Talk smack to \(opponentFirst)" : "Hype up \(opponentFirst)")
                        .font(.ds_caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.ds_labelSmall)
                    .foregroundStyle(LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing))
            }
            .padding(Spacing.sm)
            .sleekCardSubtle(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Today's Progress Card
    
    private var todayProgressCard: some View {
        let myLive = ChallengeProgressResolver.shared.liveProgress(for: challenge)
        let oppToday = challenge.opponentTodayProgress ?? 0
        let target = challenge.dailyTarget ?? 1
        let myPercent = min(1.0, Double(myLive) / Double(target))
        let oppPercent = min(1.0, Double(oppToday) / Double(target))
        
        return VStack(spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(typeGradient)
                    .font(.title3)
                Text("Today")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if challenge.amWinningToday == true {
                    Text("You're ahead!")
                        .font(.ds_caption)
                        .foregroundColor(.green)
                } else if challenge.amWinningToday == false {
                    Text("\(opponentFirst) leads")
                        .font(.ds_caption)
                        .foregroundColor(.orange)
                }
            }
            
            // My progress bar
            VStack(spacing: Spacing.xxs) {
                HStack {
                    Text("You")
                        .font(.ds_labelSmall)
                        .foregroundColor(.primary)
                    Spacer()
                    Text("\(myLive) / \(target)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(myPercent >= 1.0 ? .green : typeColor)
                    if myPercent >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        Capsule()
                            .fill(typeGradient)
                            .frame(width: geo.size.width * myPercent, height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: myPercent)
                    }
                }
                .frame(height: 8)
            }
            
            // Opponent progress bar
            VStack(spacing: Spacing.xxs) {
                HStack {
                    HStack(spacing: 2) {
                        Text(opponentFirst)
                            .font(.ds_labelSmall)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        if challenge.opponentIsVerified == true || challenge.opponentIsGoldVerified == true {
                            VerifiedBadge(size: 9, isGold: challenge.opponentIsGoldVerified == true)
                        }
                    }
                    Spacer()
                    Text(oppToday > 0 ? "\(oppToday) / \(target)" : "–")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(oppPercent >= 1.0 ? .green : (oppToday > 0 ? .primary : .secondary))
                    if oppPercent >= 1.0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                    }
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 8)
                        Capsule()
                            .fill(LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * oppPercent, height: 8)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: oppPercent)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(Spacing.md)
        .sleekCardSubtle(cornerRadius: 16)
    }
    
    // MARK: - Battle Log (Day-by-Day Timeline)
    
    private var battleLogSection: some View {
        VStack(spacing: Spacing.sm) {
            // Section header
            HStack(spacing: Spacing.xs) {
                Image(systemName: "calendar.circle.fill")
                    .foregroundStyle(typeGradient)
                    .font(.title3)
                Text("Battle Log")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Day \(challenge.daysElapsed) of \(challenge.durationDays)")
                    .font(.ds_caption)
                    .foregroundColor(.secondary)
            }
            
            if let details = details, let participants = details.participants {
                let myProgress = participants.first { $0.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString }
                let opponentProgress = participants.first { $0.userId.uuidString != SupabaseManager.shared.currentUser?.id.uuidString }
                let calendar = createUTCCalendar()
                let allDays = generateDays(from: challenge.startDate, to: challenge.endDate)
                
                VStack(spacing: 0) {
                    ForEach(Array(allDays.enumerated()), id: \.offset) { index, date in
                        let myEntry = myProgress?.dailyProgress?.first { entry in
                            calendar.startOfDay(for: entry.date) == date
                        }
                        let oppEntry = opponentProgress?.dailyProgress?.first { entry in
                            calendar.startOfDay(for: entry.date) == date
                        }
                        
                        BattleLogRow(
                            dayNumber: index + 1,
                            date: date,
                            myValue: myEntry?.value ?? 0,
                            opponentValue: oppEntry?.value ?? 0,
                            target: challenge.dailyTarget ?? 1,
                            targetUnit: challenge.targetUnit,
                            opponentName: opponentFirst,
                            typeColor: typeColor,
                            typeGradientColors: challengeType.gradientColors,
                            colorScheme: colorScheme
                        )
                        
                        if index < allDays.count - 1 {
                            Rectangle()
                                .fill(Color.primary.opacity(0.04))
                                .frame(height: 1)
                                .padding(.horizontal, Spacing.sm)
                        }
                    }
                }
                .sleekCardSubtle(cornerRadius: 16)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(0..<min(challenge.durationDays, 7), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                            .fill(Color.primary.opacity(0.04))
                            .frame(height: 56)
                    }
                }
                .padding(Spacing.sm)
                .sleekCardSubtle(cornerRadius: 16)
            }
        }
    }
    
    // MARK: - Notification Toggle
    
    private var notificationToggleCard: some View {
        Group {
            if challenge.status == "active" || challenge.status == "pending" {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: notifyOnOpponentComplete ? "bell.fill" : "bell.slash")
                        .font(.ds_bodyMedium)
                        .foregroundColor(notifyOnOpponentComplete ? typeColor : .secondary)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Opponent alerts")
                            .font(.ds_bodySmall)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Notified when \(opponentFirst) hits their goal")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isTogglingNotification {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: $notifyOnOpponentComplete)
                            .labelsHidden()
                            .tint(typeColor)
                            .onChange(of: notifyOnOpponentComplete) { _, newValue in
                                toggleNotificationPreference(newValue)
                            }
                    }
                }
                .padding(Spacing.sm)
                .sleekCardSubtle(cornerRadius: 14)
            }
        }
    }
    
    // MARK: - Cancel Button
    
    private var cancelChallengeButton: some View {
        Button(action: { showingCancelConfirmation = true }) {
            HStack(spacing: Spacing.xs) {
                if isCancelling {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .red))
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .font(.ds_bodyMedium)
                }
                
                Text(isCancelling ? "Cancelling..." : "Cancel Challenge")
                    .font(.ds_bodySmall)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
                            .fill(Color.red.opacity(colorScheme == .dark ? 0.08 : 0.04))
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCancelling)
    }
    
    // MARK: - Helpers
    
    private func loadDetails() {
        Task {
            AppLogger.debug("🔄 [CHALLENGE DETAIL] Fetching details for challenge: \(challenge.challengeId)", category: .social)
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
            
            if let fetchedDetails = details {
                AppLogger.info("✅ [CHALLENGE DETAIL] Details loaded - \(fetchedDetails.participants?.count ?? 0) participants", category: .social)
                await MainActor.run {
                    notifyOnOpponentComplete = fetchedDetails.shouldNotifyOnOpponentComplete
                }
            } else {
                AppLogger.error("❌ [CHALLENGE DETAIL] Failed to load details", category: .social)
            }
            
            isLoading = false
            await syncMyProgressInBackground()
        }
    }
    
    private func syncMyProgressInBackground() async {
        guard challenge.status == "active" || challenge.status == "pending" else { return }
        let challengeType = challenge.challengeType
        guard challengeType == "steps" || challengeType == "active_minutes" else { return }
        
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
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
        }
    }
    
    private func refreshProgressIfNeeded() async {
        await syncMyProgressInBackground()
    }
    
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
                } else {
                    notifyOnOpponentComplete = !notify
                    HapticManager.notification(.error)
                }
            }
        }
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.2))
                        dismiss()
                    }
                } else {
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

// MARK: - Battle Log Row

private struct BattleLogRow: View {
    let dayNumber: Int
    let date: Date
    let myValue: Int
    let opponentValue: Int
    let target: Int
    let targetUnit: String
    let opponentName: String
    let typeColor: Color
    let typeGradientColors: [Color]
    let colorScheme: ColorScheme
    
    private var isToday: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.isDateInToday(date)
    }
    
    private var isFuture: Bool {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return date > calendar.startOfDay(for: Date())
    }
    
    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    private var myWon: Bool { myValue >= target && !isFuture }
    private var oppWon: Bool { opponentValue >= target && !isFuture }
    private var iAmAhead: Bool { myValue > opponentValue && !isFuture }
    
    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Day column
            VStack(spacing: 1) {
                if isToday {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(typeColor)
                } else {
                    Text("Day \(dayNumber)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isFuture ? .secondary.opacity(0.4) : .secondary)
                }
                
                Text(dayLabel)
                    .font(.ds_caption)
                    .foregroundColor(.secondary.opacity(isFuture ? 0.3 : 0.6))
            }
            .frame(width: 44)
            
            if isFuture {
                // Future day — locked
                HStack {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.ds_caption)
                        .foregroundColor(.secondary.opacity(0.2))
                    Spacer()
                }
            } else {
                // My result
                VStack(alignment: .trailing, spacing: 1) {
                    Text("You")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: Spacing.xxxs) {
                        Text(myValue > 0 ? formatValue(myValue) : "–")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(myWon ? .green : (myValue > 0 ? .primary : .secondary.opacity(0.4)))
                        
                        if myWon {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        } else if myValue > 0 {
                            miniRing(progress: min(1.0, Double(myValue) / Double(target)))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                
                // Winner indicator
                if myValue > 0 || opponentValue > 0 {
                    ZStack {
                        if iAmAhead {
                            Image(systemName: "arrowtriangle.left.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.green.opacity(0.6))
                        } else if opponentValue > myValue {
                            Image(systemName: "arrowtriangle.right.fill")
                                .font(.system(size: 7))
                                .foregroundColor(.orange.opacity(0.6))
                        } else {
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }
                
                // Opponent result
                VStack(alignment: .leading, spacing: 1) {
                    Text(opponentName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    HStack(spacing: Spacing.xxxs) {
                        if oppWon {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        } else if opponentValue > 0 {
                            miniRing(progress: min(1.0, Double(opponentValue) / Double(target)))
                        }
                        
                        Text(opponentValue > 0 ? formatValue(opponentValue) : "–")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(oppWon ? .green : (opponentValue > 0 ? .primary : .secondary.opacity(0.4)))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isToday
                    ? typeColor.opacity(colorScheme == .dark ? 0.1 : 0.06)
                    : Color.clear)
        )
    }
    
    private func miniRing(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1.5)
                .frame(width: 12, height: 12)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, lineWidth: 1.5)
                .frame(width: 12, height: 12)
                .rotationEffect(.degrees(-90))
        }
    }
    
    private func formatValue(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
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
}
