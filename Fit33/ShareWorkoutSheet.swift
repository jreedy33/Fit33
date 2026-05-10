import SwiftUI
import CoreData

// MARK: - Share Workout Sheet

struct ShareWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let workout: Workout
    let accentColor: Color
    var onFinish: (() -> Void)? = nil
    
    @ObservedObject private var friendService = FriendService.shared
    @ObservedObject private var rankingService = FriendRankingService.shared
    // Multi-select up to 3 (matches the challenge-flow share page); see
    // `FriendShareSelectionSheet`. Bubble-row taps toggle add/remove;
    // "Search" opens the full multi-select picker.
    @State private var selectedFriends: [Friend] = []
    @State private var sentFriendsSnapshot: [Friend] = []
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showingSuccess = false
    @State private var sendError: String?
    @State private var isCardExpanded = false
    @State private var showingFriendSearch = false
    
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
    
    private var workoutGradient: [Color] {
        [accentColor, accentColor.opacity(0.7)]
    }
    
    private var topMuscles: [String] {
        var muscleCount: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        for we in workoutExercises {
            for muscle in we.safeMuscleGroups {
                let key = muscle.capitalized
                muscleCount[key, default: 0] += 1
                if firstSeen[key] == nil {
                    firstSeen[key] = order
                    order += 1
                }
            }
        }
        return muscleCount.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return (firstSeen[$0.key] ?? 0) < (firstSeen[$1.key] ?? 0)
        }.prefix(3).map { $0.key }
    }
    
    private var friendsForPicker: [Friend] {
        let rankedIds = rankingService.rankedFriends.prefix(5).map { $0.friendId }
        var result: [Friend] = []
        for friendId in rankedIds {
            if let friend = friendService.friends.first(where: { $0.friendId == friendId }) {
                result.append(friend)
            }
        }
        let remaining = friendService.friends.filter { f in !result.contains(where: { $0.friendId == f.friendId }) }
        result.append(contentsOf: remaining)
        return Array(result.prefix(5))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedOrbBackground.workout(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                if showingSuccess {
                    successView
                } else if !selectedFriends.isEmpty {
                    composeMessageView
                } else {
                    mainShareView
                }
            }
            .navigationTitle("Share Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !showingSuccess {
                        Button(action: {
                            if !selectedFriends.isEmpty {
                                withAnimation(.spring(response: 0.3)) {
                                    selectedFriends = []
                                }
                            } else {
                                dismiss()
                            }
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.ds_labelLarge)
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        onFinish?()
                        dismiss()
                    }) {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                }
            }
            .adaptiveToolbarBackground()
            .alert("Error", isPresented: .init(
                get: { sendError != nil },
                set: { if !$0 { sendError = nil } }
            )) {
                Button("OK") { sendError = nil }
            } message: {
                Text(sendError ?? "")
            }
        }
        .sheet(isPresented: $showingFriendSearch) {
            // Multi-select picker (mirrors the challenge-flow "Who do you
            // want to challenge?" page — same 3-bubble row, search,
            // frosted cards, blue orb). Returns up to 3 chosen friends;
            // the compose view below handles message + fan-out send.
            // NEVER reuse `FriendsListView` here — that's the friends-
            // management hub and routes taps to `FriendProfileView`.
            FriendShareSelectionSheet(initialSelection: selectedFriends) { picked in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    selectedFriends = picked
                }
            }
        }
        .task {
            await friendService.fetchFriends()
            await rankingService.fetchRankedFriends()
        }
    }
    
    // MARK: - Main Share View
    private var mainShareView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                expandableShareCard
                    .padding(.top, Spacing.xs)
                
                // Send to Friend section
                if !friendService.friends.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "person.fill")
                                .font(.ds_labelMedium)
                                .foregroundColor(.blue)
                            Text("Send to Friend")
                                .font(.ds_heading3)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, Spacing.md)
                        
                        horizontalFriendPicker
                    }
                } else {
                    noFriendsHint
                }
                
                // Share Via section
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.ds_labelMedium)
                            .foregroundColor(.green)
                        Text("Share Via")
                            .font(.ds_heading3)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, Spacing.md)
                    
                    Button(action: {
                        HapticManager.impact(.light)
                        WorkoutSharingService.shared.shareWorkout(workout: workout)
                    }) {
                        HStack(spacing: Spacing.sm) {
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
                                    .font(.ds_heading3)
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                                Text("Messages, Instagram & more")
                                    .font(.ds_labelMedium)
                                    .foregroundColor(.primary)
                                Text("Share via other apps")
                                    .font(.ds_bodySmall)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.ds_bodySmall).fontWeight(.medium)
                                .foregroundColor(.secondary)
                        }
                        .padding(Spacing.md)
                        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.horizontal, Spacing.md)
                }
            }
            .padding(.bottom, Spacing.xl)
        }
    }
    
    // MARK: - Expandable Share Card
    private var expandableShareCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isCardExpanded.toggle()
                }
            }) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: workoutGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2.5
                                )
                                .frame(width: 48, height: 48)
                            
                            Image(systemName: "checkmark")
                                .font(.ds_heading3)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: workoutGradient,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text(workoutName)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if let date = workout.date {
                                Text(formatDate(date))
                                    .font(.ds_bodySmall)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Image(systemName: isCardExpanded ? "chevron.up" : "chevron.down")
                            .font(.ds_labelMedium).fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.top, Spacing.xs)
                    }
                    
                    Divider()
                        .padding(.vertical, Spacing.sm)
                    
                    HStack(spacing: 0) {
                        ShareStatItem(value: "\(duration)", unit: "min", icon: "clock.fill", color: .blue)
                        Divider().frame(height: 30)
                        ShareStatItem(value: "\(exerciseCount)", unit: "exercises", icon: "figure.strengthtraining.traditional", color: .green)
                        Divider().frame(height: 30)
                        ShareStatItem(value: "\(totalSets)", unit: "sets", icon: "repeat", color: .orange)
                    }
                    
                    if !topMuscles.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(topMuscles, id: \.self) { muscle in
                                Text(muscle)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(accentColor)
                                    .padding(.horizontal, Spacing.xs)
                                    .padding(.vertical, Spacing.xxs)
                                    .background(
                                        Capsule().fill(accentColor.opacity(0.12))
                                    )
                            }
                            Spacer()
                        }
                        .padding(.top, Spacing.sm)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isCardExpanded && !workoutExercises.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.top, Spacing.sm)
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(workoutExercises, id: \.id) { we in
                            shareExerciseRow(we)
                        }
                    }
                    .padding(.top, Spacing.sm)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: accentColor)
        .padding(.horizontal, Spacing.md)
    }
    
    private func shareExerciseRow(_ we: WorkoutExercise) -> some View {
        let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
        let completedSets = sets.filter { $0.isCompleted }
        
        return HStack(spacing: Spacing.sm) {
            Circle()
                .fill(accentColor.opacity(0.15))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.ds_labelSmall)
                        .foregroundColor(accentColor)
                )
            
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(we.safeDisplayName)
                    .font(.ds_labelMedium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(completedSets.count) sets")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, Spacing.xxs)
    }
    
    // MARK: - Horizontal Friend Picker
    private var horizontalFriendPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                // Search friend button
                Button(action: {
                    HapticManager.impact(.light)
                    showingFriendSearch = true
                }) {
                    VStack(spacing: Spacing.xs) {
                        ZStack {
                            Circle()
                                .fill(Color.cardBackground)
                                .frame(width: 56, height: 56)
                                .overlay(
                                    Circle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1.5)
                                )
                            
                            Image(systemName: "magnifyingglass")
                                .font(.ds_heading3)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("Search")
                            .font(.ds_bodySmall)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: 64)
                }
                .buttonStyle(PlainButtonStyle())
                
                ForEach(friendsForPicker) { friend in
                    Button(action: { toggleFriend(friend) }) {
                        VStack(spacing: Spacing.xs) {
                            CachedFriendPhoto(
                                friendId: friend.friendId.uuidString,
                                photoUrl: friend.profilePhotoUrl,
                                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                                size: 56,
                                showGradientRing: isFriendSelected(friend),
                                gradientColors: [accentColor, accentColor.opacity(0.7)]
                            )
                            .scaleEffect(isFriendSelected(friend) ? 1.06 : 1.0)

                            Text(friend.displayName.components(separatedBy: " ").first ?? friend.displayName)
                                .font(.ds_bodySmall)
                                .fontWeight(isFriendSelected(friend) ? .semibold : .regular)
                                .foregroundColor(isFriendSelected(friend) ? accentColor : .primary)
                                .lineLimit(1)
                        }
                        .frame(width: 64)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFriendSelected(friend))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .accessibilityLabel(
                        isFriendSelected(friend)
                            ? "\(friend.displayName), selected"
                            : friend.displayName
                    )
                    .accessibilityHint(
                        isFriendSelected(friend)
                            ? "Removes from recipients"
                            : "Adds to recipients (max 3)"
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }
    
    // MARK: - No Friends Hint
    private var noFriendsHint: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: "person.2.slash")
                .font(.ds_heading1)
                .foregroundColor(.secondary)
            
            Text("No Friends Yet")
                .font(.ds_heading3)
                .foregroundColor(.primary)
            
            Text("Add friends from the Social tab to share workouts in-app")
                .font(.ds_bodySmall)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.lg)
        .padding(.horizontal, Spacing.xl)
    }
    
    // MARK: - Compose Message View
    private var composeMessageView: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                if !selectedFriends.isEmpty {
                    composeRecipientsCard
                }

                expandableShareCard
                    .padding(.horizontal, -Spacing.md)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Add a message (optional)")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)

                    TextField("Great workout! Try it out", text: $messageText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.ds_bodyMedium)
                        .padding(Spacing.sm)
                        .background(Color.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
                        .lineLimit(3...5)
                }

                Button(action: sendWorkoutToFriends) {
                    HStack(spacing: Spacing.xs) {
                        if isSending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.ds_labelLarge)
                            Text(sendButtonTitle)
                                .font(.ds_labelLarge)
                                .fontWeight(.bold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
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
                .padding(.top, Spacing.xs)
            }
            .padding(Spacing.md)
        }
    }

    private var sendButtonTitle: String {
        switch selectedFriends.count {
        case 0:  return "Send Workout"
        case 1:  return "Send Workout"
        default: return "Send to \(selectedFriends.count) Friends"
        }
    }

    private var composeRecipientsCard: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(selectedFriends.count == 1
                     ? "Sending to"
                     : "Sending to \(selectedFriends.count) friends")
                    .font(.ds_bodySmall)
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(selectedFriends) { friend in
                        HStack(spacing: 6) {
                            CachedFriendPhoto(
                                friendId: friend.friendId.uuidString,
                                photoUrl: friend.profilePhotoUrl,
                                name: friend.friendName ?? friend.friendUsername ?? "Friend",
                                size: 22,
                                showGradientRing: false,
                                gradientColors: [accentColor, accentColor.opacity(0.7)]
                            )
                            Text(friend.friendName?.components(separatedBy: " ").first
                                 ?? friend.friendUsername ?? "Friend")
                                .font(.ds_bodySmall)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                            Button(action: { toggleFriend(friend) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.ds_bodySmall)
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .accessibilityLabel("Remove \(friend.displayName)")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(accentColor.opacity(0.15))
                                .overlay(
                                    Capsule()
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1)
                                )
                        )
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }

            Spacer(minLength: Spacing.xs)

            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    selectedFriends = []
                }
            }) {
                Text("Change")
                    .font(.ds_labelMedium)
                    .foregroundColor(accentColor)
            }
            .accessibilityLabel("Change recipients")
        }
        .padding(Spacing.md)
        .adaptiveSleekCardSubtle(cornerRadius: CornerRadius.lg)
    }

    private func isFriendSelected(_ friend: Friend) -> Bool {
        selectedFriends.contains(where: { $0.friendId == friend.friendId })
    }

    private func toggleFriend(_ friend: Friend) {
        HapticManager.impact(.light)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            if let idx = selectedFriends.firstIndex(where: { $0.friendId == friend.friendId }) {
                selectedFriends.remove(at: idx)
            } else if selectedFriends.count < 3 {
                selectedFriends.append(friend)
            } else {
                // At cap — replace the oldest pick (FIFO).
                selectedFriends.removeFirst()
                selectedFriends.append(friend)
            }
        }
    }
    
    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: Spacing.lg) {
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
                    .font(.ds_displayMedium)
                    .foregroundColor(.white)
            }
            
            VStack(spacing: Spacing.xs) {
                Text("Workout Sent!")
                    .font(.ds_heading2)
                    .fontWeight(.bold)

                Text(successHeadline)
                    .font(.ds_bodyMedium)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Text("Done")
                    .font(.ds_labelLarge)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [accentColor, accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.xl)
        }
    }
    
    // MARK: - Helpers
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
    
    private var successHeadline: String {
        switch sentFriendsSnapshot.count {
        case 0:
            return "Your workout has been sent."
        case 1:
            return "Your workout has been sent to \(sentFriendsSnapshot[0].displayName)."
        case 2:
            let a = sentFriendsSnapshot[0].friendName?.components(separatedBy: " ").first ?? sentFriendsSnapshot[0].displayName
            let b = sentFriendsSnapshot[1].friendName?.components(separatedBy: " ").first ?? sentFriendsSnapshot[1].displayName
            return "Your workout has been sent to \(a) & \(b)."
        default:
            let first = sentFriendsSnapshot[0].friendName?.components(separatedBy: " ").first ?? sentFriendsSnapshot[0].displayName
            return "Your workout has been sent to \(first) and \(sentFriendsSnapshot.count - 1) others."
        }
    }

    private func sendWorkoutToFriends() {
        guard !selectedFriends.isEmpty else { return }

        isSending = true

        let sharedExercises = workoutExercises.compactMap { we -> SharedExercise? in
            guard let name = we.exercise?.name ?? we.exercise?.displayName else { return nil }

            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            let completedSets = sets.filter { $0.isCompleted }

            let repsString: String
            if let bestSet = completedSets.max(by: { $0.reps < $1.reps }) {
                repsString = "\(bestSet.reps)"
            } else {
                repsString = "8-12"
            }

            return SharedExercise(
                exerciseId: we.exercise?.id?.uuidString,
                name: name,
                sets: completedSets.count,
                reps: repsString,
                restSeconds: nil,
                notes: nil
            )
        }

        let recipients = selectedFriends
        let nameToSend = workoutName
        let durationMinutes = duration
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            // Fan out one RPC per recipient, concurrently.
            let successes = await withTaskGroup(of: (UUID, Bool).self, returning: Int.self) { group in
                for friend in recipients {
                    group.addTask {
                        let ok = await friendService.sendWorkoutToFriend(
                            toUserId: friend.friendId,
                            workoutName: nameToSend,
                            exercises: sharedExercises,
                            description: "Shared from completed workout",
                            message: trimmedMessage.isEmpty ? nil : trimmedMessage,
                            duration: durationMinutes,
                            difficulty: "Custom"
                        )
                        return (friend.friendId, ok)
                    }
                }
                var count = 0
                for await (_, ok) in group where ok {
                    count += 1
                }
                return count
            }

            await MainActor.run {
                isSending = false

                if successes == recipients.count {
                    HapticManager.notification(.success)
                    sentFriendsSnapshot = recipients
                    withAnimation(.spring(response: 0.4)) {
                        showingSuccess = true
                    }
                } else if successes > 0 {
                    HapticManager.notification(.warning)
                    sentFriendsSnapshot = recipients
                    sendError = "Sent to \(successes) of \(recipients.count) friends. Some sends failed — please try the rest again later."
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
                    .font(.ds_labelSmall)
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
    let context = PersistenceController.preview.container.viewContext
    let workout = Workout(context: context)
    workout.id = UUID()
    workout.name = "Morning Chest Workout"
    workout.date = Date()
    workout.duration = 45 * 60
    workout.isCompleted = true
    
    return ShareWorkoutSheet(workout: workout, accentColor: .blue)
}
