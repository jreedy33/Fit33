-- ============================================================================
-- RECIPE TRACKING & RECOMMENDATION SYSTEM
-- Tracks user food preferences and recipe interactions for smart recommendations
-- ============================================================================

-- 1. User Food Preferences - Tracks ingredients and foods users search/add
CREATE TABLE IF NOT EXISTS user_food_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    food_name TEXT NOT NULL,
    ingredient_name TEXT, -- Normalized ingredient (e.g., "chicken" from "grilled chicken breast")
    search_count INTEGER DEFAULT 0, -- How many times they searched for this
    add_count INTEGER DEFAULT 0, -- How many times they added this to meals
    last_searched_at TIMESTAMPTZ,
    last_added_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, food_name)
);

-- 2. User Recipe Interactions - Tracks how users interact with recipes
CREATE TABLE IF NOT EXISTS user_recipe_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL, -- Spoonacular recipe ID
    recipe_title TEXT NOT NULL,
    interaction_type TEXT NOT NULL, -- 'view', 'favorite', 'add_to_meal', 'unfavorite'
    meal_type TEXT, -- 'breakfast', 'lunch', 'dinner', 'snacks' (for add_to_meal)
    calories INTEGER,
    protein INTEGER,
    carbs INTEGER,
    fat INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. User Taste Profile - Aggregated preferences for recommendations
CREATE TABLE IF NOT EXISTS user_taste_profile (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Preferred ingredients (JSON array of most used ingredients)
    preferred_ingredients JSONB DEFAULT '[]'::jsonb,
    
    -- Cuisine preferences (based on recipes they add)
    preferred_cuisines JSONB DEFAULT '[]'::jsonb,
    
    -- Diet preferences detected from behavior
    prefers_high_protein BOOLEAN DEFAULT false,
    prefers_low_carb BOOLEAN DEFAULT false,
    prefers_low_calorie BOOLEAN DEFAULT false,
    prefers_vegetarian BOOLEAN DEFAULT false,
    prefers_gluten_free BOOLEAN DEFAULT false,
    
    -- Average nutrition targets (learned from what they add)
    avg_calories_per_meal INTEGER,
    avg_protein_per_meal INTEGER,
    
    -- Time-based preferences
    preferred_breakfast_types JSONB DEFAULT '[]'::jsonb,
    preferred_lunch_types JSONB DEFAULT '[]'::jsonb,
    preferred_dinner_types JSONB DEFAULT '[]'::jsonb,
    
    -- Stats
    total_recipes_viewed INTEGER DEFAULT 0,
    total_recipes_added INTEGER DEFAULT 0,
    total_recipes_favorited INTEGER DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id)
);

-- 4. Recipe Carousel State - Tracks what recipes user has seen
CREATE TABLE IF NOT EXISTS user_recipe_carousel_state (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    shown_recipe_ids JSONB DEFAULT '[]'::jsonb, -- Recipe IDs shown today
    last_refresh_at TIMESTAMPTZ DEFAULT NOW(),
    refresh_count_today INTEGER DEFAULT 0,
    date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, date)
);

-- 5. Recommended Recipes Cache - Personalized recommendations
CREATE TABLE IF NOT EXISTS user_recommended_recipes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    recipe_id INTEGER NOT NULL,
    recipe_title TEXT NOT NULL,
    recipe_image TEXT,
    calories INTEGER,
    protein INTEGER,
    carbs INTEGER,
    fat INTEGER,
    recommendation_reason TEXT, -- Why this was recommended
    recommendation_score FLOAT DEFAULT 0, -- How confident we are
    is_shown BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '24 hours')
);

-- ============================================================================
-- INDEXES for performance
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_food_prefs_user ON user_food_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_food_prefs_ingredient ON user_food_preferences(ingredient_name);
CREATE INDEX IF NOT EXISTS idx_food_prefs_add_count ON user_food_preferences(user_id, add_count DESC);

CREATE INDEX IF NOT EXISTS idx_recipe_interactions_user ON user_recipe_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_recipe ON user_recipe_interactions(recipe_id);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_type ON user_recipe_interactions(user_id, interaction_type);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_date ON user_recipe_interactions(created_at);

CREATE INDEX IF NOT EXISTS idx_taste_profile_user ON user_taste_profile(user_id);

CREATE INDEX IF NOT EXISTS idx_carousel_state_user_date ON user_recipe_carousel_state(user_id, date);

CREATE INDEX IF NOT EXISTS idx_recommended_recipes_user ON user_recommended_recipes(user_id);
CREATE INDEX IF NOT EXISTS idx_recommended_recipes_expires ON user_recommended_recipes(expires_at);

-- ============================================================================
-- FUNCTIONS for updating taste profile
-- ============================================================================

-- Function to update user taste profile based on their interactions
CREATE OR REPLACE FUNCTION update_user_taste_profile()
RETURNS TRIGGER AS $$
BEGIN
    -- Upsert taste profile
    INSERT INTO user_taste_profile (user_id)
    VALUES (NEW.user_id)
    ON CONFLICT (user_id) DO UPDATE SET
        total_recipes_viewed = CASE 
            WHEN NEW.interaction_type = 'view' 
            THEN user_taste_profile.total_recipes_viewed + 1 
            ELSE user_taste_profile.total_recipes_viewed 
        END,
        total_recipes_added = CASE 
            WHEN NEW.interaction_type = 'add_to_meal' 
            THEN user_taste_profile.total_recipes_added + 1 
            ELSE user_taste_profile.total_recipes_added 
        END,
        total_recipes_favorited = CASE 
            WHEN NEW.interaction_type = 'favorite' 
            THEN user_taste_profile.total_recipes_favorited + 1 
            WHEN NEW.interaction_type = 'unfavorite'
            THEN GREATEST(0, user_taste_profile.total_recipes_favorited - 1)
            ELSE user_taste_profile.total_recipes_favorited 
        END,
        -- Update protein preference if they consistently add high protein meals
        prefers_high_protein = CASE
            WHEN NEW.protein >= 25 AND NEW.interaction_type = 'add_to_meal'
            THEN true
            ELSE user_taste_profile.prefers_high_protein
        END,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update taste profile on recipe interaction
DROP TRIGGER IF EXISTS trigger_update_taste_profile ON user_recipe_interactions;
CREATE TRIGGER trigger_update_taste_profile
    AFTER INSERT ON user_recipe_interactions
    FOR EACH ROW
    EXECUTE FUNCTION update_user_taste_profile();

-- Function to extract and track ingredients from food additions
CREATE OR REPLACE FUNCTION track_food_preference()
RETURNS TRIGGER AS $$
DECLARE
    normalized_ingredient TEXT;
BEGIN
    -- Normalize common ingredients
    normalized_ingredient := LOWER(TRIM(NEW.food_name));
    
    -- Extract key ingredients (simplified - can be enhanced)
    IF normalized_ingredient LIKE '%chicken%' THEN normalized_ingredient := 'chicken';
    ELSIF normalized_ingredient LIKE '%salmon%' OR normalized_ingredient LIKE '%fish%' THEN normalized_ingredient := 'fish';
    ELSIF normalized_ingredient LIKE '%beef%' OR normalized_ingredient LIKE '%steak%' THEN normalized_ingredient := 'beef';
    ELSIF normalized_ingredient LIKE '%egg%' THEN normalized_ingredient := 'eggs';
    ELSIF normalized_ingredient LIKE '%rice%' THEN normalized_ingredient := 'rice';
    ELSIF normalized_ingredient LIKE '%pasta%' OR normalized_ingredient LIKE '%noodle%' THEN normalized_ingredient := 'pasta';
    ELSIF normalized_ingredient LIKE '%salad%' OR normalized_ingredient LIKE '%vegetable%' THEN normalized_ingredient := 'vegetables';
    ELSIF normalized_ingredient LIKE '%oat%' OR normalized_ingredient LIKE '%cereal%' THEN normalized_ingredient := 'oats';
    ELSIF normalized_ingredient LIKE '%yogurt%' THEN normalized_ingredient := 'yogurt';
    ELSIF normalized_ingredient LIKE '%protein%' OR normalized_ingredient LIKE '%shake%' THEN normalized_ingredient := 'protein shake';
    END IF;
    
    -- Update ingredient tracking
    NEW.ingredient_name := normalized_ingredient;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to normalize ingredients
DROP TRIGGER IF EXISTS trigger_track_food_preference ON user_food_preferences;
CREATE TRIGGER trigger_track_food_preference
    BEFORE INSERT OR UPDATE ON user_food_preferences
    FOR EACH ROW
    EXECUTE FUNCTION track_food_preference();

-- ============================================================================
-- RLS POLICIES
-- ============================================================================

ALTER TABLE user_food_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_recipe_interactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_taste_profile ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_recipe_carousel_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_recommended_recipes ENABLE ROW LEVEL SECURITY;

-- Users can only access their own data
CREATE POLICY "Users can view own food preferences" ON user_food_preferences
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own food preferences" ON user_food_preferences
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own food preferences" ON user_food_preferences
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own recipe interactions" ON user_recipe_interactions
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own recipe interactions" ON user_recipe_interactions
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view own taste profile" ON user_taste_profile
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own taste profile" ON user_taste_profile
    FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own taste profile" ON user_taste_profile
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can view own carousel state" ON user_recipe_carousel_state
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own carousel state" ON user_recipe_carousel_state
    FOR ALL USING (auth.uid() = user_id);

CREATE POLICY "Users can view own recommended recipes" ON user_recommended_recipes
    FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can manage own recommended recipes" ON user_recommended_recipes
    FOR ALL USING (auth.uid() = user_id);

-- ============================================================================
-- HELPER VIEW for getting user's top ingredients
-- ============================================================================

CREATE OR REPLACE VIEW user_top_ingredients AS
SELECT 
    user_id,
    ingredient_name,
    SUM(add_count) as total_adds,
    SUM(search_count) as total_searches,
    MAX(last_added_at) as last_used
FROM user_food_preferences
WHERE ingredient_name IS NOT NULL
GROUP BY user_id, ingredient_name
ORDER BY total_adds DESC, total_searches DESC;
