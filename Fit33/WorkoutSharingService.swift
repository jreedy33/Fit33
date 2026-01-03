import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Workout Sharing Service
/// Handles all sharing functionality for the app - both app invites and workout sharing

@MainActor
class WorkoutSharingService: ObservableObject {
    static let shared = WorkoutSharingService()
    
    // MARK: - App Store Constants
    // TODO: Replace with your actual App Store URL once published
    private let appStoreURL = "https://apps.apple.com/app/fit33/id123456789" // Placeholder
    private let appWebsiteURL = "https://fit33.app" // Your website
    private let deepLinkScheme = "fit33"
    
    // MARK: - Shared Workout State
    @Published var pendingSharedWorkout: SharedWorkoutData?
    @Published var showSharedWorkoutSheet = false
    
    private init() {}
    
    // MARK: - App Sharing
    
    /// Share the app with a pre-filled message
    func shareApp(from viewController: UIViewController? = nil) {
        let shareMessage = """
        💪 Check out Fit33 - the smart workout app that creates personalized programs just for you!
        
        🎯 AI-powered exercise selection
        📊 Track your progress & PRs
        🏋️ 500+ exercises with video demos
        
        Download free: \(appStoreURL)
        """
        
        presentShareSheet(items: [shareMessage], from: viewController)
    }
    
    /// Share via iMessage specifically
    func shareAppViaMessages() {
        let message = "Hey! I've been using Fit33 for my workouts - it's awesome! Try it out: \(appStoreURL)"
        
        if let url = URL(string: "sms:&body=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            UIApplication.shared.open(url)
        }
    }
    
    /// Share via WhatsApp specifically
    func shareAppViaWhatsApp() {
        let message = "Hey! 💪 Check out Fit33 - the smart workout app I've been using. Download free: \(appStoreURL)"
        
        if let url = URL(string: "whatsapp://send?text=\(message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // WhatsApp not installed - fall back to share sheet
                shareApp()
            }
        }
    }
    
    // MARK: - Workout Sharing
    
    /// Create a shareable link for a completed workout
    func createShareableWorkoutLink(workout: Workout) -> URL? {
        guard let workoutId = workout.id?.uuidString else { return nil }
        
        // Create a deep link URL
        // Format: fit33://workout/{workoutId}
        var components = URLComponents()
        components.scheme = deepLinkScheme
        components.host = "workout"
        components.path = "/\(workoutId)"
        
        // Add workout metadata as query params for preview
        var queryItems: [URLQueryItem] = []
        
        if let name = workout.name {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        queryItems.append(URLQueryItem(name: "exercises", value: "\(exercises.count)"))
        
        let duration = Int(workout.duration) / 60
        queryItems.append(URLQueryItem(name: "duration", value: "\(duration)"))
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        return components.url
    }
    
    /// Share a completed workout with rich preview
    func shareWorkout(workout: Workout, from viewController: UIViewController? = nil) {
        let exercises = workout.exercises?.allObjects as? [WorkoutExercise] ?? []
        let exerciseCount = exercises.count
        let duration = Int(workout.duration) / 60
        let totalSets = exercises.reduce(0) { total, we in
            let sets = we.sets?.allObjects as? [WorkoutSet] ?? []
            return total + sets.filter { $0.isCompleted }.count
        }
        
        // Create workout summary
        let workoutName = cleanWorkoutName(workout.name ?? "Workout")
        let exerciseNames = exercises
            .compactMap { $0.exercise?.name }
            .prefix(3)
            .joined(separator: ", ")
        let moreExercises = exerciseCount > 3 ? " +\(exerciseCount - 3) more" : ""
        
        let shareMessage = """
        💪 Just crushed: \(workoutName)
        
        ⏱ \(duration) min • 🏋️ \(exerciseCount) exercises • 📊 \(totalSets) sets
        
        Exercises: \(exerciseNames)\(moreExercises)
        
        Try this workout on Fit33! 👇
        \(appStoreURL)
        """
        
        // If we have a shareable link, include it
        if let shareURL = createShareableWorkoutLink(workout: workout) {
            let workoutLinkMessage = """
            💪 Try my workout: \(workoutName)
            
            ⏱ \(duration) min • 🏋️ \(exerciseCount) exercises
            
            Tap to open in Fit33:
            \(shareURL.absoluteString)
            
            Don't have the app? Download free:
            \(appStoreURL)
            """
            presentShareSheet(items: [workoutLinkMessage], from: viewController)
        } else {
            presentShareSheet(items: [shareMessage], from: viewController)
        }
    }
    
    /// Share workout summary as an image (for social media)
    func shareWorkoutAsImage(workout: Workout, stats: WorkoutShareStats, from viewController: UIViewController? = nil) {
        // Create a visual summary card
        let renderer = ImageRenderer(content: WorkoutShareCard(workout: workout, stats: stats))
        renderer.scale = UIScreen.main.scale
        
        if let image = renderer.uiImage {
            let shareMessage = "💪 Workout complete! #Fit33 #FitnessGoals"
            presentShareSheet(items: [image, shareMessage], from: viewController)
        } else {
            // Fallback to text-only sharing
            shareWorkout(workout: workout, from: viewController)
        }
    }
    
    // MARK: - Receiving Shared Workouts
    
    /// Handle a deep link URL for a shared workout
    func handleSharedWorkoutURL(_ url: URL) -> Bool {
        guard url.scheme == deepLinkScheme,
              url.host == "workout" else {
            return false
        }
        
        // Extract workout ID from path
        let path = url.path
        let workoutId = path.hasPrefix("/") ? String(path.dropFirst()) : path
        
        guard !workoutId.isEmpty else { return false }
        
        // Extract preview data from query params
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        
        let name = queryItems.first(where: { $0.name == "name" })?.value ?? "Shared Workout"
        let exerciseCount = Int(queryItems.first(where: { $0.name == "exercises" })?.value ?? "0") ?? 0
        let duration = Int(queryItems.first(where: { $0.name == "duration" })?.value ?? "0") ?? 0
        
        // Create pending shared workout data
        pendingSharedWorkout = SharedWorkoutData(
            workoutId: workoutId,
            name: name,
            exerciseCount: exerciseCount,
            duration: duration
        )
        
        showSharedWorkoutSheet = true
        
        print("📥 [SHARE] Received shared workout: \(name) (\(workoutId))")
        return true
    }
    
    /// Load full workout details from the server
    func loadSharedWorkout(workoutId: String) async -> SharedWorkoutDetails? {
        // TODO: Implement Supabase query to load shared workout
        // For now, check local storage
        
        let context = PersistenceController.shared.container.viewContext
        let fetchRequest: NSFetchRequest<Workout> = Workout.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", workoutId)
        fetchRequest.fetchLimit = 1
        
        do {
            if let workout = try context.fetch(fetchRequest).first {
                return SharedWorkoutDetails(
                    workout: workout,
                    exercises: (workout.exercises?.allObjects as? [WorkoutExercise])?.compactMap { $0.exercise } ?? []
                )
            }
        } catch {
            print("❌ [SHARE] Error loading shared workout: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func presentShareSheet(items: [Any], from viewController: UIViewController? = nil) {
        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        
        // Exclude some activities that don't make sense
        activityVC.excludedActivityTypes = [
            .addToReadingList,
            .assignToContact,
            .openInIBooks
        ]
        
        // Get the presenting view controller
        if let vc = viewController {
            vc.present(activityVC, animated: true)
        } else if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController {
            // Handle iPad popover
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func cleanWorkoutName(_ name: String) -> String {
        // Remove date suffixes like " - Jan 3" or " - 1/3"
        if let range = name.range(of: " - ", options: .backwards) {
            let potentialDate = String(name[range.upperBound...])
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if months.contains(where: { potentialDate.contains($0) }) || potentialDate.first?.isNumber == true {
                return String(name[..<range.lowerBound])
            }
        }
        return name
    }
}

// MARK: - Supporting Data Structures

struct SharedWorkoutData: Identifiable {
    let id = UUID()
    let workoutId: String
    let name: String
    let exerciseCount: Int
    let duration: Int
}

struct SharedWorkoutDetails {
    let workout: Workout
    let exercises: [Exercise]
}

struct WorkoutShareStats {
    let duration: String
    let exerciseCount: Int
    let totalSets: Int
    let totalReps: Int
    let totalVolume: Double
}

// MARK: - Workout Share Card (for Image Generation)

struct WorkoutShareCard: View {
    let workout: Workout
    let stats: WorkoutShareStats
    
    private var workoutName: String {
        // Clean the workout name
        let name = workout.name ?? "Workout"
        if let range = name.range(of: " - ", options: .backwards) {
            return String(name[..<range.lowerBound])
        }
        return name
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Workout Complete!")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(workoutName)
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            
            // Stats Grid
            HStack(spacing: 24) {
                WorkoutShareStatBubble(value: stats.duration, label: "Duration", icon: "clock.fill", color: .blue)
                WorkoutShareStatBubble(value: "\(stats.exerciseCount)", label: "Exercises", icon: "dumbbell.fill", color: .green)
                WorkoutShareStatBubble(value: "\(stats.totalSets)", label: "Sets", icon: "repeat", color: .orange)
            }
            
            // App branding
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                Text("Fit33")
                    .fontWeight(.bold)
            }
            .font(.headline)
            .foregroundColor(.primary)
        }
        .padding(32)
        .frame(width: 375)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.98), Color(white: 0.95)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

private struct WorkoutShareStatBubble: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Share Action Button Component

struct ShareButton: View {
    let action: () -> Void
    var style: ShareButtonStyle = .icon
    
    enum ShareButtonStyle {
        case icon
        case iconWithLabel
        case fullWidth
    }
    
    var body: some View {
        Button(action: {
            HapticManager.impact(.light)
            action()
        }) {
            switch style {
            case .icon:
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.blue)
            
            case .iconWithLabel:
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                    Text("Share")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.blue)
            
            case .fullWidth:
                HStack {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                    Text("Share Workout")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Invite Friends Section Component

struct InviteFriendsSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingShareOptions = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.blue)
                Text("Invite Friends")
                    .font(.headline)
                    .fontWeight(.bold)
            }
            
            VStack(spacing: 12) {
                // Main share button
                Button(action: {
                    showingShareOptions = true
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
                            
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share Fit33")
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text("Invite friends to workout together")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(Color.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .confirmationDialog("Share Fit33", isPresented: $showingShareOptions) {
            Button("Share via Messages") {
                WorkoutSharingService.shared.shareAppViaMessages()
            }
            
            Button("Share via WhatsApp") {
                WorkoutSharingService.shared.shareAppViaWhatsApp()
            }
            
            Button("More Options...") {
                WorkoutSharingService.shared.shareApp()
            }
            
            Button("Cancel", role: .cancel) {}
        }
    }
}
