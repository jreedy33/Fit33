-- Add calories_burned column to workout_history for strength workout calorie tracking
ALTER TABLE workout_history
  ADD COLUMN IF NOT EXISTS calories_burned DOUBLE PRECISION DEFAULT NULL;

-- Index for queries that filter/sort by calories
CREATE INDEX IF NOT EXISTS idx_workout_history_calories
  ON workout_history (calories_burned)
  WHERE calories_burned IS NOT NULL;
