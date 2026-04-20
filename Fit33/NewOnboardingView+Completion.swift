import SwiftUI

/// Sprint 3 (Q2-37): explicit error states raised from `completeOnboarding()`.
/// Shown to the user via a confirmation dialog with the option to retry or
/// start over (deleting any already-created cloud profile).
enum OnboardingError: LocalizedError, Identifiable {
    case invalidWeight
    case invalidHeight

    var id: String {
        switch self {
        case .invalidWeight: return "invalid_weight"
        case .invalidHeight: return "invalid_height"
        }
    }

    var errorDescription: String? {
        switch self {
        case .invalidWeight:
            return "We couldn't read your weight. Please edit it and try again."
        case .invalidHeight:
            return "We couldn't read your height. Please edit it and try again."
        }
    }
}

extension NewOnboardingView {
    func confirmationRowSimple(title: String, value: String, editStep: OnboardingStep? = nil, focusField: FocusedField? = nil) -> some View {
        Button(action: {
            if let step = editStep {
                isEditingFromConfirmation = true
                navigateTo(step)
                
                // Auto-focus the field after a short delay
                if let field = focusField {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.4))
                        guard !Task.isCancelled else { return }
                        focusedField = field
                    }
                }
            }
        }) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                if editStep != nil {
                    Image(systemName: "chevron.right")
                        .font(.ds_labelMedium)
                        .foregroundColor(.secondary)
                        .padding(.leading, 8)
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    func formatHeightDisplay() -> String {
        let digits = heightFeetInchesDigits.filter { $0.isNumber }
        guard !digits.isEmpty else { return "-" }
        let feet = String(digits.prefix(1))
        let inches = String(digits.dropFirst().prefix(2))
        if inches.isEmpty {
            return "\(feet)'0\""
        }
        return "\(feet)'\(inches)\""
    }
    
    func handleConfirmation() {
        // Use existing auth/account creation logic from the confirmation step
        Task {
            await completeOnboardingFlow()
        }
    }
    
    func completeOnboardingFlow() async {
        // Create Supabase account first, then complete onboarding
        await MainActor.run {
            createAccountAndComplete()
        }
    }

    // MARK: - Basics Step (Birthday + Gender)
    // Parse birthday from MM/DD/YYYY or DD/MM/YYYY format based on locale
    var birthdayDate: Date? {
        let parts = birthday.split(separator: "/")
        guard parts.count == 3 else { return nil }
        
        let month: Int
        let day: Int
        let year: Int
        
        if usesMonthFirstDate {
            // MM/DD/YYYY format (US)
            guard let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            month = m
            day = d
            year = y
        } else {
            // DD/MM/YYYY format (UK, most of world)
            guard let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) else { return nil }
            day = d
            month = m
            year = y
        }
        
        guard month >= 1 && month <= 12,
              day >= 1 && day <= 31,
              year >= 1900 && year <= Calendar.current.component(.year, from: Date())
        else { return nil }

        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year

        // Validate actual calendar date (catches Feb 30, Apr 31, etc.)
        guard let date = Calendar.current.date(from: components),
              Calendar.current.component(.month, from: date) == month,
              Calendar.current.component(.day, from: date) == day,
              Calendar.current.component(.year, from: date) == year
        else { return nil }

        return date
    }
    
    var isBirthdayValid: Bool {
        birthdayDate != nil
    }
    
    var calculatedAge: Int {
        guard let date = birthdayDate else { return 0 }
        return Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
    }
    
    /// Birthday in ISO format (YYYY-MM-DD) for database storage
    /// Converts from locale-specific format (MM/DD/YYYY or DD/MM/YYYY) to ISO
    var birthdayISO: String? {
        guard let date = birthdayDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    // MARK: - Height/Weight Validation (restored from audit cleanup)
    
    var parsedHeightFeetInches: (feet: Int, inches: Int)? {
        let digits = heightDigits
        guard !digits.isEmpty else { return nil }
        let feet = Int(String(digits.prefix(1))) ?? 0
        let inchDigits = String(digits.dropFirst())
        let inches: Int
        if inchDigits.isEmpty {
            inches = 0
        } else if inchDigits.count == 1 {
            inches = Int(inchDigits) ?? 0
        } else {
            inches = Int(inchDigits.prefix(2)) ?? 0
        }
        if feet >= 3 && feet <= 8 && inches >= 0 && inches <= 11 {
            return (feet, inches)
        }
        return nil
    }
    
    var isHeightValid: Bool {
        if heightUnit == .cm {
            let trimmed = heightCm.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let cm: Int?
            if let intValue = Int(trimmed) {
                cm = intValue
            } else if let doubleValue = Double(trimmed) {
                cm = Int(doubleValue)
            } else {
                cm = nil
            }
            guard let validCm = cm else { return false }
            return validCm >= 90 && validCm <= 270
        } else {
            return parsedHeightFeetInches != nil
        }
    }
    
    var isWeightValid: Bool {
        let trimmed = weight.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let w = Double(normalized), w > 0 else { return false }
        if weightUnit == .lbs {
            return w >= 50 && w <= 700
        } else {
            return w >= 23 && w <= 320
        }
    }
    
    var heightInCm: Int {
        if heightUnit == .cm {
            let trimmed = heightCm.trimmingCharacters(in: .whitespaces)
            if let intValue = Int(trimmed) { return intValue }
            if let doubleValue = Double(trimmed) { return Int(doubleValue) }
            return 0
        } else if let parsed = parsedHeightFeetInches {
            let totalInches = (parsed.feet * 12) + parsed.inches
            return Int(Double(totalInches) * 2.54)
        }
        return 0
    }
    
    var formattedHeight: String {
        if heightUnit == .cm {
            return "\(heightCm) cm"
        } else if let parsed = parsedHeightFeetInches {
            return "\(parsed.feet)'\(parsed.inches)\""
        }
        return heightFeetInchesDigits
    }
    
    var formattedWeight: String {
        if weightUnit == .lbs {
            return "\(weight) lbs"
        } else {
            return "\(weight) kg"
        }
    }

    // MARK: - Complete Step
    var completeStep: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Spacer()
                
                // Success animation
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 110, height: 110)
                    
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.green)
                }
                
                Spacer()
                    .frame(height: 24)
                
                VStack(spacing: 8) {
                    Text("You're all set!")
                        .font(.ds_heading2)
                        .foregroundColor(.primary)
                    
                    Text("Let's start building a stronger you")
                        .font(.ds_bodyMedium)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                    .frame(height: 28)
                
                // Summary
                VStack(spacing: 12) {
                    SummaryRow(icon: "target", label: "Goal", value: selectedGoals.sorted().joined(separator: ", "))
                    SummaryRow(icon: "figure.walk", label: "Level", value: selectedExperience)
                    SummaryRow(icon: "hand.raised.fill", label: "Strength", value: selectedStrengthLevel.displayName)
                    SummaryRow(icon: "calendar", label: "Schedule", value: "\(selectedDays) days/week")
                }
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .fill(Color(.systemBackground))
                        .shadow(color: Color.blue.opacity(0.08), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.lg)
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .padding(.horizontal, Spacing.lg)
                
                Spacer()
            }
            .padding(.bottom, 100)
            
            // Start button - floating at bottom
            Button(action: finishOnboarding) {
                Text("Start Training 💪")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.md)
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(CornerRadius.lg)
                    .shadow(color: Color.green.opacity(0.4), radius: 10, x: 0, y: 5)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, 30)
        }
    }
    
    /// Upload the profile photo selected during onboarding to Supabase
    func uploadOnboardingProfilePhoto(_ image: UIImage) async {
        guard SupabaseManager.shared.currentUser?.id != nil else {
            AppLogger.warning("No user ID available for profile photo", category: .ui)
            return
        }
        
        // Compress to JPEG with good quality but small file size
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            AppLogger.error("Failed to convert image to JPEG", category: .ui)
            return
        }
        
        do {
            let photoUrl = try await SupabaseManager.shared.uploadProfilePhoto(imageData: imageData)
            AppLogger.info("Profile photo uploaded: \(photoUrl)", category: .ui)
            
            // Cache the image locally for immediate display
            await MainActor.run {
                ProfilePhotoCache.shared.cacheImage(image)
            }
        } catch {
            AppLogger.error("Failed to upload profile photo: \(error)", category: .ui)
            // Don't block onboarding completion - photo upload is optional
        }
    }
    
    func saveLimitationsToCloud() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            AppLogger.warning("No user ID available for limitations", category: .ui)
            return
        }
        
        let limitations = selectedLimitations.map { area in
            UserLimitation(
                id: UUID(),
                userId: userId,
                limitationType: .injury,
                affectedArea: area,
                severity: limitationAccommodations[area] ?? .beCareful,
                exercisesToAvoid: [],  // Will be populated from mappings
                movementPatternsToAvoid: [],
                equipmentToAvoid: [],
                notes: nil,
                startedDate: Date(),
                expectedRecoveryDate: nil,
                resolvedDate: nil,
                isActive: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
        
        do {
            try await LimitationsService.shared.addLimitations(limitations)
            AppLogger.info("Saved \(limitations.count) limitations to cloud", category: .ui)
        } catch {
            AppLogger.error("Failed to save limitations: \(error)", category: .ui)
        }
    }
    
    /// Sprint 3 (Q2-37): trigger the error dialog from the completion flow.
    func presentOnboardingCompletionError(_ error: OnboardingError) {
        completionError = error
    }

    /// Sprint 3 (Q2-37): if an OAuth user has already had a cloud profile row
    /// created (via `createProfileForOAuthUser` earlier in this session) but
    /// we detected invalid inputs afterwards, blow away the orphan so they
    /// can start fresh without the server-side "email already exists" trap.
    ///
    /// Idempotent: silently no-ops if no cloud profile exists yet.
    func rollbackCloudProfileIfNeeded() async {
        guard supabaseManager.isAuthenticated else {
            AppLogger.debug("Onboarding rollback: not authenticated, nothing to undo", category: .auth)
            return
        }
        AppLogger.warning("Onboarding rollback: deleting orphan cloud profile so user can restart", category: .auth)
        do {
            try await supabaseManager.deleteAccount()
        } catch {
            // Deletion may fail if the row was never created — treat as no-op.
            AppLogger.debug("Onboarding rollback: deleteAccount failed (expected if no profile exists): \(error.localizedDescription)", category: .auth)
        }
    }

    func completeOnboarding() {
        // Sprint 3 (Q2-37): validate every SYNCHRONOUS input up-front, BEFORE
        // we kick any detached `Task {}` that writes to Supabase. The old
        // sequence fired the OAuth-profile Task at ~line 430, then parsed
        // weight synchronously at ~line 542. A failed weight parse `return`ed
        // without awaiting or cancelling that task, leaving a cloud profile
        // row with no matching local `User` — the classic "orphan account".
        guard let parsedWeight = Double(weight) else {
            AppLogger.error("Onboarding completion aborted — invalid weight input", category: .ui)
            presentOnboardingCompletionError(.invalidWeight)
            return
        }

        // Log onboarding completion
        SessionLogManager.shared.logOnboardingComplete(
            totalSteps: OnboardingStep.allCases.count,
            duration: 0 // We don't track duration yet
        )
        
        // Collect all onboarding data for logging
        let heightCmValue = Double(heightInCm)
        var weightKgValue: Double = 0
        weightKgValue = weightUnit == .lbs ? parsedWeight / 2.20462 : parsedWeight
        let ageValue = calculatedAge > 0 ? calculatedAge : nil
        
        let onboardingData: [String: Any] = [
            "name": name,
            "email": email.isEmpty ? (supabaseManager.currentUser?.email ?? "none") : email,
            "username": username.isEmpty ? "none" : username,
            "age": ageValue ?? 0,
            "gender": selectedGender ?? "not_specified",
            "height_cm": heightCmValue,
            "weight_kg": weightKgValue,
            "fitness_goals": selectedGoals.sorted().joined(separator: ", "),
            "experience_level": selectedExperience,
            "equipment": Array(selectedEquipment),
            "available_days": selectedDays,
            "workout_environment": selectedWorkoutLocation.rawValue,
            "limitations_count": selectedLimitations.count,
            "has_profile_photo": profilePhotoImage != nil,
            "is_authenticated": supabaseManager.isAuthenticated,
            "auth_provider": detectedAuthProvider,
            "session_duration_seconds": OnboardingSessionManager.shared.sessionDuration
        ]
        
        // Log the completion attempt
        Task {
            await supabaseManager.logOnboardingEvent(
                eventType: "onboarding_completed",
                stepName: "complete",
                eventData: onboardingData
            )
            
            // ═══════════════════════════════════════════════════════════════════
            // FIELD-LEVEL LOGGING: Log each field at "collected" stage
            // This captures exactly what was entered in the UI
            // ═══════════════════════════════════════════════════════════════════
            AppLogger.debug("Logging all collected field values...", category: .ui)
            
            await supabaseManager.logOnboardingField(fieldName: "name", stage: "collected", value: name)
            await supabaseManager.logOnboardingField(fieldName: "email", stage: "collected", value: email.isEmpty ? supabaseManager.currentUser?.email : email)
            await supabaseManager.logOnboardingField(fieldName: "username", stage: "collected", value: username.isEmpty ? nil : username)
            await supabaseManager.logOnboardingField(fieldName: "birthday", stage: "collected", value: birthday, rawInput: birthday)
            await supabaseManager.logOnboardingField(fieldName: "age", stage: "collected", value: ageValue, rawInput: birthday, convertedValue: ageValue.map { "\($0) years" })
            await supabaseManager.logOnboardingField(fieldName: "gender", stage: "collected", value: selectedGender)
            await supabaseManager.logOnboardingField(fieldName: "height_cm", stage: "collected", value: heightCmValue > 0 ? heightCmValue : nil, rawInput: heightUnit == .ftIn ? heightFeetInchesDigits : "\(heightCm) cm", convertedValue: "\(heightCmValue) cm")
            await supabaseManager.logOnboardingField(fieldName: "weight_kg", stage: "collected", value: weightKgValue > 0 ? weightKgValue : nil, rawInput: "\(weight) \(weightUnit.rawValue)", convertedValue: "\(weightKgValue) kg")
            await supabaseManager.logOnboardingField(fieldName: "fitness_goal", stage: "collected", value: selectedGoals.isEmpty ? nil : selectedGoals.sorted().joined(separator: ", "))
            await supabaseManager.logOnboardingField(fieldName: "experience_level", stage: "collected", value: selectedExperience.isEmpty ? nil : selectedExperience)
            await supabaseManager.logOnboardingField(fieldName: "equipment", stage: "collected", value: selectedEquipment.isEmpty ? nil : Array(selectedEquipment))
            await supabaseManager.logOnboardingField(fieldName: "available_days", stage: "collected", value: selectedDays > 0 ? selectedDays : nil)
            await supabaseManager.logOnboardingField(fieldName: "workout_environment", stage: "collected", value: selectedWorkoutLocation.rawValue)
        }
        
        // For OAuth users (Apple/Google/Facebook), create the profile NOW at the end of onboarding
        // This ensures we don't create "zombie" accounts if user abandons onboarding
        if supabaseManager.isAuthenticated {
            Task {
                // Log profile creation start
                await supabaseManager.logOnboardingEvent(
                    eventType: "profile_create_started",
                    stepName: "complete",
                    eventData: onboardingData
                )
                
                do {
                    // ═══════════════════════════════════════════════════════════════════
                    // FIELD-LEVEL LOGGING: Log each field at "sent_to_db" stage
                    // This captures exactly what we're sending to Supabase
                    // ═══════════════════════════════════════════════════════════════════
                    AppLogger.debug("Logging values being sent to database...", category: .ui)
                    
                    let emailToSend = email.isEmpty ? (supabaseManager.currentUser?.email ?? "") : email
                    let heightToSend = heightCmValue > 0 ? heightCmValue : nil
                    let weightToSend = weightKgValue > 0 ? weightKgValue : nil
                    let goalsToSend = selectedGoals.isEmpty ? nil : selectedGoals.sorted().joined(separator: ", ")
                    let experienceToSend = selectedExperience.isEmpty ? nil : selectedExperience
                    let equipmentToSend = selectedEquipment.isEmpty ? nil : Array(selectedEquipment)
                    let daysToSend = selectedDays > 0 ? selectedDays : nil
                    
                    await supabaseManager.logOnboardingField(fieldName: "name", stage: "sent_to_db", value: name)
                    await supabaseManager.logOnboardingField(fieldName: "email", stage: "sent_to_db", value: emailToSend)
                    await supabaseManager.logOnboardingField(fieldName: "username", stage: "sent_to_db", value: username.isEmpty ? nil : username)
                    await supabaseManager.logOnboardingField(fieldName: "birthday", stage: "sent_to_db", value: birthdayISO, rawInput: birthday, convertedValue: birthdayISO)
                    await supabaseManager.logOnboardingField(fieldName: "age", stage: "sent_to_db", value: ageValue)
                    await supabaseManager.logOnboardingField(fieldName: "gender", stage: "sent_to_db", value: selectedGender)
                    await supabaseManager.logOnboardingField(fieldName: "height_cm", stage: "sent_to_db", value: heightToSend)
                    await supabaseManager.logOnboardingField(fieldName: "weight_kg", stage: "sent_to_db", value: weightToSend)
                    await supabaseManager.logOnboardingField(fieldName: "fitness_goal", stage: "sent_to_db", value: goalsToSend)
                    await supabaseManager.logOnboardingField(fieldName: "experience_level", stage: "sent_to_db", value: experienceToSend)
                    await supabaseManager.logOnboardingField(fieldName: "equipment", stage: "sent_to_db", value: equipmentToSend)
                    await supabaseManager.logOnboardingField(fieldName: "available_days", stage: "sent_to_db", value: daysToSend)
                    await supabaseManager.logOnboardingField(fieldName: "workout_environment", stage: "sent_to_db", value: selectedWorkoutLocation.rawValue)
                    
                    // Use full international phone number (with country code) if verified
                    let phoneForOAuth = isPhoneVerified ? fullPhoneNumber : nil
                    
                    AppLogger.debug("Creating profile for OAuth user (late path)... Birthday: display='\(birthday)' -> ISO='\(birthdayISO ?? "nil")'", category: .auth)
                    try await supabaseManager.createProfileForOAuthUser(
                        name: name,
                        email: emailToSend,
                        username: username.isEmpty ? nil : username,
                        birthday: birthdayISO,  // Birthday in ISO format (YYYY-MM-DD) for database
                        age: ageValue,
                        gender: selectedGender,
                        heightCm: heightToSend,
                        weightKg: weightToSend,
                        fitnessGoal: goalsToSend,
                        experienceLevel: experienceToSend,
                        equipment: equipmentToSend,
                        availableDays: daysToSend,
                        workoutEnvironment: selectedWorkoutLocation.rawValue,
                        phoneNumber: phoneForOAuth  // 2FA phone number with country code (private)
                    )
                    AppLogger.info("OAuth user profile created successfully!", category: .auth)
                    
                    // Log success
                    await supabaseManager.logOnboardingEvent(
                        eventType: "profile_create_success",
                        stepName: "complete",
                        eventData: ["user_id": supabaseManager.currentUser?.id.uuidString ?? "unknown"]
                    )
                    
                    // ═══════════════════════════════════════════════════════════════════
                    // VERIFY: Read back what was actually saved to the database
                    // This will log each field at "verified_in_db" stage
                    // ═══════════════════════════════════════════════════════════════════
                    AppLogger.debug("Verifying what was actually saved to database...", category: .ui)
                    await supabaseManager.verifyAndLogSavedProfile()
                    
                    // 📬 NOTIFY EXISTING USERS: If phone is verified and contacts synced, notify contacts
                    // This sends push notifications to existing Fit33 users who have this new user in their contacts
                    if isPhoneVerified && ContactsService.shared.hasCheckedContacts {
                        AppLogger.info("Phone verified + contacts synced → notifying existing users...", category: .social)
                        await ContactsService.shared.notifyExistingUsersOfNewJoin()
                    } else {
                        AppLogger.warning("Skipping contact notifications (phone verified: \(isPhoneVerified), contacts synced: \(ContactsService.shared.hasCheckedContacts))", category: .social)
                    }
                    
                } catch {
                    AppLogger.error("Failed to create OAuth profile: \(error.localizedDescription)", category: .auth)
                    
                    // Log the error with full details
                    await supabaseManager.logOnboardingEvent(
                        eventType: "profile_create_error",
                        stepName: "complete",
                        eventData: onboardingData,
                        errorMessage: error.localizedDescription
                    )
                    
                    // Continue with local setup even if cloud fails
                }
            }
        }
        
        // Calculate age from birthday
        let ageInt = Int16(calculatedAge)
        
        // Get height in cm
        let heightInt = Int16(heightInCm)
        
        // Get weight in kg (parsedWeight is guaranteed non-nil from the
        // Sprint 3 up-front validation at the top of this function).
        let weightInt: Int16
        if weightUnit == .lbs {
            weightInt = Int16(parsedWeight / 2.20462) // Convert lbs to kg
        } else {
            weightInt = Int16(parsedWeight)
        }
        
        let limitationsStr = selectedLimitations.isEmpty ? "None" : selectedLimitations.map { "\($0.rawValue): \((limitationAccommodations[$0] ?? .beCareful).displayName)" }.joined(separator: ", ")
        AppLogger.info("Onboarding complete - Name: \(name), Age: \(ageInt), Gender: \(selectedGender ?? "N/A"), Height: \(heightInt)cm, Weight: \(weightInt)kg, Goals: \(selectedGoals.sorted().joined(separator: ", ")), Exp: \(selectedExperience), Strength: \(selectedStrengthLevel.rawValue), Env: \(selectedWorkoutLocation.rawValue), Equipment: \(selectedEquipment.sorted().joined(separator: ", ")), Days: \(selectedDays), Limitations: \(limitationsStr)", category: .ui)
        
        // Get original height in total inches for storage
        let heightInches: Int16
        if heightUnit == .ftIn, let parsed = parsedHeightFeetInches {
            heightInches = Int16(parsed.feet * 12 + parsed.inches)
        } else {
            // Convert from cm to inches if user used metric
            heightInches = Int16(Double(heightInCm) / 2.54)
        }
        
        // Get original weight in lbs for storage (reuse parsedWeight).
        let weightLbs: Double
        if weightUnit == .lbs {
            weightLbs = parsedWeight
        } else {
            weightLbs = parsedWeight * 2.20462
        }
        
        // Use full international phone number (with country code) if verified
        let phoneForUser = isPhoneVerified ? fullPhoneNumber : nil
        
        userManager.createUser(
            name: name,
            age: ageInt,
            gender: selectedGender,
            email: email.isEmpty ? nil : email,
            height: heightInt,
            weight: weightInt,
            fitnessGoal: selectedGoals.sorted().joined(separator: ", "),
            experienceLevel: selectedExperience,
            equipment: Array(selectedEquipment),
            availableDays: Int16(selectedDays),
            strengthLevel: selectedStrengthLevel.rawValue,
            workoutEnvironment: selectedWorkoutLocation.rawValue,
            birthday: birthday.isEmpty ? nil : birthday,
            weightLbs: weightLbs,
            heightInches: heightInches,
            phoneNumber: phoneForUser  // 2FA phone number with country code (private)
        )
        
        // Save user limitations to cloud
        if !selectedLimitations.isEmpty {
            Task {
                await saveLimitationsToCloud()
            }
        }
        
        // Upload profile photo if provided
        if let photo = profilePhotoImage {
            Task {
                await uploadOnboardingProfilePhoto(photo)
            }
        }
        
        // Sync video gender preference based on user's gender selection
        VideoStreamingService.shared.syncGenderFromUserProfile()
        
        // 👤 Set centralized gender preference
        if let gender = selectedGender {
            let genderPref: GenderFilterService.Gender = gender.lowercased().contains("female") ? .female : .male
            GenderFilterService.shared.setPreferredGender(genderPref)
        }
        
        // 📬 NOTIFY EXISTING USERS: For email/password signup users
        // This sends push notifications to existing Fit33 users who have this new user in their contacts
        // (OAuth users are handled in the Task block above)
        if !supabaseManager.isAuthenticated {
            // This shouldn't happen, but log it
            AppLogger.warning("User not authenticated after profile creation - skipping contact notifications", category: .auth)
        } else {
            Task {
                // Check if phone is verified and contacts are synced
                if isPhoneVerified && ContactsService.shared.hasCheckedContacts {
                    AppLogger.info("Phone verified + contacts synced → notifying existing users (non-OAuth path)...", category: .social)
                    await ContactsService.shared.notifyExistingUsersOfNewJoin()
                } else {
                    AppLogger.warning("Skipping contact notifications - non-OAuth (phone verified: \(isPhoneVerified), contacts synced: \(ContactsService.shared.hasCheckedContacts))", category: .social)
                }
            }
        }
        
        // Show completion screen
        navigateTo(.complete)
    }
    
    func finishOnboarding() {
        // UserManager.createUser already sets hasCompletedOnboarding = true
        // The view will automatically transition via ContentView
        AppLogger.info("Onboarding complete! Transitioning to main app...", category: .ui)
        
        // 🔔 REQUEST NOTIFICATION PERMISSIONS IMMEDIATELY
        // This triggers the native iOS permission prompt right as they complete onboarding
        // All notification types are defaulted ON in NotificationManager for maximum engagement
        Task {
            // Request notification permission - this shows native iOS prompt
            let granted = await NotificationManager.shared.requestAuthorization()
            if granted {
                AppLogger.info("Notification permissions granted during onboarding - scheduling all notifications", category: .ui)
                // Schedule all default notifications immediately
                await MainActor.run {
                    NotificationManager.shared.scheduleAllNotifications()
                }
            } else {
                AppLogger.warning("User declined notification permission", category: .ui)
                // We'll show them a banner on the Dashboard to reconsider
            }
        }
        
        // Generate personalized programs based on user profile
        if let user = userManager.currentUser {
            Task {
                AppLogger.debug("Generating personalized workout programs...", category: .workout)
                _ = await GeneratedProgramService.shared.generateProgramsForUser(user)
                AppLogger.info("Programs generated!", category: .workout)
            }
        }
    }
}
