-- Add missing equipment column to user_similarity_profiles
-- CollaborativeLearningEngine.swift upserts with this column but it was
-- never added to the live table (only exists in docs/COLLABORATIVE_LEARNING_SCHEMA.sql)

ALTER TABLE user_similarity_profiles
ADD COLUMN IF NOT EXISTS equipment TEXT[] NOT NULL DEFAULT '{}';
