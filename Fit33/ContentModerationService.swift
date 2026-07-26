//
//  ContentModerationService.swift
//  Fit33
//
//  Lightweight client for the moderate-content Edge Function.
//  Pre-checks user-generated text before sending to the server.
//  Uses OpenAI Moderation API via the Edge Function (free, ~100ms).
//

import Foundation
import Auth

@MainActor
class ContentModerationService {
    static let shared = ContentModerationService()
    
    struct ModerationResult {
        let flagged: Bool
        let categories: [String]
        /// Audit PR-8 (2026-07-26): true when the content was NOT screened
        /// (no session / non-200 / network failure). UGC write paths must
        /// treat this as fail-CLOSED — the old behavior silently allowed
        /// everything through whenever the edge function was unreachable.
        var unavailable: Bool = false
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
        
        // The edge function's `requireUserAuth` helper calls
        // `supabase.auth.getUser(token)` which requires a real user session JWT.
        // Sending the anon key here would succeed past Supabase's edge gate but
        // fail our function's own auth check — causing the precheck to silently
        // fail-open and let flagged content through.
        let session: Session
        do {
            session = try await SupabaseManager.shared.client.auth.session
        } catch {
            AppLogger.warning("Moderation pre-check unavailable — no user session: \(error.localizedDescription)", category: .network)
            return ModerationResult(flagged: false, categories: [], unavailable: true)
        }
        let accessToken = session.accessToken

        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(AppConfig.Supabase.anonKey, forHTTPHeaderField: "apikey")
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
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                let bodyPreview = String(data: data.prefix(200), encoding: .utf8) ?? "<non-utf8>"
                AppLogger.warning("Moderation API returned HTTP \(code) — reporting unavailable (fail closed). Body: \(bodyPreview)", category: .network)
                return ModerationResult(flagged: false, categories: [], unavailable: true)
            }
            
            let result = try JSONDecoder().decode(PrecheckResponse.self, from: data)
            return ModerationResult(
                flagged: result.flagged,
                categories: result.categories ?? []
            )
        } catch {
            // Audit PR-8: fail CLOSED — callers on UGC write paths block the
            // write and ask the user to retry (server-side Layer-2 webhook
            // moderation still backstops anything that slips through).
            AppLogger.warning("Moderation pre-check failed — reporting unavailable (fail closed): \(error.localizedDescription)", category: .network)
            return ModerationResult(flagged: false, categories: [], unavailable: true)
        }
    }
}
