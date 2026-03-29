//
//  ContentModerationService.swift
//  Fit33
//
//  Lightweight client for the moderate-content Edge Function.
//  Pre-checks user-generated text before sending to the server.
//  Uses OpenAI Moderation API via the Edge Function (free, ~100ms).
//

import Foundation

@MainActor
class ContentModerationService {
    static let shared = ContentModerationService()
    
    struct ModerationResult {
        let flagged: Bool
        let categories: [String]
    }
    
    private struct PrecheckRequest: Encodable {
        let mode: String
        let content: String
        let user_id: String?
        let source: String?
    }
    
    private struct PrecheckResponse: Decodable {
        let flagged: Bool
        let categories: [String]?
    }
    
    func checkContent(content: String, source: String? = nil) async -> ModerationResult {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ModerationResult(flagged: false, categories: [])
        }
        
        guard let url = URL(string: "\(AppConfig.Supabase.url)/functions/v1/moderate-content") else {
            AppLogger.error("Invalid moderation Edge Function URL", category: .network)
            return ModerationResult(flagged: false, categories: [])
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(AppConfig.Supabase.anonKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 5
            
            let userId = SupabaseManager.shared.currentUser?.id.uuidString
            let body = PrecheckRequest(
                mode: "precheck",
                content: content,
                user_id: userId,
                source: source
            )
            request.httpBody = try JSONEncoder().encode(body)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                AppLogger.warning("Moderation API returned non-200, allowing content through", category: .network)
                return ModerationResult(flagged: false, categories: [])
            }
            
            let result = try JSONDecoder().decode(PrecheckResponse.self, from: data)
            return ModerationResult(
                flagged: result.flagged,
                categories: result.categories ?? []
            )
        } catch {
            // Fail-open: if moderation service is down, allow content through
            AppLogger.warning("Moderation pre-check failed, allowing content: \(error.localizedDescription)", category: .network)
            return ModerationResult(flagged: false, categories: [])
        }
    }
}
