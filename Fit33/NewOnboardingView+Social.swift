import SwiftUI
import Contacts

extension NewOnboardingView {
    // MARK: - Profile Photo Step (Optional)
    var profilePhotoStepContent: some View {
        VStack(spacing: 32) {
            // Large avatar circle with add button
            Button(action: {
                HapticManager.impact(.light)
                showingPhotoOptions = true
            }) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: profilePhotoImage != nil 
                                    ? [Color.green.opacity(0.6), Color.green.opacity(0.3)]
                                    : [Color.blue.opacity(0.4), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 180, height: 180)
                    
                    // Avatar circle
                    if let image = profilePhotoImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 160, height: 160)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 160, height: 160)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue.opacity(0.7))
                                    Text("Add Photo")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.blue.opacity(0.8))
                                }
                            )
                    }
                    
                    // Edit badge when photo exists
                    if profilePhotoImage != nil {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 44, height: 44)
                            .overlay(
                                Image(systemName: "pencil")
                                    .font(.ds_heading3)
                                    .foregroundColor(.white)
                            )
                            .offset(x: 60, y: 60)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            // Instructions
            VStack(spacing: 8) {
                Text(profilePhotoImage != nil ? "Looking great! 👍" : "Tap to add a profile photo")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Your photo helps friends recognize you when sharing workouts")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.lg)
            }
            
            // Skip button (only show if no photo)
            if profilePhotoImage == nil {
                Button(action: {
                    navigateTo(.contacts)
                }) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .underline()
                }
                .padding(.top, 8)
            }
            
            // Loading indicator
            if isUploadingPhoto {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.top, 32)
        .confirmationDialog("Profile Photo", isPresented: $showingPhotoOptions) {
            Button("Take Photo") {
                showingCamera = true
            }
            Button("Choose from Library") {
                showingPhotoPicker = true
            }
            if profilePhotoImage != nil {
                Button("Remove Photo", role: .destructive) {
                    profilePhotoImage = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingPhotoPicker) {
            OnboardingPhotoPicker { image in
                processOnboardingPhoto(image)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            OnboardingCameraPicker { image in
                processOnboardingPhoto(image)
            }
        }
    }

    /// Process, resize, and immediately upload the photo for onboarding.
    ///
    /// Sync-triage 2026-04-28: previously this just set
    /// `profilePhotoImage = scaledImage` and the actual cloud upload was
    /// deferred until `completeOnboarding()` (when the user taps "Create
    /// Account" on the Review & Confirm step). That created a window
    /// where the user could send friend requests from the Add Friends
    /// step (step 14) BEFORE the photo URL landed in
    /// `user_profiles.profile_photo_url` — receivers got the friend
    /// request card with the initials fallback (e.g. "JO" green circle)
    /// instead of the photo. Reproduced 2026-04-28: @joe sent @jreedy a
    /// request mid-onboarding; @jreedy received the card with initials
    /// even though @joe had picked a photo at step 12.
    ///
    /// Fix: kick off the cloud upload immediately when the photo is
    /// picked. The upload still runs as a fire-and-forget Task so the
    /// UI stays responsive — but by the time the user finishes the next
    /// step or two and reaches Add Friends, the URL is in the row and
    /// any friend request fires with a populated photo.
    ///
    /// Also folds in the resize that the camera path always applied —
    /// the previous library-picked photo path bypassed
    /// `resizeImageForOnboarding` because it wrote directly to the
    /// `@State profilePhotoImage` binding from `OnboardingPhotoPicker`,
    /// which uploaded a full-resolution image to Storage. Unifying both
    /// paths through this function caps the upload at ~300px on every
    /// device (per the original camera-path intent).
    func processOnboardingPhoto(_ image: UIImage) {
        // Resize to reasonable dimensions (300x300 max) for profile photos
        let maxDimension: CGFloat = 300
        let scaledImage = resizeImageForOnboarding(image, maxDimension: maxDimension)
        profilePhotoImage = scaledImage

        // Upload immediately so the photo URL is populated in
        // user_profiles before the user can send any friend requests
        // from the Add Friends step. `uploadOnboardingProfilePhoto`
        // is fire-and-forget and short-circuits cleanly if the user
        // isn't authenticated yet (defensive — shouldn't happen here
        // because the photo step comes after both signup and phone
        // verification, both of which establish the auth session).
        Task {
            await uploadOnboardingProfilePhoto(scaledImage)
        }
    }
    
    /// Resize image maintaining aspect ratio
    func resizeImageForOnboarding(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let aspectRatio = size.width / size.height
        
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }
    
    // MARK: - Contacts Permission Step (Optional)
    var contactsStepContent: some View {
        VStack(spacing: 16) {
            // Icon
            if contactsPermissionGranted {
                // Success state
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "checkmark.circle.fill")
                        .font(.ds_heading1)
                        .foregroundColor(.green)
                }
            } else {
                // Contacts icon
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "person.2.fill")
                        .font(.ds_heading1)
                        .foregroundStyle(
                            LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                }
            }
            
            // Title and description
            VStack(spacing: 6) {
                Text(contactsPermissionGranted ? "You're Connected! 🎉" : "Train with Friends")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text(contactsPermissionGranted 
                    ? "We'll notify you when your contacts join Fit33"
                    : "Allow contacts access to find friends who are already on Fit33")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.md)
            }
            
            // Benefits list - compact
            if !contactsPermissionGranted {
                VStack(alignment: .leading, spacing: 10) {
                    compactBenefitRow(
                        icon: "trophy.fill",
                        color: .orange,
                        title: "Challenge Friends",
                        subtitle: "Compete with step challenges, workout streaks & more"
                    )
                    
                    compactBenefitRow(
                        icon: "paperplane.fill",
                        color: .blue,
                        title: "Share Workouts",
                        subtitle: "Send workouts you create to friends who need motivation"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            
            // Permission button
            if !contactsPermissionGranted {
                VStack(spacing: 6) {
                    Button(action: {
                        HapticManager.impact(.medium)
                        AppLogger.debug("Allow Contacts tapped - auth: \(contactsService.authorizationStatus.rawValue), phone: \(phoneNumber.isEmpty ? "(none)" : fullPhoneNumber), verified: \(isPhoneVerified)", category: .social)
                        
                        // Check if already denied - need to go to settings
                        if contactsService.permissionDenied {
                            AppLogger.warning("Contacts permission previously denied, opening Settings...", category: .social)
                            if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsUrl)
                            }
                            return
                        }
                        
                        Task {
                            contactsPermissionRequested = true
                            AppLogger.debug("Requesting contact access from iOS...", category: .social)
                            
                            let granted = await contactsService.requestAccess()
                            // Note: requestAccess() already calls fetchContactsAndFindFriends() if granted
                            
                            AppLogger.info("Contacts permission result: \(granted ? "GRANTED" : "DENIED")", category: .social)
                            
                            if granted {
                                AppLogger.debug("Contact scan: phones=\(contactsService.contactPhoneNumbers.count), emails=\(contactsService.contactEmails.count), matched=\(contactsService.suggestedFriends.count)", category: .social)
                                
                                if !contactsService.suggestedFriends.isEmpty {
                                    AppLogger.info("Friends found on Fit33: \(contactsService.suggestedFriends.count)", category: .social)
                                    for (i, friend) in contactsService.suggestedFriends.prefix(5).enumerated() {
                                        AppLogger.debug("\(i + 1). \(friend.name ?? "Unknown") (@\(friend.username ?? "no-username"))", category: .social)
                                    }
                                    if contactsService.suggestedFriends.count > 5 {
                                        AppLogger.debug("... and \(contactsService.suggestedFriends.count - 5) more", category: .social)
                                    }
                                } else {
                                    AppLogger.debug("No contacts found on Fit33 — fetching PYMK as fallback", category: .social)
                                    Task { await contactsService.fetchPeopleYouMayKnow() }
                                }
                            }
                            
                            await MainActor.run {
                                contactsPermissionGranted = granted
                                if granted {
                                    AppLogger.debug("Auto-navigating to Add Friends step...", category: .social)
                                    HapticManager.notification(.success)
                                    
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .seconds(0.4))
                                        guard !Task.isCancelled else { return }
                                        navigateTo(.addFriends)
                                    }
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: contactsService.permissionDenied ? "gear" : "person.crop.circle.badge.plus")
                                .font(.ds_labelLarge)
                            Text(contactsService.permissionDenied ? "Open Settings" : "Allow Contacts Access")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.8), .purple.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(CornerRadius.md)
                    }
                    .padding(.horizontal, 20)
                    
                    // Privacy note
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green.opacity(0.8))
                        Text("Your contacts are never shared or stored on our servers")
                            .font(.ds_caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, 8)
        .onAppear {
            // Refresh and check current status on appear
            contactsService.checkAuthorizationStatus()
            contactsPermissionGranted = contactsService.canAccessContacts
            AppLogger.debug("Contacts step appeared - status: \(contactsService.authorizationStatus.rawValue), canAccess: \(contactsService.canAccessContacts)", category: .social)
        }
    }
    
    func compactBenefitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.ds_labelMedium)
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
    }
    
    
    
    
    // MARK: - Add Friends Step (after contacts permission)
    var addFriendsStepContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.ds_bodyRegular)
                
                TextField("Search by name", text: $friendSearchText)
                    .font(.body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                
                if !friendSearchText.isEmpty {
                    Button(action: { friendSearchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(Color(.systemGray6))
            .cornerRadius(CornerRadius.md)
            .padding(.horizontal, Spacing.lg)
            .padding(.top, 16)
            .padding(.bottom, 16)
            
            // Friends list
            if contactsService.isLoading || isLoadingFriends {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Finding your friends...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 60)
            } else if !filteredSuggestedFriends.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredSuggestedFriends) { friend in
                            onboardingFriendRow(friend: friend)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, 100)
                }
            } else if !filteredPYMK.isEmpty && contactsPermissionGranted {
                ScrollView {
                    VStack(spacing: 0) {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 38))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan, .purple.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Already part of the club!")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("People you might know on Fit33")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        
                        LazyVStack(spacing: 12) {
                            ForEach(filteredPYMK) { friend in
                                onboardingFriendRow(friend: friend)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, 100)
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: contactsPermissionGranted ? "person.2.slash" : "person.crop.circle.badge.questionmark")
                        .font(.system(size: 50))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text(contactsPermissionGranted
                        ? (friendSearchText.isEmpty ? "No contacts on Fit33 yet" : "No results for \"\(friendSearchText)\"")
                        : "Enable contacts to find friends")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text(contactsPermissionGranted
                        ? "When your contacts join, you'll be notified!"
                        : "Go back and allow contacts access")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
                .padding(.horizontal, Spacing.xl)
            }
            
            Spacer()
        }
        .onAppear {
            AppLogger.debug("Add Friends step appeared - granted: \(contactsPermissionGranted), canAccess: \(contactsService.canAccessContacts), loading: \(contactsService.isLoading), checked: \(contactsService.hasCheckedContacts), friends: \(contactsService.suggestedFriends.count), pymk: \(contactsService.peopleYouMayKnow.count), emails: \(contactsService.contactEmails.count), phones: \(contactsService.contactPhoneNumbers.count)", category: .social)
            
            if contactsService.canAccessContacts {
                if !contactsService.hasCheckedContacts || contactsService.suggestedFriends.isEmpty {
                    AppLogger.debug("Fetching/refreshing contacts and friends...", category: .social)
                    Task {
                        isLoadingFriends = true
                        await contactsService.fetchContactsAndFindFriends()
                        if contactsService.suggestedFriends.isEmpty && contactsService.peopleYouMayKnow.isEmpty {
                            await contactsService.fetchPeopleYouMayKnow()
                        }
                        isLoadingFriends = false
                        AppLogger.info("Add Friends fetch complete - contacts: \(contactsService.suggestedFriends.count), pymk: \(contactsService.peopleYouMayKnow.count)", category: .social)
                    }
                } else {
                    AppLogger.debug("Already have \(contactsService.suggestedFriends.count) suggested friends - no refresh needed", category: .social)
                }
            }
        }
    }
    
    // Filtered list based on search
    var filteredSuggestedFriends: [SuggestedFriend] {
        let friends = contactsService.suggestedFriends.filter { !$0.isFriend }
        
        if friendSearchText.isEmpty {
            return friends
        }
        
        let searchLower = friendSearchText.lowercased()
        return friends.filter { friend in
            if let name = friend.name, name.lowercased().contains(searchLower) {
                return true
            }
            if let username = friend.username, username.lowercased().contains(searchLower) {
                return true
            }
            return false
        }
    }
    
    /// Friends-of-friends fallback when no contact matches exist
    var filteredPYMK: [SuggestedFriend] {
        let pymk = contactsService.peopleYouMayKnow.filter { suggestion in
            !suggestion.isFriend
            && !suggestion.hasOutgoingRequest
            && !suggestion.hasIncomingRequest
            && !sentFriendRequests.contains(suggestion.userId)
        }
        
        if friendSearchText.isEmpty {
            return pymk
        }
        
        let searchLower = friendSearchText.lowercased()
        return pymk.filter { friend in
            if let name = friend.name, name.lowercased().contains(searchLower) { return true }
            if let username = friend.username, username.lowercased().contains(searchLower) { return true }
            return false
        }
    }
    
    func onboardingFriendRow(friend: SuggestedFriend) -> some View {
        let isRequestSent = sentFriendRequests.contains(friend.userId) || friend.hasOutgoingRequest
        let isLoading = loadingFriendRequests.contains(friend.userId)
        let hasFailed = failedFriendRequests.contains(friend.userId)
        
        return HStack(spacing: 14) {
            // Avatar (cached)
            CachedFriendPhoto(
                friendId: friend.userId.uuidString,
                photoUrl: friend.profilePhotoUrl,
                name: friend.name ?? friend.username ?? "?",
                size: 50,
                showGradientRing: false,
                gradientColors: [.blue, .purple]
            )
            
            // Name & username
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name ?? "Unknown")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                if let username = friend.username, !username.isEmpty {
                    Text("@\(username)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Add button with loading and error states
            Button(action: {
                guard !isRequestSent && !isLoading else { return }
                
                // Clear any previous failure
                failedFriendRequests.remove(friend.userId)
                
                // Set loading state
                loadingFriendRequests.insert(friend.userId)
                HapticManager.impact(.medium)
                
                AppLogger.debug("Tapped Add for \(friend.name ?? "Unknown") (ID: \(friend.userId))", category: .social)
                
                Task {
                    let success = await FriendService.shared.sendFriendRequest(toUserId: friend.userId)
                    
                    await MainActor.run {
                        loadingFriendRequests.remove(friend.userId)
                        
                        if success {
                            AppLogger.info("Friend request sent successfully to \(friend.name ?? "Unknown")", category: .social)
                            sentFriendRequests.insert(friend.userId)
                            HapticManager.notification(.success)
                        } else {
                            AppLogger.error("Failed to send friend request to \(friend.name ?? "Unknown")", category: .social)
                            failedFriendRequests.insert(friend.userId)
                            HapticManager.notification(.error)
                        }
                    }
                }
            }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: isRequestSent ? "checkmark" : (hasFailed ? "exclamationmark.triangle" : "plus"))
                            .font(.ds_bodySmall).fontWeight(.bold)
                    }
                    Text(isRequestSent ? "Sent" : (hasFailed ? "Retry" : (isLoading ? "" : "Add")))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                .foregroundColor(isRequestSent ? .green : (hasFailed ? .orange : .white))
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Group {
                        if isRequestSent {
                            Color.green.opacity(0.15)
                        } else if hasFailed {
                            Color.orange.opacity(0.15)
                        } else {
                            LinearGradient(colors: [.blue, .blue.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                        }
                    }
                )
                .cornerRadius(20)
            }
            .disabled(isRequestSent || isLoading)
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(14)
    }
    
    func friendInitialsCircle(friend: SuggestedFriend) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.6), .purple.opacity(0.4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 50, height: 50)
            .overlay(
                Text(friend.initials)
                    .font(.ds_heading3)
                    .foregroundColor(.white)
            )
    }
}
