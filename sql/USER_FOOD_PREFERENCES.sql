-- ============================================================================
-- USER FOOD PREFERENCES - Database Schema
-- ============================================================================
-- Stores user's liked/disliked ingredients and food preferences for 
-- personalized recipe recommendations
-- ============================================================================

-- ============================================================================
-- TABLE 1: User Ingredient Preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_ingredient_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Ingredient info
    ingredient_name TEXT NOT NULL,
    ingredient_normalized TEXT NOT NULL, -- Lowercase, trimmed version for matching
    
    -- Preference type: 'like' or 'dislike'
    preference_type TEXT NOT NULL CHECK (preference_type IN ('like', 'dislike')),
    
    -- Optional: strength of preference (1-5, 5 being strongest)
    preference_strength INTEGER DEFAULT 3 CHECK (preference_strength BETWEEN 1 AND 5),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint: one preference per ingredient per user
    UNIQUE(user_id, ingredient_normalized)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_ingredient_prefs_user ON user_ingredient_preferences(user_id);
CREATE INDEX IF NOT EXISTS idx_user_ingredient_prefs_type ON user_ingredient_preferences(user_id, preference_type);

-- RLS
ALTER TABLE user_ingredient_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own ingredient preferences" ON user_ingredient_preferences;
CREATE POLICY "Users can manage own ingredient preferences" ON user_ingredient_preferences
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 2: User Cuisine Preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_cuisine_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Cuisine info
    cuisine_name TEXT NOT NULL, -- e.g., 'Italian', 'Mexican', 'Asian'
    
    -- Preference type: 'like' or 'dislike'
    preference_type TEXT NOT NULL CHECK (preference_type IN ('like', 'dislike')),
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint
    UNIQUE(user_id, cuisine_name)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_cuisine_prefs_user ON user_cuisine_preferences(user_id);

-- RLS
ALTER TABLE user_cuisine_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own cuisine preferences" ON user_cuisine_preferences;
CREATE POLICY "Users can manage own cuisine preferences" ON user_cuisine_preferences
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 3: User Dietary Restrictions
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_dietary_restrictions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Restriction type: 'vegetarian', 'vegan', 'gluten_free', 'dairy_free', 
    -- 'nut_allergy', 'shellfish_allergy', 'keto', 'paleo', 'halal', 'kosher'
    restriction_type TEXT NOT NULL,
    
    -- Is it an allergy (strict) or preference (flexible)?
    is_allergy BOOLEAN DEFAULT FALSE,
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Unique constraint
    UNIQUE(user_id, restriction_type)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_user_dietary_user ON user_dietary_restrictions(user_id);

-- RLS
ALTER TABLE user_dietary_restrictions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own dietary restrictions" ON user_dietary_restrictions;
CREATE POLICY "Users can manage own dietary restrictions" ON user_dietary_restrictions
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 4: Recipe Interaction History (for ML/recommendations)
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_recipe_interactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Recipe info (external ID from Spoonacular)
    recipe_id INTEGER NOT NULL,
    recipe_title TEXT,
    
    -- Interaction type
    interaction_type TEXT NOT NULL CHECK (interaction_type IN ('view', 'add_to_meal', 'favorite', 'share', 'dismiss')),
    
    -- Additional context
    meal_type TEXT, -- breakfast, lunch, dinner, snack
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_user ON user_recipe_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_recipe ON user_recipe_interactions(recipe_id);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_type ON user_recipe_interactions(user_id, interaction_type);
CREATE INDEX IF NOT EXISTS idx_recipe_interactions_recent ON user_recipe_interactions(user_id, created_at DESC);

-- RLS
ALTER TABLE user_recipe_interactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own recipe interactions" ON user_recipe_interactions;
CREATE POLICY "Users can manage own recipe interactions" ON user_recipe_interactions
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- TABLE 5: User Recipe Preferences Summary (cached for fast lookups)
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_recipe_preferences_summary (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Cached preference lists (JSON arrays for fast API queries)
    liked_ingredients JSONB DEFAULT '[]'::JSONB,
    disliked_ingredients JSONB DEFAULT '[]'::JSONB,
    liked_cuisines JSONB DEFAULT '[]'::JSONB,
    disliked_cuisines JSONB DEFAULT '[]'::JSONB,
    dietary_restrictions JSONB DEFAULT '[]'::JSONB,
    allergies JSONB DEFAULT '[]'::JSONB,
    
    -- Inferred preferences from interactions
    inferred_favorite_ingredients JSONB DEFAULT '[]'::JSONB,
    inferred_favorite_cuisines JSONB DEFAULT '[]'::JSONB,
    
    -- Preferences
    prefers_high_protein BOOLEAN DEFAULT FALSE,
    prefers_low_carb BOOLEAN DEFAULT FALSE,
    prefers_low_calorie BOOLEAN DEFAULT FALSE,
    max_cook_time_minutes INTEGER,
    
    -- Stats
    total_recipes_viewed INTEGER DEFAULT 0,
    total_recipes_added INTEGER DEFAULT 0,
    total_recipes_favorited INTEGER DEFAULT 0,
    
    -- Timestamps
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE user_recipe_preferences_summary ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can manage own preferences summary" ON user_recipe_preferences_summary;
CREATE POLICY "Users can manage own preferences summary" ON user_recipe_preferences_summary
    FOR ALL TO authenticated
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================================================
-- FUNCTION: Update preferences summary when ingredients change
-- ============================================================================
CREATE OR REPLACE FUNCTION update_recipe_preferences_summary()
RETURNS TRIGGER AS $$
BEGIN
    -- Upsert the summary record
    INSERT INTO user_recipe_preferences_summary (user_id, liked_ingredients, disliked_ingredients)
    VALUES (
        COALESCE(NEW.user_id, OLD.user_id),
        (SELECT COALESCE(jsonb_agg(ingredient_name), '[]'::JSONB) 
         FROM user_ingredient_preferences 
         WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'like'),
        (SELECT COALESCE(jsonb_agg(ingredient_name), '[]'::JSONB) 
         FROM user_ingredient_preferences 
         WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'dislike')
    )
    ON CONFLICT (user_id) DO UPDATE SET
        liked_ingredients = (SELECT COALESCE(jsonb_agg(ingredient_name), '[]'::JSONB) 
                            FROM user_ingredient_preferences 
                            WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'like'),
        disliked_ingredients = (SELECT COALESCE(jsonb_agg(ingredient_name), '[]'::JSONB) 
                               FROM user_ingredient_preferences 
                               WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'dislike'),
        updated_at = NOW();
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for ingredient preferences
DROP TRIGGER IF EXISTS trigger_update_prefs_summary_ingredients ON user_ingredient_preferences;
CREATE TRIGGER trigger_update_prefs_summary_ingredients
    AFTER INSERT OR UPDATE OR DELETE ON user_ingredient_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_recipe_preferences_summary();

-- ============================================================================
-- FUNCTION: Update cuisine summary when cuisines change
-- ============================================================================
CREATE OR REPLACE FUNCTION update_cuisine_preferences_summary()
RETURNS TRIGGER AS $$
BEGIN
    -- Update the summary record
    INSERT INTO user_recipe_preferences_summary (user_id, liked_cuisines, disliked_cuisines)
    VALUES (
        COALESCE(NEW.user_id, OLD.user_id),
        (SELECT COALESCE(jsonb_agg(cuisine_name), '[]'::JSONB) 
         FROM user_cuisine_preferences 
         WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'like'),
        (SELECT COALESCE(jsonb_agg(cuisine_name), '[]'::JSONB) 
         FROM user_cuisine_preferences 
         WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'dislike')
    )
    ON CONFLICT (user_id) DO UPDATE SET
        liked_cuisines = (SELECT COALESCE(jsonb_agg(cuisine_name), '[]'::JSONB) 
                         FROM user_cuisine_preferences 
                         WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'like'),
        disliked_cuisines = (SELECT COALESCE(jsonb_agg(cuisine_name), '[]'::JSONB) 
                            FROM user_cuisine_preferences 
                            WHERE user_id = COALESCE(NEW.user_id, OLD.user_id) AND preference_type = 'dislike'),
        updated_at = NOW();
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for cuisine preferences
DROP TRIGGER IF EXISTS trigger_update_prefs_summary_cuisines ON user_cuisine_preferences;
CREATE TRIGGER trigger_update_prefs_summary_cuisines
    AFTER INSERT OR UPDATE OR DELETE ON user_cuisine_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_cuisine_preferences_summary();

-- ============================================================================
-- POPULAR INGREDIENTS (Reference table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS popular_ingredients (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    category TEXT NOT NULL, -- 'protein', 'vegetable', 'fruit', 'grain', 'dairy', 'other'
    emoji TEXT,
    usage_count INTEGER DEFAULT 0, -- Track how often users add this
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert popular ingredients
INSERT INTO popular_ingredients (name, category, emoji) VALUES
    -- Proteins
    ('Chicken', 'protein', '🍗'),
    ('Salmon', 'protein', '🐟'),
    ('Beef', 'protein', '🥩'),
    ('Turkey', 'protein', '🦃'),
    ('Eggs', 'protein', '🥚'),
    ('Shrimp', 'protein', '🦐'),
    ('Tuna', 'protein', '🐟'),
    ('Tofu', 'protein', '🧈'),
    ('Pork', 'protein', '🥓'),
    ('Greek Yogurt', 'protein', '🥛'),
    -- Vegetables
    ('Broccoli', 'vegetable', '🥦'),
    ('Spinach', 'vegetable', '🥬'),
    ('Avocado', 'vegetable', '🥑'),
    ('Sweet Potato', 'vegetable', '🍠'),
    ('Tomatoes', 'vegetable', '🍅'),
    ('Bell Peppers', 'vegetable', '🫑'),
    ('Onions', 'vegetable', '🧅'),
    ('Garlic', 'vegetable', '🧄'),
    ('Mushrooms', 'vegetable', '🍄'),
    ('Zucchini', 'vegetable', '🥒'),
    ('Carrots', 'vegetable', '🥕'),
    ('Asparagus', 'vegetable', '🌿'),
    ('Kale', 'vegetable', '🥬'),
    ('Cauliflower', 'vegetable', '🥦'),
    -- Fruits
    ('Banana', 'fruit', '🍌'),
    ('Blueberries', 'fruit', '🫐'),
    ('Strawberries', 'fruit', '🍓'),
    ('Apple', 'fruit', '🍎'),
    ('Lemon', 'fruit', '🍋'),
    ('Lime', 'fruit', '🍋'),
    ('Mango', 'fruit', '🥭'),
    ('Pineapple', 'fruit', '🍍'),
    -- Grains & Carbs
    ('Rice', 'grain', '🍚'),
    ('Quinoa', 'grain', '🌾'),
    ('Oats', 'grain', '🥣'),
    ('Pasta', 'grain', '🍝'),
    ('Bread', 'grain', '🍞'),
    ('Potatoes', 'grain', '🥔'),
    -- Dairy & Alternatives
    ('Cheese', 'dairy', '🧀'),
    ('Milk', 'dairy', '🥛'),
    ('Butter', 'dairy', '🧈'),
    ('Almond Milk', 'dairy', '🥛'),
    -- Nuts & Seeds
    ('Almonds', 'other', '🥜'),
    ('Peanuts', 'other', '🥜'),
    ('Walnuts', 'other', '🥜'),
    ('Chia Seeds', 'other', '🌱'),
    -- Other
    ('Olive Oil', 'other', '🫒'),
    ('Honey', 'other', '🍯'),
    ('Coconut', 'other', '🥥')
ON CONFLICT (name) DO NOTHING;

-- Make popular_ingredients readable by everyone
ALTER TABLE popular_ingredients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read popular ingredients" ON popular_ingredients;
CREATE POLICY "Anyone can read popular ingredients" ON popular_ingredients
    FOR SELECT TO authenticated
    USING (true);

-- ============================================================================
-- POPULAR CUISINES (Reference table)
-- ============================================================================
CREATE TABLE IF NOT EXISTS popular_cuisines (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    emoji TEXT,
    api_value TEXT NOT NULL -- Value to use with Spoonacular API
);

-- Insert popular cuisines
INSERT INTO popular_cuisines (name, emoji, api_value) VALUES
    ('Italian', '🇮🇹', 'italian'),
    ('Mexican', '🇲🇽', 'mexican'),
    ('Chinese', '🇨🇳', 'chinese'),
    ('Japanese', '🇯🇵', 'japanese'),
    ('Indian', '🇮🇳', 'indian'),
    ('Thai', '🇹🇭', 'thai'),
    ('Mediterranean', '🫒', 'mediterranean'),
    ('American', '🇺🇸', 'american'),
    ('French', '🇫🇷', 'french'),
    ('Greek', '🇬🇷', 'greek'),
    ('Korean', '🇰🇷', 'korean'),
    ('Vietnamese', '🇻🇳', 'vietnamese'),
    ('Spanish', '🇪🇸', 'spanish'),
    ('Middle Eastern', '🧆', 'middle eastern'),
    ('Caribbean', '🏝️', 'caribbean')
ON CONFLICT (name) DO NOTHING;

-- Make popular_cuisines readable by everyone
ALTER TABLE popular_cuisines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read popular cuisines" ON popular_cuisines;
CREATE POLICY "Anyone can read popular cuisines" ON popular_cuisines
    FOR SELECT TO authenticated
    USING (true);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ User food preferences schema created!';
    RAISE NOTICE '   - user_ingredient_preferences: Store liked/disliked ingredients';
    RAISE NOTICE '   - user_cuisine_preferences: Store cuisine preferences';
    RAISE NOTICE '   - user_dietary_restrictions: Store dietary needs & allergies';
    RAISE NOTICE '   - user_recipe_interactions: Track recipe engagement';
    RAISE NOTICE '   - user_recipe_preferences_summary: Cached preferences for fast API calls';
    RAISE NOTICE '   - popular_ingredients: Reference table with 50+ common ingredients';
    RAISE NOTICE '   - popular_cuisines: Reference table with 15 cuisines';
END $$;
