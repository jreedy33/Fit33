// ============================================================================
// BUILT SIMPLE - USDA API PROXY EDGE FUNCTION
// ============================================================================
// Supabase Edge Function to securely proxy USDA FoodData Central API
// 
// Deploy with:
// supabase functions deploy usda-food-search
//
// Set secret:
// supabase secrets set USDA_API_KEY=QNZnzcALuiyekVr86WpdzYfJzWWwEa3BvEcLdfkS
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const USDA_API_KEY = Deno.env.get("USDA_API_KEY")!;
const USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1";

// CORS headers
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SearchRequest {
  query: string;
  pageSize?: number;
  pageNumber?: number;
  dataTypes?: string[];
}

interface FoodDetailsRequest {
  fdcId: number;
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { action, ...params } = await req.json();

    // Initialize Supabase client
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    switch (action) {
      case "search":
        return await handleSearch(supabaseClient, params as SearchRequest);
      case "details":
        return await handleDetails(supabaseClient, params as FoodDetailsRequest);
      case "cache_food":
        return await handleCacheFood(supabaseClient, params);
      default:
        return new Response(
          JSON.stringify({ error: "Invalid action" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
  } catch (error) {
    console.error("Error:", error);
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ============================================================================
// SEARCH HANDLER
// ============================================================================
async function handleSearch(supabase: any, params: SearchRequest) {
  const { query, pageSize = 100, pageNumber = 1, dataTypes } = params;

  if (!query || query.trim().length === 0) {
    return new Response(
      JSON.stringify({ error: "Query is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  console.log(`🔍 Searching USDA API for: "${query}"`);

  // Step 1: Check local cache first
  const normalizedQuery = query.toLowerCase().trim();
  const { data: cachedSearch } = await supabase
    .from("food_search_cache")
    .select("result_ids")
    .eq("normalized_query", normalizedQuery)
    .single();

  if (cachedSearch && cachedSearch.result_ids.length > 0) {
    console.log(`✅ Cache hit for "${query}" - ${cachedSearch.result_ids.length} results`);
    
    // Get full food items from cache (in the order they were ranked)
    const { data: cachedFoods } = await supabase
      .from("food_items")
      .select("*")
      .in("id", cachedSearch.result_ids)
      .limit(pageSize);

    if (cachedFoods && cachedFoods.length > 0) {
      // Re-order by the cached ranking
      const orderedFoods = cachedSearch.result_ids
        .map((id: number) => cachedFoods.find((f: any) => f.id === id))
        .filter((f: any) => f !== undefined);
      
      // Update cache search count
      await supabase
        .from("food_search_cache")
        .update({ 
          search_count: supabase.raw("search_count + 1"),
          last_searched_at: new Date().toISOString()
        })
        .eq("normalized_query", normalizedQuery);

      return new Response(
        JSON.stringify({
          source: "cache",
          foods: orderedFoods,
          totalHits: orderedFoods.length,
          query
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  }

  console.log(`⚡ Cache miss - fetching from USDA API`);

  // Step 2: Fetch from USDA API
  const dataTypeParam = dataTypes?.join(",") || "Foundation,SR Legacy,Survey (FNDDS),Branded";
  const usdaUrl = `${USDA_BASE_URL}/foods/search?query=${encodeURIComponent(query)}&dataType=${dataTypeParam}&pageSize=${pageSize}&pageNumber=${pageNumber}&api_key=${USDA_API_KEY}`;

  const usdaResponse = await fetch(usdaUrl);
  
  if (!usdaResponse.ok) {
    throw new Error(`USDA API error: ${usdaResponse.statusText}`);
  }

  const usdaData = await usdaResponse.json();
  
  console.log(`📊 USDA API returned ${usdaData.foods?.length || 0} results`);

  // Step 3: Cache the results in our database
  if (usdaData.foods && usdaData.foods.length > 0) {
    const cachedFoodIds = await cacheUSDAFoods(supabase, usdaData.foods);
    
    // Return cached foods with full data and smart ranking
    const { data: cachedFoods } = await supabase
      .from("food_items")
      .select("*")
      .in("id", cachedFoodIds);

    // Apply intelligent ranking on results
    const rankedFoods = rankSearchResults(cachedFoods || [], query);
    
    // Cache the search query with ranked IDs
    const rankedIds = rankedFoods.map((f: any) => f.id);
    await supabase
      .from("food_search_cache")
      .upsert({
        search_query: query,
        normalized_query: normalizedQuery,
        result_ids: rankedIds,
        result_count: rankedIds.length,
        search_count: 1,
        last_searched_at: new Date().toISOString()
      }, {
        onConflict: "normalized_query"
      });

    return new Response(
      JSON.stringify({
        source: "usda",
        foods: rankedFoods,
        totalHits: usdaData.totalHits,
        query
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({
      source: "usda",
      foods: [],
      totalHits: 0,
      query
    }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ============================================================================
// DETAILS HANDLER
// ============================================================================
async function handleDetails(supabase: any, params: FoodDetailsRequest) {
  const { fdcId } = params;

  if (!fdcId) {
    return new Response(
      JSON.stringify({ error: "fdcId is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  console.log(`🔍 Fetching details for FDC ID: ${fdcId}`);

  // Check cache first
  const { data: cachedFood } = await supabase
    .from("food_items")
    .select("*")
    .eq("fdc_id", fdcId)
    .single();

  if (cachedFood && cachedFood.portions) {
    console.log(`✅ Cache hit for FDC ID ${fdcId}`);
    return new Response(
      JSON.stringify({ source: "cache", food: cachedFood }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Fetch from USDA API
  const usdaUrl = `${USDA_BASE_URL}/food/${fdcId}?api_key=${USDA_API_KEY}`;
  const usdaResponse = await fetch(usdaUrl);

  if (!usdaResponse.ok) {
    throw new Error(`USDA API error: ${usdaResponse.statusText}`);
  }

  const usdaData = await usdaResponse.json();

  // Cache the detailed food data
  const cachedFoodIds = await cacheUSDAFoods(supabase, [usdaData]);

  if (cachedFoodIds.length > 0) {
    const { data: updatedFood } = await supabase
      .from("food_items")
      .select("*")
      .eq("id", cachedFoodIds[0])
      .single();

    return new Response(
      JSON.stringify({ source: "usda", food: updatedFood }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ error: "Failed to cache food details" }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ============================================================================
// CACHE FOOD HANDLER
// ============================================================================
async function handleCacheFood(supabase: any, params: any) {
  const { foods } = params;

  if (!foods || !Array.isArray(foods)) {
    return new Response(
      JSON.stringify({ error: "foods array is required" }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const cachedIds = await cacheUSDAFoods(supabase, foods);

  return new Response(
    JSON.stringify({ success: true, cachedCount: cachedIds.length, cachedIds }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ============================================================================
// HELPER: RANK SEARCH RESULTS
// ============================================================================
// Ranks foods to prioritize generic items over branded items
// Matches competitor app behavior: generic eggs, meats, produce come first
function rankSearchResults(foods: any[], query: string): any[] {
  const normalizedQuery = query.toLowerCase().trim();
  
  return foods.sort((a, b) => {
    const scoreA = calculateFoodScore(a, normalizedQuery);
    const scoreB = calculateFoodScore(b, normalizedQuery);
    return scoreA - scoreB; // Lower score = better (higher priority)
  });
}

function calculateFoodScore(food: any, query: string): number {
  let score = 0;
  const name = (food.name || "").toLowerCase();
  const brandName = (food.brand_name || "").toLowerCase();
  const brandOwner = (food.brand_owner || "").toLowerCase();
  const dataType = food.data_type || "";
  const category = (food.category || "").toLowerCase();
  
  // 1. GENERIC vs BRANDED (most important)
  const isGeneric = !brandName && !brandOwner;
  if (!isGeneric) {
    score += 10000; // Heavily penalize branded items
  }
  
  // 2. Data type quality
  if (dataType === "Foundation" || dataType === "SR Legacy") {
    score += 0; // Best quality
  } else if (dataType === "Survey (FNDDS)") {
    score += 100;
  } else {
    score += 200; // Branded/other
  }
  
  // 3. Exact name match
  if (name === query) {
    score -= 5000; // Huge bonus
  } else if (name.startsWith(query)) {
    score -= 1000;
  } else if (name.includes(query)) {
    score -= 100;
  }
  
  // 4. Category relevance (e.g., searching "egg" should boost "Dairy and Egg Products")
  if (category.includes(query)) {
    score -= 500;
  }
  
  // 5. Name complexity (simpler names first)
  const wordCount = name.split(" ").length;
  score += wordCount * 10;
  
  // 6. Popularity (minor factor for generics)
  if (isGeneric) {
    score -= (food.log_count || 0) * 0.1;
    score -= (food.search_count || 0) * 0.05;
  }
  
  return score;
}

// ============================================================================
// HELPER: CACHE USDA FOODS
// ============================================================================
async function cacheUSDAFoods(supabase: any, foods: any[]): Promise<number[]> {
  const cachedIds: number[] = [];

  for (const food of foods) {
    try {
      // Extract nutrition data
      const nutrients = food.foodNutrients || [];
      const getNutrient = (number: string) => {
        const nutrient = nutrients.find((n: any) => 
          (n.nutrientNumber === number || n.nutrient?.number === number)
        );
        return nutrient ? (nutrient.value || nutrient.amount || 0) : 0;
      };

      // Prepare food portions
      const portions = food.foodPortions?.map((p: any) => ({
        id: p.id,
        amount: p.amount,
        unit: p.measureUnit?.name || p.measureUnit?.abbreviation || "serving",
        gramWeight: p.gramWeight,
        description: p.modifier
      })) || [];

      // Upsert food item
      const { data: upsertedFood, error } = await supabase
        .from("food_items")
        .upsert({
          fdc_id: food.fdcId,
          name: food.description,
          brand_name: food.brandName,
          brand_owner: food.brandOwner,
          description: food.description,
          category: food.foodCategory || food.foodCategory?.description,
          data_type: food.dataType,
          serving_size: food.servingSize || 100,
          serving_unit: food.servingSizeUnit || "g",
          household_serving: food.householdServingFullText,
          calories: getNutrient("208"),
          protein: getNutrient("203"),
          carbohydrates: getNutrient("205"),
          total_fat: getNutrient("204"),
          saturated_fat: getNutrient("606"),
          fiber: getNutrient("291"),
          sugar: getNutrient("269"),
          sodium: getNutrient("307"),
          cholesterol: getNutrient("601"),
          calcium: getNutrient("301"),
          iron: getNutrient("303"),
          vitamin_c: getNutrient("401"),
          nutrition_data: nutrients,
          portions: portions
        }, {
          onConflict: "fdc_id",
          returning: "representation"
        })
        .select("id")
        .single();

      if (error) {
        console.error(`Error caching food ${food.fdcId}:`, error);
      } else if (upsertedFood) {
        cachedIds.push(upsertedFood.id);
      }
    } catch (error) {
      console.error(`Error processing food ${food.fdcId}:`, error);
    }
  }

  console.log(`✅ Cached ${cachedIds.length} foods`);
  return cachedIds;
}






