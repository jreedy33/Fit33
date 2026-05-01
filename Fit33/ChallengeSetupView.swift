//
//  ChallengeSetupView.swift
//  Fit33
//
//  Create a new challenge with a friend - select type, duration, and target
//

import SwiftUI

struct ChallengeSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // NOTE: Removed @ObservedObject for ChallengeService to prevent sheet dismissal
    // when the service updates. Templates are loaded into local state instead.
    
    let friend: Friend
    
    // Challenge configuration
    @State private var selectedTemplate: ChallengeTemplate?
    @State private var selectedType: ChallengeType = .steps
    @State private var customTitle = ""
    @State private var dailyTarget: Int = 10000
    @State private var durationDays: Int = 7
    @State private var startDate: Date = Date().addingTimeInterval(86400) // Tomorrow
    @State private var showingCustomSetup = false
    
    // UI State
    @State private var isCreating = false
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""
    
    // Local template state (loaded once, not observed)
    @State private var templates: [ChallengeTemplate] = []
    @State private var isLoadingTemplates = true

    // Sprint 20260811 — chip-filter state. nil == "All". Tapping a chip
    // narrows the catalog to one ChallengeType.
    @State private var activityFilter: ChallengeType?

    // Strava-gated templates only surface when the user has connected
    // Strava. We observe the singleton so toggling Strava in Settings
    // updates the picker live without a re-mount.
    @ObservedObject private var strava = StravaService.shared

    /// Templates after applying Strava-gating + activity-chip filter.
    /// All downstream sections (`uniqueTemplates`, `featuredTemplates`,
    /// per-type rows) read from this — keeps the rules in one place.
    private var visibleTemplates: [ChallengeTemplate] {
        templates.filter { template in
            // Strava-required templates only shown to Strava-connected users.
            if template.requiresStrava == true, !strava.isConnected {
                return false
            }
            // Apply the chip filter, if any.
            if let filter = activityFilter,
               template.type != filter {
                return false
            }
            return true
        }
    }

    // Group templates by type (using local state)
    private var groupedTemplates: [ChallengeType: [ChallengeTemplate]] {
        Dictionary(grouping: visibleTemplates) { template in
            ChallengeType(rawValue: template.challengeType) ?? .steps
        }
    }
    
    private var featuredTemplates: [ChallengeTemplate] {
        visibleTemplates.filter { $0.isFeatured }
    }

    /// All distinct ChallengeTypes that appear in the (Strava-gated) catalog.
    /// Drives the activity chip row — empty when the catalog is empty.
    private var availableActivityChips: [ChallengeType] {
        let strict = templates.filter { template in
            template.requiresStrava != true || strava.isConnected
        }
        let types = strict.compactMap { $0.type }
        return Array(Set(types)).sorted { $0.rawValue < $1.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.06, green: 0.08, blue: 0.14), Color(red: 0.04, green: 0.05, blue: 0.08)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                if showingCustomSetup {
                    customSetupView
                } else {
                    templateSelectionView
                }
            }
            .navigationTitle("Challenge \(friend.friendName?.components(separatedBy: " ").first ?? "Friend")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                AppLogger.debug("🏆 [CHALLENGE SETUP] View appeared for friend: \(friend.friendName ?? "unknown")", category: .social)
                loadTemplates()
            }
            .onDisappear {
                AppLogger.debug("🏆 [CHALLENGE SETUP] View DISAPPEARED!", category: .social)
            }
            .alert("Challenge Sent! 🎯", isPresented: $showingSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Challenge will start when \(friend.friendName?.components(separatedBy: " ").first ?? "your friend") accepts! You can track pending challenges on your home screen.")
            }
            .alert("Failed to Send Challenge", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage.isEmpty ? "Something went wrong. Please try again." : errorMessage)
            }
        }
    }
    
    // Sprint 20260811 — server (#176) is now the dedup source of truth via
    // the `slug UNIQUE` constraint, so client-side title-dedup is no longer
    // needed. These accessors read from `visibleTemplates` (which already
    // applies Strava-gating + chip filtering — see top-of-class declarations).
    private var uniqueTemplates: [ChallengeTemplate] { visibleTemplates }

    private var uniqueFeaturedTemplates: [ChallengeTemplate] {
        visibleTemplates.filter { $0.isFeatured }
    }

    private var uniqueGroupedTemplates: [ChallengeType: [ChallengeTemplate]] {
        Dictionary(grouping: visibleTemplates) { template in
            ChallengeType(rawValue: template.challengeType) ?? .steps
        }
    }
    
    // MARK: - Template Selection View
    
    private var templateSelectionView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header with friend info
                challengeHeader
                
                // 🎯 PRIMARY: Create Custom Challenge (at the top)
                customChallengeCard

                // Activity chip-filter row — appears when there are at least
                // 2 distinct activities to filter between. Tapping a chip
                // narrows the catalog; tapping the active chip clears it.
                if availableActivityChips.count >= 2 {
                    activityChipRow
                }

                // Loading state
                if isLoadingTemplates && templates.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Loading challenges...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }
                
                // Popular/Featured Challenges (deduplicated)
                if !uniqueFeaturedTemplates.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                            Text("Popular Challenges")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, Spacing.xxs)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(uniqueFeaturedTemplates, id: \.id) { template in
                                TemplateCard(
                                    template: template,
                                    isSelected: selectedTemplate?.id == template.id,
                                    onSelect: { selectTemplate(template) }
                                )
                            }
                        }
                    }
                }
                
                // All challenge types (non-featured, deduplicated)
                ForEach(ChallengeType.allCases) { type in
                    let typeTemplates = uniqueGroupedTemplates[type]?.filter { !$0.isFeatured } ?? []
                    if !typeTemplates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: type.icon)
                                    .foregroundColor(type.color)
                                Text(type.displayName + "s")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, Spacing.xxs)
                            
                            VStack(spacing: 8) {
                                ForEach(typeTemplates, id: \.id) { template in
                                    TemplateRow(
                                        template: template,
                                        isSelected: selectedTemplate?.id == template.id,
                                        onSelect: { selectTemplate(template) }
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 100) // Space for button overlay
        }
        .overlay(alignment: .bottom) {
            if selectedTemplate != nil {
                startChallengeButton
            }
        }
    }
    
    // MARK: - Custom Challenge Card (Primary CTA)
    
    private var customChallengeCard: some View {
        Button(action: { showingCustomSetup = true }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [.purple, .pink]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: .purple.opacity(0.5), radius: 8, x: 0, y: 4)
                    
                    Image(systemName: "plus")
                        .font(.ds_heading2)
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create Your Own Challenge")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text("Steps, workouts, calories & more • Custom goals")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.ds_heading1)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .pink],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(18)
            .background(
                ZStack {
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
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
                    
                    // Purple/pink accent border (more prominent)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(colorScheme == .dark ? 0.6 : 0.4), Color.pink.opacity(colorScheme == .dark ? 0.5 : 0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Activity chip-filter row (Sprint 20260811)

    /// Horizontal scrolling row of "All / Run / Lift / …" chips. Tapping a
    /// chip narrows `visibleTemplates` via `activityFilter`; tapping the
    /// already-active chip clears it. Driven by `availableActivityChips`
    /// which already hides Strava-only types when the user isn't connected.
    private var activityChipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chipButton(label: "All", emoji: nil, isSelected: activityFilter == nil) {
                    activityFilter = nil
                }
                ForEach(availableActivityChips) { type in
                    chipButton(
                        label: type.displayName,
                        emoji: type.emoji,
                        isSelected: activityFilter == type
                    ) {
                        activityFilter = (activityFilter == type) ? nil : type
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func chipButton(label: String, emoji: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji {
                    Text(emoji).font(.caption)
                }
                Text(label)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundColor(isSelected ? .white : .primary)
            .background(
                Capsule().fill(isSelected ? Color.accentColor : Color.cardBackground)
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Challenge Header
    
    private var challengeHeader: some View {
        HStack(spacing: 16) {
            // VS style display
            HStack(spacing: 12) {
                // Current user avatar with actual profile photo
                if let cachedImage = ProfilePhotoCache.shared.cachedImage {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 3
                                )
                        )
                } else {
                    // Fallback gradient circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundColor(.white)
                        )
                }
                
                Text("VS")
                    .font(.headline)
                    .fontWeight(.black)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                // Friend avatar
                CachedFriendPhoto(
                    friendId: friend.friendId.uuidString,
                    photoUrl: friend.profilePhotoUrl,
                    name: friend.friendName ?? friend.friendUsername ?? "Friend",
                    size: 50,
                    showGradientRing: true,
                    gradientColors: [.orange, .red]
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Challenge")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(friend.displayName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            
            Spacer()
        }
        .padding(Spacing.md)
        .adaptiveSleekCard(cornerRadius: 20, accentColor: .blue)
    }
    
    // MARK: - Custom Setup View
    
    private var customSetupView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Back button
                HStack {
                    Button(action: { showingCustomSetup = false }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Templates")
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                    Spacer()
                }
                
                // Challenge Type Picker
                VStack(alignment: .leading, spacing: 12) {
                    Text("Challenge Type")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal, Spacing.xxs)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(ChallengeType.allCases) { type in
                                Button(action: { selectedType = type }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        colors: selectedType == type ? type.gradientColors : [Color.gray.opacity(0.2), Color.gray.opacity(0.3)],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 56, height: 56)
                                            
                                            Image(systemName: type.icon)
                                                .font(.ds_heading2)
                                                .foregroundColor(selectedType == type ? .white : .gray)
                                        }
                                        
                                        Text(type.displayName.replacingOccurrences(of: " Challenge", with: ""))
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(selectedType == type ? .primary : .secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, Spacing.xxs)
                    }
                }
                
                // Challenge Title
                VStack(alignment: .leading, spacing: 8) {
                    Text("Challenge Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("e.g., 10K Steps Daily", text: $customTitle)
                        .textFieldStyle(PlainTextFieldStyle())
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(Color(.systemGray6))
                        )
                }
                .padding(.horizontal, Spacing.xxs)
                
                // Daily Target
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily Target")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 16) {
                        // Decrease button
                        Button(action: { decreaseTarget() }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.ds_heading1)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(spacing: 2) {
                            Text("\(dailyTarget.formatted())")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text(targetUnitDisplay)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(minWidth: 120)
                        
                        // Increase button
                        Button(action: { increaseTarget() }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.ds_heading1)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.cardBackground)
                    )
                }
                .padding(.horizontal, Spacing.xxs)
                
                // Duration
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        ForEach([7, 14, 21, 30], id: \.self) { days in
                            Button(action: { durationDays = days }) {
                                Text(days == 7 ? "1 Week" : days == 14 ? "2 Weeks" : days == 21 ? "3 Weeks" : "1 Month")
                                    .font(.subheadline)
                                    .fontWeight(durationDays == days ? .semibold : .regular)
                                    .foregroundColor(durationDays == days ? .white : .primary)
                                    .padding(.horizontal, Spacing.md)
                                    .padding(.vertical, 10)
                                    .background(
                                        Capsule()
                                            .fill(durationDays == days
                                                ? LinearGradient(colors: selectedType.gradientColors, startPoint: .leading, endPoint: .trailing)
                                                : LinearGradient(colors: [Color.cardBackground, Color.cardBackground], startPoint: .leading, endPoint: .trailing))
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, Spacing.xxs)
                
                // Start Date
                VStack(alignment: .leading, spacing: 8) {
                    Text("Start Date")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    DatePicker("", selection: $startDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                }
                .padding(.horizontal, Spacing.xxs)
                
                // Preview Card
                challengePreviewCard
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, 16)
            .padding(.bottom, 120)
        }
        .overlay(alignment: .bottom) {
            createCustomChallengeButton
        }
    }
    
    // MARK: - Preview Card
    
    private var challengePreviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.horizontal, Spacing.xxs)
            
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: selectedType.gradientColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: selectedType.icon)
                            .font(.ds_heading2)
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(customTitle.isEmpty ? "\(dailyTarget.formatted()) \(targetUnitDisplay) Daily" : customTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(durationDays) days • Starts \(startDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Progress preview
                HStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text("0")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text("Your Progress")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Text("vs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 4) {
                        Text("0")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(friend.friendName?.components(separatedBy: " ").first ?? "Friend")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(Spacing.md)
            .adaptiveSleekCard(cornerRadius: 16, accentColor: .blue)
        }
    }
    
    // MARK: - Start Challenge Button (Template)
    
    private var startChallengeButton: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack(spacing: 16) {
                if let template = selectedTemplate {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Text("\(template.defaultDurationDays) days")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button(action: { createChallengeFromTemplate() }) {
                    HStack(spacing: 8) {
                        if isCreating {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Send Challenge")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.orange, .red],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
                }
                .disabled(isCreating)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(Color.cardBackground)
        }
    }
    
    // MARK: - Create Custom Challenge Button
    
    private var createCustomChallengeButton: some View {
        VStack(spacing: 0) {
            Divider()
            
            Button(action: { createCustomChallenge() }) {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("Send Challenge")
                    }
                }
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.md)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: canCreateCustom ? [.orange, .red] : [.gray, .gray],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .disabled(!canCreateCustom || isCreating)
            .padding(.horizontal, 20)
            .padding(.vertical, Spacing.md)
            .background(Color.cardBackground)
        }
    }
    
    // MARK: - Helpers
    
    private var targetUnitDisplay: String {
        switch selectedType {
        case .steps: return "steps"
        case .walk, .run, .activeMinutes: return "minutes"
        case .lift, .workoutStreak: return "workouts"
        case .hydrate: return "ml"
        case .calories: return "calories"
        case .protein: return "grams"
        case .sleepHours: return "hours"
        case .readinessAverage: return "score"
        case .strainBudget: return "strain"
        // Sprint 20260811 — new ChallengeType cases. Custom-flow defaults
        // to the most-common authoring unit per type (templates can override
        // via target_unit). Cycling/swim default to minutes (low friction);
        // stairs to flights; volume to lbs; mind/body to minutes.
        case .cycling, .swim, .mindBodyMinutes: return "minutes"
        case .stairsClimbed: return "flights"
        case .totalVolumeLifted: return "lbs"
        }
    }
    
    private var canCreateCustom: Bool {
        dailyTarget > 0
    }
    
    private func selectTemplate(_ template: ChallengeTemplate) {
        HapticManager.impact(.light)
        selectedTemplate = template
    }
    
    private func increaseTarget() {
        HapticManager.impact(.light)
        switch selectedType {
        case .steps:
            dailyTarget = min(50000, dailyTarget + 1000)
        case .walk, .run, .activeMinutes:
            dailyTarget = min(180, dailyTarget + 5)
        case .lift, .workoutStreak:
            dailyTarget = min(3, dailyTarget + 1)
        case .hydrate:
            dailyTarget = min(5000, dailyTarget + 250)
        case .calories:
            dailyTarget = min(5000, dailyTarget + 100)
        case .protein:
            dailyTarget = min(300, dailyTarget + 10)
        case .sleepHours:
            dailyTarget = min(12, dailyTarget + 1)
        case .readinessAverage:
            dailyTarget = min(100, dailyTarget + 5)
        case .strainBudget:
            dailyTarget = min(21, dailyTarget + 1)
        // Sprint 20260811 — new ChallengeType cases. Step sizes mirror
        // realistic daily targets (cycling/swim 5-min blocks like
        // activeMinutes; stairs 5 flights/tap; mind-body 5-min blocks;
        // volume 1000 lb increments — a single working set is ~500-2000 lbs).
        case .cycling, .swim, .mindBodyMinutes:
            dailyTarget = min(180, dailyTarget + 5)
        case .stairsClimbed:
            dailyTarget = min(200, dailyTarget + 5)
        case .totalVolumeLifted:
            dailyTarget = min(50_000, dailyTarget + 1_000)
        }
    }
    
    private func decreaseTarget() {
        HapticManager.impact(.light)
        switch selectedType {
        case .steps:
            dailyTarget = max(1000, dailyTarget - 1000)
        case .walk, .run, .activeMinutes:
            dailyTarget = max(5, dailyTarget - 5)
        case .lift, .workoutStreak:
            dailyTarget = max(1, dailyTarget - 1)
        case .hydrate:
            dailyTarget = max(250, dailyTarget - 250)
        case .calories:
            dailyTarget = max(100, dailyTarget - 100)
        case .protein:
            dailyTarget = max(10, dailyTarget - 10)
        case .sleepHours:
            dailyTarget = max(5, dailyTarget - 1)
        case .readinessAverage:
            dailyTarget = max(50, dailyTarget - 5)
        case .strainBudget:
            dailyTarget = max(5, dailyTarget - 1)
        // Sprint 20260811 — symmetric floors per type.
        case .cycling, .swim, .mindBodyMinutes:
            dailyTarget = max(5, dailyTarget - 5)
        case .stairsClimbed:
            dailyTarget = max(5, dailyTarget - 5)
        case .totalVolumeLifted:
            dailyTarget = max(1_000, dailyTarget - 1_000)
        }
    }
    
    private func loadTemplates() {
        // Load templates into local state WITHOUT triggering @Published updates
        // This prevents other views (DashboardView, etc.) from re-rendering
        // which could dismiss this sheet
        AppLogger.debug("🏆 [CHALLENGE SETUP] Starting template load (silent)...", category: .social)
        
        Task {
            // Use the silent method that doesn't update @Published
            let fetchedTemplates = await ChallengeService.shared.getTemplatesWithoutPublishing()
            
            await MainActor.run {
                self.templates = fetchedTemplates
                self.isLoadingTemplates = false
                AppLogger.debug("🏆 [CHALLENGE SETUP] Template load complete - \(fetchedTemplates.count) templates", category: .social)
            }
        }
    }
    
    private func createChallengeFromTemplate() {
        guard let template = selectedTemplate else { return }
        
        HapticManager.impact(.medium)
        isCreating = true
        
        Task {
            let challengeId = await ChallengeService.shared.createChallenge(
                opponentId: friend.friendId,
                type: template.type ?? .steps,
                title: template.title,
                description: template.description,
                dailyTarget: template.defaultDailyTarget,
                targetUnit: template.targetUnit,
                startDate: Date().addingTimeInterval(86400),
                durationDays: template.defaultDurationDays
            )
            
            isCreating = false
            
            if challengeId != nil {
                // Refresh pending sent challenges so it appears on home screen
                await ChallengeService.shared.fetchPendingSentChallenges()
                HapticManager.notification(.success)
                showingSuccess = true
            } else {
                HapticManager.notification(.error)
                errorMessage = "Could not send challenge. Please try again."
                showingError = true
            }
        }
    }
    
    private func createCustomChallenge() {
        HapticManager.impact(.medium)
        isCreating = true
        
        let title = customTitle.isEmpty ? "\(dailyTarget.formatted()) \(targetUnitDisplay) Daily" : customTitle
        
        Task {
            let challengeId = await ChallengeService.shared.createChallenge(
                opponentId: friend.friendId,
                type: selectedType,
                title: title,
                dailyTarget: dailyTarget,
                targetUnit: targetUnitDisplay,
                startDate: startDate,
                durationDays: durationDays
            )
            
            isCreating = false
            
            if challengeId != nil {
                // Refresh pending sent challenges so it appears on home screen
                await ChallengeService.shared.fetchPendingSentChallenges()
                HapticManager.notification(.success)
                showingSuccess = true
            } else {
                HapticManager.notification(.error)
                errorMessage = "Could not send challenge. Please try again."
                showingError = true
            }
        }
    }
}

// MARK: - Template Card

struct TemplateCard: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let template: ChallengeTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var type: ChallengeType {
        template.type ?? .steps
    }
    
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 12) {
                // Emoji/Icon with gradient circle
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: type.gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                        .shadow(color: type.color.opacity(0.4), radius: 8, x: 0, y: 4)
                    
                    Text(template.displayEmoji)
                        .font(.ds_heading2)
                }
                
                VStack(spacing: 4) {
                    Text(template.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if template.requiresStrava == true {
                        // Sprint 20260811 — attribution pill for Strava-gated
                        // templates. Mandatory by Strava brand guidelines.
                        Text("Powered by Strava")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundColor(.orange)
                    }

                    Text("\(template.defaultDurationDays) days")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .padding(.horizontal, Spacing.xs)
            .background(
                ZStack {
                    // Bottom shadow layer (deepest) - color glow
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(type.color.opacity(colorScheme == .dark ? 0.15 : 0.08))
                        .offset(y: 8)
                        .blur(radius: 4)
                    
                    // Middle shadow layer
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.2 : 0.04))
                        .offset(y: 4)
                    
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected 
                                    ? type.gradientColors
                                    : [type.color.opacity(colorScheme == .dark ? 0.4 : 0.3), type.gradientColors.last?.opacity(colorScheme == .dark ? 0.3 : 0.2) ?? type.color.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.08), radius: 12, x: 0, y: 6)
            .shadow(color: type.color.opacity(colorScheme == .dark ? 0.2 : 0.12), radius: 20, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Template Row

struct TemplateRow: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let template: ChallengeTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var type: ChallengeType {
        template.type ?? .steps
    }
    
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Emoji with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: type.gradientColors),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 40, height: 40)
                        .shadow(color: type.color.opacity(0.3), radius: 4, x: 0, y: 2)
                    
                    Text(template.displayEmoji)
                        .font(.ds_heading3)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)

                        if template.requiresStrava == true {
                            Text("STRAVA")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.18)))
                                .foregroundColor(.orange)
                        }
                    }

                    if let description = template.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Text("\(template.defaultDurationDays)d")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(type.color.opacity(0.1))
                    )
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.ds_heading2)
                    .foregroundStyle(
                        isSelected 
                            ? AnyShapeStyle(LinearGradient(colors: type.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.secondary.opacity(0.3))
                    )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    // Main card background with gradient
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            Color.cardBackground
                        )
                    
                    // Inner highlight (top edge glow)
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02), Color.clear]
                                    : [Color.white, Color.white.opacity(0.5), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                    
                    // Colored accent border
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: isSelected 
                                    ? type.gradientColors
                                    : [type.color.opacity(colorScheme == .dark ? 0.3 : 0.2), type.gradientColors.last?.opacity(colorScheme == .dark ? 0.2 : 0.1) ?? type.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.06), radius: 8, x: 0, y: 4)
            .shadow(color: type.color.opacity(isSelected ? 0.2 : 0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ChallengeSetupView(friend: Friend(
        friendshipId: UUID(),
        friendId: UUID(),
        friendName: "Leo Smith",
        friendEmail: nil,
        friendUsername: "leosmith",
        fitnessGoal: "Build Muscle",
        experienceLevel: "Intermediate",
        profilePhotoUrl: nil,
        friendsSince: Date(),
        totalWorkoutsShared: 5,
        isVerified: false,
        isGoldVerified: false
    ))
}
