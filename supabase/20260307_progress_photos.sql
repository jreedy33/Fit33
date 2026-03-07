-- Migration: Progress Photos table
-- Date: 2026-03-07
-- Agent: Data & Backend
-- Reason: Support progress photo tracking with metadata for smart comparison feature

BEGIN;

CREATE TABLE IF NOT EXISTS progress_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
    photo_type TEXT CHECK (photo_type IN ('front', 'side', 'back')) NOT NULL,
    local_filename TEXT NOT NULL,
    cloud_url TEXT,
    weight_at_capture FLOAT,
    body_fat_at_capture FLOAT,
    program_name TEXT,
    program_week INT,
    notes TEXT,
    taken_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE progress_photos ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_select_own_progress_photos" ON progress_photos
FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "users_insert_own_progress_photos" ON progress_photos
FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "users_update_own_progress_photos" ON progress_photos
FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "users_delete_own_progress_photos" ON progress_photos
FOR DELETE USING (user_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_progress_photos_user_date
ON progress_photos (user_id, taken_at DESC);

CREATE INDEX IF NOT EXISTS idx_progress_photos_user_type
ON progress_photos (user_id, photo_type, taken_at DESC);

COMMIT;

-- ROLLBACK:
-- DROP TABLE IF EXISTS progress_photos;
