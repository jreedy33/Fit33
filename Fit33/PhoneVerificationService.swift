//
//  PhoneVerificationService.swift
//  Fit33
//
//  Phone verification via SMS using Twilio Verify
//  Calls Supabase Edge Functions to send/verify codes
//

import Foundation
import Supabase

/// Service for SMS-based phone verification
/// Uses Twilio Verify via Supabase Edge Functions
@MainActor
class PhoneVerificationService: ObservableObject {
    static let shared = PhoneVerificationService()
    
    // MARK: - Published State
    @Published var isLoading = false
    @Published var verificationSent = false
    @Published var isVerified = false
    @Published var error: String?
    @Published var remainingAttempts: Int {
        didSet {
            UserDefaults.standard.set(remainingAttempts, forKey: "phone_verify_remaining")
            if remainingAttempts <= 0 {
                UserDefaults.standard.set(Date().timeIntervalSince1970 + 3600, forKey: "phone_verify_lockout")
            }
        }
    }
    
    // MARK: - Private
    private let supabaseManager = SupabaseManager.shared
    
    private init() {
        let lockout = UserDefaults.standard.double(forKey: "phone_verify_lockout")
        if lockout > 0 && Date().timeIntervalSince1970 >= lockout {
            UserDefaults.standard.removeObject(forKey: "phone_verify_lockout")
            UserDefaults.standard.set(5, forKey: "phone_verify_remaining")
            _remainingAttempts = Published(initialValue: 5)
        } else {
            let stored = UserDefaults.standard.object(forKey: "phone_verify_remaining") as? Int ?? 5
            _remainingAttempts = Published(initialValue: stored)
        }
    }
    
    // MARK: - Send Verification Code
    
    /// Sends a verification code to the given phone number
    /// - Parameter phoneNumber: Phone number (digits only, e.g., "5551234567")
    /// - Returns: True if code was sent successfully
    func sendVerificationCode(to phoneNumber: String) async -> Bool {
        let lockout = UserDefaults.standard.double(forKey: "phone_verify_lockout")
        if lockout > 0 && Date().timeIntervalSince1970 < lockout {
            let minutes = Int((lockout - Date().timeIntervalSince1970) / 60)
            error = "Too many attempts. Try again in \(max(minutes, 1)) minutes."
            return false
        }
        
        guard !phoneNumber.isEmpty else {
            error = "Please enter a phone number"
            return false
        }
        
        // Extract digits only
        let digits = phoneNumber.filter { $0.isNumber }
        guard digits.count >= 10 else {
            error = "Please enter a valid phone number"
            return false
        }
        
        isLoading = true
        error = nil
        
        do {
            AppLogger.debug("📱 [VERIFY] Sending verification code to: \(digits)", category: .auth)
            
            // Call Supabase Edge Function
            let response: VerificationResponse = try await supabaseManager.client
                .functions
                .invoke(
                    "send-verification",
                    options: FunctionInvokeOptions(
                        body: ["phone_number": digits]
                    )
                )
            
            if response.success {
                AppLogger.info("✅ [VERIFY] Code sent successfully", category: .auth)
                verificationSent = true
                isLoading = false
                return true
            } else {
                AppLogger.error("❌ [VERIFY] Failed: \(response.error ?? "Unknown error")", category: .auth)
                error = response.error ?? "Failed to send verification code"
                isLoading = false
                return false
            }
            
        } catch {
            AppLogger.error("❌ [VERIFY] Error sending code: \(error)", category: .auth)
            self.error = "Failed to send code. Please try again."
            isLoading = false
            return false
        }
    }
    
    // MARK: - Verify Code
    
    /// Verifies the code entered by the user
    /// - Parameters:
    ///   - code: The 6-digit code from SMS
    ///   - phoneNumber: The phone number being verified
    /// - Returns: True if verification successful
    func verifyCode(_ code: String, for phoneNumber: String) async -> Bool {
        let lockout = UserDefaults.standard.double(forKey: "phone_verify_lockout")
        if lockout > 0 && Date().timeIntervalSince1970 < lockout {
            let minutes = Int((lockout - Date().timeIntervalSince1970) / 60)
            error = "Too many attempts. Try again in \(max(minutes, 1)) minutes."
            return false
        }
        
        guard code.count == 6 else {
            error = "Please enter the 6-digit code"
            return false
        }
        
        let digits = phoneNumber.filter { $0.isNumber }
        
        isLoading = true
        error = nil
        
        do {
            AppLogger.debug("🔐 [VERIFY] Checking code for: \(digits)", category: .auth)
            
            // Call Supabase Edge Function
            let response: VerificationResponse = try await supabaseManager.client
                .functions
                .invoke(
                    "verify-code",
                    options: FunctionInvokeOptions(
                        body: [
                            "phone_number": digits,
                            "code": code
                        ]
                    )
                )
            
            if response.success && response.status == "approved" {
                AppLogger.info("✅ [VERIFY] Phone verified successfully!", category: .auth)
                isVerified = true
                isLoading = false
                return true
            } else {
                AppLogger.error("❌ [VERIFY] Invalid code: \(response.error ?? "Unknown error")", category: .auth)
                error = response.error ?? "Invalid code. Please try again."
                remainingAttempts -= 1
                isLoading = false
                return false
            }
            
        } catch {
            AppLogger.error("❌ [VERIFY] Error verifying code: \(error)", category: .auth)
            self.error = "Verification failed. Please try again."
            isLoading = false
            return false
        }
    }
    
    // MARK: - Resend Code
    
    /// Resends the verification code
    func resendCode(to phoneNumber: String) async -> Bool {
        verificationSent = false
        return await sendVerificationCode(to: phoneNumber)
    }
    
    // MARK: - Reset State
    
    func reset() {
        isLoading = false
        verificationSent = false
        isVerified = false
        error = nil
        remainingAttempts = 5
        UserDefaults.standard.removeObject(forKey: "phone_verify_lockout")
    }
}

// MARK: - Response Models

private struct VerificationResponse: Codable {
    let success: Bool
    let status: String?
    let message: String?
    let error: String?
}
