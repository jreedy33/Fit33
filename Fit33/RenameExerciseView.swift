import SwiftUI
import CoreData

// MARK: - Rename Exercise View
struct RenameExerciseView: View {
    let exercise: Exercise
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var nickname: String = ""
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    @FocusState private var isTextFieldFocused: Bool
    
    private var officialName: String {
        exercise.displayName
    }
    
    private var hasExistingNickname: Bool {
        ExerciseNicknameService.shared.hasNickname(for: officialName)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Exercise icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "pencil.line")
                        .font(.ds_heading1)
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)
                
                // Official name display
                VStack(spacing: 4) {
                    Text("Official Name")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(officialName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Nickname input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your Custom Name")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    TextField("Enter nickname...", text: $nickname)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color(.systemGray6))
                        )
                        .focused($isTextFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit {
                            saveNickname()
                        }
                    
                    Text("This name will appear everywhere in your app")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Action buttons
                VStack(spacing: 12) {
                    // Save button
                    Button(action: saveNickname) {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "checkmark")
                                Text("Save Nickname")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(nickname.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                        )
                    }
                    .disabled(nickname.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    
                    // Reset to official name (only show if there's an existing nickname)
                    if hasExistingNickname {
                        Button(action: resetToOfficialName) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Reset to Official Name")
                            }
                            .font(.subheadline)
                            .foregroundColor(.red)
                        }
                        .disabled(isSaving)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationTitle("Rename Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Pre-fill with existing nickname if one exists
                if let existingNickname = ExerciseNicknameService.shared.nicknames[officialName.lowercased()] {
                    nickname = existingNickname
                }
                
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.3))
                    guard !Task.isCancelled else { return }
                    isTextFieldFocused = true
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func saveNickname() {
        let trimmedNickname = nickname.trimmingCharacters(in: .whitespaces)
        guard !trimmedNickname.isEmpty else { return }
        
        isSaving = true
        
        Task {
            do {
                try await ExerciseNicknameService.shared.setNickname(
                    trimmedNickname,
                    for: officialName,
                    exerciseId: exercise.id
                )
                
                await MainActor.run {
                    HapticManager.notification(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                    HapticManager.notification(.error)
                }
            }
        }
    }
    
    private func resetToOfficialName() {
        isSaving = true
        
        Task {
            do {
                try await ExerciseNicknameService.shared.removeNickname(for: officialName)
                
                await MainActor.run {
                    HapticManager.notification(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}
