import SwiftUI

extension NewOnboardingView {
    // MARK: - Username Step Content
    var usernameStepContent: some View {
        VStack(spacing: 28) {
            // Name field - always show for all users (email, Apple, Google auth)
            // For email signup: user enters manually
            // For Apple/Google: autofills from OAuth but is editable
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Image(systemName: "person.fill")
                        .font(.ds_heading3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: !name.isEmpty ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26)
                    
                    TextField("What should we call you?", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)
                }
                .font(.ds_bodyRegular)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.14), Color(white: 0.10)]
                                        : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.clear)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: focusedField == .name ? 12 : 8,
                                x: 0,
                                y: focusedField == .name ? 6 : 3
                            )
                    }
                )
            }
            
            // Username - matching Birthday field style exactly
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Username")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    // Status indicator in top right
                    if isCheckingUsername {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Checking...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if isUsernameAvailable && isUsernameValid {
                        Text("Available ✓")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if !usernameError.isEmpty {
                        Text(usernameError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                // Username field - same style as OnboardingTextField (no checkmark inside)
                HStack(spacing: 16) {
                    // @ symbol instead of icon
                    Text("@")
                        .font(.ds_heading3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: isUsernameValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26)
                    
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .onChange(of: username) { _, newValue in
                            // Clean the username - remove spaces and special chars (allow uppercase and lowercase)
                            let cleaned = newValue
                                .filter { $0.isLetter || $0.isNumber || $0 == "_" }
                            if cleaned != newValue {
                                username = cleaned
                            }
                            // Reset availability when typing
                            isUsernameAvailable = false
                            usernameError = ""
                        }
                }
                .font(.ds_bodyRegular)
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark 
                                        ? [Color(white: 0.14), Color(white: 0.10)]
                                        : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        RoundedRectangle(cornerRadius: CornerRadius.lg)
                            .fill(Color.clear)
                            .shadow(
                                color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08),
                                radius: focusedField == .username ? 12 : 8,
                                x: 0,
                                y: focusedField == .username ? 6 : 3
                            )
                    }
                )
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
    
    // Check username availability
    func checkUsernameAvailability() {
        guard isUsernameValid else { return }
        
        isCheckingUsername = true
        usernameError = ""
        
        Task {
            do {
                let available = try await supabaseManager.isUsernameAvailable(username)
                
                await MainActor.run {
                    isUsernameAvailable = available
                    if !available {
                        usernameError = "This username is already taken"
                        isCheckingUsername = false
                    } else {
                        // Username is available! Auto-advance to next step
                        isCheckingUsername = false
                        // Small delay for smooth UX (show checkmark briefly)
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.3))
                            guard !Task.isCancelled else { return }
                            withAnimation {
                                goToNextStep()
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    usernameError = "Error checking username: \(error.localizedDescription)"
                    isCheckingUsername = false
                }
            }
        }
    }
    
    var basicsStepContent: some View {
        VStack(spacing: 28) {
            // Birthday
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Birthday")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    if isBirthdayValid && calculatedAge >= 13 && calculatedAge <= 120 {
                        Text("\(calculatedAge) years old ✓")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                OnboardingTextField(
                    icon: "calendar",
                    placeholder: birthdayPlaceholder,
                    text: $birthday,
                    keyboardType: .numberPad,
                    focusedField: $focusedField,
                    fieldValue: .birthday,
                    isValid: isBirthdayValid
                )
                .onChange(of: birthday) { _, newValue in
                    birthday = formatBirthday(newValue)
                }
            }
            
            // Gender
            VStack(alignment: .leading, spacing: 10) {
                Text("Gender (optional)")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 10) {
                    ForEach(["Male", "Female", "Other"], id: \.self) { gender in
                        GenderButton(
                            title: gender,
                            isSelected: selectedGender == gender,
                            action: { selectedGender = selectedGender == gender ? nil : gender }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
    }
    
    var bodyStepContent: some View {
        let keyboardUp = keyboardObserver.keyboardHeight > 0
        
        return VStack(alignment: .leading, spacing: keyboardUp ? 16 : 24) {
            // Height with unit toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Height")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                measurementInputField(
                    icon: "ruler",
                    placeholder: heightUnit == .ftIn ? "5'10\"" : "175",
                    text: heightUnit == .ftIn ? $heightFeetInchesDigits : $heightCm,
                    keyboardType: .numberPad,
                    field: .height,
                    isValid: isHeightValid,
                    unitOptions: ["ft", "cm"],
                    selectedUnit: heightUnit.rawValue,
                    onUnitChange: { newUnit in
                        convertHeight(to: HeightUnit(rawValue: newUnit) ?? .ftIn)
                    }
                )
                .onChange(of: heightFeetInchesDigits) { oldValue, newValue in
                    guard heightUnit == .ftIn else { return }
                    
                    let oldDigits = oldValue.filter { $0.isNumber }
                    let newDigits = newValue.filter { $0.isNumber }
                    
                    // Detect backspace on the closing quote " - delete last digit instead
                    if oldValue.hasSuffix("\"") && !newValue.hasSuffix("\"") && newDigits == oldDigits && !oldDigits.isEmpty {
                        let reducedDigits = String(oldDigits.dropLast())
                        if reducedDigits.isEmpty {
                            heightFeetInchesDigits = ""
                            return
                        }
                        let feet = String(reducedDigits.prefix(1))
                        let inches = String(reducedDigits.dropFirst().prefix(2))
                        if inches.isEmpty {
                            heightFeetInchesDigits = "\(feet)'"
                        } else {
                            heightFeetInchesDigits = "\(feet)'\(inches)\""
                        }
                        return
                    }
                    
                    // Detect backspace on the ' - delete the feet digit (clear field)
                    if oldValue.hasSuffix("'") && !newValue.hasSuffix("'") && newDigits == oldDigits && oldDigits.count == 1 {
                        heightFeetInchesDigits = ""
                        return
                    }
                    
                    // If empty, clear
                    guard !newDigits.isEmpty else {
                        if heightFeetInchesDigits != "" {
                            heightFeetInchesDigits = ""
                        }
                        return
                    }
                    
                    // Limit to 3 digits max (1 feet + 2 inches)
                    let limitedDigits = String(newDigits.prefix(3))
                    
                    // Format as X'XX"
                    let feet = String(limitedDigits.prefix(1))
                    let inches = String(limitedDigits.dropFirst().prefix(2))
                    
                    let formatted: String
                    if inches.isEmpty {
                        formatted = "\(feet)'"
                    } else {
                        formatted = "\(feet)'\(inches)\""
                    }
                    
                    // Only update if different to avoid infinite loop
                    if heightFeetInchesDigits != formatted {
                        heightFeetInchesDigits = formatted
                    }
                    
                    // Auto-advance to weight when height is complete
                    // 3 digits: always complete (e.g., 5'10")
                    // 2 digits: complete if inches is 2-9 (can't be 10, 11, etc.)
                    let inchValue = Int(inches) ?? 0
                    let isComplete = limitedDigits.count == 3 || 
                        (limitedDigits.count == 2 && !inches.isEmpty && inchValue >= 2)
                    if isComplete && isHeightValid {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.1))
                            guard !Task.isCancelled else { return }
                            focusedField = .weight
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.2))
                            guard !Task.isCancelled else { return }
                            focusedField = .weight
                        }
                    }
                }
                .onChange(of: heightCm) { oldValue, newValue in
                    guard heightUnit == .cm else { return }
                    
                    // Auto-advance to weight when cm height is complete (3 digits like 175)
                    let digits = newValue.filter { $0.isNumber }
                    if digits.count == 3 && isHeightValid {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.1))
                            guard !Task.isCancelled else { return }
                            focusedField = .weight
                        }
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.2))
                            guard !Task.isCancelled else { return }
                            focusedField = .weight
                        }
                    }
                }
                .onChange(of: isHeightValid) { oldValue, newValue in
                    // Auto-advance when height becomes valid
                    if newValue && !oldValue && focusedField == .height {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.15))
                            guard !Task.isCancelled else { return }
                            focusedField = .weight
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // Weight with unit toggle
            VStack(alignment: .leading, spacing: 8) {
                Text("Weight")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                measurementInputField(
                    icon: "scalemass",
                    placeholder: weightUnit == .lbs ? "150" : "68",
                    text: $weight,
                    keyboardType: .numberPad,
                    field: .weight,
                    isValid: isWeightValid,
                    unitOptions: ["lbs", "kg"],
                    selectedUnit: weightUnit.rawValue,
                    onUnitChange: { newUnit in
                        convertWeight(to: WeightUnit(rawValue: newUnit) ?? .lbs)
                    }
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.lg)
    }
    
    // Custom measurement input field with unit toggle
    @ViewBuilder
    func measurementInputField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType,
        field: FocusedField,
        isValid: Bool,
        unitOptions: [String],
        selectedUnit: String,
        onUnitChange: @escaping (String) -> Void
    ) -> some View {
        let isFocused = focusedField == field
        
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.ds_heading3)
                .foregroundStyle(
                    LinearGradient(
                        colors: isValid ? [Color.blue, Color.cyan] : [Color.gray.opacity(0.6), Color.gray.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26)
            
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .focused($focusedField, equals: field)
            
            // Unit toggle pill
            HStack(spacing: 0) {
                ForEach(unitOptions, id: \.self) { unit in
                    Button(action: {
                        if unit != selectedUnit {
                            onUnitChange(unit)
                        }
                    }) {
                        Text(unit)
                            .font(.ds_labelMedium)
                            .foregroundColor(unit == selectedUnit ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(unit == selectedUnit ? Color.blue : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .background(Capsule().fill(Color(.systemGray5)))
            
            // Checkmark when valid
            if isValid {
                Image(systemName: "checkmark.circle.fill")
                    .font(.ds_heading3)
                    .foregroundColor(.blue)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .font(.ds_bodyRegular)
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .fill(Color.cardBackground)
                
                RoundedRectangle(cornerRadius: CornerRadius.lg)
                    .stroke(
                        isFocused || isValid
                            ? LinearGradient(colors: [Color.blue, Color.cyan.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isFocused ? 2 : 1.5
                    )
            }
        )
        .animation(.easeInOut(duration: 0.2), value: isValid)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
    
    // Convert height between ft/in and cm
    func convertHeight(to newUnit: HeightUnit) {
        let oldUnit = heightUnit
        guard newUnit != oldUnit else { return }
        
        if newUnit == .cm && oldUnit == .ftIn {
            // Convert ft/in to cm
            let digits = heightFeetInchesDigits.filter { $0.isNumber }
            guard !digits.isEmpty else {
                heightUnit = newUnit
                return
            }
            let feet = Int(String(digits.prefix(1))) ?? 0
            let inches = Int(String(digits.dropFirst().prefix(2))) ?? 0
            let totalInches = (feet * 12) + inches
            // Use rounding instead of truncation
            let cm = Int((Double(totalInches) * 2.54).rounded())
            heightCm = "\(cm)"
        } else if newUnit == .ftIn && oldUnit == .cm {
            // Convert cm to ft/in
            guard let cm = Int(heightCm), cm > 0 else {
                heightUnit = newUnit
                return
            }
            // Use rounding instead of truncation
            let totalInches = Int((Double(cm) / 2.54).rounded())
            let feet = totalInches / 12
            let inches = totalInches % 12
            // Store as digits only (e.g., "510" for 5'10") - parsedHeightFeetInches expects this format
            if inches < 10 {
                heightFeetInchesDigits = "\(feet)0\(inches)"
            } else {
                heightFeetInchesDigits = "\(feet)\(inches)"
            }
        }
        heightUnit = newUnit
    }
    
    // Convert weight between lbs and kg
    func convertWeight(to newUnit: WeightUnit) {
        let oldUnit = weightUnit
        guard newUnit != oldUnit else { return }
        
        guard let currentWeight = Double(weight), currentWeight > 0 else {
            weightUnit = newUnit
            return
        }
        
        if newUnit == .kg && oldUnit == .lbs {
            // Convert lbs to kg
            let kg = currentWeight / 2.20462
            weight = "\(Int(kg.rounded()))"
        } else if newUnit == .lbs && oldUnit == .kg {
            // Convert kg to lbs
            let lbs = currentWeight * 2.20462
            weight = "\(Int(lbs.rounded()))"
        }
        weightUnit = newUnit
    }
    
    var goalStepContent: some View {
        let goals: [(String, String, String, Color)] = [
            ("Build Muscle", "💪", "Gain size & strength", .blue),
            ("Lose Weight", "🔥", "Burn fat & get lean", .orange),
            ("Get Stronger", "🏋️", "Increase max lifts", .purple),
            ("Stay Active", "⚡", "General fitness", .green),
            ("Build Endurance", "🏃", "Improve stamina", .cyan),
            ("Improve Health", "❤️", "Overall wellness", .red)
        ]
        
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(goals, id: \.0) { goal in
                    Button(action: {
                        if selectedGoals.contains(goal.0) {
                            selectedGoals.remove(goal.0)
                        } else {
                            selectedGoals.insert(goal.0)
                        }
                    }) {
                        VStack(spacing: 8) {
                            Text(goal.1)
                                .font(.ds_heading1)
                            Text(goal.0)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text(goal.2)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(selectedGoals.contains(goal.0) 
                                    ? AnyShapeStyle(goal.3.opacity(0.2))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .stroke(selectedGoals.contains(goal.0) ? goal.3 : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 16)
        }
    }
    
    var experienceStepContent: some View {
        let levels = [
            ("Beginner", "🌱", "New to fitness or returning after a long break"),
            ("Intermediate", "💪", "1-3 years of consistent training"),
            ("Advanced", "🏆", "3+ years of dedicated training")
        ]
        
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(levels, id: \.0) { level in
                    Button(action: { selectedExperience = level.0 }) {
                        HStack {
                            Text(level.1)
                                .font(.title)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(level.0)
                                    .font(.headline)
                                Text(level.2)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedExperience == level.0 {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedExperience == level.0 
                                    ? AnyShapeStyle(Color.blue.opacity(0.1))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(selectedExperience == level.0 ? Color.blue : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 16)
        }
    }
    
    var strengthStepContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                ForEach(StrengthProfileRecommendationEngine.StrengthLevel.allCases, id: \.self) { level in
                    Button(action: { selectedStrengthLevel = level }) {
                        HStack(spacing: 12) {
                            Text(level.emoji)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.displayName)
                                    .font(.headline)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if selectedStrengthLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .fill(selectedStrengthLevel == level 
                                    ? AnyShapeStyle(Color.orange.opacity(0.15))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(selectedStrengthLevel == level ? Color.orange : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 16)
        }
    }
    
    var locationStepContent: some View {
        let locations: [(WorkoutEnvironmentService.WorkoutEnvironment, String, String, Color)] = [
            (.gym, "🏋️", "Full Gym", .blue),
            (.home, "🏠", "Home", .green),
            (.outdoor, "🌳", "Outdoor", .orange),
            (.hybrid, "🔄", "Hybrid", .purple)
        ]
        
        return ScrollView(showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(locations, id: \.0) { loc in
                    Button(action: { 
                        selectionFeedback.selectionChanged()
                        selectedWorkoutLocation = loc.0 
                    }) {
                        VStack(spacing: 8) {
                            Text(loc.1)
                                .font(.ds_heading1)
                            Text(loc.2)
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .fill(selectedWorkoutLocation == loc.0 
                                    ? AnyShapeStyle(loc.3.opacity(0.2))
                                    : AnyShapeStyle(LinearGradient(
                                        colors: colorScheme == .dark 
                                            ? [Color(white: 0.14), Color(white: 0.10)]
                                            : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.lg)
                                .stroke(selectedWorkoutLocation == loc.0 ? loc.3 : Color.clear, lineWidth: 2)
                        )
                    }
                    .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 16)
        }
    }
    
    var equipmentStepContent: some View {
        EquipmentTilesView(
            selectedEquipment: $selectedEquipment,
            selectedLocation: $selectedEquipmentLocation
        )
    }
    
    @ViewBuilder
    func limitationRowWithDropdown(for area: AffectedArea) -> some View {
        let isSelected = selectedLimitations.contains(area)
        let needsSelection = isSelected && !confirmedAccommodations.contains(area)
        
        VStack(alignment: .leading, spacing: 0) {
            // Main selection button
            Button(action: {
                if isSelected {
                    selectedLimitations.remove(area)
                    limitationAccommodations.removeValue(forKey: area)
                    confirmedAccommodations.remove(area)
                } else {
                    selectedLimitations.insert(area)
                    // Default to "Be Careful" but mark as needing explicit selection
                    limitationAccommodations[area] = .beCareful
                }
            }) {
                HStack {
                    Image(systemName: area.icon)
                        .font(.title2)
                        .foregroundColor(area.color)
                        .frame(width: 30)
                    Text(area.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    
                    // Show status indicator
                    if needsSelection {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray.opacity(0.3))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(isSelected 
                            ? AnyShapeStyle(needsSelection ? Color.orange.opacity(0.08) : Color.blue.opacity(0.1))
                            : AnyShapeStyle(LinearGradient(
                                colors: colorScheme == .dark 
                                    ? [Color(white: 0.14), Color(white: 0.10)]
                                    : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isSelected ? (needsSelection ? Color.orange : Color.blue) : Color.clear, lineWidth: 1.5)
                )
            }
            .foregroundColor(.primary)
            
            // Auto-expanded options when selected
            if isSelected {
                VStack(spacing: 6) {
                    // Helper text
                    if needsSelection {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.point.down.fill")
                                .font(.ds_bodySmall)
                            Text("Select an accommodation level")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.orange)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .padding(.leading, 12)
                    }
                    
                    // Options as buttons (not dropdown)
                    ForEach(AccommodationLevel.allCases, id: \.self) { level in
                        Button(action: {
                            limitationAccommodations[area] = level
                            confirmedAccommodations.insert(area)
                        }) {
                            HStack(spacing: 10) {
                                Image(systemName: level.icon)
                                    .font(.ds_bodyMedium)
                                    .foregroundColor(level.color)
                                    .frame(width: 22)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(level.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(level.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                if limitationAccommodations[area] == level {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.ds_heading3)
                                        .foregroundColor(level.color)
                                }
                            }
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(limitationAccommodations[area] == level 
                                        ? AnyShapeStyle(level.color.opacity(0.12))
                                        : AnyShapeStyle(LinearGradient(
                                            colors: colorScheme == .dark 
                                                ? [Color(white: 0.14), Color(white: 0.10)]
                                                : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ))
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(limitationAccommodations[area] == level ? level.color.opacity(0.5) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
    }
    
    var scheduleStepContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                Text("How many days per week can you workout?")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 12) {
                    ForEach(2...6, id: \.self) { day in
                        Button(action: { selectedDays = day }) {
                            Text("\(day)")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(width: 50, height: 50)
                                .background(
                                    Circle()
                                        .fill(selectedDays == day 
                                            ? AnyShapeStyle(Color.blue)
                                            : AnyShapeStyle(LinearGradient(
                                                colors: colorScheme == .dark 
                                                    ? [Color(white: 0.14), Color(white: 0.10)]
                                                    : [Color.white, Color(red: 0.97, green: 0.98, blue: 1.0)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                        )
                                )
                                .foregroundColor(selectedDays == day ? .white : .primary)
                        }
                        .accessibilityLabel("\(day) days per week, \(selectedDays == day ? "selected" : "not selected")")
                    }
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 32)
        }
    }
}
