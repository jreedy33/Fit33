import SwiftUI

struct BugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bugService = BugReportService.shared
    @ObservedObject var shakeManager = ShakeDetectionManager.shared
    
    @State private var bugDescription = ""
    @State private var expectedBehavior = ""
    @State private var reproducesEveryTime = false
    @State private var additionalNotes = ""
    @State private var showingSubmitConfirmation = false
    @State private var showingSubmitError = false
    @State private var submitSuccess = false
    @State private var includeSessionLog = true
    @State private var showingLogPreview = false
    // Rage-shake v2 fields
    @State private var severity: BugSeverity = .medium
    @State private var detectedScreen: String = ""
    @State private var detectedFiles: [String] = []

    private var inputBackground: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color.gray.opacity(0.05)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with Profile/Stats screens)
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header with icon
                        headerSection

                        // Context Claude will receive: current screen + files
                        contextSection

                        // Severity picker (user tells Claude how bad it is)
                        severitySection

                        // Screenshot preview
                        screenshotSection
                        
                        // Privacy warning
                        privacyWarning
                        
                        // Bug description
                        descriptionSection
                        
                        // Expected behavior
                        expectedBehaviorSection
                        
                        // Reproduces checkbox
                        reproducesSection
                        
                        // Additional notes
                        additionalNotesSection
                        
                        // Session log toggle
                        sessionLogSection
                        
                        // Submit button
                        submitButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
                // Sprint 5 M-9: bug reports have multi-line text views; allow
                // interactive swipe-to-dismiss so the user can review their
                // screenshot while writing.
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        shakeManager.clearScreenshot()
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .sheet(isPresented: $showingLogPreview) {
                SessionLogPreviewView()
            }
            .alert("Bug Report Submitted", isPresented: $showingSubmitConfirmation) {
                Button("OK") {
                    shakeManager.clearScreenshot()
                    dismiss()
                }
            } message: {
                Text("Thank you for helping us improve the app! We'll review your report and work on fixing the issue.")
            }
            .alert("Submission Failed", isPresented: $showingSubmitError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not submit bug report. Please check your internet connection and try again.")
            }
            .onAppear {
                // Snapshot screen + files at the moment the user shook — if
                // we wait until submit, they may have navigated.
                let info = SessionLogManager.shared.getCurrentScreenInfo()
                detectedScreen = info.name
                detectedFiles = ScreenCodeMap.filesForScreen(info.name)
            }
        }
    }

    // MARK: - Context Section (screen + likely files)
    //
    // Shows the user which screen was detected and which source files Claude
    // will focus on. `ScreenCodeMap` returns up to 4 file candidates; we
    // display relative paths (e.g. `Fit33/DashboardView.swift`) so the
    // chosen scope is transparent to the user.
    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "location.viewfinder")
                    .foregroundColor(.cyan)
                Text("Captured Context")
                    .font(.headline)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.on.rectangle")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(detectedScreen.isEmpty ? "Unknown" : detectedScreen)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Spacer()
            }

            if !detectedFiles.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "swift")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Files Claude will review")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        ForEach(detectedFiles, id: \.self) { f in
                            Text(f)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Severity
    //
    // User picks how bad this is; Claude uses `severity` to set the
    // resulting `bug_intelligence_reports.severity` (and our daily rollup
    // regression detector uses it). Default is `.medium`.
    private var severitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("How bad is it?")
                    .font(.headline)
                Spacer()
            }

            Picker("Severity", selection: $severity) {
                ForEach(BugSeverity.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)

            Text(severity.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.red.opacity(0.8), Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 70, height: 70)
                
                Image(systemName: "ant.fill")
                    .font(.ds_heading1)
                    .foregroundColor(.white)
            }
            
            Text("Report a Bug")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Help us squash this bug!")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
    
    // MARK: - Screenshot Preview
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.blue)
                Text("Screenshot Captured")
                    .font(.headline)
                Spacer()
            }
            
            if let screenshot = shakeManager.capturedScreenshot {
                Image(uiImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .cornerRadius(CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.md)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                RoundedRectangle(cornerRadius: CornerRadius.md)
                    .fill(inputBackground)
                    .frame(height: 150)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundColor(.gray)
                            Text("No screenshot captured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    )
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Privacy Warning
    private var privacyWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy Notice")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Screenshots may be reviewed by our team to diagnose and fix bugs. They help us understand exactly what happened.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.1))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.purple)
                Text("What happened?")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
            }
            
            TextEditor(text: $bugDescription)
                .frame(minHeight: 100)
                .padding(Spacing.xs)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if bugDescription.isEmpty {
                            Text("Describe the bug in detail. What were you doing when it happened?")
                                .font(.subheadline)
                                .foregroundColor(.gray.opacity(0.5))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.md)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Expected Behavior Section
    private var expectedBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("What should have happened?")
                    .font(.headline)
            }
            
            TextEditor(text: $expectedBehavior)
                .frame(minHeight: 80)
                .padding(Spacing.xs)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if expectedBehavior.isEmpty {
                            Text("What did you expect to happen instead?")
                                .font(.subheadline)
                                .foregroundColor(.gray.opacity(0.5))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.md)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Reproduces Section
    private var reproducesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundColor(.blue)
                Text("Reproducibility")
                    .font(.headline)
                Spacer()
            }
            
            Button(action: {
                HapticManager.selectionChanged()
                reproducesEveryTime.toggle()
            }) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(reproducesEveryTime ? Color.blue : Color.gray.opacity(0.4), lineWidth: 2)
                            .frame(width: 24, height: 24)
                        
                        if reproducesEveryTime {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.blue)
                                .frame(width: 16, height: 16)
                            
                            Image(systemName: "checkmark")
                                .font(.ds_bodySmall).fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    
                    Text("This bug happens every time I try")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Additional Notes Section
    private var additionalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.gray)
                Text("Additional Notes (Optional)")
                    .font(.headline)
            }
            
            TextEditor(text: $additionalNotes)
                .frame(minHeight: 60)
                .padding(Spacing.xs)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .overlay(
                    Group {
                        if additionalNotes.isEmpty {
                            Text("Any other details that might help us fix this...")
                                .font(.subheadline)
                                .foregroundColor(.gray.opacity(0.5))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.md)
                                .allowsHitTesting(false)
                        }
                    },
                    alignment: .topLeading
                )
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Session Log Section
    private var sessionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("Session Log")
                    .font(.headline)
                Spacer()
            }
            
            Toggle(isOn: $includeSessionLog) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include session log")
                        .font(.subheadline)
                    Text("Helps us troubleshoot faster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
            
            if includeSessionLog {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Log will be attached to report")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Preview") {
                        showingLogPreview = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(10)
                .background(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1))
                .cornerRadius(CornerRadius.sm)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Submit Button
    private var submitButton: some View {
        Button(action: submitBugReport) {
            HStack {
                if bugService.isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Image(systemName: "paperplane.fill")
                    Text("Submit Bug Report")
                }
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: canSubmit ? [Color.blue, Color.blue.opacity(0.8)] : [Color.gray, Color.gray.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(14)
        }
        .disabled(!canSubmit || bugService.isSubmitting)
    }
    
    private var canSubmit: Bool {
        !bugDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func submitBugReport() {
        // Mark that we're submitting a bug report (keeps logs from being deleted)
        if includeSessionLog {
            SessionLogManager.shared.bugReportPending = true
        }
        
        Task {
            // Get session log if enabled
            var sessionLogText: String? = nil
            if includeSessionLog {
                sessionLogText = SessionLogManager.shared.exportLogsAsText()
            }
            
            let success = await bugService.submitBugReport(
                description: bugDescription,
                expectedBehavior: expectedBehavior,
                reproducesEveryTime: reproducesEveryTime,
                screenshot: shakeManager.capturedScreenshot,
                screenName: detectedScreen.isEmpty ? nil : detectedScreen,
                additionalInfo: additionalNotes.isEmpty ? nil : additionalNotes,
                sessionLog: sessionLogText,
                severity: severity,
                bugCategory: nil,
                likelySourceFiles: detectedFiles.isEmpty ? nil : detectedFiles
            )
            
            if success {
                showingSubmitConfirmation = true
            } else {
                showingSubmitError = true
            }
        }
    }
}

// MARK: - Session Log Preview View
struct SessionLogPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var logText = ""
    @State private var showingShareSheet = false
    @State private var logFileURL: URL?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logText)
                    .font(.system(.caption, design: .monospaced))
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(.systemGray6))
            .navigationTitle("Session Log Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: shareLog) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = logFileURL {
                    ActivityView(activityItems: [url])
                }
            }
        }
        .onAppear {
            logText = SessionLogManager.shared.exportLogsAsText()
        }
    }
    
    private func shareLog() {
        logFileURL = SessionLogManager.shared.getLogFileURL()
        if logFileURL != nil {
            showingShareSheet = true
        }
    }
}

// MARK: - Activity View for Sharing
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Manual Bug Report View (for Settings menu)
/// Allows users to manually report bugs with optional screenshot attachment
struct ManualBugReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var bugService = BugReportService.shared
    
    @State private var bugDescription = ""
    @State private var expectedBehavior = ""
    @State private var reproducesEveryTime = false
    @State private var additionalNotes = ""
    @State private var showingSubmitConfirmation = false
    @State private var showingSubmitError = false
    @State private var isSubmitting = false
    @State private var includeSessionLog = true
    @State private var showingLogPreview = false
    @State private var severity: BugSeverity = .medium

    // Photo picker
    @State private var selectedImage: UIImage?
    @State private var showingPhotoPicker = false
    
    
    private var inputBackground: Color {
        colorScheme == .dark ? Color(white: 0.08) : Color.gray.opacity(0.1)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Animated orb background (consistent with Profile/Stats screens)
                AnimatedOrbBackground.stats(colorScheme: colorScheme)
                    .ignoresSafeArea(.all, edges: .all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Screenshot section with add button
                        screenshotSection
                        
                        // Privacy warning
                        privacyWarning

                        // Severity (same component shape as rage shake)
                        manualSeveritySection

                        // Bug description
                        descriptionSection
                        
                        // Expected behavior
                        expectedBehaviorSection
                        
                        // Reproduces checkbox
                        reproducesSection
                        
                        // Additional notes
                        additionalNotesSection
                        
                        // Session log toggle
                        manualSessionLogSection
                        
                        // Submit button
                        submitButton
                        
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.red)
                }
            }
            .alert("Bug Report Submitted", isPresented: $showingSubmitConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Thank you for helping us improve the app! We'll review your report and work on fixing the issue.")
            }
            .alert("Submission Failed", isPresented: $showingSubmitError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not submit bug report. Please check your internet connection and try again.")
            }
            .sheet(isPresented: $showingPhotoPicker) {
                ImagePicker(image: $selectedImage)
            }
            .sheet(isPresented: $showingLogPreview) {
                SessionLogPreviewView()
            }
        }
    }
    
    // MARK: - Header
    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [.red.opacity(0.2), .orange.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "ant.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.red)
            }
            
            Text("Report a Bug")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Help us improve your experience")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top)
    }
    
    // MARK: - Screenshot Section
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "camera.viewfinder")
                    .foregroundColor(.blue)
                Text("Screenshot")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if let screenshot = selectedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: screenshot)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .cornerRadius(CornerRadius.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                    
                    // Remove button
                    Button(action: {
                        selectedImage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                            .background(Circle().fill(.white))
                    }
                    .offset(x: 8, y: -8)
                }
            } else {
                Button(action: {
                    HapticManager.selectionChanged()
                    showingPhotoPicker = true
                }) {
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .fill(inputBackground)
                        .frame(height: 120)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                Text("Tap to add screenshot")
                                    .font(.subheadline)
                                    .foregroundColor(.blue)
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: CornerRadius.md)
                                .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        )
                }
            }
            
            Text("Adding a screenshot helps us understand and fix the issue faster")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Privacy Warning
    private var privacyWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundColor(.orange)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Privacy Notice")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text("Screenshots may be reviewed by our team to diagnose and fix bugs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(colorScheme == .dark ? 0.2 : 0.1))
        .cornerRadius(CornerRadius.md)
    }
    
    // MARK: - Description Section
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "text.alignleft")
                    .foregroundColor(.purple)
                Text("What happened?")
                    .font(.headline)
                Text("*")
                    .foregroundColor(.red)
            }
            
            TextEditor(text: $bugDescription)
                .frame(minHeight: 100)
                .padding(Spacing.sm)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            Text("Describe what you were doing when the bug occurred")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Expected Behavior Section
    private var expectedBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("What should have happened?")
                    .font(.headline)
            }
            
            TextEditor(text: $expectedBehavior)
                .frame(minHeight: 80)
                .padding(Spacing.sm)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Reproduces Section
    private var reproducesSection: some View {
        HStack {
            Image(systemName: reproducesEveryTime ? "checkmark.square.fill" : "square")
                .font(.title2)
                .foregroundColor(reproducesEveryTime ? .blue : .gray)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("This bug happens every time")
                    .font(.subheadline)
                Text("Can you reproduce this issue consistently?")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
        .onTapGesture {
            HapticManager.selectionChanged()
            reproducesEveryTime.toggle()
        }
    }
    
    // MARK: - Additional Notes Section
    private var additionalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(.orange)
                Text("Additional Notes")
                    .font(.headline)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            TextEditor(text: $additionalNotes)
                .frame(minHeight: 60)
                .padding(Spacing.sm)
                .scrollContentBackground(.hidden)
                .background(inputBackground)
                .cornerRadius(CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Severity (Manual)
    private var manualSeveritySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("How bad is it?")
                    .font(.headline)
                Spacer()
            }
            Picker("Severity", selection: $severity) {
                ForEach(BugSeverity.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.segmented)
            Text(severity.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }

    // MARK: - Session Log Section
    private var manualSessionLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("Session Log")
                    .font(.headline)
                Spacer()
            }
            
            Toggle(isOn: $includeSessionLog) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Include session log")
                        .font(.subheadline)
                    Text("Helps us troubleshoot faster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.blue)
            
            if includeSessionLog {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Log will be attached to report")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Preview") {
                        showingLogPreview = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(10)
                .background(Color.green.opacity(colorScheme == .dark ? 0.2 : 0.1))
                .cornerRadius(CornerRadius.sm)
            }
        }
        .padding()
        .background(Color.cardBackground)
        .cornerRadius(CornerRadius.lg)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Submit Button
    private var submitButton: some View {
        Button(action: submitBugReport) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                    Text("Submit Bug Report")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
                    .opacity(bugDescription.isEmpty ? 0.5 : 1.0)
            )
            .foregroundColor(.white)
            .cornerRadius(CornerRadius.lg)
            .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(bugDescription.isEmpty || isSubmitting)
    }
    
    // MARK: - Submit Action
    private func submitBugReport() {
        // Mark that we're submitting a bug report (keeps logs from being deleted)
        if includeSessionLog {
            SessionLogManager.shared.bugReportPending = true
        }
        
        isSubmitting = true
        
        Task {
            // Get session log if enabled
            var sessionLogText: String? = nil
            if includeSessionLog {
                sessionLogText = SessionLogManager.shared.exportLogsAsText()
            }
            
            let success = await bugService.submitBugReport(
                description: bugDescription,
                expectedBehavior: expectedBehavior,
                reproducesEveryTime: reproducesEveryTime,
                screenshot: selectedImage,
                additionalInfo: additionalNotes.isEmpty ? nil : additionalNotes,
                sessionLog: sessionLogText,
                severity: severity,
                bugCategory: nil,
                likelySourceFiles: nil
            )
            
            await MainActor.run {
                isSubmitting = false
                if success {
                    showingSubmitConfirmation = true
                } else {
                    showingSubmitError = true
                }
            }
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    BugReportView()
}

#Preview("Manual Bug Report") {
    ManualBugReportView()
}

