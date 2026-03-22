-- FAQ System Schema + Seed Data
-- Owner: Support & Knowledge Agent
-- Date: 2026-03-22

BEGIN;

-- ============================================================================
-- 1. faq_categories
-- ============================================================================

CREATE TABLE IF NOT EXISTS faq_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  slug TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  display_order INT NOT NULL DEFAULT 0,
  icon TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_categories_order ON faq_categories(display_order);

ALTER TABLE faq_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages faq_categories" ON faq_categories;
CREATE POLICY "Service role manages faq_categories"
  ON faq_categories FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 2. faq_entries
-- ============================================================================

CREATE TABLE IF NOT EXISTS faq_entries (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  entry_id TEXT UNIQUE NOT NULL,
  category_id UUID REFERENCES faq_categories(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  answer TEXT NOT NULL,
  keywords TEXT[] DEFAULT '{}',
  channel TEXT DEFAULT 'both' CHECK (channel IN ('web', 'app', 'both')),
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
  display_order INT NOT NULL DEFAULT 0,
  auto_generated BOOLEAN DEFAULT false,
  source_commit TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_faq_entries_category ON faq_entries(category_id);
CREATE INDEX IF NOT EXISTS idx_faq_entries_status ON faq_entries(status);
CREATE INDEX IF NOT EXISTS idx_faq_entries_entry_id ON faq_entries(entry_id);

ALTER TABLE faq_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role manages faq_entries" ON faq_entries;
CREATE POLICY "Service role manages faq_entries"
  ON faq_entries FOR ALL USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Public can read published faq_entries" ON faq_entries;
CREATE POLICY "Public can read published faq_entries"
  ON faq_entries FOR SELECT USING (status = 'published');

DROP POLICY IF EXISTS "Public can read faq_categories" ON faq_categories;
CREATE POLICY "Public can read faq_categories"
  ON faq_categories FOR SELECT USING (true);

-- ============================================================================
-- 3. Seed Categories
-- ============================================================================

INSERT INTO faq_categories (slug, name, display_order, icon) VALUES
  ('getting-started',       'Getting Started',        1,  '🚀'),
  ('workouts-exercises',    'Workouts & Exercises',   2,  '💪'),
  ('smart-programs',        'Smart Programs',         3,  '📋'),
  ('nutrition-meals',       'Nutrition & Meals',      4,  '🍎'),
  ('social-challenges',     'Social & Challenges',    5,  '👥'),
  ('gamification-progress', 'Gamification & Progress',6,  '🏆'),
  ('health-integrations',   'Health Integrations',    7,  '❤️'),
  ('tracking-body-stats',   'Tracking & Body Stats',  8,  '📊'),
  ('account-settings',      'Account & Settings',     9,  '⚙️'),
  ('troubleshooting',       'Troubleshooting',        10, '🔧'),
  ('running-cardio',        'Running & Cardio',       11, '🏃')
ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- 4. Seed FAQ Entries (87 entries from FAQ_PLAN.md)
-- ============================================================================

-- Getting Started (8)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('GS-1', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'How do I create an account?', 'Sign up with email, Apple, Google, or Facebook. Tap "Get Started" on the launch screen.', 'published', 1),
('GS-2', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'What happens during onboarding?', '13-step quiz: name, age, body stats, goals, equipment, experience, schedule, limitations, phone verify. Takes about 3 minutes.', 'published', 2),
('GS-3', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'Can I skip the onboarding quiz?', 'No — the quiz personalizes your workouts, programs, and nutrition. Every answer matters.', 'published', 3),
('GS-4', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'How do I reset my onboarding answers?', 'Settings → Profile → Edit any field (goals, equipment, experience, limitations).', 'published', 4),
('GS-5', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'Why do you need my phone number?', 'Phone verification prevents fake accounts and enables friend discovery via contacts. You can skip it.', 'published', 5),
('GS-6', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'What are the 5 tabs?', 'Home (dashboard), Workout (generator + history), Social (friends + challenges), Meals (nutrition), Stats (progress).', 'published', 6),
('GS-7', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'Is Fit33 free?', 'Yes — all core features are free. Premium features coming soon.', 'published', 7),
('GS-8', (SELECT id FROM faq_categories WHERE slug = 'getting-started'), 'What devices does Fit33 support?', 'iPhone running iOS 17 or later. iPad support is planned.', 'published', 8)
ON CONFLICT (entry_id) DO NOTHING;

-- Workouts & Exercises (12)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('WK-1', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'How do I start a workout?', 'Workout tab → "Surprise Me" (auto-generate) or "Build Custom" (manual).', 'published', 1),
('WK-2', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'What is "Surprise Me"?', 'AI generates a personalized workout based on your goals, equipment, experience, history, and limitations.', 'published', 2),
('WK-3', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'How do I build a custom workout?', 'Workout tab → Build Custom → search/filter 7,000+ exercises → add to workout → set reps/sets → GO!', 'published', 3),
('WK-4', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'How do I log a set during a workout?', 'Tap the set row → enter weight and reps → tap checkmark. The rest timer starts automatically.', 'published', 4),
('WK-5', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'Can I swap an exercise mid-workout?', 'Yes — tap the exercise name → "Swap" → choose a smart suggestion (same muscle group + equipment).', 'published', 5),
('WK-6', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'How do I reorder exercises?', 'Long-press an exercise → drag to new position.', 'published', 6),
('WK-7', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'What are supersets?', 'Two exercises performed back-to-back with no rest between. Tap "Superset" to pair exercises.', 'published', 7),
('WK-8', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'How does the rest timer work?', 'Auto-starts after logging a set. Default rest varies by exercise type. Tap timer to adjust or skip.', 'published', 8),
('WK-9', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'Where is my workout history?', 'Workout tab → History section. Tap any past workout to see full details.', 'published', 9),
('WK-10', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'Why did I get this specific exercise?', 'Auto-gen considers: your goals, equipment, experience level, physical limitations, and recent workout history to avoid repeats.', 'published', 10),
('WK-11', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'Does Fit33 have warm-ups?', 'Yes — a smart warm-up is auto-generated based on the muscles in your workout. Toggle it on before starting.', 'published', 11),
('WK-12', (SELECT id FROM faq_categories WHERE slug = 'workouts-exercises'), 'Can I stretch after my workout?', 'Yes — tap "Stretch Mode" after finishing. Guided stretches target the muscles you just worked.', 'published', 12)
ON CONFLICT (entry_id) DO NOTHING;

-- Smart Programs (6)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('SP-1', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'What are Smart Programs?', 'AI-generated multi-day training plans (7, 14, 21, or 30 days) with progressive overload and periodization.', 'published', 1),
('SP-2', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'How do I start a program?', 'Workout tab → Programs → Browse → Select a program → Start. Your daily workout appears on the home screen.', 'published', 2),
('SP-3', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'Can I customize my program?', 'Yes — swap exercises, adjust sets/reps, skip days. The program adapts around your changes.', 'published', 3),
('SP-4', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'What happens if I miss a program day?', 'The program shifts forward. No penalty — just pick up where you left off.', 'published', 4),
('SP-5', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'What is a deload week?', 'A planned easier week (reduced volume/intensity) to prevent overtraining. Built into longer programs automatically.', 'published', 5),
('SP-6', (SELECT id FROM faq_categories WHERE slug = 'smart-programs'), 'How is a program different from a workout?', 'A workout is a single session. A program is a structured multi-day plan with progression built in.', 'published', 6)
ON CONFLICT (entry_id) DO NOTHING;

-- Nutrition & Meals (10)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('NM-1', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'How do I log food?', 'Meals tab → tap a meal slot (Breakfast/Lunch/Dinner/Snack) → search or scan barcode.', 'published', 1),
('NM-2', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'How does the barcode scanner work?', 'Meals tab → tap barcode icon → point camera at product barcode → nutrition data auto-fills.', 'published', 2),
('NM-3', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'Why can''t I find my food?', 'We use the USDA FoodData Central database. Some branded products may not be listed. Try generic terms (e.g., "chicken breast" instead of a brand name).', 'published', 3),
('NM-4', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'How do I set my calorie/macro goals?', 'Settings → Nutrition Goals. Or let Fit33 calculate them based on your body stats and goals.', 'published', 4),
('NM-5', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'Where do I see my daily macros?', 'Meals tab — the macro ring at the top shows calories, protein, carbs, and fat progress.', 'published', 5),
('NM-6', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'How do I save a meal for quick logging?', 'After logging a meal → tap "Save Meal" → name it. Find saved meals in the "Saved" tab.', 'published', 6),
('NM-7', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'How do I find recipes?', 'Meals tab → Recipes → browse by goal, cuisine, or dietary preference. Powered by Spoonacular.', 'published', 7),
('NM-8', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'Can I import a recipe from a URL?', 'Yes — Meals tab → Recipes → Import → paste any recipe URL. We extract ingredients and nutrition.', 'published', 8),
('NM-9', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'What is "What to Eat Right Now"?', 'A smart suggestion based on time of day, your remaining macro budget, and your preferences.', 'published', 9),
('NM-10', (SELECT id FROM faq_categories WHERE slug = 'nutrition-meals'), 'Where is my shopping list?', 'Meals tab → Shopping List. Auto-generated from your meal plan.', 'published', 10)
ON CONFLICT (entry_id) DO NOTHING;

-- Social & Challenges (8)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('SC-1', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'How do I add friends?', 'Social tab → Add Friends → QR code, search by name, or import from contacts.', 'published', 1),
('SC-2', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'How do I challenge a friend?', 'Social tab → tap a friend → "Challenge" → choose type (steps, workouts, streaks, etc.) → set duration → send.', 'published', 2),
('SC-3', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'Can I challenge multiple friends at once?', 'Yes — create a Group Challenge. Social tab → Challenges → Create → add multiple friends.', 'published', 3),
('SC-4', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'What are Community Challenges?', 'Public challenges anyone can join. Social tab → Community → browse active challenges → join.', 'published', 4),
('SC-5', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'How do I share my workout?', 'After finishing a workout → tap "Share" → select friends to send it to. They can view your full workout.', 'published', 5),
('SC-6', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'Can I see my friend''s workouts?', 'Yes — tap their profile in the Social tab to see their recent activity, stats, and shared workouts.', 'published', 6),
('SC-7', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'Where do I see rankings?', 'Social tab → Rankings. Leaderboards by XP, streaks, workouts completed, and more.', 'published', 7),
('SC-8', (SELECT id FROM faq_categories WHERE slug = 'social-challenges'), 'How do I react to a friend''s activity?', 'Tap the reaction icon on any friend activity in your feed.', 'published', 8)
ON CONFLICT (entry_id) DO NOTHING;

-- Gamification & Progress (9)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('GP-1', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'How do I earn XP?', 'Complete workouts, finish daily quests, win challenges, hit streaks. XP earns you levels.', 'published', 1),
('GP-2', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'What are levels?', 'Your fitness rank based on total XP earned. Higher levels unlock bragging rights and future rewards.', 'published', 2),
('GP-3', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'What are Daily Quests?', '3 new quests every day (e.g., "Log 2 meals", "Complete a workout", "Drink 8 glasses of water"). Earn bonus XP.', 'published', 3),
('GP-4', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'When do Daily Quests reset?', 'Midnight in your local timezone.', 'published', 4),
('GP-5', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'What are Weekly Leagues?', 'Duolingo-style tiered leagues. Compete with other users weekly. Top performers promote to higher tiers.', 'published', 5),
('GP-6', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'How do streaks work?', 'Complete at least one workout per day to build your streak. Consecutive days = longer streak.', 'published', 6),
('GP-7', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'I lost my streak! Can I get it back?', 'Use a Streak Shield — it protects your streak for one missed day. Shields are limited, so use them wisely.', 'published', 7),
('GP-8', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'How are Personal Records tracked?', 'Automatically. When you lift more weight or do more reps than your previous best, you''ll see a PR badge. View all PRs in Stats.', 'published', 8),
('GP-9', (SELECT id FROM faq_categories WHERE slug = 'gamification-progress'), 'How do I unlock achievements?', 'Hit milestones (first workout, 7-day streak, 100 workouts, etc.). View all achievements in Stats → Achievements.', 'published', 9)
ON CONFLICT (entry_id) DO NOTHING;

-- Health Integrations (6)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('HI-1', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'How do I connect Apple Health?', 'Settings → Integrations → Apple Health → Allow. Steps, workouts, and weight sync automatically.', 'published', 1),
('HI-2', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'How do I connect Strava?', 'Settings → Integrations → Strava → Authorize. Running and cycling activities sync both ways.', 'published', 2),
('HI-3', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'How do I connect Fitbit?', 'Settings → Integrations → Fitbit → Log in. Steps, heart rate, and sleep data sync to Fit33.', 'published', 3),
('HI-4', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'How do I import InBody scans?', 'Stats → Body Composition → Import InBody → scan QR code or enter results. Data appears in Stats.', 'published', 4),
('HI-5', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'How do I connect Bluetooth gym equipment?', 'Active workout → tap Bluetooth icon → select your treadmill, bike, or rower. Auto-detects nearby devices.', 'published', 5),
('HI-6', (SELECT id FROM faq_categories WHERE slug = 'health-integrations'), 'Does step data count toward challenges?', 'Yes — if Apple Health or Fitbit is connected, steps auto-count toward step-based challenges.', 'published', 6)
ON CONFLICT (entry_id) DO NOTHING;

-- Tracking & Body Stats (7)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('TB-1', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'How do I log my weight?', 'Home tab → Weight widget → tap to enter today''s weight. Also syncs from Apple Health.', 'published', 1),
('TB-2', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'How do I track body fat?', 'Stats → Body Composition. Enter manually or import from InBody scans.', 'published', 2),
('TB-3', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'How do I track water intake?', 'Home tab → Hydration widget → tap glasses to log water throughout the day.', 'published', 3),
('TB-4', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'Where do I see my steps?', 'Home tab → Steps widget. Pulled from Apple Health or Fitbit.', 'published', 4),
('TB-5', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'What is the muscle heatmap?', 'Stats → Muscle Heatmap. Visual showing which muscles you''ve trained recently and how often. Darker = more trained.', 'published', 5),
('TB-6', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'What are Activity Rings?', 'Visual rings showing daily movement, exercise, and stand goals — similar to Apple Watch rings.', 'published', 6),
('TB-7', (SELECT id FROM faq_categories WHERE slug = 'tracking-body-stats'), 'How do I switch between kg and lbs?', 'Settings → Units → toggle between Metric and Imperial. Applies everywhere instantly.', 'published', 7)
ON CONFLICT (entry_id) DO NOTHING;

-- Account & Settings (7)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('AS-1', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'How do I change my profile?', 'Settings → Profile. Edit name, photo, goals, equipment, experience, and limitations.', 'published', 1),
('AS-2', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'How do I change my fitness goals?', 'Settings → Profile → Goals. Your workouts and programs will adapt to your new goals.', 'published', 2),
('AS-3', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'Is my data backed up?', 'Yes — all data syncs to the cloud automatically when you''re signed in.', 'published', 3),
('AS-4', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'Can I download my data?', 'Yes — Settings → Privacy → Download My Data. You''ll receive a full export.', 'published', 4),
('AS-5', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'How do I turn off notifications?', 'Settings → Notifications. Toggle individual notification types on/off.', 'published', 5),
('AS-6', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'How do I delete my account?', 'Settings → Account → Delete Account. This permanently removes all your data.', 'published', 6),
('AS-7', (SELECT id FROM faq_categories WHERE slug = 'account-settings'), 'Where is the privacy policy?', 'Settings → Privacy Policy. Also at fit33app.com/privacy.html.', 'published', 7)
ON CONFLICT (entry_id) DO NOTHING;

-- Troubleshooting (10)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('TS-1', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'The app crashed during my workout — is my data saved?', 'Yes — workout progress is saved locally every time you log a set. Reopen the app to resume.', 'published', 1),
('TS-2', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'My workout data isn''t syncing', 'Check internet connection. Go to Settings → Cloud Backup → Force Sync. If the issue persists, report a bug.', 'published', 2),
('TS-3', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'I can''t find a specific food', 'Try generic terms instead of brand names. Use the barcode scanner for packaged foods. The USDA database covers most whole foods.', 'published', 3),
('TS-4', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'My streak disappeared', 'Streaks require one workout per calendar day (midnight-to-midnight in your timezone). Use Streak Shields to protect missed days. If this seems like a bug, report it.', 'published', 4),
('TS-5', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'Challenge progress shows wrong numbers', 'Known issue with timezone differences. We''re actively fixing this. Your data is accurate — only the display timing may be off.', 'published', 5),
('TS-6', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'The app doesn''t work offline', 'Some features require internet (food search, cloud sync, challenges). Workouts can be logged offline and will sync when reconnected.', 'published', 6),
('TS-7', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'Exercise videos won''t play', 'Check your internet connection. Videos stream on demand. Try closing and reopening the exercise. If the issue persists, report a bug.', 'published', 7),
('TS-8', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'Push notifications aren''t working', 'Settings (iOS) → Fit33 → Notifications → ensure enabled. Also check in-app: Settings → Notifications.', 'published', 8),
('TS-9', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'The app feels slow or laggy', 'Try force-closing and reopening. Ensure you''re on the latest version. If performance issues persist, report a bug with your device model and iOS version.', 'published', 9),
('TS-10', (SELECT id FROM faq_categories WHERE slug = 'troubleshooting'), 'How do I report a bug?', 'Settings → Contact Support → Report a Bug. Include what happened, what you expected, and whether it''s reproducible. Attach session logs if possible.', 'published', 10)
ON CONFLICT (entry_id) DO NOTHING;

-- Running & Cardio (4)
INSERT INTO faq_entries (entry_id, category_id, question, answer, status, display_order) VALUES
('RC-1', (SELECT id FROM faq_categories WHERE slug = 'running-cardio'), 'How do I track an outdoor run?', 'Workout tab → Running → Start Run. GPS tracks your route, pace, and distance with Live Activities on lock screen.', 'published', 1),
('RC-2', (SELECT id FROM faq_categories WHERE slug = 'running-cardio'), 'Can I log treadmill workouts?', 'Yes — Workout tab → Cardio → select treadmill. Enter distance/time manually or connect via Bluetooth.', 'published', 2),
('RC-3', (SELECT id FROM faq_categories WHERE slug = 'running-cardio'), 'How do I set a running goal?', 'Workout tab → Running → Goals → set a distance, time, or calorie target.', 'published', 3),
('RC-4', (SELECT id FROM faq_categories WHERE slug = 'running-cardio'), 'Does running count toward my streak?', 'Yes — any completed workout (strength, cardio, running) counts toward your daily streak.', 'published', 4)
ON CONFLICT (entry_id) DO NOTHING;

-- ============================================================================
-- 5. Verification
-- ============================================================================

DO $$
DECLARE
  cat_count INT;
  entry_count INT;
BEGIN
  SELECT COUNT(*) INTO cat_count FROM faq_categories;
  SELECT COUNT(*) INTO entry_count FROM faq_entries;
  RAISE NOTICE 'FAQ system created: % categories, % entries', cat_count, entry_count;
END $$;

COMMIT;
