import SwiftUI
import Supabase

struct AuthView: View {
    @StateObject private var supabaseManager = SupabaseManager.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var errorMessage = ""
    @State private var showError = false
    #if DEBUG
    @State private var testUserCounter = 1
    #endif
    
    var body: some View {
        ZStack {
            // App's signature gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.88, green: 0.93, blue: 0.98),
                    Color(red: 0.78, green: 0.88, blue: 0.98)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    Spacer()
                        .frame(height: 60)
                    
                    #if DEBUG
                    // Developer Quick Test Button (Debug only)
                    HStack {
                        Spacer()
                        Button(action: quickTestUser) {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt.fill")
                                    .font(.ds_bodySmall).fontWeight(.bold)
                                Text("Test User \(testUserCounter)")
                                    .font(.ds_labelMedium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                            .padding(.vertical, Spacing.xs)
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [Color.orange, Color.red]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(20)
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, -20)
                    #endif
                    
                    // Logo/Title
                    VStack(spacing: 4) {
                        Text("Built. Simple.")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.black, .black.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Welcome to your fitness journey")
                            .font(.ds_bodyLarge)
                            .foregroundColor(.black.opacity(0.6))
                            .padding(.top, 4)
                    }
                    .padding(.bottom, 50)
                    
                    // Auth Card
                    VStack(spacing: 20) {
                        // Tabs
                        HStack(spacing: 0) {
                            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isSignUp = false } }) {
                                Text("Sign In")
                                    .font(.system(size: 17, weight: isSignUp ? .medium : .bold))
                                    .foregroundColor(isSignUp ? .black.opacity(0.5) : .white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            
                            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isSignUp = true } }) {
                                Text("Sign Up")
                                    .font(.system(size: 17, weight: isSignUp ? .bold : .medium))
                                    .foregroundColor(isSignUp ? .white : .black.opacity(0.5))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                        }
                        .background(
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.4, green: 0.6, blue: 1.0),
                                                Color(red: 0.3, green: 0.5, blue: 0.95)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geometry.size.width / 2 - 4)
                                    .offset(x: isSignUp ? geometry.size.width / 2 + 2 : 2)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSignUp)
                            }
                        )
                        .background(Color.white.opacity(0.3))
                        .clipShape(Capsule())
                        .padding(Spacing.xxxs)
                        
                        // Input Fields
                        VStack(spacing: 16) {
                            if isSignUp {
                                CustomTextField(
                                    icon: "person.fill",
                                    placeholder: "Full Name",
                                    text: $name
                                )
                            }
                            
                            CustomTextField(
                                icon: "envelope.fill",
                                placeholder: "Email",
                                text: $email,
                                keyboardType: .emailAddress,
                                autocapitalization: .never
                            )
                            
                            CustomTextField(
                                icon: "lock.fill",
                                placeholder: "Password",
                                text: $password,
                                isSecure: true
                            )
                        }
                        
                        // Error Message
                        if showError {
                            Text(errorMessage)
                                .font(.ds_bodySmall)
                                .foregroundColor(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Action Button
                        Button(action: handleAuth) {
                            HStack(spacing: 8) {
                                if supabaseManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.ds_heading3)
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.ds_heading3)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.3, green: 0.6, blue: 1.0),
                                        Color(red: 0.4, green: 0.7, blue: 1.0)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(CornerRadius.lg)
                            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
                        }
                        .disabled(supabaseManager.isLoading || !isValid)
                        .opacity((supabaseManager.isLoading || !isValid) ? 0.5 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isValid)
                        
                        // Social Login Divider
                        SocialLoginDivider()
                            .padding(.vertical, Spacing.xs)
                        
                        // Google Sign-In Button
                        Button(action: handleGoogleSignIn) {
                            HStack(spacing: 12) {
                                // Google "G" logo
                                Image(systemName: "g.circle.fill")
                                    .font(.ds_heading3)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.red, .yellow, .green, .blue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Text("Continue with Google")
                                    .font(.ds_labelLarge)
                                    .foregroundColor(.primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Apple Sign-In Button
                        SignInWithAppleButton {
                            handleAppleSignIn()
                        }
                        .padding(.top, 4)
                    }
                    .padding(28)
                    .background(
                        RoundedRectangle(cornerRadius: CornerRadius.xl)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.xl)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            )
                            .shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 15)
                            .shadow(color: Color.blue.opacity(0.1), radius: 15, x: 0, y: 8)
                    )
                    .padding(.horizontal, Spacing.lg)
                    
                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
            )
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private var isValid: Bool {
        if isSignUp {
            return !email.isEmpty && !password.isEmpty && password.count >= 6 && !name.isEmpty
        } else {
            return !email.isEmpty && !password.isEmpty
        }
    }
    
    #if DEBUG
    // MARK: - Quick Test User Function (Debug only)
    private func quickTestUser() {
        // Auto-fill and submit with test user data
        isSignUp = true
        name = "Test User \(testUserCounter)"
        email = "testuser\(testUserCounter)@gmail.com"
        password = "Password"
        
        // Increment counter for next time
        testUserCounter += 1
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            handleAuth()
        }
    }
    #endif
    
    private func handleAuth() {
        showError = false
        errorMessage = ""
        
        Task {
            do {
                if isSignUp {
                    try await supabaseManager.signUp(email: email, password: password, name: name)
                } else {
                    try await supabaseManager.signIn(email: email, password: password)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func handleGoogleSignIn() {
        showError = false
        errorMessage = ""
        
        // Open Google OAuth in Safari
        if let url = supabaseManager.getGoogleOAuthURL() {
            UIApplication.shared.open(url)
        } else {
            errorMessage = "Could not create Google Sign-In URL"
            showError = true
        }
    }
    
    private func handleAppleSignIn() {
        showError = false
        errorMessage = ""
        
        SocialAuthService.shared.signInWithApple { result in
            switch result {
            case .success(let credentials):
                Task {
                    do {
                        try await supabaseManager.signInWithApple(
                            idToken: credentials.identityToken,
                            nonce: credentials.nonce
                        )
                    } catch {
                        await MainActor.run {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    if (error as NSError).code != 1001 { // User cancelled
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
            }
        }
    }
}

// MARK: - Custom Text Field
struct CustomTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words
    var isSecure: Bool = false
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.4, green: 0.6, blue: 1.0),
                            Color(red: 0.3, green: 0.5, blue: 0.9)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .font(.ds_heading3)
                .frame(width: 24)
            
            if isSecure {
                SecureField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .font(.ds_bodyRegular)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .font(.ds_bodyRegular)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, Spacing.md)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
    }
}

#Preview {
    AuthView()
}

