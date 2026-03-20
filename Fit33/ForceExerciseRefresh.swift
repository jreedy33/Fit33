import SwiftUI

struct ForceExerciseRefreshView: View {
    @State private var isRefreshing = false
    @State private var refreshComplete = false
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
                    Text("Exercises refreshed!")
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
                    .cornerRadius(CornerRadius.lg)
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
            await ExerciseLibraryService.shared.forceSyncExercises()
            await MainActor.run {
                isRefreshing = false
                refreshComplete = true
                HapticManager.notification(.success)
            }
        }
    }
}

#Preview {
    ForceExerciseRefreshView()
}
