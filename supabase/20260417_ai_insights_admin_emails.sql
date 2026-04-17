-- =============================================================================
-- AI Insights Admin Allowlist
-- =============================================================================
-- generate-ai-insights Edge Function previously accepted ANY valid user JWT,
-- which meant every signed-in app user could trigger cross-user data
-- aggregation + paid Anthropic calls.
--
-- This migration creates the allowlist table the function now consults.
-- Seed it with the app-team admin emails via the Supabase UI after applying.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.ai_insights_admin_emails (
    email TEXT PRIMARY KEY,
    added_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    note TEXT
);

ALTER TABLE public.ai_insights_admin_emails ENABLE ROW LEVEL SECURITY;

-- No policies => not readable by end users. Only service_role (RPC / edge
-- function) can SELECT via the service role bypass.

-- Handy index in case we later lookup by lowercased email via a function.
CREATE INDEX IF NOT EXISTS ai_insights_admin_emails_added_at_idx
  ON public.ai_insights_admin_emails (added_at DESC);

-- Seed row:
-- INSERT INTO public.ai_insights_admin_emails (email, note)
-- VALUES ('admin@doublethr33s.com', 'founding admin')
-- ON CONFLICT (email) DO NOTHING;
