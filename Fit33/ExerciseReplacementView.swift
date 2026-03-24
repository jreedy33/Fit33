import SwiftUI

struct ExerciseReplacementView: View {
    @Environment(\.dismiss) private var dismiss
    let currentExercise: Exercise
    let onReplaceExercise: () -> Void
    
    @State private var similarExercises: [Exercise] = []
    @State private var selectedExercise: Exercise?
    
    var body: some View {
        NavigationStack {
            VStack {
                if similarExercises.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("Finding similar exercises...")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(similarExercises, id: \.id) { exercise in
                        ExerciseReplacementRow(
                            exercise: exercise,
                            isSelected: selectedExercise?.id == exercise.id
                        ) {
                            selectedExercise = exercise
                        }
                    }
                }
            }
            .navigationTitle("Replace Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                LinearGradient(
                    gradient: Gradient(colors: [Color.green.opacity(0.1), Color.blue.opacity(0.05)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), for: .navigationBar
            )
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Replace") {
                        if selectedExercise != nil {
                            onReplaceExercise()
                            dismiss()
                        }
                    }
                    .disabled(selectedExercise == nil)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                loadSimilarExercises()
            }
        }
    }
    
    private func loadSimilarExercises() {
        // Use smart alternative engine for intelligent matching
        Task {
            let userEquipment = UserManager.shared.currentUser?.getEquipment() ?? []
            
            let alternatives = SmartExercisePairingEngine.shared.getAlternatives(
                for: currentExercise,
                userEquipment: userEquipment,
                excludeIds: [],
                maxResults: 15
            )
            
            await MainActor.run {
                similarExercises = alternatives.map { $0.exercise }
                AppLogger.debug("🔄 Loaded \(alternatives.count) smart alternatives for replacement", category: .workout)
                if let top = alternatives.first {
                    AppLogger.debug("   Top: \(top.exercise.name ?? "") (score: \(top.score))", category: .workout)
                }
            }
        }
    }
}

struct ExerciseReplacementRow: View {
    let exercise: Exercise
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack {
                        if let category = exercise.category {
                            Text(category)
                                .font(.caption)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        if let equipment = exercise.equipment {
                            Text(equipment)
                                .font(.caption)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            .padding(.vertical, Spacing.xs)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
