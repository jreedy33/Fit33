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
    
    @ObservedObject private var challengeService = ChallengeService.shared
    
    let challenge: ActiveChallenge
    
    @State private var details: ChallengeDetails?
    @State private var isLoading = true
    @State private var showingLogProgress = false
    @State private var manualProgressValue: String = ""
    @State private var showingCancelConfirmation = false
    @State private var isCancelling = false
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    private var challengeType: ChallengeType {
        challenge.type ?? .steps
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Animated gradient background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Epic head-to-head display
                            headToHeadSection
                            
                            // Progress bars comparison
                            progressComparisonSection
                            
                            // Stats grid
                            statsGridSection
                            
                            // Daily breakdown calendar
                            dailyBreakdownSection
                            
                            // Log progress button
                            if challenge.status == "active" {
                                logProgressButton
                            }
                            
                            // Cancel challenge button
                            if challenge.status == "active" || challenge.status == "pending" {
                                cancelChallengeButton
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle(challenge.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                loadDetails()
            }
            .sheet(isPresented: $showingLogProgress) {
                LogProgressSheet(
                    challenge: challenge,
                    onLog: { value in
                        Task {
                            await challengeService.logProgress(challengeId: challenge.challengeId, progressValue: value)
                            loadDetails()
                        }
                    }
                )
                .presentationDetents([.medium])
            }
            .alert("Cancel Challenge?", isPresented: $showingCancelConfirmation) {
                Button("Keep Challenge", role: .cancel) { }
                Button("Cancel Challenge", role: .destructive) {
                    cancelChallenge()
                }
            } message: {
                Text("This will end the challenge for both you and \(challenge.opponentName?.components(separatedBy: " ").first ?? "your friend"). They will be notified that you cancelled.")
            }
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
                        .font(.system(size: 18))
                }
                
                Text(isCancelling ? "Cancelling..." : "Cancel Challenge")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
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
        Task {
            let success = await challengeService.cancelChallenge(challengeId: challenge.challengeId)
            await MainActor.run {
                isCancelling = false
                if success {
                    dismiss()
                }
            }
        }
    }
    
    // MARK: - Head to Head Section
    
    private var headToHeadSection: some View {
        VStack(spacing: 20) {
            // Challenge type badge
            HStack(spacing: 8) {
                Image(systemName: challengeType.icon)
                    .font(.system(size: 14))
                Text(challengeType.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: challengeType.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            
            // VS Battle Display
            HStack(spacing: 0) {
                // Me
                VStack(spacing: 12) {
                    // Avatar
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
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        )
                        .overlay(
                            // Winning crown
                            Group {
                                if challenge.amWinning && challenge.myTotalProgress > 0 {
                                    Image(systemName: "crown.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.yellow)
                                        .offset(y: -40)
                                }
                            }
                        )
                    
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
                            gradientColors: [.orange, .red]
                        )
                        
                        // Winning crown
                        if !challenge.amWinning && challenge.opponentTotalProgress > 0 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 20))
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
            }
            
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
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(cardBackground)
                .shadow(color: challengeType.color.opacity(0.2), radius: 16, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(
                    LinearGradient(
                        colors: [challengeType.gradientColors[0].opacity(0.5), challengeType.gradientColors[1].opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
    
    // MARK: - Progress Comparison Section
    
    private var progressComparisonSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Progress")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            VStack(spacing: 16) {
                // My progress bar
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
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 8)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * challenge.progressPercentage, height: 12)
                                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: challenge.progressPercentage)
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
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 12)
                            
                            // Progress
                            RoundedRectangle(cornerRadius: 8)
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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
            )
        }
    }
    
    // MARK: - Stats Grid Section
    
    private var statsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stats")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
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
                .padding(.horizontal, 4)
            
            if let details = details, let participants = details.participants {
                let myProgress = participants.first { $0.userId.uuidString == SupabaseManager.shared.currentUser?.id.uuidString }
                let opponentProgress = participants.first { $0.userId.uuidString != SupabaseManager.shared.currentUser?.id.uuidString }
                
                // Generate days from start to today
                let calendar = Calendar.current
                let days = generateDays(from: challenge.startDate, to: min(Date(), challenge.endDate))
                
                VStack(spacing: 4) {
                    // Header
                    HStack {
                        Text("Day")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)
                        
                        Spacer()
                        
                        Text("You")
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .frame(width: 60)
                        
                        Text(challenge.opponentName?.components(separatedBy: " ").first ?? "Them")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .frame(width: 60)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    
                    // Daily rows
                    ForEach(days, id: \.self) { date in
                        let myValue = myProgress?.dailyProgress?.first { calendar.isDate($0.date, inSameDayAs: date) }?.value ?? 0
                        let oppValue = opponentProgress?.dailyProgress?.first { calendar.isDate($0.date, inSameDayAs: date) }?.value ?? 0
                        let target = challenge.dailyTarget ?? 1
                        
                        DailyProgressRow(
                            date: date,
                            myValue: myValue,
                            opponentValue: oppValue,
                            target: target,
                            targetUnit: challenge.targetUnit
                        )
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            } else {
                // Loading state
                VStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: 36)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            }
        }
    }
    
    // MARK: - Log Progress Button
    
    private var logProgressButton: some View {
        Button(action: { showingLogProgress = true }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22))
                
                Text("Log Today's Progress")
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: challengeType.gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helpers
    
    private func loadDetails() {
        Task {
            details = await challengeService.getChallengeDetails(challengeId: challenge.challengeId)
            isLoading = false
        }
    }
    
    private func formatProgress(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
    
    private func generateDays(from start: Date, to end: Date) -> [Date] {
        var dates: [Date] = []
        var current = start
        let calendar = Calendar.current
        
        while current <= end {
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
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
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
            RoundedRectangle(cornerRadius: 12)
                .fill(cardBackground)
        )
    }
}

// MARK: - Daily Progress Row

struct DailyProgressRow: View {
    let date: Date
    let myValue: Int
    let opponentValue: Int
    let target: Int
    let targetUnit: String
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
    
    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    var body: some View {
        HStack {
            // Day label
            VStack(alignment: .leading, spacing: 2) {
                Text(dayLabel)
                    .font(.caption)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundColor(isToday ? .primary : .secondary)
                
                if isToday {
                    Text("Today")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 40, alignment: .leading)
            
            Spacer()
            
            // My progress
            HStack(spacing: 4) {
                if myValue >= target {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                Text(formatValue(myValue))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(myValue >= target ? .green : .primary)
            }
            .frame(width: 60)
            
            // Opponent progress
            HStack(spacing: 4) {
                if opponentValue >= target {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                }
                Text(formatValue(opponentValue))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(opponentValue >= target ? .green : .primary)
            }
            .frame(width: 60)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isToday ? Color.blue.opacity(0.1) : Color.clear)
        )
    }
    
    private func formatValue(_ value: Int) -> String {
        if value >= 10000 {
            return String(format: "%.1fk", Double(value) / 1000)
        }
        return value.formatted()
    }
}

// MARK: - Log Progress Sheet

struct LogProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: ActiveChallenge
    let onLog: (Int) -> Void
    
    @State private var progressValue: Int = 0
    @State private var isLogging = false
    
    private var challengeType: ChallengeType {
        challenge.type ?? .steps
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: challengeType.gradientColors.map { $0.opacity(0.2) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: challengeType.icon)
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: challengeType.gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("Log Today's \(challengeType.displayName.replacingOccurrences(of: " Challenge", with: ""))")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                // Value input
                HStack(spacing: 24) {
                    Button(action: { decrease() }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                    
                    VStack(spacing: 4) {
                        Text(progressValue.formatted())
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(challenge.targetUnit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(minWidth: 140)
                    
                    Button(action: { increase() }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                    }
                }
                .padding(.vertical, 20)
                
                // Target indicator
                if let target = challenge.dailyTarget {
                    HStack(spacing: 8) {
                        Image(systemName: progressValue >= target ? "checkmark.circle.fill" : "target")
                            .foregroundColor(progressValue >= target ? .green : .secondary)
                        
                        Text(progressValue >= target ? "Target reached! 🎉" : "Target: \(target.formatted()) \(challenge.targetUnit)")
                            .font(.subheadline)
                            .foregroundColor(progressValue >= target ? .green : .secondary)
                    }
                }
                
                Spacer()
                
                // Log button
                Button(action: { logProgress() }) {
                    HStack(spacing: 8) {
                        if isLogging {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "checkmark")
                            Text("Log Progress")
                        }
                    }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: progressValue > 0 ? challengeType.gradientColors : [.gray, .gray],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .disabled(progressValue <= 0 || isLogging)
            }
            .padding(24)
            .navigationTitle("Log Progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                // Pre-fill with HealthKit data if available
                if challengeType == .steps {
                    progressValue = HealthKitService.shared.todaySteps
                } else if challengeType == .activeMinutes {
                    progressValue = HealthKitService.shared.todayActiveMinutes
                }
            }
        }
    }
    
    private func increase() {
        HapticManager.impact(.light)
        switch challengeType {
        case .steps:
            progressValue += 1000
        case .walk, .run, .activeMinutes:
            progressValue += 5
        case .lift, .workoutStreak:
            progressValue += 1
        }
    }
    
    private func decrease() {
        HapticManager.impact(.light)
        switch challengeType {
        case .steps:
            progressValue = max(0, progressValue - 1000)
        case .walk, .run, .activeMinutes:
            progressValue = max(0, progressValue - 5)
        case .lift, .workoutStreak:
            progressValue = max(0, progressValue - 1)
        }
    }
    
    private func logProgress() {
        HapticManager.impact(.medium)
        isLogging = true
        
        onLog(progressValue)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            HapticManager.notification(.success)
            dismiss()
        }
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
