import SwiftUI

/// Shared exercise card row component used by both ExerciseLibraryView and CustomWorkoutBuilderView.
/// Renders a consistent 40x40 gradient icon, exercise name/category/equipment, and optional
/// checkbox, chevron, info button, or favorite star based on the display context.
struct ExerciseCardRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let exercise: Exercise
    var showCheckbox: Bool = false
    var isSelected: Bool = false
    var showChevron: Bool = false
    var showInfoButton: Bool = false
    var onInfo: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if showCheckbox {
                checkboxView
            }

            exerciseIcon
            exerciseDetails

            Spacer()

            if exercise.isFavorite {
                Image(systemName: "star.fill")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.yellow)
            }

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.ds_bodySmall).fontWeight(.medium)
                    .foregroundColor(.secondary)
            }

            if showInfoButton, let onInfo {
                Button(action: {
                    HapticManager.selectionChanged()
                    onInfo()
                }) {
                    Image(systemName: "info.circle")
                        .font(.ds_bodyRegular).fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.leading, Spacing.xxs)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .sleekCardSubtle(cornerRadius: CornerRadius.lg)
    }

    // MARK: - Checkbox

    private var checkboxView: some View {
        ZStack {
            Circle()
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                .frame(width: 28, height: 28)

            if isSelected {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)

                Image(systemName: "checkmark")
                    .font(.ds_bodySmall).fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
    }

    // MARK: - Exercise Icon (40x40 gradient circle)

    private var exerciseIcon: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: categoryGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)

            if exercise.category?.lowercased() == "core" {
                CoreIcon(size: 22, color: .white)
            } else {
                Image(systemName: resolvedIcon)
                    .font(.ds_labelLarge)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Exercise Details

    private var exerciseDetails: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            Text(exercise.displayName)
                .font(.ds_bodyLarge)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)

            HStack(spacing: Spacing.xs) {
                if let category = exercise.category {
                    Text(category)
                        .font(.ds_bodySmall)
                        .foregroundColor(categoryColor)
                        .fontWeight(.medium)
                }

                if let equipment = exercise.equipment {
                    Text("•")
                        .font(.ds_labelSmall)
                        .foregroundColor(.secondary)

                    Text(equipment)
                        .font(.ds_bodySmall)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
    }

    // MARK: - Category Styling

    var categoryColor: Color {
        switch exercise.category?.lowercased() {
        case "chest": return .purple
        case "back": return .blue
        case "legs": return .green
        case "shoulders": return .orange
        case "arms": return .purple
        case "core": return .yellow
        case "full body": return .pink
        default: return .gray
        }
    }

    var categoryGradient: [Color] {
        switch exercise.category?.lowercased() {
        case "chest": return [Color.purple, Color.pink]
        case "back": return [Color.blue, Color.cyan]
        case "legs": return [Color.green, Color.teal]
        case "shoulders": return [Color.orange, Color.yellow]
        case "arms": return [Color.purple, Color.indigo]
        case "core": return [Color.yellow, Color.orange]
        case "full body": return [Color.pink, Color.red]
        default: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }

    // MARK: - Smart Icon Resolution
    // Prioritizes exercise-name-specific icons, then equipment, then category fallback.

    var resolvedIcon: String {
        if let instructions = exercise.instructions,
           instructions.contains("[CUSTOM_EXERCISE|ICON:"),
           let iconRange = instructions.range(of: #"\[CUSTOM_EXERCISE\|ICON:([^\]]+)\]"#, options: .regularExpression),
           let iconName = instructions[iconRange].split(separator: ":").last?.replacingOccurrences(of: "]", with: "") {
            return String(iconName)
        }

        if let name = exercise.name?.lowercased() {
            if name.contains("dumbbell") { return "dumbbell.fill" }
            if name.contains("barbell") { return "figure.strengthtraining.traditional" }
            if name.contains("cable") { return "dot.radiowaves.left.and.right" }
            if name.contains("push") && name.contains("up") { return "figure.strengthtraining.traditional" }
            if name.contains("pull") && (name.contains("up") || name.contains("chin")) { return "figure.climbing" }
            if name.contains("squat") { return "figure.squat" }
            if name.contains("lunge") { return "figure.walk" }
            if name.contains("thrust") || name.contains("bridge") { return "figure.strengthtraining.functional" }
            if name.contains("deadlift") { return "figure.strengthtraining.functional" }
            if name.contains("curl") { return "figure.arms.open" }
            if name.contains("press") && !name.contains("leg") { return "arrow.up.circle.fill" }
            if name.contains("row") { return "arrow.left.and.right.circle.fill" }
            if name.contains("fly") || name.contains("flye") { return "arrow.up.left.and.arrow.down.right.circle.fill" }
            if name.contains("raise") { return "arrow.up.circle" }
            if name.contains("shrug") { return "arrow.up.and.down.circle.fill" }
            if name.contains("plank") { return "figure.core.training" }
            if name.contains("run") || name.contains("jog") { return "figure.run" }
            if name.contains("jump") { return "figure.jumprope" }
        }

        if let equipment = exercise.equipment?.lowercased() {
            switch equipment {
            case "dumbbells": return "dumbbell.fill"
            case "barbell": return "figure.strengthtraining.traditional"
            case "cables": return "dot.radiowaves.left.and.right"
            case "machines": return "gearshape.fill"
            case "bodyweight": return "figure.strengthtraining.traditional"
            default: break
            }
        }

        switch exercise.category?.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.climbing"
        case "legs": return "figure.squat"
        case "shoulders": return "arrow.up.circle.fill"
        case "arms": return "dumbbell.fill"
        case "core": return "figure.core.training"
        case "full body": return "figure.mixed.cardio"
        default: return "dumbbell.fill"
        }
    }
}
