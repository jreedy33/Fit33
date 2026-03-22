-- Fix: Add updated_at column to insights tables
-- Resolves: "record new has no field updated_at" crash (b90b7245)
-- These tables have triggers that reference NEW.updated_at but the column was missing.

BEGIN;

ALTER TABLE IF EXISTS user_behavior_patterns
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE IF EXISTS user_personalized_insights
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE IF EXISTS user_performance_windows
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

COMMIT;
