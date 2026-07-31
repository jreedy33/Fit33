import SwiftUI

extension DashboardView {
    // MARK: - Program Conflict Alert
    @ViewBuilder
    var programConflictAlert: some View {
        let accentColor: Color = {
            if let program = generatedProgramService.activeProgram {
                return colorFromProgramType(program.programType)
            }
            return .blue
        }()
        
        if showingProgramConflictAlert {
            ZStack {
                // Background overlay with blur
                Color.black.opacity(colorScheme == .dark ? 0.6 : 0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingProgramConflictAlert = false
                            pendingWorkoutType = nil
                        }
                    }
                
                // Alert card with modern styling
                VStack(spacing: 0) {
                    // Header with animated icon
                    VStack(spacing: 20) {
                        ZStack {
                            // Outer glow ring
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [accentColor.opacity(0.5), accentColor.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                                .frame(width: 80, height: 80)
                            
                            // Main icon circle
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 68, height: 68)
                                .shadow(color: accentColor.opacity(0.4), radius: 12, x: 0, y: 6)
                            
                            Image(systemName: generatedProgramService.activeProgram?.icon ?? "calendar")
                                .font(.ds_heading1)
                                .foregroundColor(.white)
                        }
                        
                        VStack(spacing: 10) {
                            Text("Active Program Detected")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                            
                            Text("You have a workout scheduled for today. Continue your program or start something different.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                    
                    // Action buttons
                    VStack(spacing: 12) {
                        // Continue with program workout - Primary action
                        Button(action: {
                            HapticManager.impact(.medium)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.1))
                                guard !Task.isCancelled else { return }
                                navigateToTodaysWorkout = true
                            }
                        }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.ds_labelLarge)
                                        .foregroundColor(.white)
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Continue Program")
                                        .font(.ds_labelLarge)
                                    
                                    if let currentDay = generatedProgramService.currentDay {
                                        Text(currentDay.name)
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.ds_heading2)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 14)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                                        .fill(
                                            LinearGradient(
                                                colors: [accentColor, accentColor.opacity(0.85)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    // Subtle inner highlight
                                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                }
                            )
                            .shadow(color: accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        
                        // Skip and continue with custom/auto workout - Secondary action
                        Button(action: {
                            HapticManager.impact(.light)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.1))
                                guard !Task.isCancelled else { return }
                                if pendingWorkoutType == .custom {
                                    navigateToCustomWorkout = true
                                } else if pendingWorkoutType == .auto {
                                    workoutManager.shouldNavigateToAutoGen = true
                                }
                            }
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: pendingWorkoutType == .custom ? "plus.circle.fill" : "bolt.circle.fill")
                                    .font(.ds_heading3)
                                
                                Text("Start \(pendingWorkoutType == .custom ? "Custom" : "Auto") Workout Instead")
                                    .font(.ds_labelLarge)
                            }
                            .foregroundColor(accentColor)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                            .background(
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(accentColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
                                    
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(accentColor.opacity(0.4), lineWidth: 1.5)
                                }
                            )
                        }
                        .scaleButtonStyle(.standard, withHaptic: true)
                        
                        // Cancel button - Tertiary action
                        Button(action: {
                            HapticManager.selectionChanged()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingProgramConflictAlert = false
                                pendingWorkoutType = nil
                            }
                        }) {
                            Text("Cancel")
                                .font(.ds_bodyMedium)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 10)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .frame(maxWidth: 360)
                .background(
                    ZStack {
                        // Main background — adaptive (frosted ↔ solid via setting)
                        AdaptiveCardSurface(cornerRadius: CornerRadius.xl)
                        
                        // Subtle gradient overlay
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        accentColor.opacity(colorScheme == .dark ? 0.08 : 0.03),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        // Border
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .stroke(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color.white.opacity(0.1), Color.clear]
                                        : [Color.white, Color.black.opacity(0.05)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                )
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.15), radius: 30, x: 0, y: 15)
                .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 10)
                .padding(.horizontal, Spacing.lg)
                .scaleEffect(showingProgramConflictAlert ? 1 : 0.9)
                .opacity(showingProgramConflictAlert ? 1 : 0)
            }
            .transition(.opacity)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showingProgramConflictAlert)
        }
    }

    // MARK: - Smart Active Program Widget
    
    func smartActiveProgramWidget(program: DynamicProgramGenerator.GeneratedProgram) -> some View {
        let displayInfo = generatedProgramService.getDisplayInfo(for: program)
        let programColor = colorFromProgramType(program.programType)
        let completedDays = program.generatedDays.filter { $0.isCompleted }.count
        let totalDays = program.durationWeeks * program.daysPerWeek
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: program.icon)
                            .font(.ds_heading2)
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.name)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(displayInfo.currentWeek)/\(program.durationWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()

                    // Hidden until the real `ProgramDetailsView` ships — avoid
                    // shipping a chevron that opens a "Coming Soon" placeholder
                    // (App Review flags these as broken flows).
                    // TODO: Re-enable when ProgramDetailsView destination is implemented.
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * (displayInfo.progressPercentage / 100), height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(displayInfo.progressPercentage))%")
                                .font(.ds_caption).fontWeight(.bold)
                                .foregroundColor((displayInfo.progressPercentage / 100) > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT with rounded inner card
            if let currentDay = generatedProgramService.currentDay {
                NavigationLink(value: DashboardRoute.smartWorkoutPreview) {
                    HStack(spacing: 12) {
                        // Left: Workout info
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(currentDay.name)
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                
                                Text("Day \(currentDay.dayNumber)")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(programColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(programColor.opacity(0.12))
                                    )
                            }
                            
                            HStack(spacing: 6) {
                                Label("\(currentDay.exercises.count)", systemImage: "dumbbell.fill")
                                Label("~\(currentDay.estimatedDuration)min", systemImage: "clock")
                                
                                // Muscle targets from focusMuscles
                                if !currentDay.focusMuscles.isEmpty {
                                    Text("•")
                                        .font(.caption2)
                                    Text(currentDay.focusMuscles.prefix(3).joined(separator: ", "))
                                        .lineLimit(1)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Right: Start button
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                                .font(.ds_caption)
                            Text("Start")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [programColor, programColor.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Swipeable Program & Challenge Widget
    

    // MARK: - Unified Smart Program Widget
    
    /// Determines if this is a brand new user who hasn't started any workout or program
    var isFirstTimeUser: Bool {
        let totalWorkouts = userManager.currentUser?.totalWorkouts ?? 0
        let hasStartedProgram = !smartProgramEngine.userPrograms.isEmpty
        return totalWorkouts == 0 && !hasStartedProgram
    }
    
    /// Get the 10 personalized programs from SmartProgramEngine
    var personalizedPrograms: [PersonalizedProgram] {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
    }
    
    /// Get the best recommended program (highest match, unlocked)
    var topRecommendedSmartProgram: PersonalizedProgram? {
        personalizedPrograms
            .filter { !$0.isCompleted && $0.isUnlocked }
            .sorted { $0.matchPercentage > $1.matchPercentage }
            .first
    }
    
    /// Get active SmartProgram if any (most recently started)
    var activeSmartProgramForWidget: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    /// Compute widget refresh ID based on program state
    var activeProgramWidgetId: String {
        guard let program = activeSmartProgramForWidget else { return "none" }
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        return "\(program.id)-\(program.completedDays.count)-\(currentDay?.isCompleted ?? false)"
    }
    
    @ViewBuilder
    var unifiedProgramWidget: some View {
        unifiedProgramWidgetWithGlow(isVisible: true)
    }
    
    @ViewBuilder
    func unifiedProgramWidgetWithGlow(isVisible: Bool) -> some View {
        if !userManager.hasCompletedOnboarding {
            EmptyView()
        } else if let activeProgram = activeSmartProgramForWidget {
            activeSmartProgramDetailWidget(program: activeProgram, isVisible: isVisible)
                .id(activeProgramWidgetId)
        } else if let recommended = topRecommendedSmartProgram, showRecommendedWidget {
            // Show recommended program widget (even for first-time users)
            recommendedSmartProgramWidget(program: recommended)
        } else if !showRecommendedWidget {
            // If recommended is hidden, show browse programs instead
            browseProgramsWidget
        } else {
            browseProgramsWidget
        }
    }
    
    // MARK: - Get Started Widget (First Time Users) - Uses SmartProgramEngine
    
    var getStartedSmartWidget: some View {
        let accentColor = Color.green
        
        return VStack(spacing: 10) {
            // Compact header with icon and text side by side
            HStack(spacing: 12) {
                // Sparkle icon - smaller
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor.opacity(0.2), accentColor.opacity(0.05)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "sparkles")
                        .font(.ds_heading3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Started!")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("10 programs created for you")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Show top recommended program preview
            if let program = topRecommendedSmartProgram {
                let template = program.template
                let totalWeeks = (template.totalDays + 6) / 7
                
                HStack(spacing: 10) {
                    // Program icon - smaller
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accentColor, accentColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: template.category.icon)
                            .font(.ds_bodySmall).fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(program.personalizedName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 4) {
                            Text("\(totalWeeks) weeks")
                            Text("•")
                            Text("\(program.matchPercentage)% match")
                                .foregroundColor(accentColor)
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text("Start")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, accentColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.97))
                )
                .onTapGesture {
                    if let user = userManager.currentUser {
                        if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: template.id, for: user) {
                            // Navigate to the first day of the program
                            if let firstDay = startedProgram.generatedDays.first {
                                workoutManager.navigateProgramData = startedProgram
                                workoutManager.navigateProgramDay = firstDay
                                workoutManager.shouldNavigateToProgramDay = true
                            }
                        }
                    }
                }
            }
            
            // Divider
            HStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 1)
            }
            .padding(.horizontal, Spacing.md)
            
            // Or explore all programs
            Button(action: {
                // 🔧 Redirect to Workout tab's programs view
                workoutManager.shouldNavigateToPrograms = true
            }) {
                Text("or explore all programs →")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 4)
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [accentColor.opacity(0.3), accentColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: accentColor.opacity(0.15), radius: 20, x: 0, y: 8)
    }

    // MARK: - Recommended For You Widget (Returning Users) - Uses SmartProgramEngine
    
    func recommendedSmartProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let accent = template.category.color
        let secondaryAccent = accent.opacity(0.7)
        let totalWeeks = max(1, (template.totalDays + 6) / 7)

        return Button {
            workoutManager.shouldNavigateToPrograms = true
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .center, spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [accent, secondaryAccent],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: accent.opacity(0.35), radius: 8, x: 0, y: 4)

                        Image(systemName: template.category.icon)
                            .font(.ds_heading3)
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recommended for you")
                            .font(.ds_labelSmall)
                            .foregroundColor(.adaptiveSecondaryText)
                            .tracking(1)

                        Text(template.baseName)
                            .font(.ds_heading3)
                            .foregroundColor(.adaptiveText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.adaptiveSecondaryText)
                }

                Text(program.personalizedDescription.isEmpty ? template.description : program.personalizedDescription)
                    .font(.ds_bodySmall)
                    .foregroundColor(.adaptiveSecondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Spacing.xs) {
                    recommendedProgramFloatingChip(
                        icon: "calendar",
                        label: "\(template.daysPerWeek) days/week",
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                    recommendedProgramFloatingChip(
                        icon: "clock.fill",
                        label: totalWeeks == 1 ? "1 week" : "\(totalWeeks) weeks",
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                    recommendedProgramFloatingChip(
                        icon: "chart.line.uptrend.xyaxis",
                        label: template.difficulty.displayName,
                        color: accent
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(Spacing.md)
        }
        .buttonStyle(PlainButtonStyle())
        .adaptiveSleekCard(cornerRadius: CornerRadius.xl, accentColor: accent)
    }

    private func recommendedProgramFloatingChip(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.ds_labelSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundColor(color)
        .padding(.vertical, 4)
    }
    
    // MARK: - Active Smart Program Widget (With Today/Tomorrow Preview)
    
    
    
    func activeSmartProgramDetailWidget(program: SmartActiveProgram, isVisible: Bool = true) -> some View {
        let programColor = Color.green
        let template = personalizedPrograms.first { $0.template.id == program.templateId }?.template
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? program.generatedDays.count
        let totalWeeks = (totalDays + 6) / 7
        let currentWeek = (program.currentDay - 1) / max(1, template?.daysPerWeek ?? 4) + 1
        let progress = totalDays > 0 ? Double(completedDays) / Double(totalDays) * 100 : 0
        
        // Determine which day to show
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { !$0.isCompleted && $0.dayNumber > program.currentDay }
        let dayToShow = isTodayCompleted ? nextDay : currentDay
        let dayLabel = isTodayCompleted ? "Tomorrow's Workout" : "Today's Workout"
        
        return VStack(spacing: 0) {
            // Header - Tap anywhere to go to Program Overview (on Workout tab)
            Button {
                workoutManager.navigateProgramData = program
                workoutManager.navigateProgramTemplate = template
                workoutManager.shouldNavigateToProgramOverview = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Progress ring as icon
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                            .frame(width: 44, height: 44)
                        
                        Circle()
                            .trim(from: 0, to: progress / 100)
                            .stroke(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round)
                            )
                            .frame(width: 44, height: 44)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(progress))%")
                            .font(.ds_caption)
                            .foregroundColor(programColor)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template?.baseName ?? "Training Program")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 6) {
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Today/Tomorrow's workout section
            if isTodayCompleted {
                // Completed state - "Great work!" message
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Great work!")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        
                        if let next = nextDay {
                            Text("Next up: \(next.name)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("You're all caught up!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if let next = nextDay {
                        Button {
                            workoutManager.navigateProgramData = program
                            workoutManager.navigateProgramDay = next
                            workoutManager.shouldNavigateToProgramDay = true
                        } label: {
                            Text("Preview")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(programColor)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .stroke(programColor.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(Color.green.opacity(colorScheme == .dark ? 0.08 : 0.06))
                )
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 12)
            } else if let day = dayToShow {
                // Active workout - Left accent bar style (navigates to Workout tab)
                Button {
                    workoutManager.navigateProgramData = program
                    workoutManager.navigateProgramDay = day
                    workoutManager.shouldNavigateToProgramDay = true
                } label: {
                    HStack(spacing: 0) {
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, Spacing.xxs)
                        
                        HStack(spacing: 12) {
                            // Workout info
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(day.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Day \(day.dayNumber)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(programColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.15))
                                        )
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(day.exercises.count) exercises")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text(muscleTargets)
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.ds_caption)
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [programColor.opacity(0.9), programColor.opacity(0.7)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .padding(.leading, 12)
                        .padding(.trailing, 14)
                    }
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .fill(colorScheme == .dark 
                                ? Color.white.opacity(0.04) 
                                : Color.black.opacity(0.03))
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, Spacing.sm)
                .padding(.bottom, 12)
            } else {
                // All days completed
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.yellow)
                    
                    Text("Program Complete! 🎉")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Congratulations on finishing your program!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(20)
            }
        }
        .background(
            ZStack {
                // Soft glow when visible and workout not complete
                if isVisible && !isTodayCompleted {
                    RoundedRectangle(cornerRadius: 26)
                        .stroke(programColor.opacity(0.3), lineWidth: 2)
                        .blur(radius: 6)
                }
                
                // Main card background with gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle accent border - enhanced when visible
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: isTodayCompleted 
                                ? [Color.gray.opacity(0.15), Color.gray.opacity(0.05), Color.clear]
                                : [programColor.opacity(isVisible ? 0.35 : 0.2), programColor.opacity(isVisible ? 0.15 : 0.08), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isVisible ? 1.5 : 1
                    )
            }
        )
        // Enhanced shadows when visible, subtle when off-screen
        .shadow(color: programColor.opacity(isVisible ? (colorScheme == .dark ? 0.25 : 0.18) : (colorScheme == .dark ? 0.1 : 0.06)), radius: isVisible ? 16 : 8, x: 0, y: isVisible ? 4 : 3)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
    }
    
    // MARK: - Browse Programs Widget (Fallback)
    
    /// Get any program to suggest (broader than topRecommendedSmartProgram)
    var anyRecommendableProgram: PersonalizedProgram? {
        personalizedPrograms
            .filter { $0.isUnlocked }
            .sorted { $0.matchPercentage > $1.matchPercentage }
            .first
    }
    
    var browseProgramsWidget: some View {
        let suggestedProgram = anyRecommendableProgram
        let template = suggestedProgram?.template
        let programColor = template?.category.color ?? .blue
        let totalWeeks = ((template?.totalDays ?? 28) + 6) / 7
        
        return VStack(spacing: 0) {
            // Header - Tap to view all programs (matches active program header style)
            Button {
                workoutManager.shouldNavigateToPrograms = true
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    // Category icon in accent circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [programColor.opacity(0.2), programColor.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: template?.category.icon ?? "dumbbell.fill")
                            .font(.ds_heading3)
                            .foregroundColor(programColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your Programs")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text("Find your next challenge")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Inner card - Recommended program or explore prompt
            if let program = suggestedProgram, let tmpl = template {
                Button {
                    if let user = userManager.currentUser {
                        if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: tmpl.id, for: user) {
                            if let firstDay = startedProgram.generatedDays.first {
                                workoutManager.navigateProgramData = startedProgram
                                workoutManager.navigateProgramDay = firstDay
                                workoutManager.shouldNavigateToProgramDay = true
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 0) {
                        // Left accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, Spacing.xxs)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(tmpl.baseName)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    // Match badge
                                    Text("\(program.matchPercentage)% match")
                                        .font(.ds_caption).fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.85))
                                        )
                                }
                                
                                HStack(spacing: 4) {
                                    Text("\(totalWeeks) weeks")
                                    Text("•")
                                        .font(.caption2)
                                    Text("\(tmpl.daysPerWeek) days/wk")
                                    Text("•")
                                        .font(.caption2)
                                    Text("\(tmpl.estimatedMinutesPerDay) min")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding(.leading, 10)
                            
                            Spacer()
                            
                            // Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.ds_caption)
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [programColor, programColor.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(Spacing.sm)
                    .background(
                        AdaptiveCardSurface(cornerRadius: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(programColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 12)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // No specific program to suggest - show explore prompt
                Button {
                    workoutManager.shouldNavigateToPrograms = true
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(programColor)
                            .frame(width: 4)
                            .padding(.vertical, Spacing.xxs)
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
            Text("Explore Programs")
                                    .font(.subheadline)
                .fontWeight(.bold)
                                    .foregroundColor(.primary)
            
                                Text("10+ programs tailored to your goals")
                .font(.caption)
                .foregroundColor(.secondary)
                            }
                            .padding(.leading, 10)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text("Browse")
                    .font(.subheadline)
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.right")
                                    .font(.ds_caption)
                            }
                    .foregroundColor(.white)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 10)
                    .background(
                        Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [programColor, programColor.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                    }
                    .padding(Spacing.sm)
        .background(
                        AdaptiveCardSurface(cornerRadius: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(programColor.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, Spacing.sm)
                    .padding(.bottom, 12)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .background(
            ZStack {
                // Main card background with gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.16), Color(white: 0.10)]
                                : [Color.white, Color(white: 0.98)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Subtle accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.25), programColor.opacity(0.1), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Matching shadows from active/recommended program widgets
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.15 : 0.1), radius: 12, x: 0, y: 6)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 3)
    }
    
    // MARK: - Program Recommendations Widget (Legacy - kept for scrolling list)
    
    var smartProgramRecommendationsWidget: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Your Programs")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink(value: DashboardRoute.generatedProgramsList) {
                    Text("View All")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }
            
            // Show top 2 program recommendations
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(generatedProgramService.generatedPrograms.prefix(3)) { program in
                        SmartProgramMiniCard(
                            program: program,
                            onStart: {
                                generatedProgramService.startProgram(program)
                            }
                        )
                        .frame(width: 260)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.1), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
    }
    
    // MARK: - Smart Programs Widget (context-aware)
    
    var activeSmartProgram: SmartActiveProgram? {
        smartProgramEngine.userPrograms
            .filter { !$0.isCompleted }
            .sorted { $0.startDate > $1.startDate }  // Most recent first
            .first
    }
    
    var generateProgramsWidget: some View {
        Group {
            if let activeProgram = activeSmartProgram {
                // Show active program status
                activeProgramWidget(activeProgram)
            } else {
                // Show browse programs card
                browseProgramsCard
            }
        }
    }
    
    // MARK: - Active Program Widget
    
    
    
    func activeProgramWidget(_ program: SmartActiveProgram) -> some View {
        let template = smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .first { $0.template.id == program.templateId }?.template
        let currentDay = program.generatedDays.first { $0.dayNumber == program.currentDay }
        let isTodayCompleted = currentDay?.isCompleted ?? false
        let nextDay = program.generatedDays.first { $0.dayNumber == program.currentDay + 1 }
        let completedDays = program.completedDays.count
        let totalDays = template?.totalDays ?? 1
        let progressPercent = Double(completedDays) / Double(totalDays)
        let programColor: Color = .green
        let currentWeek = (program.currentDay - 1) / 7 + 1
        let totalWeeks = (totalDays + 6) / 7
        
        return VStack(spacing: 0) {
            // Streamlined Header
            VStack(spacing: 10) {
                // Top row: Icon, Name, and Menu
                HStack(alignment: .center, spacing: 12) {
                    // Gradient icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [programColor, programColor.opacity(0.7)]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: programColor.opacity(0.3), radius: 6, x: 0, y: 3)
                        
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.ds_heading2)
                            .foregroundColor(.white)
                    }
                    
                    // Program info
                    VStack(alignment: .leading, spacing: 3) {
                        Text(program.personalizedName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        HStack(spacing: 8) {
                            // Week and progress combined
                            Text("Week \(currentWeek)/\(totalWeeks)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(completedDays)/\(totalDays) days")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(programColor)
                        }
                    }
                    
                    Spacer()
                    
                    // View all button
                    NavigationLink(value: DashboardRoute.smartProgramOverview(programId: program.id)) {
                        Image(systemName: "chevron.right")
                            .font(.ds_labelMedium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Compact progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Capsule()
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 8)
                        
                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progressPercent, height: 8)
                        
                        // Percentage overlay
                        HStack {
                            Spacer()
                            Text("\(Int(progressPercent * 100))%")
                                .font(.ds_caption).fontWeight(.bold)
                                .foregroundColor(progressPercent > 0.15 ? .white : programColor)
                                .padding(.trailing, 6)
                        }
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            
            // Today's workout - COMPACT
            if let day = currentDay {
                if !isTodayCompleted && !day.exercises.isEmpty {
                    NavigationLink(value: DashboardRoute.smartProgramDayPreview(programId: program.id, dayNumber: day.dayNumber)) {
                        HStack(spacing: 12) {
                            // Left: Workout info
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(day.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    
                                    Text("Day \(day.dayNumber)")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(programColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(programColor.opacity(0.12))
                                        )
                                }
                                
                                HStack(spacing: 6) {
                                    Label("\(day.exercises.count)", systemImage: "dumbbell.fill")
                                    Label("~\(day.targetDuration)min", systemImage: "clock")
                                    
                                    // Muscle targets
                                    let muscleTargets = getMuscleTargets(for: day.exercises)
                                    if !muscleTargets.isEmpty {
                                        Text("•")
                                            .font(.caption2)
                                        Text(muscleTargets)
                                            .lineLimit(1)
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // Right: Start button
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.ds_caption)
                                Text("Start")
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [programColor, programColor.opacity(0.8)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, Spacing.sm)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if isTodayCompleted {
                    // Today completed view - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.ds_heading2)
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Great work!")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            if let next = nextDay {
                                Text("Tomorrow: \(next.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.green.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                } else if day.exercises.isEmpty {
                    // Rest day - more compact
                    HStack(spacing: 10) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.ds_heading2)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rest Day")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            
                            Text("Recovery is important!")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.12))
                    )
                    .padding(.horizontal, 14)
                }
            }
        }
        .background(
            ZStack {
                // Base gradient
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark 
                                ? [Color(white: 0.18), Color.cardBackground]
                                : [Color.white, Color.white.opacity(0.95)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Inner glow
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color.white.opacity(0.12), Color.white.opacity(0.02), Color.clear]
                                : [Color.white, Color.white.opacity(0.5), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                
                // Accent border
                RoundedRectangle(cornerRadius: CornerRadius.xl)
                    .stroke(
                        LinearGradient(
                            colors: [programColor.opacity(0.3), programColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            }
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 16, x: 0, y: 8)
        // Subtle glow effect to draw attention
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 16, x: 0, y: 0)
        .shadow(color: programColor.opacity(colorScheme == .dark ? 0.2 : 0.15), radius: 24, x: 0, y: 0)
    }
    
    // MARK: - Helper: Extract Muscle Targets from Exercises
    
    func getMuscleTargets(for exercises: [SmartProgramExercise]) -> String {
        let exerciseLibrary = ExerciseLibraryService.shared
        var muscleGroups: [String: Int] = [:]
        
        for exercise in exercises {
            // Try to find the exercise in the library
            if let libraryExercise = exerciseLibrary.getExercise(byName: exercise.exerciseName) {
                if let muscles = libraryExercise.muscleGroups as? [String], let primary = muscles.first {
                    muscleGroups[primary, default: 0] += 1
                }
            } else {
                // Fallback: extract from exercise name
                let nameLower = exercise.exerciseName.lowercased()
                if nameLower.contains("chest") || nameLower.contains("bench") || nameLower.contains("fly") {
                    muscleGroups["Chest", default: 0] += 1
                } else if nameLower.contains("back") || nameLower.contains("row") || nameLower.contains("lat") || nameLower.contains("pull") {
                    muscleGroups["Back", default: 0] += 1
                } else if nameLower.contains("shoulder") || nameLower.contains("delt") || nameLower.contains("press") {
                    muscleGroups["Shoulders", default: 0] += 1
                } else if nameLower.contains("bicep") || nameLower.contains("curl") || nameLower.contains("tricep") {
                    muscleGroups["Arms", default: 0] += 1
                } else if nameLower.contains("leg") || nameLower.contains("squat") || nameLower.contains("quad") || nameLower.contains("hamstring") || nameLower.contains("glute") {
                    muscleGroups["Legs", default: 0] += 1
                } else if nameLower.contains("core") || nameLower.contains("ab") || nameLower.contains("plank") {
                    muscleGroups["Core", default: 0] += 1
                }
            }
        }
        
        let sorted = muscleGroups.sorted {
            if $0.value != $1.value { return $0.value > $1.value }
            return $0.key < $1.key
        }
        let topMuscles = sorted.prefix(3).map { $0.key }
        
        return topMuscles.joined(separator: ", ")
    }
    
    // MARK: - Your Perfect Program Widget (no active program)
    
    var topRecommendedProgram: PersonalizedProgram? {
        smartProgramEngine.getPersonalizedPrograms(for: userManager.currentUser)
            .filter { !$0.isCompleted && $0.isUnlocked }
            .first
    }
    
    var browseProgramsCard: some View {
        Group {
            if let recommended = topRecommendedProgram {
                perfectProgramWidget(program: recommended)
            } else {
                fallbackProgramsCard
            }
        }
    }
    
    
    
    func perfectProgramWidget(program: PersonalizedProgram) -> some View {
        let template = program.template
        let matchPercent = program.matchPercentage
        let accentColor = Color.green
        let totalWeeks = (template.totalDays + 6) / 7
        
        return NavigationLink(value: DashboardRoute.personalizedPrograms) {
            HStack(spacing: 14) {
                // Program icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [accentColor, Color.mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
                .shadow(color: accentColor.opacity(0.3), radius: 6, x: 0, y: 3)
                
                // Program info
                VStack(alignment: .leading, spacing: 5) {
                    Text(program.personalizedName)
                        .font(.ds_labelLarge)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Text("\(totalWeeks)wk • \(template.daysPerWeek)x/wk")
                        Text("•")
                        Text("\(matchPercent)% match")
                            .foregroundColor(accentColor)
                    }
                    .font(.ds_labelSmall)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Compact start button
                Button {
                    HapticManager.impact(.medium)
                    programToStart = program
                    showStartProgramConfirm = true
                } label: {
                    Text("Start")
                        .font(.ds_bodySmall)
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [accentColor, Color.mint],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.md)
            .background(
                ZStack {
                    // Animated glow border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4),
                                    accentColor.opacity(0.5),
                                    Color.mint.opacity(0.4)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 3
                        )
                        .blur(radius: 6)

                    // Main background — adaptive (frosted ↔ solid via setting)
                    AdaptiveCardSurface(cornerRadius: 24)

                    // Inner border - more evenly distributed
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3),
                                    accentColor.opacity(0.4),
                                    Color.mint.opacity(0.3)
                                ]),
                                center: .center,
                                startAngle: .degrees(programGlowRotation),
                                endAngle: .degrees(programGlowRotation + 360)
                            ),
                            lineWidth: 1.5
                        )
                }
            )
            .shadow(color: accentColor.opacity(colorScheme == .dark ? 0.3 : 0.2), radius: 12, x: 0, y: 0) // Even glow
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.08), radius: 8, x: 0, y: 3) // Subtle depth
        }
        .buttonStyle(PlainButtonStyle())
        .confirmationDialog("Start \(program.personalizedName)?", isPresented: $showStartProgramConfirm, titleVisibility: .visible) {
            Button("Start Program") {
                if let toStart = programToStart,
                   let user = userManager.currentUser {
                    if let startedProgram = SmartProgramEngine.shared.startProgram(templateId: toStart.template.id, for: user) {
                        // Navigate to the first day of the program
                        if let firstDay = startedProgram.generatedDays.first {
                            workoutManager.navigateProgramData = startedProgram
                            workoutManager.navigateProgramDay = firstDay
                            workoutManager.shouldNavigateToProgramDay = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This \(totalWeeks)-week program is \(matchPercent)% matched to your goals and equipment.")
        }
    }
    
    // Fallback card if no programs available
    var fallbackProgramsCard: some View {
        NavigationLink(value: DashboardRoute.personalizedPrograms) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [Color.green, Color.mint]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .green.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "star.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                VStack(spacing: 4) {
                    Text("Training Programs")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("10 personalized plans")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(AdaptiveCardSurface(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.green.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: .green.opacity(0.2), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    
    func colorFromProgramType(_ type: DynamicProgramGenerator.GeneratedProgram.ProgramType) -> Color {
        switch type {
        case .hypertrophy: return .blue
        case .strength: return .red
        case .fatLoss: return .orange
        case .toning: return .purple
        case .generalFitness: return .green
        case .powerbuilding: return .yellow
        }
    }
    
}
