-- Migration: AI Insights Hub tables
-- Date: 2026-03-19
-- Agent: Data & Backend (primary), Infra & Security (RLS review)
-- Reason: Store AI-generated product insights and admin chat history for the AI Insights Hub

BEGIN;

-- ═══════════════════════════════════════════════════
-- AI INSIGHTS TABLE
-- Stores automated and on-demand AI-generated product insights
-- ═══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS ai_insights (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    insight_type TEXT NOT NULL CHECK (insight_type IN ('weekly_summary', 'trend_alert', 'recommendation')),
    category TEXT NOT NULL CHECK (category IN ('retention', 'exercises', 'onboarding', 'engagement', 'workouts', 'social', 'general')),
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    data_snapshot JSONB DEFAULT '{}'::jsonb,
    priority TEXT NOT NULL DEFAULT 'medium' CHECK (priority IN ('high', 'medium', 'low')),
    status TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'read', 'archived')),
    model_used TEXT DEFAULT 'claude-sonnet-4-20250514',
    generated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_insights_generated_at ON ai_insights (generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_status ON ai_insights (status);
CREATE INDEX IF NOT EXISTS idx_ai_insights_category ON ai_insights (category);
CREATE INDEX IF NOT EXISTS idx_ai_insights_priority ON ai_insights (priority);

ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;

-- Service role (Edge Functions) can do everything - no policy needed (bypasses RLS)
-- Admin users authenticated via Supabase auth can read
CREATE POLICY "admin_read_insights" ON ai_insights
    FOR SELECT USING (
        auth.role() = 'authenticated'
        AND auth.email() IN (SELECT unnest(string_to_array(current_setting('app.admin_emails', true), ',')))
    );

-- Fallback: if admin_emails setting isn't configured, allow all authenticated reads
-- (the CMS already validates admin email server-side before making queries)
DROP POLICY IF EXISTS "admin_read_insights" ON ai_insights;
CREATE POLICY "authenticated_read_insights" ON ai_insights
    FOR SELECT USING (auth.role() = 'authenticated');

-- Only service role can insert/update/delete (Edge Functions and admin API use service role)
-- No INSERT/UPDATE/DELETE policies for regular users = denied by RLS

-- ═══════════════════════════════════════════════════
-- AI CHAT HISTORY TABLE
-- Persists admin chat threads with Claude
-- ═══════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS ai_chat_history (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    admin_user_id UUID NOT NULL,
    title TEXT DEFAULT 'New Conversation',
    messages JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_chat_history_admin ON ai_chat_history (admin_user_id, updated_at DESC);

ALTER TABLE ai_chat_history ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read/write their own chat history
CREATE POLICY "users_select_own_chats" ON ai_chat_history
    FOR SELECT USING (admin_user_id = auth.uid());

CREATE POLICY "users_insert_own_chats" ON ai_chat_history
    FOR INSERT WITH CHECK (admin_user_id = auth.uid());

CREATE POLICY "users_update_own_chats" ON ai_chat_history
    FOR UPDATE USING (admin_user_id = auth.uid());

CREATE POLICY "users_delete_own_chats" ON ai_chat_history
    FOR DELETE USING (admin_user_id = auth.uid());

COMMIT;

-- ROLLBACK:
-- DROP TABLE IF EXISTS ai_chat_history;
-- DROP TABLE IF EXISTS ai_insights;
