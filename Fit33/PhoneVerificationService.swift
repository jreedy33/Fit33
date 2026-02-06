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
    @Published var remainingAttempts = 5
    
    // MARK: - Private
    private let supabaseManager = SupabaseManager.shared
    
    private init() {}
    
    // MARK: - Send Verification Code
    
    /// Sends a verification code to the given phone number
    /// - Parameter phoneNumber: Phone number (digits only, e.g., "5551234567")
    /// - Returns: True if code was sent successfully
    func sendVerificationCode(to phoneNumber: String) async -> Bool {
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
            print("📱 [VERIFY] Sending verification code to: \(digits)")
            
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
                print("✅ [VERIFY] Code sent successfully")
                verificationSent = true
                isLoading = false
                return true
            } else {
                print("❌ [VERIFY] Failed: \(response.error ?? "Unknown error")")
                error = response.error ?? "Failed to send verification code"
                isLoading = false
                return false
            }
            
        } catch {
            print("❌ [VERIFY] Error sending code: \(error)")
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
        guard code.count == 6 else {
            error = "Please enter the 6-digit code"
            return false
        }
        
        let digits = phoneNumber.filter { $0.isNumber }
        
        isLoading = true
        error = nil
        
        do {
            print("🔐 [VERIFY] Checking code for: \(digits)")
            
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
                print("✅ [VERIFY] Phone verified successfully!")
                isVerified = true
                isLoading = false
                return true
            } else {
                print("❌ [VERIFY] Invalid code: \(response.error ?? "Unknown error")")
                error = response.error ?? "Invalid code. Please try again."
                remainingAttempts -= 1
                isLoading = false
                return false
            }
            
        } catch {
            print("❌ [VERIFY] Error verifying code: \(error)")
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
    }
}

// MARK: - Response Models

private struct VerificationResponse: Codable {
    let success: Bool
    let status: String?
    let message: String?
    let error: String?
}
