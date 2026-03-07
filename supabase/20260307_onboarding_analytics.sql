-- Onboarding step analytics for tracking drop-off and completion rates
-- Used by OnboardingSessionManager to log per-step timing data

CREATE TABLE IF NOT EXISTS onboarding_analytics (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    session_id TEXT NOT NULL,
    step_name TEXT NOT NULL,
    step_index INTEGER NOT NULL,
    duration_seconds NUMERIC,
    completed BOOLEAN DEFAULT false,
    drop_off BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE onboarding_analytics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own analytics"
    ON onboarding_analytics FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can read own analytics"
    ON onboarding_analytics FOR SELECT
    USING (auth.uid() = user_id);

CREATE INDEX idx_onboarding_analytics_user ON onboarding_analytics(user_id);
CREATE INDEX idx_onboarding_analytics_session ON onboarding_analytics(session_id);
CREATE INDEX idx_onboarding_analytics_step ON onboarding_analytics(step_name, completed);
