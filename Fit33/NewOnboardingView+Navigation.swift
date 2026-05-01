import SwiftUI

extension NewOnboardingView {
    func navigateTo(_ step: OnboardingStep, animated: Bool = true) {
        AppLogger.debug("navigateTo(\(step)) called, animated: \(animated), isEditingFromConfirmation: \(isEditingFromConfirmation)", category: .ui)
        AppLogger.debug("Previous step: \(currentStep)", category: .ui)
        let previousStep = currentStep
        
        OnboardingSessionManager.shared.trackStepCompleted(previousStep.rawValue)
        OnboardingSessionManager.shared.trackStepStarted(step.rawValue)
        
        // Map onboarding step to screen ID
        let screenMap: [OnboardingStep: SessionLogManager.Screen] = [
            .auth: .authScreen,
            .phoneNumber: .authScreen, // Use auth screen for logging
            .username: .authScreen, // Use auth screen for logging
            .basics: .onboardingBasics,
            .body: .onboardingBody,
            .goal: .onboardingGoal,
            .experience: .onboardingExperience,
            .strengthAssessment: .onboardingStrength,
            .workoutLocation: .onboardingLocation,
            .equipment: .onboardingEquipment,
            .limitations: .onboardingLimitations,
            .schedule: .onboardingSchedule,
            .confirmation: .onboardingConfirmation,
            .complete: .onboardingComplete
        ]
        
        // Log with screen ID
        if let screen = screenMap[step] {
            SessionLogManager.shared.logScreen(screen, metadata: [
                "step_number": step.rawValue,
                "editing_from_confirmation": isEditingFromConfirmation
            ])
        }
        
        // Log onboarding step transition
        SessionLogManager.shared.logOnboardingStep(
            step: step.rawValue,
            stepName: "\(step)",
            action: "navigated"
        )

        // New User Journey Tracker — mirror to the 72h-TTL funnel pipeline.
        // No-op until the user has authenticated (the auth step itself fires
        // first, but the server RPC silently drops anonymous calls). Once
        // post-signup, every step transition becomes a funnel event with
        // monotonic step_index, drives the per-user report's onboarding section.
        let stepName = "\(step)"
        let stepIndex = step.rawValue
        let editing = isEditingFromConfirmation
        // Capture has_goals at the moment the user is LEAVING the .goal step
        // (Migration #175 trigger contract: payload.step='goals' AND
        // payload.has_goals='true' → flips `goal_set` flag on enrollment).
        let leavingGoalStep = (previousStep == .goal && step != .goal)
        let hasGoalsAtLeave = !selectedGoals.isEmpty
        Task { @MainActor in
            NewUserJourneyTracker.shared.logFunnelStep(
                funnel: "onboarding",
                step: stepName,
                stepIndex: stepIndex,
                extra: ["is_editing": editing]
            )
            if leavingGoalStep {
                NewUserJourneyTracker.shared.logFunnelStep(
                    funnel: "onboarding",
                    step: "goals",
                    stepIndex: OnboardingStep.goal.rawValue,
                    extra: [
                        "has_goals": hasGoalsAtLeave,
                        "goal_count": selectedGoals.count
                    ]
                )
            }
            if step == .complete {
                NewUserJourneyTracker.shared.logFunnelStep(
                    funnel: "onboarding",
                    step: "completed",
                    stepIndex: stepIndex
                )
            }
        }
        
        // Log step completion to cloud (for debugging UK user issue)
        Task {
            // Log the previous step as completed
            if previousStep != step {
                await supabaseManager.logOnboardingEvent(
                    eventType: "step_completed",
                    stepName: "\(previousStep)",
                    eventData: [
                        "step_number": previousStep.rawValue,
                        "next_step": "\(step)",
                        "session_duration": OnboardingSessionManager.shared.sessionDuration
                    ]
                )
            }
            
            // Log the new step as started
            await supabaseManager.logOnboardingEvent(
                eventType: "step_started",
                stepName: "\(step)",
                eventData: [
                    "step_number": step.rawValue,
                    "previous_step": "\(previousStep)",
                    "is_editing": isEditingFromConfirmation
                ]
            )
        }
        
        currentStep = step
        
        // Save checkpoint so progress survives app close
        if step != .complete {
            OnboardingSessionManager.shared.saveCheckpoint(
                step: step.rawValue,
                data: collectCheckpointData()
            )
        } else {
            OnboardingSessionManager.shared.clearCheckpoint()
        }
    }

    // MARK: - Checkpoint Persistence
    
    func collectCheckpointData() -> [String: String] {
        var data: [String: String] = [:]
        if !email.isEmpty { data["email"] = email }
        if !name.isEmpty { data["name"] = name }
        if !username.isEmpty { data["username"] = username }
        if !birthday.isEmpty { data["birthday"] = birthday }
        if let gender = selectedGender { data["gender"] = gender }
        if !heightFeetInchesDigits.isEmpty { data["heightFtIn"] = heightFeetInchesDigits }
        if !heightCm.isEmpty { data["heightCm"] = heightCm }
        if !weight.isEmpty { data["weight"] = weight }
        data["heightUnit"] = heightUnit == .cm ? "cm" : "ft"
        data["weightUnit"] = weightUnit == .lbs ? "lbs" : "kg"
        if !selectedGoals.isEmpty { data["goals"] = selectedGoals.joined(separator: ",") }
        if !selectedExperience.isEmpty { data["experience"] = selectedExperience }
        data["strength"] = selectedStrengthLevel.rawValue
        data["location"] = "\(selectedWorkoutLocation)"
        if !selectedEquipment.isEmpty { data["equipment"] = selectedEquipment.joined(separator: ",") }
        return data
    }
    
    func restoreFromCheckpoint() {
        guard let checkpoint = OnboardingSessionManager.shared.loadCheckpoint(),
              checkpoint.step > 0 else { return }
        
        let data = checkpoint.data
        if let e = data["email"] { email = e }
        if let n = data["name"] { name = n }
        if let u = data["username"] { username = u }
        if let b = data["birthday"] { birthday = b }
        selectedGender = data["gender"]
        if let h = data["heightFtIn"] { heightFeetInchesDigits = h }
        if let h = data["heightCm"] { heightCm = h }
        if let w = data["weight"] { weight = w }
        if data["heightUnit"] == "cm" { heightUnit = .cm }
        if data["weightUnit"] == "kg" { weightUnit = .kg }
        if let g = data["goals"] { selectedGoals = Set(g.split(separator: ",").map(String.init)) }
        if let exp = data["experience"] { selectedExperience = exp }
        if let s = data["strength"], let level = StrengthProfileRecommendationEngine.StrengthLevel(rawValue: s) { selectedStrengthLevel = level }
        if let loc = data["location"] {
            switch loc {
            case "gym": selectedWorkoutLocation = .gym
            case "home": selectedWorkoutLocation = .home
            case "outdoor": selectedWorkoutLocation = .outdoor
            case "hybrid": selectedWorkoutLocation = .hybrid
            default: break
            }
        }
        if let eq = data["equipment"] { selectedEquipment = Set(eq.split(separator: ",").map(String.init)) }
        
        if let step = OnboardingStep(rawValue: checkpoint.step) {
            currentStep = step
        }
    }
    
    // MARK: - Navigation Helpers
    func goToNextStep() {
        if currentStep == .confirmation {
            // Handle account creation
            handleConfirmation()
            return
        }
        
        // If editing from confirmation, return to confirmation screen
        if isEditingFromConfirmation {
            isEditingFromConfirmation = false
            navigateTo(.confirmation)
            return
        }
        
        // Special case: if contacts permission not granted, skip addFriends step
        if currentStep == .contacts && !contactsPermissionGranted {
            navigateTo(.confirmation)
            return
        }
        
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        navigateTo(nextStep)
    }
    
    func goToPreviousStep() {
        // If editing from confirmation, go back to confirmation
        if isEditingFromConfirmation {
            isEditingFromConfirmation = false
            navigateTo(.confirmation)
            return
        }
        
        // Special case: if on phone step with code sent, go back to phone input (not previous step)
        if currentStep == .phoneNumber && isVerificationCodeSent {
            // If max attempts reached, going back triggers email verification fallback
            if phoneVerificationAttempts >= maxPhoneVerificationAttempts {
                withAnimation(.easeInOut(duration: 0.3)) {
                    hasSkippedPhoneVerification = true
                    isVerificationCodeSent = false
                    verificationCode = ""
                    verificationError = ""
                }
                sendEmailVerification()
                return
            }
            
            isVerificationCodeSent = false
            verificationCode = ""
            verificationError = ""
            
            sendCodeCountdown = 30
            startSendCodeCountdownTimer()
            
            focusedField = .phoneNumber
            return
        }
        
        // If on phone step showing email fallback, don't go back further
        if currentStep == .phoneNumber && hasSkippedPhoneVerification {
            return
        }
        
        // Special case: if on confirmation and contacts weren't granted, skip addFriends when going back
        if currentStep == .confirmation && !contactsPermissionGranted {
            navigateTo(.contacts)
            return
        }
        
        guard let prevStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else { return }
        navigateTo(prevStep)
    }
}
