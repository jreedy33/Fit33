import SwiftUI

/// Settings view for managing user's physical limitations/injuries
struct LimitationsSettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var limitationsService = LimitationsService.shared
    
    @State private var showAddLimitation = false
    @State private var selectedLimitationToEdit: UserLimitation?
    @State private var showDeleteConfirmation = false
    @State private var limitationToDelete: UserLimitation?
    
    // Clean gradient card background matching app style
    
    var body: some View {
        ZStack {
            // Animated orb background (consistent with Profile/Stats screens)
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header explanation
                    headerCard
                    
                    // Safety Disclaimer
                    safetyDisclaimerCard
                    
                    // Active Limitations
                    if !limitationsService.userLimitations.isEmpty {
                        activeLimitationsSection
                    }
                    
                    // Add New Button
                    addNewButton
                    
                    // Empty State
                    if limitationsService.userLimitations.isEmpty {
                        emptyState
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Physical Limitations")
                    .font(.headline)
            }
        }
        .sheet(isPresented: $showAddLimitation) {
            AddLimitationSheet(onSave: { limitation in
                Task {
                    try? await limitationsService.addLimitation(limitation)
                }
            })
        }
        .sheet(item: $selectedLimitationToEdit) { limitation in
            EditLimitationSheet(limitation: limitation, onSave: { updated in
                Task {
                    try? await limitationsService.updateLimitation(updated)
                }
            }, onResolve: {
                Task {
                    try? await limitationsService.resolveLimitation(limitation)
                }
            })
        }
        .alert("Remove Limitation?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                if let limitation = limitationToDelete {
                    Task {
                        try? await limitationsService.deleteLimitation(limitation)
                    }
                }
            }
        } message: {
            Text("This will remove the limitation from your profile. You can add it back anytime.")
        }
        .task {
            await limitationsService.fetchUserLimitations()
        }
    }
    
    // MARK: - Header Card
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                
                Text("Your Safety First")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text("Tell us about any injuries or physical limitations so we can avoid exercises that might cause pain or discomfort.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.lg)
                .fill(Color.cardBackground)
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 8, x: 0, y: 4)
        )
    }
    
    // MARK: - Safety Disclaimer
    
    private var safetyDisclaimerCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
                
                Text("IMPORTANT SAFETY NOTICE")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .tracking(0.5)
            }
            
            Text("Fit33 is not responsible for any injuries that may occur while working out or using our app. Please consult with a healthcare professional before starting any exercise program. If you experience pain, discomfort, or any medical emergency, stop exercising immediately and seek medical attention.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.orange.opacity(0.08) : Color.orange.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Active Limitations Section
    
    private var activeLimitationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Limitations")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
            
            ForEach(limitationsService.userLimitations) { limitation in
                LimitationRowCard(
                    limitation: limitation,
                    onTap: {
                        selectedLimitationToEdit = limitation
                    },
                    onDelete: {
                        limitationToDelete = limitation
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }
    
    // MARK: - Add New Button
    
    private var addNewButton: some View {
        Button(action: { showAddLimitation = true }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [.blue.opacity(0.15), .purple.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Limitation")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Track a new injury or condition")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(colors: [.green, .mint], startPoint: .top, endPoint: .bottom)
                )
            
            Text("No Limitations")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("You haven't added any physical limitations. If you have any injuries or conditions that affect your workouts, add them here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 40)
    }
}

// MARK: - Limitation Row Card

struct LimitationRowCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let limitation: UserLimitation
    let onTap: () -> Void
    let onDelete: () -> Void
    
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Area icon with colored background
                ZStack {
                    Circle()
                        .fill(limitation.affectedArea.color.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: limitation.affectedArea.icon)
                        .font(.system(size: 20))
                        .foregroundColor(limitation.affectedArea.color)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(limitation.affectedArea.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 6) {
                        // Accommodation level badge
                        HStack(spacing: 4) {
                            Image(systemName: limitation.severity.icon)
                                .font(.system(size: 9))
                            Text(limitation.severity.displayName)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(limitation.severity.color)
                        )
                        
                        // Type badge
                        Text(limitation.limitationType.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(limitation.affectedArea.color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Limitation Sheet

struct AddLimitationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let onSave: (UserLimitation) -> Void
    
    @State private var selectedArea: AffectedArea = .lowerBack
    @State private var selectedAccommodation: AccommodationLevel = .beCareful
    @State private var selectedType: LimitationType = .injury
    @State private var notes = ""
    
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Area Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AFFECTED AREA")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(AffectedArea.commonAreas) { area in
                                    AreaSelectionCard(
                                        area: area,
                                        isSelected: selectedArea == area,
                                        action: { selectedArea = area }
                                    )
                                }
                            }
                        }
                        
                        // What can you do?
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WHAT CAN YOU DO?")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 8) {
                                ForEach(AccommodationLevel.allCases) { level in
                                    AccommodationButton(
                                        level: level,
                                        isSelected: selectedAccommodation == level,
                                        action: { selectedAccommodation = level }
                                    )
                                }
                            }
                        }
                        
                        // Type Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TYPE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 8) {
                                ForEach(LimitationType.allCases, id: \.self) { type in
                                    TypeButton(
                                        type: type,
                                        isSelected: selectedType == type,
                                        action: { selectedType = type }
                                    )
                                }
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NOTES (OPTIONAL)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            TextField("Any additional details...", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(Color.cardBackground)
                                )
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Limitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
                        
                        let limitation = UserLimitation(
                            id: UUID(),
                            userId: userId,
                            limitationType: selectedType,
                            affectedArea: selectedArea,
                            severity: selectedAccommodation,
                            notes: notes.isEmpty ? nil : notes
                        )
                        
                        onSave(limitation)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Edit Limitation Sheet

struct EditLimitationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let limitation: UserLimitation
    let onSave: (UserLimitation) -> Void
    let onResolve: () -> Void
    
    @State private var selectedAccommodation: AccommodationLevel
    @State private var selectedType: LimitationType
    @State private var notes: String
    
    
    init(limitation: UserLimitation, onSave: @escaping (UserLimitation) -> Void, onResolve: @escaping () -> Void) {
        self.limitation = limitation
        self.onSave = onSave
        self.onResolve = onResolve
        _selectedAccommodation = State(initialValue: limitation.severity)
        _selectedType = State(initialValue: limitation.limitationType)
        _notes = State(initialValue: limitation.notes ?? "")
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                (colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Area display (not editable)
                        VStack(alignment: .leading, spacing: 12) {
                            Text("AFFECTED AREA")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(limitation.affectedArea.color.opacity(0.15))
                                        .frame(width: 50, height: 50)
                                    
                                    Image(systemName: limitation.affectedArea.icon)
                                        .font(.title2)
                                        .foregroundColor(limitation.affectedArea.color)
                                }
                                
                                Text(limitation.affectedArea.rawValue)
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                
                                Spacer()
                            }
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(Color.cardBackground)
                            )
                        }
                        
                        // What can you do?
                        VStack(alignment: .leading, spacing: 12) {
                            Text("WHAT CAN YOU DO?")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 8) {
                                ForEach(AccommodationLevel.allCases) { level in
                                    AccommodationButton(
                                        level: level,
                                        isSelected: selectedAccommodation == level,
                                        action: { selectedAccommodation = level }
                                    )
                                }
                            }
                        }
                        
                        // Type Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TYPE")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            VStack(spacing: 8) {
                                ForEach(LimitationType.allCases, id: \.self) { type in
                                    TypeButton(
                                        type: type,
                                        isSelected: selectedType == type,
                                        action: { selectedType = type }
                                    )
                                }
                            }
                        }
                        
                        // Notes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("NOTES")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            TextField("Any additional details...", text: $notes, axis: .vertical)
                                .lineLimit(3...6)
                                .padding(Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: CornerRadius.md)
                                        .fill(Color.cardBackground)
                                )
                        }
                        
                        // Resolved button
                        Button(action: {
                            onResolve()
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Mark as Recovered")
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: CornerRadius.md)
                                    .fill(Color.green.opacity(0.1))
                            )
                        }
                        .padding(.top, 12)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Limitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let updated = UserLimitation(
                            id: limitation.id,
                            userId: limitation.userId,
                            limitationType: selectedType,
                            affectedArea: limitation.affectedArea,
                            severity: selectedAccommodation,
                            exercisesToAvoid: limitation.exercisesToAvoid,
                            movementPatternsToAvoid: limitation.movementPatternsToAvoid,
                            equipmentToAvoid: limitation.equipmentToAvoid,
                            notes: notes.isEmpty ? nil : notes,
                            startedDate: limitation.startedDate,
                            expectedRecoveryDate: limitation.expectedRecoveryDate,
                            resolvedDate: limitation.resolvedDate,
                            isActive: limitation.isActive,
                            createdAt: limitation.createdAt,
                            updatedAt: Date()
                        )
                        
                        onSave(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Helper Views

struct AreaSelectionCard: View {
    let area: AffectedArea
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? area.color.opacity(0.2) : Color(.systemGray6))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: area.icon)
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? area.color : .secondary)
                }
                
                Text(area.rawValue)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isSelected ? area.color : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct AccommodationButton: View {
    let level: AccommodationLevel
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: level.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .white : level.color)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? level.color : level.color.opacity(0.15))
                    )
                
                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(isSelected ? level.color : .primary)
                    
                    Text(level.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(level.color)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(isSelected ? level.color.opacity(0.1) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .stroke(isSelected ? level.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TypeButton: View {
    let type: LimitationType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LimitationsSettingsView()
    }
}

