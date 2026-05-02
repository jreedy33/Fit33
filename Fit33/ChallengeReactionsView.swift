//
//  ChallengeReactionsView.swift
//  Fit33
//
//  "Battle Cries" (competition) & "Power Ups" (accountability)
//  Quick-reaction system for active challenges — like Rocket League quick-chat
//  meets iMessage reactions. Fun, expressive, rate-limited (5/day).
//

import SwiftUI

// MARK: - Reaction Preset

struct ReactionPreset: Identifiable {
    let id: String          // Unique key e.g. "trash_catch_me"
    let emoji: String       // Display emoji
    let text: String        // Display text
    let category: ReactionCategory
    
    /// Full display string
    var display: String { "\(emoji) \(text)" }
}

enum ReactionCategory: String {
    case trashTalk = "trash_talk"
    case cheer = "cheer"
}

// MARK: - Preset Libraries

struct ReactionPresets {
    
    // ⚔️ COMPETITION — Trash Talk / Battle Cries
    static let trashTalk: [ReactionPreset] = [
        // Pinned at the top so it's the loudest, most "shoutable" line —
        // matches the home-screen widget shout-bubble copy that yells
        // out of the icon when an opponent fires this off at you.
        ReactionPreset(id: "trash_do_better",       emoji: "📢", text: "Do better!",                category: .trashTalk),
        ReactionPreset(id: "trash_catch_me",        emoji: "🔥", text: "Catch me if you can!",      category: .trashTalk),
        ReactionPreset(id: "trash_all_you_got",     emoji: "😤", text: "That all you got?",          category: .trashTalk),
        ReactionPreset(id: "trash_see_you_slack",   emoji: "👀", text: "I see you slacking...",      category: .trashTalk),
        ReactionPreset(id: "trash_youre_done",      emoji: "💀", text: "You're done for",            category: .trashTalk),
        ReactionPreset(id: "trash_victory_mine",    emoji: "🏆", text: "Victory is mine",            category: .trashTalk),
        ReactionPreset(id: "trash_too_easy",        emoji: "😎", text: "Too easy",                   category: .trashTalk),
        ReactionPreset(id: "trash_slow_start",      emoji: "🐢", text: "Slow start?",                category: .trashTalk),
        ReactionPreset(id: "trash_warming_up",      emoji: "⚡", text: "Just getting warmed up",     category: .trashTalk),
        ReactionPreset(id: "trash_not_even_close",  emoji: "🫠", text: "Not even close",             category: .trashTalk),
        ReactionPreset(id: "trash_scoreboard",      emoji: "📊", text: "Check the scoreboard",       category: .trashTalk),
        ReactionPreset(id: "trash_scared",          emoji: "😈", text: "Scared yet?",                category: .trashTalk),
        ReactionPreset(id: "trash_levels",          emoji: "🎮", text: "Different levels",            category: .trashTalk),
        ReactionPreset(id: "trash_nap_time",        emoji: "😴", text: "Take a nap, I'll wait",      category: .trashTalk),
        ReactionPreset(id: "trash_crying",          emoji: "😢", text: "Need a tissue?",             category: .trashTalk),
        ReactionPreset(id: "trash_wave_bye",        emoji: "👋", text: "Bye bye 👋",                 category: .trashTalk),
    ]
    
    // 🤝 ACCOUNTABILITY — Cheers / Power Ups
    static let cheers: [ReactionPreset] = [
        ReactionPreset(id: "cheer_you_got_this",    emoji: "💪", text: "You got this!",              category: .cheer),
        ReactionPreset(id: "cheer_great_work",      emoji: "🌟", text: "Great work today!",          category: .cheer),
        ReactionPreset(id: "cheer_crush_it",        emoji: "🙌", text: "Let's crush it together!",   category: .cheer),
        ReactionPreset(id: "cheer_on_target",       emoji: "🎯", text: "Stay on target!",            category: .cheer),
        ReactionPreset(id: "cheer_keep_pushing",    emoji: "🏃", text: "Keep pushing!",              category: .cheer),
        ReactionPreset(id: "cheer_proud",           emoji: "❤️‍🔥", text: "Proud of you!",            category: .cheer),
        ReactionPreset(id: "cheer_together",        emoji: "🤜🤛", text: "We're in this together!",  category: .cheer),
        ReactionPreset(id: "cheer_look_at_us",      emoji: "📈", text: "Look at us go!",             category: .cheer),
        ReactionPreset(id: "cheer_unstoppable",     emoji: "🚀", text: "Unstoppable!",               category: .cheer),
        ReactionPreset(id: "cheer_beast_mode",      emoji: "🦁", text: "Beast mode activated!",      category: .cheer),
        ReactionPreset(id: "cheer_no_excuses",      emoji: "⏰", text: "No excuses today!",          category: .cheer),
        ReactionPreset(id: "cheer_streak_alive",    emoji: "🔥", text: "Keep the streak alive!",     category: .cheer),
        ReactionPreset(id: "cheer_almost_there",    emoji: "🏁", text: "Almost there!",              category: .cheer),
        ReactionPreset(id: "cheer_legend",          emoji: "👑", text: "Absolute legend",            category: .cheer),
        ReactionPreset(id: "cheer_grind",           emoji: "⚒️", text: "Respect the grind",          category: .cheer),
    ]

    // 🌍 COMMUNITY — encouragement-only (no smack talk). Same RPC
    // category as `.cheer` so `send_challenge_reaction` accepts the
    // payload without a schema change.
    static let communityEncouragement: [ReactionPreset] = [
        ReactionPreset(id: "comm_lets_go",       emoji: "🙌", text: "Let's go!",               category: .cheer),
        ReactionPreset(id: "comm_crushing",      emoji: "💥", text: "Crushing it!",            category: .cheer),
        ReactionPreset(id: "comm_proud",         emoji: "✨", text: "So proud of this crew!", category: .cheer),
        ReactionPreset(id: "comm_keep_climbing", emoji: "📈", text: "Keep climbing!",          category: .cheer),
        ReactionPreset(id: "comm_stay_strong",   emoji: "💪", text: "Stay strong out there!", category: .cheer),
        ReactionPreset(id: "comm_you_inspire",   emoji: "🌟", text: "You all inspire me!",    category: .cheer),
        ReactionPreset(id: "comm_one_day",      emoji: "☀️", text: "One day at a time!",     category: .cheer),
        ReactionPreset(id: "comm_roots",        emoji: "🌱", text: "Rooting for everyone!",  category: .cheer),
        ReactionPreset(id: "comm_big_energy",   emoji: "⚡", text: "Big energy today!",       category: .cheer),
        ReactionPreset(id: "comm_love_this",    emoji: "❤️", text: "Love this community!",   category: .cheer),
    ]
    
    /// Returns the right presets based on challenge mode
    static func presets(for mode: ChallengeMode) -> [ReactionPreset] {
        switch mode {
        case .competition: return trashTalk
        case .accountability: return cheers
        }
    }
    
    /// Find a preset by its key
    static func find(key: String) -> ReactionPreset? {
        trashTalk.first(where: { $0.id == key })
            ?? cheers.first(where: { $0.id == key })
            ?? communityEncouragement.first(where: { $0.id == key })
    }
}


// MARK: - Reaction Data Model (from server)

struct ChallengeReaction: Codable, Identifiable {
    let reactionId: UUID
    /// `challenge_reactions.challenge_id` — added 2026-05-02 alongside
    /// the dashboard `BattleCryShoutBubble` work. Required so the
    /// `RealtimeService.latestIncomingReaction` stream can be filtered
    /// per dashboard widget card to "is this reaction for the
    /// challenge I'm rendering?". Optional because the historical RPC
    /// view (`get_reactions_for_challenge`) doesn't return the column
    /// in its joined SELECT — back-compat-safe.
    let challengeId: UUID?
    let senderId: UUID
    let senderName: String?
    let senderPhotoUrl: String?
    let recipientId: UUID
    let reactionKey: String
    let reactionEmoji: String
    let reactionText: String
    let reactionCategory: String
    let createdAt: Date

    var id: UUID { reactionId }

    /// Whether I sent this reaction
    var isMine: Bool {
        senderId == SupabaseManager.shared.currentUser?.id
    }

    /// Sender first name
    var senderFirstName: String {
        senderName?.components(separatedBy: " ").first ?? "Someone"
    }

    /// Time ago string
    var timeAgo: String {
        let seconds = Int(Date().timeIntervalSince(createdAt))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }

    enum CodingKeys: String, CodingKey {
        case reactionId = "reaction_id"
        case challengeId = "challenge_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderPhotoUrl = "sender_photo_url"
        case recipientId = "recipient_id"
        case reactionKey = "reaction_key"
        case reactionEmoji = "reaction_emoji"
        case reactionText = "reaction_text"
        case reactionCategory = "reaction_category"
        case createdAt = "created_at"
    }
}


// MARK: - Send Reaction Response

struct SendReactionResponse: Codable {
    let success: Bool
    let reactionId: String?
    let remainingToday: Int?
    let error: String?
    
    enum CodingKeys: String, CodingKey {
        case success
        case reactionId = "reaction_id"
        case remainingToday = "remaining_today"
        case error
    }
}


// MARK: - ChallengeService Extension (Reactions)

extension ChallengeService {
    
    /// Send a reaction to opponent in a challenge
    func sendReaction(
        challengeId: UUID,
        recipientId: UUID,
        preset: ReactionPreset
    ) async -> (success: Bool, remaining: Int?) {
        do {
            struct Params: Encodable {
                let p_challenge_id: String
                let p_recipient_id: String
                let p_reaction_key: String
                let p_reaction_emoji: String
                let p_reaction_text: String
                let p_reaction_category: String
            }
            
            let response: SendReactionResponse = try await SupabaseManager.shared.supabaseClient
                .rpc("send_challenge_reaction", params: Params(
                    p_challenge_id: challengeId.uuidString,
                    p_recipient_id: recipientId.uuidString,
                    p_reaction_key: preset.id,
                    p_reaction_emoji: preset.emoji,
                    p_reaction_text: preset.text,
                    p_reaction_category: preset.category.rawValue
                ))
                .execute()
                .value
            
            if response.success {
                AppLogger.info("✅ [REACTIONS] Sent reaction: \(preset.emoji) \(preset.text)", category: .social)
                // PE invariant 13: any RPC that inserts into push_notification_queue
                // must flush so the recipient sees the push within seconds (not on
                // the next 60s cron tick). `send_challenge_reaction` queues a
                // 'challenge_reaction' push to the recipient — flush immediately
                // so battle cries land like Instagram DMs.
                PushNotificationService.shared.flushPushNotificationQueue(triggeredBy: "challenge_reaction_sent")
                return (true, response.remainingToday)
            } else {
                AppLogger.warning("⚠️ [REACTIONS] Send failed: \(response.error ?? "unknown")", category: .social)
                return (false, nil)
            }
        } catch {
            AppLogger.error("❌ [REACTIONS] Error sending reaction: \(error)", category: .social)
            return (false, nil)
        }
    }
    
    /// Group fan-out: send the same reaction to every accepted recipient
    /// in a group/community challenge. The realtime listener filters by
    /// `challenge_id`, so all subscribers see all inserts; the per-row
    /// fan-out is what guarantees each member receives a push (PE
    /// invariant 13). Returns the count of successful sends.
    func sendGroupReaction(
        challengeId: UUID,
        recipientIds: [UUID],
        preset: ReactionPreset
    ) async -> Int {
        guard let me = SupabaseManager.shared.currentUser?.id else { return 0 }
        let recipients = recipientIds.filter { $0 != me }
        guard !recipients.isEmpty else { return 0 }

        var successCount = 0
        await withTaskGroup(of: Bool.self) { group in
            for recipient in recipients {
                group.addTask {
                    let result = await self.sendReaction(
                        challengeId: challengeId,
                        recipientId: recipient,
                        preset: preset
                    )
                    return result.success
                }
            }
            for await ok in group where ok {
                successCount += 1
            }
        }
        AppLogger.info("✅ [REACTIONS] Group fan-out: \(successCount)/\(recipients.count) reactions sent", category: .social)
        return successCount
    }

    /// Fetch recent reactions for a challenge
    func fetchReactions(challengeId: UUID, limit: Int = 20) async -> [ChallengeReaction] {
        do {
            struct Params: Encodable {
                let p_challenge_id: String
                let p_limit: Int
            }
            
            let reactions: [ChallengeReaction] = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_reactions", params: Params(
                    p_challenge_id: challengeId.uuidString,
                    p_limit: limit
                ))
                .execute()
                .value
            
            AppLogger.info("✅ [REACTIONS] Fetched \(reactions.count) reactions", category: .social)
            return reactions
        } catch {
            let nsError = error as NSError
            if Task.isCancelled || nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                AppLogger.debug("[REACTIONS] Fetch cancelled", category: .social)
            } else {
                AppLogger.error("❌ [REACTIONS] Error fetching reactions: \(error)", category: .social)
            }
            return []
        }
    }
    
    /// Get how many reactions the user has sent today for this challenge
    func getReactionCountToday(challengeId: UUID) async -> Int {
        do {
            struct Params: Encodable {
                let p_challenge_id: String
            }
            
            let count: Int = try await SupabaseManager.shared.supabaseClient
                .rpc("get_challenge_reaction_count_today", params: Params(
                    p_challenge_id: challengeId.uuidString
                ))
                .execute()
                .value
            
            return count
        } catch {
            AppLogger.error("❌ [REACTIONS] Error getting reaction count: \(error)", category: .social)
            return 0
        }
    }
}


// NOTE: `ReactionPickerSheet` and `ReactionQuickButton` were removed in
// the 2026-04-30 Battle Cry overhaul — the canonical surfaces are now
// `BattleCryPickerSheet` + `BattleCryQuickOpenButton` in
// `Fit33/BattleCryComposer.swift`. Per `codingrules.mdc` "remove the old
// implementation to avoid duplicate logic".


// NOTE: `ReactionToast` and `ReactionFeedView` were removed in the
// 2026-04-30 Battle Cry overhaul — use `ReactiveBattleFeed` in
// `Fit33/BattleCryComposer.swift` for any animated reaction surface.


// MARK: - Preview

#Preview("Battle Cry Picker — Competition") {
    BattleCryPickerSheet(
        mode: .competition,
        typeColor: ChallengeType.steps.color,
        gradient: ChallengeType.steps.gradientColors,
        recipientLabel: "Alex",
        onSend: { _ in }
    )
}

#Preview("Battle Cry Picker — Accountability") {
    BattleCryPickerSheet(
        mode: .accountability,
        typeColor: ChallengeType.steps.color,
        gradient: ChallengeType.steps.gradientColors,
        recipientLabel: "Alex",
        onSend: { _ in }
    )
}
