import SwiftUI

struct SevenDayProgramDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var workoutManager: WorkoutManager
    
    // Callback to trigger navigation to Day 1 after starting program
    var onProgramStarted: (() -> Void)?
    
    // Get the 7-day intro program (with safe fallback)
    private var program: WorkoutProgram {
        let allPrograms = WorkoutProgramEngine.shared.getAllPrograms()
        if let found = allPrograms.first(where: { $0.id == "7_day_intro" }) {
            return found
        }
        if let first = allPrograms.first {
            return first
        }
        // Safe fallback instead of crash
        print("⚠️ [SevenDayProgramDetailView] No programs available — using fallback")
        return WorkoutProgram(
            id: "7_day_intro_fallback",
            name: "7-Day Starter",
            description: "Programs are loading...",
            duration: 7,
            difficulty: .beginner,
            focus: .fullBody,
            schedule: [:],
            restDays: [4, 7],
            icon: "figure.strengthtraining.traditional",
            color: "blue",
            workoutsPerWeek: 3,
            estimatedTimePerWorkout: 30,
            equipment: [],
            benefits: ["Get started with fitness"],
            preview: "A gentle introduction to working out"
        )
    }
    
    // Use app's blue-cyan gradient theme
    private let accentGradient = LinearGradient(
        colors: [Color.blue, Color.cyan],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    var body: some View {
        ZStack {
            // Background - matches app theme
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.15),
                    Color.cyan.opacity(colorScheme == .dark ? 0.2 : 0.08),
                    colorScheme == .dark ? Color.black : Color.white
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Hero Icon with gradient
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 72, height: 72)
                        .blur(radius: 20)
                        .opacity(0.5)
                    
                    // Main circle
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.blue.opacity(0.4), radius: 12, x: 0, y: 6)
                    
                    Image(systemName: program.icon)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                .padding(.top, 8)
                
                // Program tagline
                Text(program.preview)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                
                // Compact stat pills - horizontal
                HStack(spacing: 6) {
                    statPill(icon: "calendar", value: "\(program.duration) Days")
                    statPill(icon: "flame.fill", value: program.difficulty.rawValue)
                    statPill(icon: "clock.fill", value: "\(program.estimatedTimePerWorkout)m")
                    statPill(icon: "figure.run", value: "\(program.workoutsPerWeek)x/wk")
                }
                .padding(.top, 14)
                .padding(.horizontal, Spacing.md)
                
                // Cards container
                VStack(spacing: 10) {
                    // About card - compact
                    infoCard(title: "About", icon: "info.circle.fill") {
                        Text(program.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    // Benefits card - horizontal layout
                    infoCard(title: "What You'll Achieve", icon: "trophy.fill") {
                        HStack(spacing: 12) {
                            ForEach(program.benefits.prefix(3), id: \.self) { benefit in
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accentGradient)
                                        .font(.caption2)
                                    
                                    Text(benefit)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    
                    // Equipment card - inline
                    infoCard(title: "Equipment", icon: "dumbbell.fill") {
                        HStack(spacing: 8) {
                            ForEach(program.equipment, id: \.self) { equipment in
                                Text(equipment)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(accentGradient)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: CornerRadius.sm)
                                            .fill(Color.blue.opacity(0.1))
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, 14)
                
                Spacer()
                
                // Hollow start button with gradient outline
                Button(action: startProgram) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("Start 7-Day Intro Program")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(accentGradient)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(colorScheme == .dark ? Color.black.opacity(0.3) : Color.white.opacity(0.8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(accentGradient, lineWidth: 2)
                    )
                    .shadow(color: Color.blue.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accentGradient)
                        .padding(Spacing.xs)
                        .background(Circle().fill(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.8)))
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func startProgram() {
        print("🔵 [7DAY] START BUTTON TAPPED")
        workoutManager.startProgram(program)
        print("🔵 [7DAY] Program started: \(program.name)")
        onProgramStarted?()
    }
    
    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(accentGradient)
            
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    @ViewBuilder
    private func infoCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentGradient)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(accentGradient)
            }
            
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
        )
    }
}

