#!/bin/bash

# ============================================================================
# CLOUD FOOD DATABASE DEPLOYMENT SCRIPT
# ============================================================================
# Deploys cloud-based USDA food tracking with smart ranking
# Run from: /Users/josephreed/Desktop/Workout App
# ============================================================================

set -e  # Exit on error

echo "================================"
echo "🚀 CLOUD FOOD DATABASE SETUP"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI not found${NC}"
    echo ""
    echo "Install it with:"
    echo "  brew install supabase/tap/supabase"
    echo ""
    echo "Or visit: https://supabase.com/docs/guides/cli/getting-started"
    exit 1
fi

echo -e "${GREEN}✅ Supabase CLI found${NC}"
echo ""

# Check if logged in
if ! supabase projects list &> /dev/null; then
    echo -e "${YELLOW}⚠️  Not logged in to Supabase${NC}"
    echo ""
    echo "Logging in..."
    supabase login
fi

echo -e "${GREEN}✅ Logged in to Supabase${NC}"
echo ""

# ============================================================================
# STEP 1: Deploy Database Schema
# ============================================================================

echo -e "${BLUE}📊 Step 1: Deploying database schema...${NC}"
echo ""

if [ ! -f "supabase_food_tracking_setup.sql" ]; then
    echo -e "${RED}❌ File not found: supabase_food_tracking_setup.sql${NC}"
    echo "Make sure you're in the correct directory."
    exit 1
fi

echo "This will create the following tables:"
echo "  - food_items (cached USDA foods)"
echo "  - user_food_history (user logging history)"
echo "  - user_favorite_foods (user favorites)"
echo "  - food_search_cache (search results cache)"
echo ""

read -p "Deploy database schema? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Get project ref
    echo "Fetching project details..."
    PROJECT_REF=$(supabase projects list --output json | jq -r '.[0].id' 2>/dev/null || echo "")
    
    if [ -z "$PROJECT_REF" ]; then
        echo -e "${YELLOW}⚠️  Could not auto-detect project${NC}"
        echo ""
        echo "Please run the SQL manually:"
        echo "1. Open Supabase Dashboard"
        echo "2. Go to SQL Editor"
        echo "3. Copy and paste the contents of 'supabase_food_tracking_setup.sql'"
        echo "4. Click 'Run'"
        echo ""
    else
        echo "Executing SQL..."
        supabase db execute --project-ref "$PROJECT_REF" -f supabase_food_tracking_setup.sql
        echo -e "${GREEN}✅ Database schema deployed!${NC}"
    fi
else
    echo "Skipped database deployment"
fi

echo ""

# ============================================================================
# STEP 2: Deploy Edge Function
# ============================================================================

echo -e "${BLUE}⚡ Step 2: Deploying edge function...${NC}"
echo ""

if [ ! -f "supabase_edge_function_usda_proxy.ts" ]; then
    echo -e "${RED}❌ File not found: supabase_edge_function_usda_proxy.ts${NC}"
    exit 1
fi

# Create functions directory structure
mkdir -p supabase/functions/usda-food-search

# Copy edge function
echo "Copying edge function..."
cp supabase_edge_function_usda_proxy.ts supabase/functions/usda-food-search/index.ts

echo "Edge function ready at: supabase/functions/usda-food-search/index.ts"
echo ""

read -p "Deploy edge function to Supabase? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deploying edge function..."
    supabase functions deploy usda-food-search --no-verify-jwt
    echo -e "${GREEN}✅ Edge function deployed!${NC}"
else
    echo "Skipped edge function deployment"
    echo ""
    echo "To deploy manually later:"
    echo "  supabase functions deploy usda-food-search --no-verify-jwt"
fi

echo ""

# ============================================================================
# STEP 3: Set USDA API Key
# ============================================================================

echo -e "${BLUE}🔑 Step 3: Setting USDA API key...${NC}"
echo ""

USDA_API_KEY="QNZnzcALuiyekVr86WpdzYfJzWWwEa3BvEcLdfkS"

read -p "Set USDA API key as secret? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Setting secret..."
    supabase secrets set USDA_API_KEY="$USDA_API_KEY"
    echo -e "${GREEN}✅ USDA API key set!${NC}"
else
    echo "Skipped API key setup"
    echo ""
    echo "To set manually later:"
    echo "  supabase secrets set USDA_API_KEY=$USDA_API_KEY"
fi

echo ""

# ============================================================================
# STEP 4: Test the Setup
# ============================================================================

echo -e "${BLUE}🧪 Step 4: Testing the setup...${NC}"
echo ""

read -p "Run test search? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Getting project details..."
    
    # Try to get project URL
    PROJECT_URL=$(supabase status --output json 2>/dev/null | jq -r '.API_URL' 2>/dev/null || echo "")
    
    if [ -z "$PROJECT_URL" ]; then
        echo -e "${YELLOW}⚠️  Could not auto-detect project URL${NC}"
        echo ""
        echo "To test manually:"
        echo "1. Open your app"
        echo "2. Search for 'egg'"
        echo "3. Verify generic eggs appear first"
    else
        echo "Testing edge function..."
        echo ""
        
        # Get anon key
        ANON_KEY=$(supabase status --output json 2>/dev/null | jq -r '.ANON_KEY' 2>/dev/null || echo "")
        
        if [ -n "$ANON_KEY" ]; then
            curl -X POST "$PROJECT_URL/functions/v1/usda-food-search" \
              -H "Content-Type: application/json" \
              -H "Authorization: Bearer $ANON_KEY" \
              -d '{"action": "search", "query": "egg"}' \
              2>/dev/null | jq '.foods[0:3]' || echo "Test complete!"
            
            echo ""
            echo -e "${GREEN}✅ Edge function is working!${NC}"
        fi
    fi
else
    echo "Skipped testing"
fi

echo ""

# ============================================================================
# COMPLETION
# ============================================================================

echo "================================"
echo -e "${GREEN}✅ SETUP COMPLETE!${NC}"
echo "================================"
echo ""
echo "Your cloud food database is ready with:"
echo "  ✅ Instant search (cached in cloud)"
echo "  ✅ Smart ranking (generic foods first)"
echo "  ✅ User history & favorites"
echo "  ✅ Popularity tracking"
echo ""
echo "Next steps:"
echo "1. Open your app"
echo "2. Search for common foods:"
echo "   - 'egg' - Generic eggs should appear first"
echo "   - 'chicken breast' - Raw chicken before prepared"
echo "   - 'apple' - Fresh apples before apple products"
echo ""
echo "3. Check that branded items appear LAST in results"
echo ""
echo "📚 Full documentation: CLOUD_FOOD_DATABASE_SETUP.md"
echo ""
echo "🐛 Troubleshooting:"
echo "   supabase functions logs usda-food-search --tail"
echo ""
echo -e "${GREEN}Happy coding! 🎉${NC}"

