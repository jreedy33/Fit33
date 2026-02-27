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
    
    /// Returns the right presets based on challenge mode
    static func presets(for mode: ChallengeMode) -> [ReactionPreset] {
        switch mode {
        case .competition: return trashTalk
        case .accountability: return cheers
        }
    }
    
    /// Find a preset by its key
    static func find(key: String) -> ReactionPreset? {
        trashTalk.first(where: { $0.id == key }) ?? cheers.first(where: { $0.id == key })
    }
}


// MARK: - Reaction Data Model (from server)

struct ChallengeReaction: Codable, Identifiable {
    let reactionId: UUID
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
                print("✅ [REACTIONS] Sent reaction: \(preset.emoji) \(preset.text)")
                return (true, response.remainingToday)
            } else {
                print("⚠️ [REACTIONS] Send failed: \(response.error ?? "unknown")")
                return (false, nil)
            }
        } catch {
            print("❌ [REACTIONS] Error sending reaction: \(error)")
            return (false, nil)
        }
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
            
            print("✅ [REACTIONS] Fetched \(reactions.count) reactions")
            return reactions
        } catch {
            print("❌ [REACTIONS] Error fetching reactions: \(error)")
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
            print("❌ [REACTIONS] Error getting reaction count: \(error)")
            return 0
        }
    }
}


// MARK: - Reaction Picker Sheet

struct ReactionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: ActiveChallenge
    let onSend: (ReactionPreset) -> Void
    
    @State private var selectedReaction: ReactionPreset?
    @State private var isSending = false
    @State private var sentConfirmation = false
    @State private var remainingToday: Int = 5
    @State private var animateEmoji = false
    
    private var mode: ChallengeMode { challenge.mode }
    private var presets: [ReactionPreset] { ReactionPresets.presets(for: mode) }
    private var opponentFirstName: String { challenge.opponentName?.components(separatedBy: " ").first ?? "them" }
    
    private var isCompetition: Bool { mode == .competition }
    
    private var themeGradient: [Color] {
        isCompetition ? [.orange, .red] : [.blue, .cyan]
    }
    
    private var themeColor: Color {
        isCompetition ? .orange : .cyan
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.14) : Color(white: 0.97)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Fun header
                    headerSection
                    
                    // Reaction grid
                    reactionGrid
                    
                    // Daily limit indicator
                    dailyLimitBadge
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color(white: 0.06), Color(white: 0.04)]
                        : [Color(white: 0.96), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle(isCompetition ? "⚔️ Battle Cries" : "💪 Power Ups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.medium)
                }
            }
            .overlay {
                // Full-screen sent confirmation overlay
                if sentConfirmation, let reaction = selectedReaction {
                    sentOverlay(reaction: reaction)
                }
            }
            .task {
                let usedToday = await ChallengeService.shared.getReactionCountToday(challengeId: challenge.challengeId)
                remainingToday = 5 - usedToday
            }
        }
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            // Animated emoji
            Text(isCompetition ? "🗣️" : "✨")
                .font(.system(size: 48))
                .scaleEffect(animateEmoji ? 1.1 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: animateEmoji)
                .onAppear { animateEmoji = true }
            
            Text(isCompetition ? "Talk Your Smack" : "Send Some Love")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(isCompetition
                 ? "Let \(opponentFirstName) know who's boss 😈"
                 : "Hype up \(opponentFirstName) to crush today 🔥")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Reaction Grid
    
    private var reactionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(presets) { preset in
                reactionCard(preset)
            }
        }
    }
    
    private func reactionCard(_ preset: ReactionPreset) -> some View {
        Button {
            guard !isSending && remainingToday > 0 else { return }
            sendReaction(preset)
        } label: {
            HStack(spacing: 8) {
                Text(preset.emoji)
                    .font(.system(size: 22))
                
                Text(preset.text)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selectedReaction?.id == preset.id
                            ? LinearGradient(colors: themeGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isSending || remainingToday <= 0)
        .opacity(remainingToday <= 0 ? 0.5 : 1)
    }
    
    // MARK: - Daily Limit Badge
    
    private var dailyLimitBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: remainingToday > 0 ? "bolt.fill" : "bolt.slash.fill")
                .font(.caption)
                .foregroundColor(remainingToday > 0 ? themeColor : .secondary)
            
            Text(remainingToday > 0
                 ? "\(remainingToday) \(isCompetition ? "battle cries" : "power ups") left today"
                 : "All fired up for today! Come back tomorrow 🔄")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(
            Capsule()
                .fill(themeColor.opacity(0.1))
        )
    }
    
    // MARK: - Send Reaction
    
    private func sendReaction(_ preset: ReactionPreset) {
        selectedReaction = preset
        isSending = true
        HapticManager.impact(.medium)
        
        Task {
            let result = await ChallengeService.shared.sendReaction(
                challengeId: challenge.challengeId,
                recipientId: challenge.opponentId,
                preset: preset
            )
            
            await MainActor.run {
                isSending = false
                
                if result.success {
                    if let remaining = result.remaining {
                        remainingToday = remaining
                    } else {
                        remainingToday = max(0, remainingToday - 1)
                    }
                    
                    // Show sent confirmation
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        sentConfirmation = true
                    }
                    HapticManager.notification(.success)
                    
                    // Auto-dismiss after delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeOut(duration: 0.3)) {
                            sentConfirmation = false
                        }
                        selectedReaction = nil
                    }
                } else {
                    HapticManager.notification(.error)
                    selectedReaction = nil
                }
            }
        }
    }
    
    // MARK: - Sent Overlay
    
    private func sentOverlay(reaction: ReactionPreset) -> some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { sentConfirmation = false }
                }
            
            VStack(spacing: 16) {
                Text(reaction.emoji)
                    .font(.system(size: 64))
                
                Text("Sent to \(opponentFirstName)!")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(reaction.text)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .italic()
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: themeGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: themeColor.opacity(0.4), radius: 20)
            )
            .transition(.scale.combined(with: .opacity))
        }
    }
}


// MARK: - Reaction Feed (for Challenge Detail Page)

struct ReactionFeedView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: ActiveChallenge
    
    @State private var reactions: [ChallengeReaction] = []
    @State private var isLoading = true
    
    private var mode: ChallengeMode { challenge.mode }
    private var isCompetition: Bool { mode == .competition }
    
    private var themeGradient: [Color] {
        isCompetition ? [.orange, .red] : [.blue, .cyan]
    }
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color(white: 0.12) : Color.white
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text(isCompetition ? "🗣️ Battle Log" : "✨ Hype Feed")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if !reactions.isEmpty {
                    Text("\(reactions.count) messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if reactions.isEmpty {
                // Empty state
                emptyState
            } else {
                // Reaction bubbles
                VStack(spacing: 8) {
                    ForEach(reactions.prefix(10)) { reaction in
                        reactionBubble(reaction)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(cardBackground)
                )
            }
        }
        .task {
            reactions = await ChallengeService.shared.fetchReactions(challengeId: challenge.challengeId)
            isLoading = false
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(isCompetition ? "🤐" : "💬")
                .font(.system(size: 32))
            
            Text(isCompetition ? "No smack talk yet..." : "No messages yet...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text(isCompetition
                 ? "Be the first to fire a shot!"
                 : "Send some motivation!")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardBackground)
        )
    }
    
    // MARK: - Reaction Bubble
    
    private func reactionBubble(_ reaction: ChallengeReaction) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Sender avatar
            if reaction.isMine {
                Spacer(minLength: 40)
            } else {
                CachedFriendPhoto(
                    friendId: reaction.senderId.uuidString,
                    photoUrl: reaction.senderPhotoUrl,
                    name: reaction.senderName ?? "?",
                    size: 28,
                    showGradientRing: false,
                    gradientColors: themeGradient
                )
            }
            
            VStack(alignment: reaction.isMine ? .trailing : .leading, spacing: 3) {
                // Name + time
                HStack(spacing: 4) {
                    if !reaction.isMine {
                        Text(reaction.senderFirstName)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(reaction.timeAgo)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                
                // Reaction bubble
                HStack(spacing: 6) {
                    Text(reaction.reactionEmoji)
                        .font(.system(size: 16))
                    Text(reaction.reactionText)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(reaction.isMine ? .white : .primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            reaction.isMine
                                ? AnyShapeStyle(LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(colorScheme == .dark ? Color(white: 0.18) : Color(white: 0.93))
                        )
                )
            }
            
            if !reaction.isMine {
                Spacer(minLength: 40)
            }
        }
    }
}


// MARK: - Reaction Quick Button (for Widget + Detail Page)
// A compact button that shows the latest reaction or a send button

struct ReactionQuickButton: View {
    @Environment(\.colorScheme) private var colorScheme
    
    let challenge: ActiveChallenge
    @Binding var showingReactionPicker: Bool
    
    @State private var latestReaction: ChallengeReaction?
    @State private var showBubble = false
    @State private var pulseAnimation = false
    
    private var mode: ChallengeMode { challenge.mode }
    private var isCompetition: Bool { mode == .competition }
    
    private var themeGradient: [Color] {
        isCompetition ? [.orange, .red] : [.blue, .cyan]
    }
    
    private var themeColor: Color {
        isCompetition ? .orange : .cyan
    }
    
    var body: some View {
        Button {
            HapticManager.impact(.light)
            showingReactionPicker = true
        } label: {
            HStack(spacing: 6) {
                // Latest received reaction or default button
                if let reaction = latestReaction, !reaction.isMine {
                    // Show incoming reaction as a teaser
                    Text(reaction.reactionEmoji)
                        .font(.system(size: 14))
                    Text(reaction.reactionText)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                } else {
                    Image(systemName: isCompetition ? "flame.fill" : "bolt.heart.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(
                            LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing)
                        )
                    Text(isCompetition ? "Talk Smack" : "Send Hype")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(themeColor.opacity(colorScheme == .dark ? 0.15 : 0.1))
            )
            .overlay(
                Capsule()
                    .stroke(themeColor.opacity(0.3), lineWidth: 1)
            )
            .scaleEffect(pulseAnimation ? 1.03 : 1.0)
        }
        .buttonStyle(.plain)
        .task {
            // Fetch latest reaction for this challenge
            let reactions = await ChallengeService.shared.fetchReactions(challengeId: challenge.challengeId, limit: 1)
            if let latest = reactions.first {
                latestReaction = latest
                
                // Pulse animation if there's a new unread reaction
                if !latest.isMine {
                    withAnimation(.easeInOut(duration: 0.8).repeatCount(3)) {
                        pulseAnimation = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        pulseAnimation = false
                    }
                }
            }
        }
    }
}


// MARK: - Incoming Reaction Toast
// Animated toast that appears when opponent sends a reaction

struct ReactionToast: View {
    let emoji: String
    let text: String
    let senderName: String
    let isCompetition: Bool
    
    @State private var isVisible = false
    
    private var themeGradient: [Color] {
        isCompetition ? [.orange, .red] : [.blue, .cyan]
    }
    
    var body: some View {
        if isVisible {
            HStack(spacing: 10) {
                Text(emoji)
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(senderName)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(text)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: themeGradient, startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
            )
            .padding(.horizontal, 16)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}


// MARK: - Preview

#Preview("Reaction Picker - Competition") {
    ReactionPickerSheet(
        challenge: ActiveChallenge(
            challengeId: UUID(),
            challengeType: "steps",
            title: "⚔️ 10K Steps Daily",
            description: nil,
            dailyTarget: 10000,
            totalTarget: nil,
            targetUnit: "steps",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 7),
            durationDays: 7,
            daysElapsed: 3,
            daysRemaining: 4,
            status: "active",
            myTotalProgress: 28500,
            myDaysCompleted: 2,
            myCurrentStreak: 2,
            opponentId: UUID(),
            opponentName: "Leo Smith",
            opponentUsername: nil,
            opponentPhotoUrl: nil,
            opponentTotalProgress: 25000,
            opponentDaysCompleted: 2,
            amWinning: true
        ),
        onSend: { _ in }
    )
}

#Preview("Reaction Picker - Accountability") {
    ReactionPickerSheet(
        challenge: ActiveChallenge(
            challengeId: UUID(),
            challengeType: "steps",
            title: "🤝 10K Steps Daily",
            description: nil,
            dailyTarget: 10000,
            totalTarget: nil,
            targetUnit: "steps",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 7),
            durationDays: 7,
            daysElapsed: 3,
            daysRemaining: 4,
            status: "active",
            myTotalProgress: 28500,
            myDaysCompleted: 2,
            myCurrentStreak: 2,
            opponentId: UUID(),
            opponentName: "Leo Smith",
            opponentUsername: nil,
            opponentPhotoUrl: nil,
            opponentTotalProgress: 25000,
            opponentDaysCompleted: 2,
            amWinning: true
        ),
        onSend: { _ in }
    )
}
