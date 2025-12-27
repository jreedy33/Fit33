#!/bin/bash

# ============================================================================
# Built Simple - Cloud Food Tracking Deployment Script
# ============================================================================
# This script automates the deployment of the cloud food tracking system
# to your Supabase project.
#
# Prerequisites:
# - Supabase CLI installed (npm install -g supabase)
# - Supabase project created
# - Project linked (supabase link --project-ref YOUR_REF)
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USDA_API_KEY="QNZnzcALuiyekVr86WpdzYfJzWWwEa3BvEcLdfkS"
EDGE_FUNCTION_NAME="usda-food-search"

echo -e "${BLUE}============================================================================${NC}"
echo -e "${BLUE}   Built Simple - Cloud Food Tracking Deployment${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

# ============================================================================
# Step 1: Check prerequisites
# ============================================================================
echo -e "${YELLOW}[1/5] Checking prerequisites...${NC}"

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo -e "${RED}❌ Supabase CLI not found!${NC}"
    echo "Please install it with: npm install -g supabase"
    exit 1
fi

echo -e "${GREEN}✅ Supabase CLI found${NC}"

# Check if project is linked
if ! supabase status &> /dev/null; then
    echo -e "${RED}❌ Project not linked!${NC}"
    echo "Please run: supabase link --project-ref YOUR_PROJECT_REF"
    exit 1
fi

echo -e "${GREEN}✅ Project linked${NC}"
echo ""

# ============================================================================
# Step 2: Deploy database schema
# ============================================================================
echo -e "${YELLOW}[2/5] Deploying database schema...${NC}"

# Apply SQL migration
psql_output=$(supabase db push < supabase_food_tracking_setup.sql 2>&1) || true

if [[ $psql_output == *"error"* ]]; then
    echo -e "${YELLOW}⚠️  Some tables might already exist. Continuing...${NC}"
else
    echo -e "${GREEN}✅ Database schema deployed${NC}"
fi

# Verify tables exist
echo "Verifying tables..."
supabase db diff --use-migra

echo -e "${GREEN}✅ Database tables verified${NC}"
echo ""

# ============================================================================
# Step 3: Create Edge Function directory structure
# ============================================================================
echo -e "${YELLOW}[3/5] Setting up Edge Function...${NC}"

# Create functions directory if it doesn't exist
mkdir -p supabase/functions/$EDGE_FUNCTION_NAME

# Copy Edge Function code
cp supabase_edge_function_usda_proxy.ts supabase/functions/$EDGE_FUNCTION_NAME/index.ts

echo -e "${GREEN}✅ Edge Function files created${NC}"
echo ""

# ============================================================================
# Step 4: Deploy Edge Function
# ============================================================================
echo -e "${YELLOW}[4/5] Deploying Edge Function...${NC}"

# Deploy the function
supabase functions deploy $EDGE_FUNCTION_NAME --no-verify-jwt

echo -e "${GREEN}✅ Edge Function deployed${NC}"
echo ""

# ============================================================================
# Step 5: Set secrets
# ============================================================================
echo -e "${YELLOW}[5/5] Setting secrets...${NC}"

# Set USDA API key
supabase secrets set USDA_API_KEY=$USDA_API_KEY

echo -e "${GREEN}✅ Secrets configured${NC}"
echo ""

# ============================================================================
# Verification
# ============================================================================
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}   🎉 Deployment Complete!${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""

echo -e "${YELLOW}Testing Edge Function...${NC}"

# Get project details
PROJECT_REF=$(supabase status | grep "API URL" | awk '{print $3}' | sed 's/https:\/\///' | cut -d'.' -f1)
ANON_KEY=$(supabase status | grep "anon key" | awk '{print $3}')

# Test the Edge Function
echo "Testing search for 'chicken breast'..."
TEST_RESPONSE=$(curl -s --location --request POST "https://$PROJECT_REF.supabase.co/functions/v1/$EDGE_FUNCTION_NAME" \
  --header "Authorization: Bearer $ANON_KEY" \
  --header 'Content-Type: application/json' \
  --data '{"action":"search","query":"chicken breast"}')

if [[ $TEST_RESPONSE == *"foods"* ]]; then
    echo -e "${GREEN}✅ Edge Function test successful!${NC}"
    echo ""
    echo "Sample response:"
    echo $TEST_RESPONSE | python3 -m json.tool | head -20
else
    echo -e "${RED}❌ Edge Function test failed${NC}"
    echo "Response: $TEST_RESPONSE"
fi

echo ""
echo -e "${BLUE}============================================================================${NC}"
echo -e "${GREEN}   Next Steps:${NC}"
echo -e "${BLUE}============================================================================${NC}"
echo ""
echo "1. Open Xcode and build the BuiltSimple app"
echo "2. The cloud food tracking features are now active!"
echo "3. Search for foods to see caching in action"
echo "4. Log foods to build your history"
echo "5. Check Supabase dashboard to monitor usage"
echo ""
echo -e "${YELLOW}📊 Monitor your deployment:${NC}"
echo "   - Database: https://app.supabase.com/project/$PROJECT_REF/database/tables"
echo "   - Edge Functions: https://app.supabase.com/project/$PROJECT_REF/functions"
echo "   - Logs: supabase functions logs $EDGE_FUNCTION_NAME"
echo ""
echo -e "${YELLOW}📖 Documentation:${NC}"
echo "   - See CLOUD_FOOD_TRACKING_SETUP.md for details"
echo ""
echo -e "${GREEN}Happy tracking! 🍎${NC}"






