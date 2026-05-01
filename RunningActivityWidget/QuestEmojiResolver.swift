//
//  QuestEmojiResolver.swift
//  RunningActivityWidget
//
//  Widget-side mirror of `Fit33/QuestEmojiResolver` (lives at the bottom of
//  `Fit33/DailyQuestService.swift`). Smart, content-aware emoji selection so
//  widget cards match the in-app cards at a glance.
//
//  Resolution order (first hit wins):
//    1. byQuestKey       — curated emoji per canonical quest_key
//    2. keywordTable     — priority-ordered keyword scan of title+description+funLabel
//    3. leadingFunEmoji  — first character of fun_label if it's an emoji
//    4. categoryFallback — category bucket (workout/nutrition/social/...)
//    5. ⭐               — generic default
//
//  KEEP THIS FILE IN SYNC with the main-app copy. When you add/edit an entry
//  in `QuestEmojiResolver` in the main app, mirror it here.
//

import Foundation

enum QuestEmojiResolver {
    static func resolve(
        questKey: String,
        title: String,
        description: String,
        category: String,
        funLabel: String? = nil
    ) -> String {
        if let exact = byQuestKey[questKey.lowercased()] {
            return exact
        }

        let haystack = "\(title) \(description) \(funLabel ?? "")".lowercased()
        for (keyword, emoji) in keywordTable where haystack.contains(keyword) {
            return emoji
        }

        if let funLabel,
           let first = funLabel.trimmingCharacters(in: .whitespaces).first,
           first.isLikelyEmoji {
            return String(first)
        }

        if let bucket = categoryFallback[category.lowercased()] {
            return bucket
        }

        return "⭐"
    }

    // MARK: Quest-key (exact) table — mirror of main-app copy.
    private static let byQuestKey: [String: String] = [
        // Workout
        "complete_workout":         "💪",
        "complete_program_day":     "📋",
        "complete_2_workouts":      "🏋️",
        "workout_30_min":           "⏱️",
        "exercise_sets_10":         "🎯",
        "exercise_sets_15":         "🎯",
        "exercise_sets_20":         "🎯",
        "exercise_sets_25":         "🎯",
        "try_new_exercise":         "✨",
        "upper_body_workout":       "🦾",
        "lower_body_workout":       "🦵",
        "stretch_session":          "🧘",
        "beat_volume_pr":           "🏆",
        "beat_personal_record":     "🏆",
        "maintain_streak":          "🔥",

        // Nutrition
        "log_breakfast":            "🥣",
        "log_lunch":                "🥗",
        "log_dinner":               "🍽️",
        "log_3_meals":              "🍱",
        "log_snack":                "🍎",
        "log_meal":                 "🍽️",
        "log_water":                "💧",
        "log_water_3":              "💧",
        "log_water_8":              "🚰",
        "hit_protein_goal":         "🥩",
        "log_high_protein_meal":    "🍗",
        "log_all_macros":           "📋",
        "hydration_before_noon":    "💧",

        // Steps & Movement
        "walk_3k_steps":            "🚶",
        "walk_5k_steps":            "🚶‍♂️",
        "walk_7500_steps":          "🥾",
        "walk_10k_steps":           "🏃",
        "hit_step_goal":            "👟",
        "active_minutes_30":        "⏱️",
        "burn_300_calories":        "🔥",
        "sleep_7_hours":            "😴",

        // Social
        "send_challenge":           "⚔️",
        "start_1v1_challenge":      "⚔️",
        "start_1v1_with_top_friend":"⚔️",
        "start_first_challenge":    "🚩",
        "react_to_workout":         "👏",
        "react_to_3_workouts":      "👏",
        "comment_on_friends_workout":"💬",
        "do_friend_workout":        "👯",
        "invite_friend":            "💌",
        "add_friend":               "🤝",
        "beat_friend_steps":        "🥾",
        "league_3_workouts":        "🏆",
        "top_3_league":             "🥇",

        // Tracking / consistency
        "log_weight":               "⚖️",
        "weekly_weigh_in":          "⚖️",
        "check_progress":           "📊",
        "log_cardio":               "❤️",

        // Wildcard / fun
        "perfect_day":              "🌟",
        "early_bird_workout":       "🌅",
        "share_workout":            "📣",
        "favorite_a_workout":       "⭐",

        // Reward
        "watch_ads":                "📺",

        // Strava / outdoor
        "beat_your_5k_pr":          "🏁",
        "negative_split_run":       "📈",
        "run_outside_8km":          "🛣️",
        "cycle_outside_30km":       "🚴",
        "complete_strava_segment":  "📍",

        // Wearable
        "match_yesterday_strain":   "⚡",
        "walk_when_red":            "🟥",

        // Day-1 beginner pack
        "beginner_sync_contacts":   "📇",
        "beginner_add_friend":      "🤝",
        "beginner_send_challenge":  "🚩",
        "beginner_first_workout":   "🎬",
        "beginner_explore_program": "📚"
    ]

    // MARK: Keyword priority table — mirror of main-app copy.
    private static let keywordTable: [(String, String)] = [
        ("heart health",     "❤️"),
        ("heart rate",       "❤️"),
        ("cardiovascular",   "❤️"),
        ("blood pressure",   "🩺"),
        ("hrv",              "💓"),
        ("resting hr",       "💓"),
        ("vo2",              "🫁"),
        ("breath",           "🫁"),

        ("strawberr",        "🍓"),
        ("blueberr",         "🫐"),
        ("raspberr",         "🍓"),
        ("blackberr",        "🫐"),
        ("watermelon",       "🍉"),
        ("pineapple",        "🍍"),
        ("avocado",          "🥑"),
        ("banana",           "🍌"),
        ("mango",             "🥭"),
        ("kiwi",             "🥝"),
        ("coconut",          "🥥"),
        ("peach",            "🍑"),
        ("pear",             "🍐"),
        ("cherry",           "🍒"),
        ("lemon",            "🍋"),
        ("orange juice",     "🍊"),
        ("grape",            "🍇"),
        ("apple",            "🍎"),
        ("berry", "🫐"), ("berries", "🫐"),
        ("fruit",            "🍇"),

        ("broccoli",         "🥦"),
        ("carrot",           "🥕"),
        ("tomato",           "🍅"),
        ("corn",             "🌽"),
        ("bell pepper",      "🫑"),
        ("onion",            "🧅"),
        ("garlic",           "🧄"),
        ("potato",           "🥔"),
        ("mushroom",         "🍄"),
        ("lettuce",          "🥬"),
        ("greens",           "🥬"),
        ("kale",             "🥬"),
        ("spinach",          "🥬"),
        ("salad",            "🥗"),

        ("scrambled",        "🍳"),
        ("omelet",           "🍳"),
        ("egg",              "🥚"),
        ("chicken",          "🍗"),
        ("turkey",           "🦃"),
        ("steak",            "🥩"),
        ("beef",             "🥩"),
        ("pork",             "🥓"),
        ("bacon",            "🥓"),
        ("salmon",           "🐟"),
        ("tuna",             "🐟"),
        ("fish",             "🐟"),
        ("shrimp",           "🦐"),
        ("tofu",             "🌱"),
        ("almond",           "🥜"),
        ("peanut",           "🥜"),
        ("nuts",             "🥜"),
        ("yogurt",           "🥛"),
        ("cottage cheese",   "🧀"),
        ("cheese",           "🧀"),
        ("milk",             "🥛"),
        ("protein shake",    "🥤"),
        ("shake",            "🥤"),
        ("smoothie",         "🥤"),
        ("protein",          "🥩"),

        ("cereal",           "🥣"),
        ("oatmeal",          "🥣"),
        ("oats",             "🥣"),
        ("porridge",         "🥣"),
        ("granola",          "🥣"),
        ("pancake",          "🥞"),
        ("waffle",           "🧇"),
        ("bagel",            "🥯"),
        ("toast",            "🍞"),
        ("bread",            "🍞"),
        ("croissant",        "🥐"),
        ("pizza",            "🍕"),
        ("burger",           "🍔"),
        ("sandwich",         "🥪"),
        ("burrito",          "🌯"),
        ("taco",             "🌮"),
        ("sushi",            "🍣"),
        ("rice",             "🍚"),
        ("ramen",            "🍜"),
        ("noodle",           "🍜"),
        ("pasta",            "🍝"),
        ("dessert",          "🍰"),
        ("ice cream",        "🍦"),

        ("water",            "💧"),
        ("hydrat",           "💧"),
        ("glass",            "💧"),
        ("coffee",           "☕"),
        ("espresso",         "☕"),
        ("matcha",           "🍵"),
        ("tea",              "🍵"),
        ("juice",            "🧃"),
        ("beer",             "🍺"),
        ("wine",             "🍷"),

        ("breakfast",        "🥣"),
        ("brunch",           "🍳"),
        ("lunch",            "🥗"),
        ("dinner",           "🍽️"),
        ("supper",           "🍽️"),
        ("snack",            "🍎"),
        ("3 meals",          "🍱"),
        ("three meals",      "🍱"),
        ("meal prep",        "🍱"),
        ("macro",            "📋"),
        ("calorie",          "🔥"),
        ("calories",         "🔥"),
        ("fasting",          "⏳"),
        ("fast ",            "⏳"),

        ("deadlift",         "🏋️"),
        ("bench press",      "🏋️"),
        ("squat",            "🦵"),
        ("pushup",           "💪"),
        ("push-up",          "💪"),
        ("push up",          "💪"),
        ("pullup",           "🤸"),
        ("pull-up",          "🤸"),
        ("pull up",          "🤸"),
        ("plank",            "🧍"),
        ("burpee",           "🤸"),
        ("lunge",            "🦵"),
        ("curl",             "💪"),
        ("row ",             "🚣"),
        ("rowing",           "🚣"),
        ("press",            "🏋️"),
        ("abs",              "🧍"),
        ("core",             "🧍"),
        ("leg day",          "🦵"),
        ("leg ",             "🦵"),
        ("arm day",          "💪"),
        ("arm ",             "💪"),
        ("back day",         "🏋️"),
        ("chest",            "🏋️"),
        ("shoulder",         "🏋️"),
        ("glute",            "🍑"),
        ("calf",             "🦵"),
        ("calves",           "🦵"),

        ("yoga",             "🧘‍♀️"),
        ("pilates",          "🧘‍♀️"),
        ("meditat",          "🧘‍♂️"),
        ("mindful",          "🧘‍♂️"),
        ("stretch",          "🧘"),
        ("flexibility",      "🧘"),
        ("mobility",         "🧘"),
        ("boxing",           "🥊"),
        ("kickbox",          "🥊"),
        ("punch",            "🥊"),
        ("martial",          "🥋"),
        ("karate",           "🥋"),

        ("basketball",       "🏀"),
        ("soccer",           "⚽"),
        ("football",         "🏈"),
        ("baseball",         "⚾"),
        ("tennis",           "🎾"),
        ("golf",             "⛳"),
        ("ping pong",        "🏓"),
        ("table tennis",     "🏓"),
        ("volleyball",       "🏐"),
        ("frisbee",          "🥏"),
        ("ski",              "🎿"),
        ("snowboard",        "🏂"),
        ("skate",            "⛸️"),
        ("surf",             "🏄"),
        ("climb",            "🧗"),
        ("boulder",          "🧗"),

        ("marathon",         "🏃"),
        ("5k",               "🏁"),
        ("10k run",          "🏁"),
        ("sprint",           "💨"),
        ("jog",              "🏃"),
        ("run ",             "🏃"),
        ("running",          "🏃"),
        ("hike",             "🥾"),
        ("trail",            "🥾"),
        ("cycle",            "🚴"),
        ("biking",           "🚴"),
        ("bike ride",        "🚴"),
        ("ride",             "🚴"),
        ("spin class",       "🚴"),
        ("swim",             "🏊"),
        ("pool",             "🏊"),
        ("cardio",           "❤️"),

        ("sleep",            "😴"),
        ("bedtime",          "😴"),
        ("rest day",         "🛌"),
        ("recovery",         "🛌"),
        ("recover",          "🛌"),
        ("strain",           "⚡"),
        ("active min",       "⏱️"),
        ("minutes",          "⏱️"),
        ("duration",         "⏱️"),
        ("burn",             "🔥"),
        ("scale",            "⚖️"),
        ("weigh",            "⚖️"),
        ("weight in",        "⚖️"),

        ("early bird",       "🌅"),
        ("sunrise",          "🌅"),
        ("morning",          "🌅"),
        ("am workout",       "🌅"),
        ("evening",          "🌇"),
        ("sunset",           "🌇"),
        ("night",            "🌙"),
        ("late",             "🌙"),
        ("noon",             "☀️"),
        ("afternoon",        "☀️"),

        ("streak",           "🔥"),
        ("personal record",  "🏆"),
        ("personal best",    "🏆"),
        (" pr ",             "🏆"),
        ("beat your",        "🏆"),
        ("trophy",           "🏆"),
        ("first place",      "🥇"),
        ("1st",              "🥇"),
        ("top 3",            "🥇"),
        ("leaderboard",      "🥇"),
        ("rank",             "🥇"),
        ("league",           "🏆"),

        ("1v1",              "⚔️"),
        ("duel",             "⚔️"),
        ("challenge",        "⚔️"),
        ("rival",            "😎"),
        ("hype",             "👏"),
        ("cheer",            "📣"),
        ("clap",             "👏"),
        ("applaud",          "👏"),
        ("react",            "👏"),
        ("comment",          "💬"),
        ("invite",           "💌"),
        ("share",            "📣"),
        ("crew",             "👯"),
        ("squad",            "👯"),
        ("group",            "👯"),
        ("contact",          "📇"),
        ("buddy",            "🤝"),
        ("friend",           "🤝"),

        ("dashboard",        "📊"),
        ("progress",         "📊"),
        ("track",            "📊"),
        ("journal",          "📓"),
        ("log",              "📝"),
        ("photo",            "📸"),
        ("selfie",           "📸"),

        ("perfect",          "🌟"),
        ("explore",          "🧭"),
        ("discover",         "🧭"),
        ("favorite",         "⭐"),
        ("rainbow",          "🌈"),
        ("treasure",         "💰"),
        ("rocket",           "🚀"),
        ("launch",           "🚀"),
        ("celebration",      "🎉"),
        ("party",            "🎉"),
        ("magic",            "🪄"),
        ("lucky",            "🍀"),
        ("luck",             "🍀"),
        ("secret",           "🤫"),

        ("watch ad",         "📺"),
        ("ads",              "📺"),
        ("video",            "📺"),
        ("bonus",            "🎁"),
        ("reward",           "🎁"),
        ("gift",             "🎁"),
        ("coin",             "🪙"),
        ("token",            "🪙"),
        ("diamond",          "💎"),
        ("premium",          "💎"),

        ("outdoor",          "🌳"),
        ("outside",          "🌳"),
        ("park",             "🌳"),
        ("indoor",           "🏠"),
        ("home workout",     "🏠"),
        ("gym",              "🏋️"),
        ("segment",          "📍"),
        ("mountain",         "🏔️"),
        ("summit",           "🏔️"),

        ("first workout",    "🎬"),
        ("first time",       "🎬"),
        ("welcome",          "👋"),
        ("beginner",         "🎬"),

        ("workout",          "💪"),
        ("exercise",         "💪"),
        ("training",         "💪"),
        ("lift",             "🏋️"),
        ("sets",             "🎯"),
        ("reps",             "🎯"),
        ("walk",             "🚶"),
        ("step",             "👟"),
        ("nutrition",        "🥗"),
        ("meal",             "🍽️")
    ]

    private static let categoryFallback: [String: String] = [
        "workout":   "💪",
        "nutrition": "🥗",
        "social":    "👥",
        "steps":     "👟",
        "tracking":  "📊",
        "wildcard":  "🌟",
        "reward":    "🎁",
        "recovery":  "🛌",
        "wellness":  "🧘"
    ]
}

private extension Character {
    var isLikelyEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && scalar.value > 0x238C
    }
}
