//
//  SocialAuthService.swift
//  BuiltSimple
//
//  Social Authentication Service for Apple and Google Sign-In
//

import Foundation
import AuthenticationServices
import SwiftUI
import CryptoKit

// MARK: - Social Auth Service
class SocialAuthService: NSObject, ObservableObject {
    static let shared = SocialAuthService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store the current nonce for Apple Sign-In verification
    private var currentNonce: String?
    
    // Completion handler for Apple Sign-In
    private var appleSignInCompletion: ((Result<AppleSignInCredentials, Error>) -> Void)?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Apple Sign-In
    
    struct AppleSignInCredentials {
        let identityToken: String
        let authorizationCode: String
        let fullName: PersonNameComponents?
        let email: String?
        let nonce: String
    }
    
    /// Initiates Apple Sign-In flow
    func signInWithApple(completion: @escaping (Result<AppleSignInCredentials, Error>) -> Void) {
        let nonce = randomNonceString()
        currentNonce = nonce
        appleSignInCompletion = completion
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
    }
    
    // MARK: - Google Sign-In
    
    /// Initiates Google Sign-In flow via Supabase OAuth
    /// This opens a web view for Google authentication
    func getGoogleSignInURL() -> URL? {
        // Supabase OAuth URL for Google
        let supabaseURL = "https://ehooeghabzefgoqzugrc.supabase.co"
        let redirectURL = "fit33://login-callback"
        
        // Construct the OAuth URL
        var components = URLComponents(string: "\(supabaseURL)/auth/v1/authorize")
        components?.queryItems = [
            URLQueryItem(name: "provider", value: "google"),
            URLQueryItem(name: "redirect_to", value: redirectURL)
        ]
        
        return components?.url
    }
    
    // MARK: - Cryptographic Helpers
    
    /// Generates a random nonce string for security
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        
        return String(nonce)
    }
    
    /// Creates SHA256 hash of the input string
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
}

// MARK: - ASAuthorizationControllerDelegate
extension SocialAuthService: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = appleIDCredential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8),
              let nonce = currentNonce else {
            appleSignInCompletion?(.failure(SocialAuthError.invalidCredentials))
            return
        }
        
        let credentials = AppleSignInCredentials(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: appleIDCredential.fullName,
            email: appleIDCredential.email,
            nonce: nonce
        )
        
        appleSignInCompletion?(.success(credentials))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
        
        appleSignInCompletion?(.failure(error))
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding
extension SocialAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Social Auth Errors
enum SocialAuthError: LocalizedError {
    case invalidCredentials
    case noIdentityToken
    case userCancelled
    case networkError
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid credentials received from provider"
        case .noIdentityToken:
            return "No identity token received"
        case .userCancelled:
            return "Sign-in was cancelled"
        case .networkError:
            return "Network error occurred"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - Sign In With Apple Button (SwiftUI) - Pill Shaped
struct SignInWithAppleButton: View {
    @Environment(\.colorScheme) var colorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "applelogo")
                    .font(.system(size: 18, weight: .semibold))
                
                Text("Continue with Apple")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
            )
        }
    }
}

// MARK: - Sign In With Google Button (SwiftUI)
struct SignInWithGoogleButton: View {
    @Environment(\.colorScheme) var colorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Google "G" logo colors
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .yellow, .green, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Social Login Divider
struct SocialLoginDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            // Gradient line - fades from center
            LinearGradient(
                colors: [.clear, Color.gray.opacity(0.25)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            
            Text("or continue with")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary.opacity(0.7))
            
            // Gradient line - fades to center
            LinearGradient(
                colors: [Color.gray.opacity(0.25), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
        }
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 16) {
        SignInWithAppleButton { }
        SignInWithGoogleButton { }
        SocialLoginDivider()
    }
    .padding()
}

