import SwiftUI
import CoreData
import PhotosUI

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var userManager: UserManager
    @EnvironmentObject var supabaseManager: SupabaseManager
    @EnvironmentObject var workoutManager: WorkoutManager
    
    // Connected apps (for reactive UI updates)
    @StateObject private var stravaService = StravaService.shared
    @StateObject private var fitbitService = FitbitService.shared
    @StateObject private var inBodyService = InBodyService.shared
    @StateObject private var healthKitService = HealthKitService.shared
    
    // Editing states
    @State private var isEditingPersonal = false
    @State private var isEditingBody = false
    @State private var isEditingFitness = false
    @State private var isEditingEquipment = false
    
    // User data states
    @State private var name: String = ""
    @State private var username: String = ""
    @State private var email: String = ""
    @State private var age: String = ""
    @State private var gender: String = "Prefer not to say"
    
    // Username sheet
    @State private var showUsernameSheet = false
    @State private var isLoadingUsername = true
    @State private var heightFeet: String = ""
    @State private var heightInches: String = ""
    @State private var weight: String = ""
    @State private var fitnessGoal: String = "General Fitness"
    @State private var experienceLevel: String = "Beginner"
    @State private var selectedEquipment: Set<String> = []
    @State private var availableDays: Int = 3
    
    @State private var showingSaveSuccess = false
    @State private var isSaving = false
    @State private var showingSignOutConfirmation = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeleting = false
    
    // 2FA / Phone Verification
    @State private var showPhoneVerificationSheet = false
    @State private var isPhoneVerified = false
    @State private var userPhoneNumber: String = ""
    private let phoneVerificationLockoutKey = "phoneVerificationLockoutTime"
    
    // Friend system
    @State private var hasLoadedFriendData = false
    @ObservedObject private var friendService = FriendService.shared
    
    // Profile stats navigation
    @State private var showWorkoutHistory = false
    @State private var showFriendsList = false
    @State private var showReceivedWorkouts = false
    
    // Profile photo
    @State private var profilePhotoURL: String? = nil
    @State private var profilePhotoImage: UIImage? = nil
    @State private var showingPhotoOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var isUploadingPhoto = false
    
    let genderOptions = ["Male", "Female", "Other", "Prefer not to say"]
    let fitnessGoalOptions = ["Build Muscle", "Get Lean", "Maintain Weight", "Improve Endurance", "General Fitness"]
    let experienceLevelOptions = ["Beginner", "Intermediate", "Advanced"]
    // Equipment names must match exactly what onboarding saves
    // Ordered from most common → least common
    let equipmentOptions = [
        // Most common (everyone has or uses)
        "Bodyweight",
        "Dumbbells",
        "Barbell",
        "Bench",
        "Cables",
        "Machines",
        // Common gym equipment
        "Smith Machine",
        "Pull-Up Bar",
        "Kettlebell",
        "Bands",
        "Plates",
        // Moderately common
        "Stability Ball",
        "Medicine Ball",
        "TRX/Rings",
        "Box",
        // Less common
        "Foam Roller",
        "Landmine",
        "Battle Ropes",
        "Step Platform",
        "Sled",
        // Improvised (least common selections)
        "Chair",
        "Wall",
        "Towel"
    ]
    
    var body: some View {
        ZStack {
            // Animated blue/cyan orb background
            AnimatedOrbBackground.stats(colorScheme: colorScheme)
                .ignoresSafeArea(.all, edges: .all)
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Profile Header
                    profileHeader
                        .padding(.bottom, 16)
                    
                    VStack(spacing: 16) {
                        // Personal Information Section
                        ProfileEditableSection(
                            title: "PERSONAL INFORMATION",
                            icon: "person.fill",
                            iconColor: .blue,
                            isEditing: $isEditingPersonal,
                            onSave: saveProfile
                        ) {
                            if isEditingPersonal {
                                // Edit Mode
                                VStack(spacing: 0) {
                                    EditableProfileRow(icon: "person.fill", label: "Name", text: $name)
                                    Divider().padding(.leading, 50)
                                    // Username row - tappable to open sheet
                                    UsernameProfileRow(
                                        username: username,
                                        isLoading: isLoadingUsername,
                                        onTap: { showUsernameSheet = true }
                                    )
                                    Divider().padding(.leading, 50)
                                    EditableProfileRow(icon: "envelope.fill", label: "Email", text: $email, keyboardType: .emailAddress)
                                    Divider().padding(.leading, 50)
                                    EditableProfileRow(icon: "calendar", label: "Age", text: $age, keyboardType: .numberPad)
                                    Divider().padding(.leading, 50)
                                    PickerProfileRow(icon: "person.2.fill", label: "Gender", selection: $gender, options: genderOptions)
                                }
                            } else {
                                // View Mode
                                VStack(spacing: 0) {
                                    ProfileInfoRow(icon: "person.fill", label: "Name", value: name.isEmpty ? "Not set" : name)
                                    Divider().padding(.leading, 50)
                                    // Username row - tappable to open sheet
                                    UsernameProfileRow(
                                        username: username,
                                        isLoading: isLoadingUsername,
                                        onTap: { showUsernameSheet = true }
                                    )
                                    Divider().padding(.leading, 50)
                                    // Phone row - shows verify option if not verified
                                    PhoneProfileRow(
                                        phoneNumber: userPhoneNumber,
                                        isVerified: isPhoneVerified,
                                        onTap: { showPhoneVerificationSheet = true }
                                    )
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "envelope.fill", label: "Email", value: email.isEmpty ? "Not set" : email)
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "calendar", label: "Age", value: age.isEmpty ? "Not set" : "\(age) years")
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "person.2.fill", label: "Gender", value: gender)
                                }
                            }
                        }
                        
                        // Body Measurements Section
                        ProfileEditableSection(
                            title: "BODY MEASUREMENTS",
                            icon: "figure.stand",
                            iconColor: .green,
                            isEditing: $isEditingBody,
                            onSave: saveProfile
                        ) {
                            if isEditingBody {
                                // Edit Mode
                                VStack(spacing: 0) {
                                    HeightEditRow(heightFeet: $heightFeet, heightInches: $heightInches)
                                    Divider().padding(.leading, 50)
                                    EditableProfileRow(icon: "scalemass.fill", label: "Weight (lbs)", text: $weight, keyboardType: .decimalPad)
                                }
                            } else {
                                // View Mode
                                VStack(spacing: 0) {
                                    ProfileInfoRow(icon: "ruler", label: "Height", value: getHeightDisplay())
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "scalemass.fill", label: "Weight", value: weight.isEmpty ? "Not set" : "\(weight) lbs")
                                }
                            }
                        }
                        
                        // Fitness Profile Section
                        ProfileEditableSection(
                            title: "FITNESS PROFILE",
                            icon: "target",
                            iconColor: .orange,
                            isEditing: $isEditingFitness,
                            onSave: saveProfile
                        ) {
                            if isEditingFitness {
                                // Edit Mode
                                VStack(spacing: 0) {
                                    PickerProfileRow(icon: "flame.fill", label: "Goal", selection: $fitnessGoal, options: fitnessGoalOptions)
                                    Divider().padding(.leading, 50)
                                    PickerProfileRow(icon: "chart.bar.fill", label: "Experience", selection: $experienceLevel, options: experienceLevelOptions)
                                    Divider().padding(.leading, 50)
                                    StepperProfileRow(icon: "calendar.badge.clock", label: "Training Days", value: $availableDays, range: 1...7)
                                }
                            } else {
                                // View Mode
                                VStack(spacing: 0) {
                                    ProfileInfoRow(icon: "flame.fill", label: "Goal", value: fitnessGoal)
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "chart.bar.fill", label: "Experience", value: experienceLevel)
                                    Divider().padding(.leading, 50)
                                    ProfileInfoRow(icon: "calendar.badge.clock", label: "Training Days", value: "\(availableDays) days/week")
                                }
                            }
                        }
                        
                        // Equipment Section
                        ProfileEditableSection(
                            title: "AVAILABLE EQUIPMENT",
                            icon: "dumbbell.fill",
                            iconColor: .blue,
                            isEditing: $isEditingEquipment,
                            onSave: saveProfile
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                if isEditingEquipment {
                                    // Edit Mode - Selectable chips
                                    FlowLayout(spacing: 8) {
                                        ForEach(equipmentOptions, id: \.self) { equipment in
                                            EquipmentSelectableTag(
                                                name: equipment,
                                                isSelected: selectedEquipment.contains(equipment),
                                                onTap: {
                                                    if selectedEquipment.contains(equipment) {
                                                        selectedEquipment.remove(equipment)
                                                    } else {
                                                        selectedEquipment.insert(equipment)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                } else {
                                    // View Mode
                                    if selectedEquipment.isEmpty {
                                        Text("No equipment selected")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 12)
                                    } else {
                                        FlowLayout(spacing: 8) {
                                            ForEach(Array(selectedEquipment).sorted(), id: \.self) { equipment in
                                                EquipmentTag(name: equipment)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                    }
                                }
                            }
                        }
                        
                        // Health & Limitations Section
                        ProfileSection(
                            title: "HEALTH & LIMITATIONS",
                            icon: "heart.text.square.fill",
                            iconColor: .red
                        ) {
                            NavigationLink(destination: LimitationsSettingsView()) {
                                HStack(spacing: 12) {
                                    Image(systemName: "bandage.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.red)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Injuries & Limitations")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        
                                        Text("Manage areas to avoid or modify")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Security / 2FA Section
                        ProfileSection(
                            title: "SECURITY",
                            icon: "lock.shield.fill",
                            iconColor: .blue
                        ) {
                            Button(action: { 
                                HapticManager.impact(.light)
                                showPhoneVerificationSheet = true 
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: isPhoneVerified ? "checkmark.shield.fill" : "shield.fill")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.blue)
                                        .frame(width: 28)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Two-Factor Authentication")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        
                                        if isPhoneVerified, !userPhoneNumber.isEmpty {
                                            Text("Enabled • \(formatPhoneForDisplay(userPhoneNumber))")
                                                .font(.caption)
                                                .foregroundColor(.blue)
                                        } else if isPhoneVerificationLockedOut {
                                            Text("Try again in \(lockoutTimeRemaining)")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        } else {
                                            Text("Secure your account with SMS verification")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if isPhoneVerified {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.blue)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isPhoneVerified)
                        }
                        
                        // Share & Invite Section
                        ProfileSection(
                            title: "SHARE & INVITE",
                            icon: "square.and.arrow.up.fill",
                            iconColor: .blue
                        ) {
                            VStack(spacing: 0) {
                                // Share App via Messages
                                Button(action: { 
                                    HapticManager.impact(.light)
                                    WorkoutSharingService.shared.shareAppViaMessages()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "message.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.green)
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Invite via iMessage")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text("Send a text to friends")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider().padding(.leading, 50)
                                
                                // Share App via WhatsApp
                                Button(action: { 
                                    HapticManager.impact(.light)
                                    WorkoutSharingService.shared.shareAppViaWhatsApp()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "paperplane.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.green)
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Invite via WhatsApp")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text("Share with WhatsApp contacts")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider().padding(.leading, 50)
                                
                                // Share App (general)
                                Button(action: { 
                                    HapticManager.impact(.light)
                                    WorkoutSharingService.shared.shareApp()
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "square.and.arrow.up")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.blue)
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("More Share Options")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text("Share via any app")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary.opacity(0.5))
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Connected Apps Section
                        ProfileSection(
                            title: "CONNECTED APPS",
                            icon: "app.connected.to.app.below.fill",
                            iconColor: .orange
                        ) {
                            VStack(spacing: 0) {
                                // Strava
                                NavigationLink(destination: StravaSettingsView()) {
                                    HStack(spacing: 12) {
                                        // Strava orange icon
                                        Image(systemName: "figure.run")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 252/255, green: 76/255, blue: 2/255))
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Strava")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text(stravaService.isConnected ? "Connected" : "Sync cardio activities")
                                                .font(.caption)
                                                .foregroundColor(stravaService.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if stravaService.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.leading, 56)
                                
                                // Fitbit
                                NavigationLink(destination: FitbitSettingsView()) {
                                    HStack(spacing: 12) {
                                        // Fitbit teal icon
                                        Image(systemName: "heart.circle.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 0, green: 0.73, blue: 0.77))
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Fitbit")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text(fitbitService.isConnected ? "Connected" : "Sync health & activity")
                                                .font(.caption)
                                                .foregroundColor(fitbitService.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if fitbitService.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.leading, 56)
                                
                                // InBody
                                NavigationLink(destination: InBodySettingsView()) {
                                    HStack(spacing: 12) {
                                        // InBody teal/cyan icon
                                        Image(systemName: "figure.stand")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(Color(red: 0/255, green: 150/255, blue: 167/255))
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("InBody")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text(inBodyService.isConnected ? "Connected" : "Body composition tracking")
                                                .font(.caption)
                                                .foregroundColor(inBodyService.isConnected ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if inBodyService.isConnected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.leading, 56)
                                
                                // Apple Health (Nike Run Club, Apple Watch, etc.)
                                NavigationLink(destination: HealthKitSettingsView()) {
                                    HStack(spacing: 12) {
                                        // Apple Health red/pink icon
                                        Image(systemName: "heart.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.red)
                                            .frame(width: 28)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Apple Health")
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            Text(healthKitService.isAuthorized ? "Connected" : "Nike Run Club & more")
                                                .font(.caption)
                                                .foregroundColor(healthKitService.isAuthorized ? .green : .secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        if healthKitService.isAuthorized {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                        }
                                        
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        
                        // Account Actions Section
                        ProfileSection(
                            title: "ACCOUNT",
                            icon: "person.circle.fill",
                            iconColor: .gray
                        ) {
                            VStack(spacing: 0) {
                                // Sign Out Row
                                Button(action: { HapticManager.impact(.light); showingSignOutConfirmation = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.orange)
                                            .frame(width: 28)
                                        
                                        Text("Sign Out")
                                            .font(.subheadline)
                                            .foregroundColor(.orange)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider().padding(.leading, 50)
                                
                                // Delete Account Row
                                Button(action: { HapticManager.impact(.light); showingDeleteAccountConfirmation = true }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash.fill")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.red)
                                            .frame(width: 28)
                                        
                                        Text("Delete Account")
                                            .font(.subheadline)
                                            .foregroundColor(.red)
                                        
                                        Spacer()
                                        
                                        if isDeleting {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isDeleting)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 0, for: .scrollContent)
            
            // Save Success Toast
            if showingSaveSuccess {
                VStack {
                    Spacer()
                    saveSuccessToast
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { HapticManager.selectionChanged(); dismiss() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17))
                    }
                    .foregroundColor(.blue)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsView()) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            SessionLogManager.shared.logScreen(.profile)
            loadUserData()
            
            // Only load data on first appear, not when returning from navigation
            guard !hasLoadedFriendData else { return }
            hasLoadedFriendData = true
            
            // Load username from database
            Task {
                await loadUsername()
            }
            
            // Load profile photo
            Task {
                await loadProfilePhoto()
            }
            
            // Load friend data for badges (load once, store in state to avoid re-render loops)
            Task {
                let friendService = FriendService.shared
                await friendService.loadPendingRequests()
                await friendService.loadReceivedWorkouts()
            }
        }
        .sheet(isPresented: $showUsernameSheet) {
            UsernameSetupSheet(
                currentUsername: username,
                onSave: { newUsername in
                    username = newUsername
                    showUsernameSheet = false
                }
            )
        }
        .sheet(isPresented: $showPhoneVerificationSheet) {
            PhoneVerificationSheet(
                isVerified: $isPhoneVerified,
                phoneNumber: $userPhoneNumber,
                onComplete: { [self] phone in
                    userPhoneNumber = phone
                    isPhoneVerified = true
                    showPhoneVerificationSheet = false
                    
                    // Save to user profile (Core Data + Cloud)
                    if let user = userManager.currentUser {
                        user.phoneNumber = phone
                        try? viewContext.save()
                    }
                    
                    // Save phone number to cloud
                    Task {
                        do {
                            try await SupabaseManager.shared.updatePhoneNumber(phone)
                            // Also mark as verified in AppStorage for Dashboard check
                            UserDefaults.standard.set(true, forKey: "userHasVerifiedPhone")
                            print("📱 [PROFILE] Phone saved to cloud: \(phone)")
                        } catch {
                            print("❌ [PROFILE] Failed to save phone to cloud: \(error)")
                        }
                    }
                }
            )
        }
        .alert("Sign Out?", isPresented: $showingSignOutConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                signOut()
            }
        } message: {
            Text("You will be signed out and all local data will be cleared. Your data is safely stored in the cloud and will be restored when you sign back in.")
        }
        .alert("Delete Account?", isPresented: $showingDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                deleteAccount()
            }
        } message: {
            Text("This will permanently delete your account and ALL your data from our servers. This action cannot be undone.")
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile Avatar with gradient ring - TAPPABLE
            Button(action: {
                HapticManager.impact(.light)
                showingPhotoOptions = true
            }) {
                ZStack {
                    // Outer glow ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 130, height: 130)
                    
                    // Avatar circle with photo or gradient
                    if let image = profilePhotoImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(Circle())
                            .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                    } else if let urlString = profilePhotoURL, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 110, height: 110)
                                    .clipShape(Circle())
                            case .failure(_):
                                defaultAvatarContent
                            case .empty:
                                ProgressView()
                                    .frame(width: 110, height: 110)
                            @unknown default:
                                defaultAvatarContent
                            }
                        }
                        .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
                    } else {
                        defaultAvatarContent
                    }
                    
                    // Camera badge overlay
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 32, height: 32)
                                
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                            .offset(x: -5, y: -5)
                        }
                    }
                    .frame(width: 130, height: 130)
                    
                    // Loading overlay
                    if isUploadingPhoto {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 110, height: 110)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8)
            
            // Name and Email
            VStack(spacing: 6) {
                Text(name.isEmpty ? "Your Name" : name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(email.isEmpty ? "your.email@example.com" : email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Instagram-style Stats Row
            profileStatsRow
        }
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoOptions) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            if profilePhotoURL != nil || profilePhotoImage != nil {
                Button("Remove Photo", role: .destructive) {
                    Task { await removeProfilePhoto() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPhotoPicker) {
            ProfilePhotoPicker { image in
                Task {
                    await processAndUploadImage(image)
                }
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPickerView { image in
                Task {
                    await processAndUploadImage(image)
                }
            }
        }
        .background(
            Group {
                // Hidden NavigationLinks for programmatic navigation (works with NavigationView)
                NavigationLink(
                    destination: WorkoutHistoryFullView(),
                    isActive: $showWorkoutHistory
                ) { EmptyView() }
                
                // Navigate to: Requests tab (1) if pending requests, Search tab (2) if 0 friends, else Friends tab (0)
                NavigationLink(
                    destination: FriendsListView(initialTab: friendService.pendingRequests.count > 0 ? 1 : (friendService.friends.count == 0 ? 2 : 0)),
                    isActive: $showFriendsList
                ) { EmptyView() }
                
                NavigationLink(
                    destination: ReceivedWorkoutsView(),
                    isActive: $showReceivedWorkouts
                ) { EmptyView() }
            }
        )
    }
    
    // MARK: - Profile Stats Row (Instagram-style, Floating)
    
    private var profileStatsRow: some View {
        HStack(spacing: 0) {
            // Completed Workouts
            Button(action: {
                HapticManager.impact(.light)
                showWorkoutHistory = true
            }) {
                VStack(spacing: 6) {
                    Text("\(userManager.currentUser?.totalWorkouts ?? 0)")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Workouts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 44)
            
            // Friends (with red dot for pending requests, or + badge if 0 friends)
            Button(action: {
                HapticManager.impact(.light)
                showFriendsList = true
            }) {
                VStack(spacing: 6) {
                    // Show 0 with + icon inline if no friends
                    if friendService.friends.count == 0 {
                        HStack(spacing: 2) {
                            Text("0")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .offset(y: -4)  // Slightly raised
                        }
                    } else {
                        ZStack(alignment: .topTrailing) {
                            Text("\(friendService.friends.count)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.primary)
                            
                            // Red dot for pending friend requests
                            if friendService.pendingRequests.count > 0 {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 12, y: -4)
                            }
                        }
                    }
                    
                    Text("Friends")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Divider
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 1, height: 44)
            
            // Received Workouts
            Button(action: {
                HapticManager.impact(.light)
                showReceivedWorkouts = true
            }) {
                VStack(spacing: 6) {
                    ZStack(alignment: .topTrailing) {
                        Text("\(friendService.receivedWorkouts.count)")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Red dot for unread workouts
                        if friendService.unreadWorkoutCount > 0 {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .offset(x: 12, y: -4)
                        }
                    }
                    
                    Text("Received")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(colorScheme == .dark ? Color(white: 0.1) : Color.white)
                .shadow(
                    color: colorScheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.12),
                    radius: 16,
                    x: 0,
                    y: 8
                )
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }
    
    private var defaultAvatarContent: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.cyan.opacity(0.8)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 110, height: 110)
                .shadow(color: .blue.opacity(0.3), radius: 15, x: 0, y: 8)
            
            Text(getInitials())
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
    
    // MARK: - Save Success Toast
    
    private var saveSuccessToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.white)
            
            Text("Changes saved successfully!")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.green, Color.mint],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: .green.opacity(0.3), radius: 10, x: 0, y: 5)
        )
        .padding(.bottom, 100)
    }
    
    // MARK: - Helper Functions
    
    private func getHeightDisplay() -> String {
        if !heightFeet.isEmpty || !heightInches.isEmpty {
            let ft = heightFeet.isEmpty ? "0" : heightFeet
            let inches = heightInches.isEmpty ? "0" : heightInches
            return "\(ft)'\(inches)\""
        }
        return "Not set"
    }
    
    private func getInitials() -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        } else if let first = components.first {
            return String(first.prefix(2)).uppercased()
        }
        return "U"
    }
    
    private func loadUserData() {
        guard let user = userManager.currentUser else { return }
        
        name = user.name ?? ""
        email = user.email ?? ""
        age = user.age > 0 ? "\(user.age)" : ""
        gender = user.gender ?? "Prefer not to say"
        
        // Convert stored height (in cm) to feet and inches
        // Use the stored heightInches if available (preserves original input)
        let storedHeightInches = Int(user.heightInches)
        if storedHeightInches > 0 {
            // Use the original inches value (more accurate)
            heightFeet = String(storedHeightInches / 12)
            heightInches = String(storedHeightInches % 12)
        } else {
            // Fallback: convert from cm with proper rounding
            let heightInCm = Double(user.height)
            if heightInCm > 0 {
                let totalInches = round(heightInCm / 2.54)  // Round to nearest inch
                heightFeet = String(Int(totalInches) / 12)
                heightInches = String(Int(totalInches) % 12)
            } else {
                heightFeet = ""
                heightInches = ""
            }
        }
        
        // Convert stored weight (in kg) to lbs
        // Use stored weightLbs if available (preserves original input)
        let storedWeightLbs = user.weightLbs
        if storedWeightLbs > 0 {
            // Use the original lbs value (more accurate)
            weight = String(Int(round(storedWeightLbs)))
        } else {
            // Fallback: convert from kg with proper rounding
            let weightInKg = Double(user.weight)
            if weightInKg > 0 {
                let weightInLbs = round(weightInKg * 2.20462)  // Round to nearest lb
                weight = String(Int(weightInLbs))
            } else {
                weight = ""
            }
        }
        
        fitnessGoal = user.fitnessGoal ?? "General Fitness"
        experienceLevel = user.experienceLevel ?? "Beginner"
        availableDays = Int(user.availableDays)
        selectedEquipment = Set((user.equipment as? [String]) ?? [])
        
        // Load phone verification status from Core Data
        userPhoneNumber = user.phoneNumber ?? ""
        isPhoneVerified = !userPhoneNumber.isEmpty
        
        // Also check Supabase if Core Data doesn't have it
        if userPhoneNumber.isEmpty {
            Task {
                if let cloudPhone = await SupabaseManager.shared.getUserPhoneNumber(), !cloudPhone.isEmpty {
                    await MainActor.run {
                        userPhoneNumber = cloudPhone
                        isPhoneVerified = true
                        // Update Core Data
                        user.phoneNumber = cloudPhone
                        try? viewContext.save()
                    }
                }
            }
        }
    }
    
    private func loadUsername() async {
        await MainActor.run { isLoadingUsername = true }
        
        do {
            if let savedUsername = try await supabaseManager.getCurrentUsername() {
                await MainActor.run {
                    username = savedUsername
                    isLoadingUsername = false
                }
            } else {
                await MainActor.run {
                    username = ""
                    isLoadingUsername = false
                }
            }
        } catch {
            print("Failed to load username: \(error)")
            await MainActor.run {
                isLoadingUsername = false
            }
        }
    }
    
    // MARK: - Phone Verification Helpers
    
    private var isPhoneVerificationLockedOut: Bool {
        if let lockoutTime = UserDefaults.standard.object(forKey: phoneVerificationLockoutKey) as? Date {
            return Date() < lockoutTime
        }
        return false
    }
    
    private var lockoutTimeRemaining: String {
        if let lockoutTime = UserDefaults.standard.object(forKey: phoneVerificationLockoutKey) as? Date {
            let remaining = lockoutTime.timeIntervalSince(Date())
            if remaining > 0 {
                let hours = Int(remaining) / 3600
                let minutes = (Int(remaining) % 3600) / 60
                if hours > 0 {
                    return "\(hours)h \(minutes)m"
                } else {
                    return "\(minutes) minutes"
                }
            }
        }
        return ""
    }
    
    private func formatPhoneForDisplay(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 10 else { return phone }
        let last2 = String(digits.suffix(2))
        return "•••-•••-••\(last2)"
    }
    
    // MARK: - Profile Photo Functions
    
    private func loadProfilePhoto() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        // Show cached image immediately for fast UX (but verify with database)
        if let cachedImage = ProfilePhotoCache.shared.cachedImage {
            await MainActor.run {
                self.profilePhotoImage = cachedImage
            }
        }
        
        // ALWAYS fetch fresh from database to ensure correct photo for current user
        do {
            let result: [ProfilePhotoResult] = try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .select("profile_photo_url")
                .eq("id", value: userId.uuidString)
                .execute()
                .value
            
            if let photoUrl = result.first?.profile_photo_url {
                await MainActor.run {
                    self.profilePhotoURL = photoUrl
                }
                
                // Always download fresh and update cache to ensure correct photo
                if let url = URL(string: photoUrl) {
                    await downloadAndCachePhoto(from: url)
                }
            } else {
                // User has no profile photo - clear any stale cache
                ProfilePhotoCache.shared.clearCache()
                await MainActor.run {
                    self.profilePhotoURL = nil
                    self.profilePhotoImage = nil
                }
            }
        } catch {
            print("❌ Error loading profile photo: \(error)")
        }
    }
    
    private func downloadAndCachePhoto(from url: URL) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                ProfilePhotoCache.shared.cacheImage(image)
                await MainActor.run {
                    self.profilePhotoImage = image
                }
            }
        } catch {
            print("❌ Error downloading profile photo: \(error)")
        }
    }
    
    
    private func processAndUploadImage(_ image: UIImage) async {
        await MainActor.run { isUploadingPhoto = true }
        
        // Resize to reasonable dimensions (300x300 max) for profile photos
        let maxDimension: CGFloat = 300
        let scaledImage = resizeImage(image, maxDimension: maxDimension)
        
        // Compress to JPEG with good quality but small file size
        guard let imageData = scaledImage.jpegData(compressionQuality: 0.7) else {
            await MainActor.run { isUploadingPhoto = false }
            return
        }
        
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            await MainActor.run { isUploadingPhoto = false }
            return
        }
        
        let fileName = "\(userId.uuidString).jpg"
        let filePath = "profile_photos/\(fileName)"
        
        do {
            // Upload to Supabase Storage
            try await SupabaseManager.shared.supabaseClient.storage
                .from("avatars")
                .upload(filePath, data: imageData, options: .init(upsert: true))
            
            // Get public URL
            let publicUrl = try SupabaseManager.shared.supabaseClient.storage
                .from("avatars")
                .getPublicURL(path: filePath)
            
            // Add cache-busting query param
            let urlString = publicUrl.absoluteString + "?t=\(Date().timeIntervalSince1970)"
            
            // Update user_profiles table
            try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .update(["profile_photo_url": urlString])
                .eq("id", value: userId.uuidString)
                .execute()
            
            // Cache the image for instant loading next time
            ProfilePhotoCache.shared.cacheImage(scaledImage)
            
            await MainActor.run {
                self.profilePhotoURL = urlString
                self.profilePhotoImage = scaledImage
                self.isUploadingPhoto = false
            }
            
            print("✅ Profile photo uploaded successfully")
        } catch {
            print("❌ Error uploading profile photo: \(error)")
            await MainActor.run { isUploadingPhoto = false }
        }
    }
    
    private func removeProfilePhoto() async {
        guard let userId = SupabaseManager.shared.currentUser?.id else { return }
        
        await MainActor.run { isUploadingPhoto = true }
        
        do {
            // Remove from storage
            let filePath = "profile_photos/\(userId.uuidString).jpg"
            try await SupabaseManager.shared.supabaseClient.storage
                .from("avatars")
                .remove(paths: [filePath])
            
            // Update user_profiles to remove photo URL
            struct NullPhotoUpdate: Encodable {
                let profile_photo_url: String? = nil
            }
            try await SupabaseManager.shared.supabaseClient
                .from("user_profiles")
                .update(NullPhotoUpdate())
                .eq("id", value: userId.uuidString)
                .execute()
            
            // Clear the cache
            ProfilePhotoCache.shared.clearCache()
            
            await MainActor.run {
                self.profilePhotoURL = nil
                self.profilePhotoImage = nil
                self.isUploadingPhoto = false
            }
            
            print("✅ Profile photo removed")
        } catch {
            print("❌ Error removing profile photo: \(error)")
            await MainActor.run { isUploadingPhoto = false }
        }
    }
    
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func saveProfile() {
        guard let user = userManager.currentUser else { return }
        
        isSaving = true
        
        // Convert feet/inches to cm for storage
        let feet = Int(heightFeet) ?? 0
        let inches = Int(heightInches) ?? 0
        let totalInches = (feet * 12) + inches
        let heightInCm = Int(Double(totalInches) * 2.54)
        
        // Convert lbs to kg for storage
        let weightInLbs = Double(weight) ?? 0
        let weightInKg = Int(weightInLbs / 2.20462)
        
        // Update Core Data
        user.name = name
        user.email = email
        user.age = Int16(age) ?? 0
        user.gender = gender
        user.height = Int16(heightInCm)
        user.weight = Int16(weightInKg)
        user.fitnessGoal = fitnessGoal
        user.experienceLevel = experienceLevel
        user.availableDays = Int16(availableDays)
        user.equipment = Array(selectedEquipment) as NSObject
        
        do {
            // Save to Core Data
            try viewContext.save()
            
            // Force UI update
            DispatchQueue.main.async {
                self.userManager.objectWillChange.send()
            }
            
            // Show success toast
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showingSaveSuccess = true
            }
            
            // Hide toast after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showingSaveSuccess = false
                }
            }
            
            // Sync to cloud (async, non-blocking)
            Task {
                try? await supabaseManager.updateUserProfile(
                    name: name,
                    heightCm: Double(heightInCm),
                    weightKg: Double(weightInKg),
                    fitnessGoal: fitnessGoal,
                    experienceLevel: experienceLevel,
                    equipment: Array(selectedEquipment),
                    availableDays: availableDays,
                    workoutEnvironment: user.workoutEnvironment,
                    age: Int(user.age),
                    gender: user.gender
                )
            }
            
            // 👤 Update gender preference if changed
            let genderPref: GenderFilterService.Gender = gender.lowercased().contains("female") ? .female : .male
            if GenderFilterService.shared.getPreferredGender() != genderPref {
                GenderFilterService.shared.setPreferredGender(genderPref)
            }
            
            // Notify other parts of the app that profile was updated
            // This ensures recommendation engine uses fresh data
            NotificationCenter.default.post(
                name: NSNotification.Name("UserProfileUpdated"), 
                object: nil,
                userInfo: ["equipment": Array(selectedEquipment)]
            )
            
            // Clear any cached exercise data to ensure fresh recommendations
            // The recommendation engine reads from UserManager.shared.currentUser
            // which is now updated with the new equipment
            
            print("✅ Profile saved successfully!")
            print("   📦 Equipment: \(Array(selectedEquipment).sorted().joined(separator: ", "))")
            print("   🎯 Goal: \(fitnessGoal)")
            print("   📊 Experience: \(experienceLevel)")
            print("   📅 Days/week: \(availableDays)")
            print("   ☁️ Cloud sync initiated")
            print("   🔄 Recommendation engine will use updated equipment on next workout")
        } catch {
            print("❌ Error saving profile: \(error)")
        }
        
        isSaving = false
    }
    
    private func deleteAccount() {
        isDeleting = true
        Task {
            do {
                // Check if user is authenticated with Supabase
                if supabaseManager.isAuthenticated {
                    // Delete from Supabase if authenticated
                    try await supabaseManager.deleteAccount()
                    print("🗑️ Cloud account deleted successfully")
                } else {
                    // Local-only user (test/debug mode) - just clear local data
                    print("🗑️ Local-only account - clearing local data")
                    PersistenceController.shared.clearAllUserData()
                }
                
                await MainActor.run {
                    isDeleting = false
                    // Reset user state to show login screen
                    userManager.resetForSignOut()
                    workoutManager.resetForSignOut()
                }
                
                print("🗑️ Account deleted successfully - returning to login")
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
                print("Error deleting account: \(error)")
            }
        }
    }
    
    private func signOut() {
        Task {
            do {
                try await supabaseManager.signOut()
                
                await MainActor.run {
                    userManager.resetForSignOut()
                    workoutManager.resetForSignOut()
                }
                
                print("🔐 Sign out complete")
            } catch {
                print("Error signing out: \(error)")
            }
        }
    }
}

// MARK: - Profile Section Component (Non-Editable)

struct ProfileSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content
    
    // Gradient card background matching app style
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            .padding(.leading, 4)
            
            // Content Box
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color(.systemGray5), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Profile Editable Section Component

struct ProfileEditableSection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let icon: String
    let iconColor: Color
    @Binding var isEditing: Bool
    let onSave: () -> Void
    @ViewBuilder let content: Content
    
    // Gradient card background matching app style
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section Header with Edit Button
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Button(action: {
                    HapticManager.selectionChanged()
                    if isEditing {
                        onSave()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isEditing.toggle()
                    }
                }) {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isEditing ? .green : .blue)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
            
            // Content Box
            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardBackground)
                    .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isEditing ? iconColor.opacity(0.3) : Color(.systemGray5), lineWidth: isEditing ? 1.5 : 0.5)
            )
        }
    }
}

// MARK: - Profile Info Row (View Mode)

struct ProfileInfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Username Profile Row

struct UsernameProfileRow: View {
    let username: String
    let isLoading: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "at")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28)
                
                Text("Username")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if username.isEmpty {
                    HStack(spacing: 4) {
                        Text("Create Username")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue.opacity(0.7))
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("@\(username)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Phone Profile Row

struct PhoneProfileRow: View {
    let phoneNumber: String
    let isVerified: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28)
                
                Text("Phone")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if isVerified && !phoneNumber.isEmpty {
                    HStack(spacing: 4) {
                        Text(formatDisplayPhone(phoneNumber))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text("Verify Phone")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.blue.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
    
    private func formatDisplayPhone(_ phone: String) -> String {
        // Format like +1 (•••) ••• - ••90 for privacy (only last 2 digits)
        let digits = phone.filter { $0.isNumber }
        if digits.count >= 10 {
            let lastTwo = String(digits.suffix(2))
            let areaCode = digits.count > 10 ? String(digits.prefix(digits.count - 10)) : ""
            if !areaCode.isEmpty {
                return "+\(areaCode) (•••) ••• - ••\(lastTwo)"
            }
            return "(•••) ••• - ••\(lastTwo)"
        }
        return phone
    }
}

// MARK: - Username Setup Sheet

struct UsernameSetupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var supabaseManager: SupabaseManager
    
    let currentUsername: String
    let onSave: (String) -> Void
    
    @State private var username: String = ""
    @State private var isCheckingAvailability = false
    @State private var isAvailable: Bool? = nil
    @State private var errorMessage: String = ""
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: colorScheme == .dark
                        ? [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.05, green: 0.06, blue: 0.10)]
                        : [Color(red: 0.95, green: 0.97, blue: 1.0), Color.white]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "at.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text(currentUsername.isEmpty ? "Create Username" : "Edit Username")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Your username is how friends find you")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    
                    // Username input
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 0) {
                            Text("@")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.blue)
                                .padding(.leading, 16)
                            
                            TextField("username", text: $username)
                                .font(.system(size: 18))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.vertical, 16)
                                .padding(.trailing, 16)
                                .onChange(of: username) { _, newValue in
                                    // Filter to only allow valid characters (allow uppercase and lowercase)
                                    let filtered = newValue.filter { $0.isLetter || $0.isNumber || $0 == "_" }
                                    if filtered != newValue {
                                        username = filtered
                                    }
                                    // Reset availability when typing
                                    isAvailable = nil
                                    errorMessage = ""
                                }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(
                                    isAvailable == true ? Color.green :
                                    isAvailable == false ? Color.red :
                                    Color.gray.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                        
                        // Validation messages
                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 4)
                        } else if isAvailable == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Username available!")
                                    .foregroundColor(.green)
                            }
                            .font(.caption)
                            .padding(.leading, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Check Availability Button
                    Button(action: checkAvailability) {
                        HStack {
                            if isCheckingAvailability {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Check Availability")
                            }
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(username.count >= 3 ? Color.blue : Color.gray)
                        )
                    }
                    .disabled(username.count < 3 || isCheckingAvailability)
                    .padding(.horizontal, 24)
                    
                    // Save Button (only shows when available)
                    if isAvailable == true {
                        Button(action: saveUsername) {
                            HStack {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Save Username")
                                }
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.green, .mint],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                            )
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, 24)
                    }
                    
                    Spacer()
                    
                    // Helper text
                    VStack(spacing: 4) {
                        Text("Usernames must be 3-30 characters")
                        Text("Only letters, numbers, and underscores allowed")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if !currentUsername.isEmpty {
                username = currentUsername
            }
        }
    }
    
    private func checkAvailability() {
        guard username.count >= 3 else {
            errorMessage = "Username must be at least 3 characters"
            return
        }
        
        isCheckingAvailability = true
        errorMessage = ""
        
        Task {
            do {
                let available = try await supabaseManager.isUsernameAvailable(username)
                await MainActor.run {
                    isAvailable = available
                    isCheckingAvailability = false
                    if !available {
                        errorMessage = "Username is already taken"
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingAvailability = false
                    errorMessage = "Failed to check availability"
                }
            }
        }
    }
    
    private func saveUsername() {
        isSaving = true
        
        Task {
            do {
                try await supabaseManager.setUsername(username)
                await MainActor.run {
                    isSaving = false
                    HapticManager.notification(.success)
                    onSave(username)
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to save username"
                    HapticManager.notification(.error)
                }
            }
        }
    }
}

// MARK: - Editable Profile Row (Edit Mode)

struct EditableProfileRow: View {
    let icon: String
    let label: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            TextField(label, text: $text)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Picker Profile Row (Edit Mode)

struct PickerProfileRow: View {
    let icon: String
    let label: String
    @Binding var selection: String
    let options: [String]
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Stepper Profile Row

struct StepperProfileRow: View {
    let icon: String
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 16) {
                Button(action: {
                    HapticManager.selectionChanged()
                    if value > range.lowerBound {
                        value -= 1
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundColor(value > range.lowerBound ? .blue : .gray.opacity(0.3))
                }
                .disabled(value <= range.lowerBound)
                
                Text("\(value)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .frame(minWidth: 30)
                
                Button(action: {
                    HapticManager.selectionChanged()
                    if value < range.upperBound {
                        value += 1
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundColor(value < range.upperBound ? .blue : .gray.opacity(0.3))
                }
                .disabled(value >= range.upperBound)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Height Edit Row

struct HeightEditRow: View {
    @Binding var heightFeet: String
    @Binding var heightInches: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "ruler")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 28)
            
            Text("Height")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            HStack(spacing: 8) {
                TextField("5", text: $heightFeet)
                    .keyboardType(.numberPad)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .frame(width: 40)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("ft")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("10", text: $heightInches)
                    .keyboardType(.numberPad)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .frame(width: 40)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                
                Text("in")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Stat Summary Card

struct StatSummaryCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Equipment Tag (View Mode)

struct EquipmentTag: View {
    let name: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [Color.blue, Color.cyan.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.5
                )
        )
    }
}

// MARK: - Equipment Selectable Tag (Edit Mode)

struct EquipmentSelectableTag: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: { HapticManager.selectionChanged(); onTap() }) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(isSelected ? .white : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .stroke(
                        isSelected ?
                        LinearGradient(
                            colors: [Color.blue, Color.cyan.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ) :
                        LinearGradient(
                            colors: [Color(.systemGray4), Color(.systemGray4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Profile Photo Result DTO

struct ProfilePhotoResult: Codable {
    let profile_photo_url: String?
}

// MARK: - Photo Picker View (with cropping support)

struct ProfilePhotoPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true  // Enable cropping
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfilePhotoPicker
        
        init(_ parent: ProfilePhotoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            // Prefer edited/cropped image, fallback to original
            if let editedImage = info[.editedImage] as? UIImage {
                parent.onImagePicked(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.onImagePicked(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Camera Picker View

struct CameraPickerView: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .camera
        picker.allowsEditing = true  // Enable cropping
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView
        
        init(_ parent: CameraPickerView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.onImagePicked(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.onImagePicked(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    NavigationView {
        ProfileView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .environmentObject(UserManager())
            .environmentObject(SupabaseManager.shared)
            .environmentObject(WorkoutManager.shared)
    }
}
