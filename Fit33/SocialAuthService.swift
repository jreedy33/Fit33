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

// Note: ASWebAuthenticationSession types require AuthenticationServices (already imported)

// MARK: - Social Auth Service
class SocialAuthService: NSObject, ObservableObject {
    static let shared = SocialAuthService()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Store the current nonce for Apple Sign-In verification
    private var currentNonce: String?
    
    // Completion handler for Apple Sign-In
    private var appleSignInCompletion: ((Result<AppleSignInCredentials, Error>) -> Void)?
    
    // Guard to prevent multiple simultaneous sign-in attempts
    private var isSignInInProgress = false
    
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
        // Prevent multiple simultaneous sign-in attempts (prevents nonce mismatch)
        guard !isSignInInProgress else {
            print("🍎 [APPLE AUTH] ⚠️ Sign-in already in progress, ignoring duplicate request")
            return
        }
        
        isSignInInProgress = true
        let nonce = randomNonceString()
        currentNonce = nonce
        appleSignInCompletion = completion
        
        print("🍎 [APPLE AUTH] Starting sign-in with nonce: \(nonce.prefix(8))...")
        
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
    
    // MARK: - Cryptographic Helpers
    
    /// Generates a random nonce string for security
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Fallback to arc4random if SecRandomCopyBytes fails (extremely rare)
            print("⚠️ [AUTH] SecRandomCopyBytes failed with OSStatus \(errorCode), using fallback")
            for i in 0..<length {
                randomBytes[i] = UInt8(arc4random_uniform(256))
            }
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
        defer {
            // Reset the flag after completion
            isSignInInProgress = false
        }
        
        DispatchQueue.main.async {
            self.isLoading = false
        }
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let identityTokenData = appleIDCredential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8),
              let authorizationCodeData = appleIDCredential.authorizationCode,
              let authorizationCode = String(data: authorizationCodeData, encoding: .utf8),
              let nonce = currentNonce else {
            print("🍎 [APPLE AUTH] ❌ Failed to extract credentials or nonce")
            appleSignInCompletion?(.failure(SocialAuthError.invalidCredentials))
            return
        }
        
        print("🍎 [APPLE AUTH] ✅ Authorization complete with nonce: \(nonce.prefix(8))...")
        
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
        defer {
            // Reset the flag after error
            isSignInInProgress = false
        }
        
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
        
        print("🍎 [APPLE AUTH] ❌ Authorization error: \(error.localizedDescription)")
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
                    .font(.ds_heading3)
                
                Text("Continue with Apple")
                    .font(.ds_labelLarge)
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color.white : Color.black)
            )
        }
    }
}

// MARK: - Sign In With Google Button (SwiftUI) - Pill Shaped (matches Apple button)
struct SignInWithGoogleButton: View {
    @Environment(\.colorScheme) var colorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Google "G" logo - transparent background
                Image("GoogleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                
                Text("Continue with Google")
                    .font(.ds_labelLarge)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.md)
            .background(
                Capsule()
                    .fill(Color.white)
            )
            .overlay(
                Capsule()
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
                .font(.ds_bodySmall).fontWeight(.medium)
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

// MARK: - Web Auth Context Provider
/// Provides presentation context for ASWebAuthenticationSession
class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()
    
    private override init() {
        super.init()
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return UIWindow()
        }
        return window
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

