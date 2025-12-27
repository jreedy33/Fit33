# Collaborative Learning Engine - Setup Guide

## Step-by-Step Setup in Supabase

### Step 1: Create Base Tables

Run these SQL statements **one at a time** in your Supabase SQL Editor:

```sql
-- Table 1: User Similarity Profiles
CREATE TABLE IF NOT EXISTS user_similarity_profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    goal TEXT NOT NULL,
    experience TEXT NOT NULL,
    equipment TEXT[] NOT NULL,
    age_range TEXT,
    gender TEXT,
    workout_location TEXT,
    total_workouts_completed INT DEFAULT 0,
    avg_workout_duration INT DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_user_similarity_goal ON user_similarity_profiles(goal);
CREATE INDEX idx_user_similarity_experience ON user_similarity_profiles(experience);
```

```sql
-- Table 2: Collaborative Workout Data
CREATE TABLE IF NOT EXISTS collaborative_workout_data (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    workout_type TEXT NOT NULL,
    program_id TEXT,
    exercises JSONB NOT NULL,
    was_successful BOOLEAN DEFAULT true,
    user_goal TEXT,
    user_experience TEXT,
    user_equipment TEXT[],
    duration_minutes INT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_collab_workout_user ON collaborative_workout_data(user_id);
CREATE INDEX idx_collab_workout_goal ON collaborative_workout_data(user_goal);
CREATE INDEX idx_collab_workout_type ON collaborative_workout_data(workout_type);
CREATE INDEX idx_collab_workout_date ON collaborative_workout_data(completed_at);
```

```sql
-- Table 3: Exercise Pairings
CREATE TABLE IF NOT EXISTS exercise_pairings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    exercise_1 TEXT NOT NULL,
    exercise_2 TEXT NOT NULL,
    muscle_group_1 TEXT,
    muscle_group_2 TEXT,
    equipment_1 TEXT,
    equipment_2 TEXT,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_pairing_ex1 ON exercise_pairings(exercise_1);
CREATE INDEX idx_pairing_ex2 ON exercise_pairings(exercise_2);
```

```sql
-- Table 4: Program Completions
CREATE TABLE IF NOT EXISTS collaborative_program_completions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    program_id TEXT NOT NULL,
    program_name TEXT NOT NULL,
    template_id TEXT NOT NULL,
    total_days INT NOT NULL,
    completed_days INT NOT NULL,
    completion_rate DECIMAL(3,2),
    user_goal TEXT,
    user_experience TEXT,
    completed_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_program_completion_user ON collaborative_program_completions(user_id);
CREATE INDEX idx_program_completion_template ON collaborative_program_completions(template_id);
CREATE INDEX idx_program_completion_rate ON collaborative_program_completions(completion_rate);
```

```sql
-- Table 5: User Exercise Preferences
CREATE TABLE IF NOT EXISTS user_exercise_preferences (
    user_id UUID REFERENCES auth.users(id),
    exercise_name TEXT NOT NULL,
    personal_score DECIMAL(5,4) DEFAULT 0,
    collaborative_score DECIMAL(5,4) DEFAULT 0,
    combined_score DECIMAL(5,4),
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (user_id, exercise_name)
);

CREATE INDEX idx_user_exercise_pref_score ON user_exercise_preferences(combined_score DESC);
```

---

### Step 2: Enable Row Level Security

```sql
-- Enable RLS
ALTER TABLE collaborative_workout_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE collaborative_program_completions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_similarity_profiles ENABLE ROW LEVEL SECURITY;

-- Insert policies - users can only add their own data
CREATE POLICY "Users can insert own workout data" ON collaborative_workout_data
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can insert own program completions" ON collaborative_program_completions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can manage own similarity profile" ON user_similarity_profiles
    FOR ALL USING (auth.uid() = user_id);

-- Select policies - authenticated users can read aggregated data
CREATE POLICY "Authenticated users can read workout data" ON collaborative_workout_data
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can read program completions" ON collaborative_program_completions
    FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Authenticated users can read similarity profiles" ON user_similarity_profiles
    FOR SELECT USING (auth.role() = 'authenticated');
```

---

### Step 3: Create Aggregation Views (AFTER you have some data)

**⚠️ Important**: Only create these views AFTER users have completed some workouts (otherwise they'll be empty).

```sql
-- View 1: Exercise Pairing Stats
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_pairing_stats AS
SELECT 
    ep.exercise_1,
    ep.exercise_2,
    ep.muscle_group_1,
    ep.muscle_group_2,
    COUNT(*) as co_occurrence_count,
    COUNT(DISTINCT ep.recorded_at::date) as days_seen_together
FROM exercise_pairings ep
GROUP BY ep.exercise_1, ep.exercise_2, ep.muscle_group_1, ep.muscle_group_2
HAVING COUNT(*) >= 5;

CREATE UNIQUE INDEX IF NOT EXISTS idx_pairing_stats ON exercise_pairing_stats(exercise_1, exercise_2);
```

```sql
-- View 2: Program Success Stats
CREATE MATERIALIZED VIEW IF NOT EXISTS program_success_stats AS
SELECT 
    template_id,
    program_name,
    COUNT(*) as completion_count,
    AVG(completion_rate) as avg_completion_rate,
    array_agg(DISTINCT user_id::text) as user_ids
FROM collaborative_program_completions
GROUP BY template_id, program_name
HAVING COUNT(*) >= 3;

CREATE INDEX IF NOT EXISTS idx_program_success_rate ON program_success_stats(avg_completion_rate DESC);
```

```sql
-- View 3: Exercise Global Stats
CREATE MATERIALIZED VIEW IF NOT EXISTS exercise_global_stats AS
WITH exercise_data AS (
    SELECT 
        jsonb_array_elements(exercises)->>'name' as exercise_name,
        was_successful
    FROM collaborative_workout_data
)
SELECT 
    LOWER(exercise_name) as exercise_name,
    COUNT(*) as completion_count,
    AVG(CASE WHEN was_successful THEN 1.0 ELSE 0.0 END) as success_rate
FROM exercise_data
WHERE exercise_name IS NOT NULL
GROUP BY LOWER(exercise_name)
HAVING COUNT(*) >= 5;

CREATE UNIQUE INDEX IF NOT EXISTS idx_exercise_global_stats ON exercise_global_stats(exercise_name);
```

---

### Step 4: Create Refresh Function

```sql
-- Function to refresh all materialized views
CREATE OR REPLACE FUNCTION refresh_collaborative_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_pairing_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY program_success_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY exercise_global_stats;
EXCEPTION
    WHEN OTHERS THEN
        -- If CONCURRENTLY fails (no unique index), try without
        REFRESH MATERIALIZED VIEW exercise_pairing_stats;
        REFRESH MATERIALIZED VIEW program_success_stats;
        REFRESH MATERIALIZED VIEW exercise_global_stats;
END;
$$ LANGUAGE plpgsql;
```

---

### Step 5: (Optional) Set Up Hourly Refresh

In Supabase Dashboard → Database → Extensions, enable `pg_cron`, then run:

```sql
-- Refresh stats hourly
SELECT cron.schedule(
    'refresh-collaborative-stats',
    '0 * * * *',  -- Every hour
    'SELECT refresh_collaborative_stats();'
);
```

---

## Quick Setup Order

1. ✅ Create Tables (Step 1) - Run all 5 CREATE TABLE statements
2. ✅ Enable RLS (Step 2) - Run all policies
3. ⏸️  **Use the app** - Complete 10+ workouts to generate data
4. ✅ Create Views (Step 3) - Run after you have data
5. ✅ Create Refresh Function (Step 4)
6. ✅ Schedule Cron (Step 5) - Optional

---

## Testing After Setup

```sql
-- Check if tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name LIKE 'collaborative%' 
  OR table_name LIKE '%pairing%';

-- Check if data is being collected
SELECT COUNT(*) as total_workouts
FROM collaborative_workout_data;

SELECT COUNT(*) as total_pairings
FROM exercise_pairings;

-- Manually refresh views (after you have data)
SELECT refresh_collaborative_stats();

-- Check if views have data
SELECT COUNT(*) FROM exercise_pairing_stats;
SELECT COUNT(*) FROM exercise_global_stats;
```

---

## Troubleshooting

| Error | Solution |
|-------|----------|
| "column does not exist" | Run tables first, then views |
| "relation does not exist" | Table not created yet - run CREATE TABLE |
| "materialized view is empty" | You don't have data yet - complete workouts first |
| "unique index needed" | Add IF EXISTS to index creation |

The key is: **Tables → Data → Views → Function → Cron**

