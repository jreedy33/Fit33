import SwiftUI
import CoreData

/// Temporary view to force refresh exercise data from Supabase
/// Add this as a button in Settings or Developer menu
struct ForceExerciseRefreshView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var isRefreshing = false
    @State private var refreshComplete = false
    @State private var exerciseCount = 0
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 20) {
            if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Try Again") {
                        errorMessage = nil
                        forceRefresh()
                    }
                    .buttonStyle(.bordered)
                }
            } else if isRefreshing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Refreshing exercises from database...")
                        .font(.headline)
                    Text("This may take 10-30 seconds...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if refreshComplete {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    Text("✅ Refreshed \(exerciseCount) exercises!")
                        .font(.headline)
                    Text("All exercise names updated from database")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: {
                    forceRefresh()
                }) {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        Text("Force Refresh Exercises")
                            .font(.headline)
                        Text("Pull latest data from Supabase")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
            }
        }
        .padding()
    }
    
    private func forceRefresh() {
        isRefreshing = true
        refreshComplete = false
        errorMessage = nil
        
        Task {
            do {
                // Step 1: Clear ALL exercises from Core Data
                await MainActor.run {
                    let fetchRequest: NSFetchRequest<NSFetchRequestResult> = Exercise.fetchRequest()
                    let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
                    
                    do {
                        try viewContext.execute(deleteRequest)
                        try viewContext.save()
                        print("✅ Cleared Core Data exercises")
                    } catch {
                        print("❌ Error clearing exercises: \(error)")
                        errorMessage = "Failed to clear cache: \(error.localizedDescription)"
                        isRefreshing = false
                    }
                }
                
                guard errorMessage == nil else { return }
                
                // Step 2: Invalidate cache
                await MainActor.run {
                    ExerciseLibraryService.shared.invalidateCache()
                }
                
                // Step 3: Fetch fresh from Supabase
                print("📥 Fetching exercises from Supabase...")
                let exerciseDTOs = try await SupabaseManager.shared.fetchAllExercises()
                print("✅ Fetched \(exerciseDTOs.count) exercises from Supabase")
                
                // Step 4: Save to Core Data
                await MainActor.run {
                    var savedCount = 0
                    
                    for exerciseDTO in exerciseDTOs {
                        let exercise = Exercise(context: viewContext)
                        
                        // Convert String ID to UUID
                        if let idString = exerciseDTO.id, let uuid = UUID(uuidString: idString) {
                            exercise.id = uuid
                        } else {
                            exercise.id = UUID()
                        }
                        
                        exercise.name = exerciseDTO.name
                        exercise.category = exerciseDTO.category
                        exercise.equipment = exerciseDTO.equipment
                        exercise.instructions = exerciseDTO.instructions
                        exercise.videoFilename = exerciseDTO.videoFilename
                        exercise.workoutType = exerciseDTO.workoutType
                        exercise.popularityScore = Int16(exerciseDTO.popularityScore ?? 0)
                        
                        // Convert muscle arrays
                        if let primaryMuscles = exerciseDTO.primaryMusclesRaw?.asArray {
                            exercise.muscleGroups = primaryMuscles as NSObject
                        }
                        
                        savedCount += 1
                        
                        // Save in batches to avoid memory issues
                        if savedCount % 500 == 0 {
                            do {
                                try viewContext.save()
                                print("💾 Saved batch: \(savedCount)/\(exerciseDTOs.count)")
                            } catch {
                                print("❌ Error in batch save: \(error)")
                                errorMessage = "Save failed at \(savedCount): \(error.localizedDescription)"
                                isRefreshing = false
                                return
                            }
                        }
                    }
                    
                    // Final save
                    do {
                        try viewContext.save()
                        exerciseCount = exerciseDTOs.count
                        print("✅ Saved \(exerciseDTOs.count) exercises to Core Data")
                        
                        // Invalidate cache again to force reload
                        ExerciseLibraryService.shared.invalidateCache()
                        
                        isRefreshing = false
                        refreshComplete = true
                        
                        // Haptic feedback
                        HapticManager.notification(.success)
                    } catch {
                        print("❌ Error in final save: \(error)")
                        errorMessage = "Final save failed: \(error.localizedDescription)"
                        isRefreshing = false
                    }
                }
            } catch {
                print("❌ Error fetching from Supabase: \(error)")
                await MainActor.run {
                    errorMessage = "Fetch failed: \(error.localizedDescription)"
                    isRefreshing = false
                }
            }
        }
    }
}

#Preview {
    ForceExerciseRefreshView()
}
