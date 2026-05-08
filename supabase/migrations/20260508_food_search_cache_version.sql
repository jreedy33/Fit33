-- ============================================================================
-- 20260508 — food_search_cache: add result_version for invalidation
-- ============================================================================
-- Adds a `result_version INTEGER` column so the edge function can invalidate
-- previously-cached search results without truncating the table.
--
-- Why this is needed (initial trigger — 2026-05-08 OFF photo rollout):
--   `food_search_cache.result_ids` is a list of `food_items.id`s captured
--   when a query was first fanned out to USDA + OFF + ranked. The 30-day TTL
--   means a search like "pringles" cached on 2026-04-15 (BEFORE the OFF
--   integration deployed 2026-04-30, see #20260801_food_items_off_barcode.sql)
--   contains ONLY USDA Branded ids — no OFF ids exist yet. On a cache HIT,
--   the edge function returns those USDA-only ids verbatim and NEVER re-runs
--   the OFF fan-out. So OFF photos for popular branded foods (Pringles,
--   Doritos, etc.) never reach the iOS thumbnail view, even though the OFF
--   integration is live and would return them on a cache miss.
--
--   Cache TTL alone doesn't fix this — it'd take 30 days for stale entries
--   to expire naturally, and every popular query would stay broken in the
--   meantime. A version bump invalidates the entire cache *immediately* on
--   the next deploy: the read path adds `result_version = $current` to the
--   filter, so old rows with the default (1) are treated as misses, and the
--   upsert overwrites them with the current version + freshly-merged ids.
--
-- Pattern (matches the bug-intel + canonical-muscle approach used elsewhere):
--   1. Edge function declares `CACHE_VERSION` constant (start at 2 — column
--      default is 1, so existing rows are auto-invalidated on first deploy).
--   2. Cache READ adds `.eq("result_version", CACHE_VERSION)` to the query.
--   3. Cache WRITE includes `result_version: CACHE_VERSION` in the upsert.
--   4. Future change to search/rank/merge logic → bump the constant by 1 →
--      next deploy auto-invalidates all stale entries; old rows get
--      overwritten by upsert (`onConflict: normalized_query`) on next hit;
--      truly cold queries are eventually evicted by the 30-day TTL.
--
-- Why not just TRUNCATE on every deploy:
--   TRUNCATE is stateful (operator must remember to run it), can't be
--   tracked in source control, and creates a brief warm-up window where
--   every query is a USDA round-trip (~3-8 RPS spike on a popular release).
--   The version column approach is declarative + replayable + the warmup
--   is naturally spread across the user base as queries trickle in.
--
-- Idempotency: `ADD COLUMN IF NOT EXISTS` — re-running this migration on a
-- DB that already has the column is a no-op (Data invariant #20). Default
-- is `1` so unfilled rows from before the deploy are uniformly invalid
-- against any `CACHE_VERSION >= 2`.
--
-- RLS: `food_search_cache` already has read-for-authenticated +
-- write-via-service-role from the original schema. No policy changes.
-- ============================================================================

BEGIN;

ALTER TABLE public.food_search_cache
    ADD COLUMN IF NOT EXISTS result_version INTEGER NOT NULL DEFAULT 1;

-- Index on (normalized_query, result_version) so the edge function's
-- combined filter is a single index seek rather than a normalized_query
-- seek + version filter. Partial — only the live-version rows participate
-- in the read path; old-version rows just sit there until the TTL evicts
-- them or the next upsert overwrites them.
CREATE INDEX IF NOT EXISTS food_search_cache_query_version_idx
    ON public.food_search_cache (normalized_query, result_version);

COMMIT;

-- Refresh PostgREST schema cache so the new column is visible to the
-- edge function immediately on deploy (SUPABASE invariant 30).
NOTIFY pgrst, 'reload schema';
