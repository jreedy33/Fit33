import SwiftUI
import CoreData

// MARK: - Share Workout Sheet
/// Presents options to share a completed workout to friends in-app or via the system share sheet

struct ShareWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: Workout
    let accentColor: Color
    
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared
    @State private var showingFriendPicker = false
    @State private var selectedFriend: Friend?
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var sendError: String?
    
    // Workout data
    private var workoutExercises: [WorkoutExercise] {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        return exercises.sorted { $0.order < $1.order }
    }
    
    private var exerciseCount: Int { workoutExercises.count }
    
    private var duration: Int { Int(workout.duration) / 60 }
    
    private var totalSets: Int {
        workoutExercises.reduce(0) { total, we in
            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
    }
    
    private var workoutName: String {
        cleanWorkoutName(workout.name ?? "Workout")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (colorScheme == .dark ? Color(white: 0.08) : Color(.systemGroupedBackground))
                    .ignoresSafeArea()
                
                if showingSuccess {
                    successView
                } else if showingFriendPicker {
                    friendPickerView
                } else {
                    mainOptionsView
                }
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if showingFriendPicker && !showingSuccess {
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showingFriendPicker = false
                                selectedFriend = nil
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Error", isPresented: .init(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )) {
                Button("OK") { sendError = nil }
            } message: {
                Text(sendError ?? "")
            }
        }
        .task {
            await friendService.fetchFriends()
            await rankingService.fetchRankedFriends()
        }
    }
    
    // MARK: - Main Options View
    private var mainOptionsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Workout Preview Card
                workoutPreviewCard
                    .padding(.top, 8)
                
                // Share Options
                VStack(spacing: 12) {
                    // Send to Friend option
                    Button(action: {
                        HapticManager.impact(.light)
                        withAnimation(.spring(response: 0.3)) {
                            showingFriendPicker = true
                        }
                    }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.blue, .cyan],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Send to Friend")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text(friendService.friends.isEmpty ? "Add friends to share workouts" : "\(friendService.friends.count) friends available")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(friendService.friends.isEmpty)
                    .opacity(friendService.friends.isEmpty ? 0.6 : 1)
                    
                    // Share via System Sheet option
                    Button(action: {
                        HapticManager.impact(.light)
                        WorkoutSharingService.shared.shareWorkout(workout: workout)
                    }) {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .teal],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Share via...")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Messages, Instagram, and more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                
                // No friends hint
                if friendService.friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text("No Friends Yet")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Add friends from the Social tab to share workouts in-app")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 32)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Friend Picker View
    private var friendPickerView: some View {
        VStack(spacing: 0) {
            if let friend = selectedFriend {
                // Compose message view
                ScrollView {
                    VStack(spacing: 20) {
                        // Selected friend card
                        HStack(spacing: 12) {
                            // Avatar
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [accentColor, accentColor.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 50, height: 50)
                                
                                Text(String(friend.displayName.prefix(1)).uppercased())
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sending to")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(friend.displayName)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                selectedFriend = nil
                            }) {
                                Text("Change")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(16)
                        .background(cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        
                        // Workout preview
                        workoutPreviewCard
                        
                        // Message input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a message (optional)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            TextField("Great workout! Try it out 💪", text: $messageText, axis: .vertical)
                                .textFieldStyle(.plain)
                                .padding(14)
                                .background(cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .lineLimit(3...5)
                        }
                        
                        // Send button
                        Button(action: sendWorkoutToFriend) {
                            HStack(spacing: 8) {
                                if isSending {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                    Text("Send Workout")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .disabled(isSending)
                        .padding(.top, 8)
                    }
                    .padding(16)
                }
            } else {
                // Friend list
                if friendService.friends.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Friends Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Add friends from the Social tab to share workouts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Spacer()
                    }
                    .padding(32)
                } else {
                    List {
                        // Top Friends section (ranked 1-3)
                        if rankingService.rankedFriends.count >= 1 {
                            Section {
                                ForEach(rankingService.rankedFriends.prefix(3)) { rankedFriend in
                                    if let friend = friendService.friends.first(where: { $0.friendId == rankedFriend.friendId }) {
                                        Button(action: {
                                            HapticManager.impact(.light)
                                            withAnimation(.spring(response: 0.3)) {
                                                selectedFriend = friend
                                            }
                                        }) {
                                            RankedFriendSelectionRow(
                                                friend: friend,
                                                rankedFriend: rankedFriend,
                                                accentColor: accentColor
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            } header: {
                                HStack(spacing: 6) {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.orange)
                                    Text("Top Friends")
                                        .textCase(nil)
                                }
                            }
                        }
                        
                        // All friends section
                        Section {
                            let topFriendIds = Set(rankingService.rankedFriends.prefix(3).map { $0.friendId })
                            let otherFriends = friendService.friends.filter { !topFriendIds.contains($0.friendId) }
                            
                            ForEach(otherFriends) { friend in
                                Button(action: {
                                    HapticManager.impact(.light)
                                    withAnimation(.spring(response: 0.3)) {
                                        selectedFriend = friend
                                    }
                                }) {
                                    FriendSelectionRow(friend: friend, accentColor: accentColor)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        } header: {
                            Text(rankingService.rankedFriends.count >= 1 ? "All Friends" : "Select a friend")
                                .textCase(nil)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
    }
    
    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .teal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 8) {
                Text("Workout Sent!")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let friend = selectedFriend {
                    Text("Your workout has been sent to \(friend.displayName)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Spacer()
            
            Button(action: {
                dismiss()
            }) {
                Text("Done")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Workout Preview Card
    private var workoutPreviewCard: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(workoutName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    if let date = workout.date {
                        Text(formatDate(date))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            
            Divider()
            
            // Stats row
            HStack(spacing: 0) {
                ShareStatItem(value: "\(duration)", unit: "min", icon: "clock.fill", color: Color.blue)
                
                Divider()
                    .frame(height: 30)
                
                ShareStatItem(value: "\(exerciseCount)", unit: "exercises", icon: "figure.strengthtraining.traditional", color: Color.green)
                
                Divider()
                    .frame(height: 30)
                
                ShareStatItem(value: "\(totalSets)", unit: "sets", icon: "repeat", color: Color.orange)
            }
            
            // Exercise list preview
            if !workoutExercises.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(workoutExercises.prefix(3), id: \.id) { we in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(accentColor.opacity(0.2))
                                .frame(width: 6, height: 6)
                            
                            Text(we.safeDisplayName)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                        }
                    }
                    
                    if workoutExercises.count > 3 {
                        Text("+\(workoutExercises.count - 3) more exercises")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helpers
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(colorScheme == .dark ? Color(white: 0.12) : Color.white)
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        var cleanName = name
        let patterns = [" - [A-Z][a-z]+ \\d+$", " - [A-Z][a-z]+$", " - \\d{1,2}/\\d{1,2}$"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(cleanName.startIndex..., in: cleanName)
                cleanName = regex.stringByReplacingMatches(in: cleanName, range: range, withTemplate: "")
            }
        }
        return cleanName.trimmingCharacters(in: .whitespaces)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }
    
    private func sendWorkoutToFriend() {
        guard let friend = selectedFriend else { return }
        
        isSending = true
        
        // Convert workout exercises to SharedExercise format
        let sharedExercises = workoutExercises.compactMap { we -> SharedExercise? in
            guard let name = we.exercise?.name ?? we.exercise?.displayName else { return nil }
            
            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            let completedSets = sets.filter { $0.isCompleted }
            
            // Get best set info for reps
            let repsString: String
            if let bestSet = completedSets.max(by: { $0.reps < $1.reps }) {
                repsString = "\(bestSet.reps)"
            } else {
                repsString = "8-12"
            }
            
            return SharedExercise(
                name: name,
                sets: completedSets.count,
                reps: repsString,
                restSeconds: nil,
                notes: nil
            )
        }
        
        Task {
            let success = await friendService.sendWorkoutToFriend(
                toUserId: friend.friendId,
                workoutName: workoutName,
                exercises: sharedExercises,
                description: "Shared from completed workout",
                message: messageText.isEmpty ? nil : messageText,
                duration: duration,
                difficulty: "Custom"
            )
            
            await MainActor.run {
                isSending = false
                
                if success {
                    HapticManager.notification(.success)
                    withAnimation(.spring(response: 0.4)) {
                        showingSuccess = true
                    }
                } else {
                    HapticManager.notification(.error)
                    sendError = "Failed to send workout. Please try again."
                }
            }
        }
    }
}

// MARK: - Friend Selection Row
private struct FriendSelectionRow: View {
    let friend: Friend
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar (cached)
            CachedFriendPhoto(
                friendId: friend.friendId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                size: 44,
                showGradientRing: false,
                gradientColors: [accentColor, accentColor.opacity(0.7)]
            )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if let goal = friend.fitnessGoal {
                    Text(goal)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accentColor, accentColor.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
            
            Text(String(friend.displayName.prefix(1)).uppercased())
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Ranked Friend Selection Row (for top friends)
private struct RankedFriendSelectionRow: View {
    let friend: Friend
    let rankedFriend: RankedFriend
    let accentColor: Color
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar (cached) with rank badge
            ZStack(alignment: .bottomTrailing) {
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 44,
                    showGradientRing: true,
                    gradientColors: [accentColor, accentColor.opacity(0.7)]
                )
                
                // Rank badge
                Text(rankEmoji)
                    .font(.system(size: 14))
                    .offset(x: 4, y: 4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(friend.displayName)
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Relationship tier badge
                    HStack(spacing: 3) {
                        Image(systemName: rankedFriend.relationshipTier.icon)
                            .font(.system(size: 9))
                        Text("\(Int(rankedFriend.relationshipScore))")
                            .font(.caption2)
                            .fontWeight(.bold)
                    }
                    .foregroundColor(rankedFriend.relationshipTier.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(rankedFriend.relationshipTier.color.opacity(0.15))
                    )
                }
                
                // Interaction summary
                HStack(spacing: 8) {
                    if rankedFriend.workoutsShared > 0 {
                        Label("\(rankedFriend.workoutsShared) shared", systemImage: "dumbbell.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    if rankedFriend.challengesTogether > 0 {
                        Label("\(rankedFriend.challengesTogether) challenges", systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if rankedFriend.workoutsShared == 0 && rankedFriend.challengesTogether == 0 {
                        Text("New workout buddy!")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var rankEmoji: String {
        switch rankedFriend.rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "⭐️"
        }
    }
    
    private var rankGradient: LinearGradient {
        switch rankedFriend.rank {
        case 1: return LinearGradient(colors: [.orange, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 2: return LinearGradient(colors: [.gray, .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case 3: return LinearGradient(colors: [.orange.opacity(0.7), .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
        default: return LinearGradient(colors: [accentColor, accentColor.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(rankGradient)
                .frame(width: 44, height: 44)
            
            Text(String(friend.displayName.prefix(1)).uppercased())
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Share Stat Item
private struct ShareStatItem: View {
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            Text(unit)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
#Preview {
    // Create a mock workout for preview
    let context = PersistenceController.preview.container.viewContext
    let workout = Workout(context: context)
    workout.id = UUID()
    workout.name = "Morning Chest Workout"
    workout.date = Date()
    workout.duration = 45 * 60
    workout.isCompleted = true
    
    return ShareWorkoutSheet(workout: workout, accentColor: .blue)
}
