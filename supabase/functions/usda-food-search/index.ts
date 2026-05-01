// ============================================================================
// BUILT SIMPLE - USDA API PROXY EDGE FUNCTION
// ============================================================================
// Supabase Edge Function to securely proxy USDA FoodData Central API
// 
// Deploy with:
// supabase functions deploy usda-food-search
//
// Set secret:
// supabase secrets set USDA_API_KEY=<your-usda-api-key>
// ============================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { buildCorsHeaders, requireUserAuth } from "../_shared/cors.ts";
import { fetchOFFByBarcode, searchOFF } from "../_shared/openFoodFacts.ts";

const USDA_API_KEY = Deno.env.get("USDA_API_KEY")!;
const USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1";

const CACHE_TTL_DAYS = 30;

// Best-effort per-IP rate limiter (resets per edge function cold start)
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_MAX = 30;
const RATE_LIMIT_WINDOW_MS = 60_000;

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now >= entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }
  entry.count++;
  return entry.count <= RATE_LIMIT_MAX;
}

interface SearchRequest {
  query: string;
  pageSize?: number;
  pageNumber?: number;
  dataTypes?: string[];
}

interface FoodDetailsRequest {
  fdcId: number;
}

interface BarcodeRequest {
  barcode: string;
}

serve(async (req) => {
  const corsHeaders = buildCorsHeaders(req);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Best-effort rate limiting per IP
  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || req.headers.get("cf-connecting-ip")
    || "unknown";
  if (!checkRateLimit(clientIp)) {
    return new Response(
      JSON.stringify({ error: "Too many requests. Please try again later.", foods: [], totalHits: 0, query: "" }),
      { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // ALL actions now require a valid user JWT (or service-role).
    // Previously search/details accepted anonymous callers and ran as
    // service-role, granting elevated DB access to the entire internet.
    const authResult = await requireUserAuth(req, supabaseClient, corsHeaders);
    if (!authResult.ok) return authResult.response;

    const { action, ...params } = await req.json();

    switch (action) {
      case "search":
        return await handleSearch(supabaseClient, params as SearchRequest, corsHeaders);
      case "details":
        return await handleDetails(supabaseClient, params as FoodDetailsRequest, corsHeaders);
      case "barcode":
        return await handleBarcode(supabaseClient, params as BarcodeRequest, corsHeaders);
      case "cache_food":
        return await handleCacheFood(supabaseClient, params, corsHeaders);
      default:
        return new Response(
          JSON.stringify({ error: "Invalid action" }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
    }
  } catch (error) {
    console.error("Error:", error);
    // Return 500 for genuine server errors so clients can distinguish
    // failures from empty results. Include the standard response shape
    // so iOS can still decode without crashing.
    return new Response(
      JSON.stringify({ 
        source: "error",
        foods: [],
        totalHits: 0,
        query: "",
        error: error.message 
      }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

// ============================================================================
// SEARCH HANDLER
// ============================================================================
async function handleSearch(supabase: any, params: SearchRequest, corsHeaders: Record<string, string>) {
  const { query, pageSize = 100, pageNumber = 1, dataTypes } = params;

  if (!query || query.trim().length === 0) {
    return new Response(
      JSON.stringify({ 
        source: "error",
        foods: [],
        totalHits: 0,
        query: query || "",
        error: "Query is required" 
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
  
  // USDA API requires minimum 3 characters for search
  // Return empty results for shorter queries to avoid API errors
  const trimmedQuery = query.trim();
  if (trimmedQuery.length < 3) {
    console.log(`⏭️ Query too short (${trimmedQuery.length} chars), skipping USDA API`);
    return new Response(
      JSON.stringify({ 
        source: "local",
        foods: [],
        totalHits: 0,
        query: trimmedQuery
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  console.log(`🔍 Searching USDA API for: "${query}"`);

  // Step 1: Check local cache first (with TTL — ignore entries older than 30 days)
  const normalizedQuery = query.toLowerCase().trim();
  const cacheCutoff = new Date(Date.now() - CACHE_TTL_DAYS * 24 * 60 * 60 * 1000).toISOString();
  const { data: cachedSearch } = await supabase
    .from("food_search_cache")
    .select("result_ids, created_at")
    .eq("normalized_query", normalizedQuery)
    .gte("created_at", cacheCutoff)
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
      
      // Transform database rows to API format (camelCase with foodNutrients array)
      const transformedFoods = orderedFoods.map(transformToApiFormat);
      
      // Update cache search count using RPC to increment
      try {
        await supabase.rpc("increment_food_search_count", { 
          query_text: normalizedQuery 
        });
      } catch (e) {
        // Non-critical - just update timestamp if RPC doesn't exist
        await supabase
          .from("food_search_cache")
          .update({ last_searched_at: new Date().toISOString() })
          .eq("normalized_query", normalizedQuery);
      }

      return new Response(
        JSON.stringify({
          source: "cache",
          foods: transformedFoods,
          totalHits: transformedFoods.length,
          query
        }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
  }

  console.log(`⚡ Cache miss - fetching from USDA API for query: "${query}"`);

  // Step 2: Fetch from USDA API using PARALLEL calls
  // CRITICAL: Make separate calls for Foundation Foods to ensure they're always included
  // Foundation Foods have the most accurate, lab-verified nutrition data
  
  // Build API URLs for different data types
  const foundationUrl = `${USDA_BASE_URL}/foods/search?query=${encodeURIComponent(query)}&dataType=Foundation&pageSize=25&pageNumber=1&api_key=${USDA_API_KEY}`;
  const srLegacyUrl = `${USDA_BASE_URL}/foods/search?query=${encodeURIComponent(query)}&dataType=${encodeURIComponent("SR Legacy")}&pageSize=25&pageNumber=1&api_key=${USDA_API_KEY}`;
  const brandedUrl = `${USDA_BASE_URL}/foods/search?query=${encodeURIComponent(query)}&dataType=Branded&pageSize=50&pageNumber=1&api_key=${USDA_API_KEY}`;
  
  console.log(`🔗 Fetching Foundation Foods...`);
  console.log(`🔗 Fetching SR Legacy Foods...`);
  console.log(`🔗 Fetching Branded Foods...`);
  console.log(`🔗 Fetching Open Food Facts...`);

  // Make parallel API calls for faster response
  console.log(`🔗 Foundation URL: ${foundationUrl.replace(USDA_API_KEY, "***")}`);

  // 4-way fan-out: 3 USDA dataType buckets + Open Food Facts (packaged products
  // / international branded items USDA's Branded set is missing). Each branch
  // catches its own error so a single source failing (e.g. OFF rate-limit, USDA
  // 503) degrades gracefully to the others — never returns a 500 to iOS.
  const [foundationResponse, srLegacyResponse, brandedResponse, offFoods] = await Promise.all([
    fetch(foundationUrl).catch(e => { console.log(`❌ Foundation fetch error: ${e}`); return { ok: false, error: e }; }),
    fetch(srLegacyUrl).catch(e => { console.log(`❌ SR Legacy fetch error: ${e}`); return { ok: false, error: e }; }),
    fetch(brandedUrl).catch(e => { console.log(`❌ Branded fetch error: ${e}`); return { ok: false, error: e }; }),
    searchOFF(query, 25).catch(e => { console.log(`❌ OFF search error: ${e}`); return [] as any[]; }),
  ]);

  console.log(`🥫 OFF returned ${offFoods.length} usable products`);

  // Parse responses
  let foundationFoods: any[] = [];
  let srLegacyFoods: any[] = [];
  let brandedFoods: any[] = [];
  
  if (foundationResponse.ok) {
    try {
      const data = await (foundationResponse as Response).json();
      foundationFoods = data.foods || [];
      console.log(`🌿 FOUNDATION FOODS: ${foundationFoods.length} results (totalHits: ${data.totalHits})`);
      foundationFoods.forEach((f: any, i: number) => {
        console.log(`🌿 Foundation ${i+1}: "${f.description}" (FDC ${f.fdcId}, dataType: ${f.dataType})`);
      });
    } catch (e) {
      console.log(`❌ Foundation JSON parse error: ${e}`);
    }
  } else {
    const status = (foundationResponse as any).status || 'unknown';
    if (status === 401) {
      console.error(`🚨 USDA_API_KEY_INVALID: Foundation API returned 401 — key may need rotation`);
    }
    const text = foundationResponse.text ? await (foundationResponse as Response).text() : '';
    console.log(`⚠️ Foundation Foods fetch failed - status: ${status}, body: ${text.substring(0, 200)}`);
  }
  
  if (srLegacyResponse.ok) {
    try {
      const data = await (srLegacyResponse as Response).json();
      srLegacyFoods = data.foods || [];
      console.log(`📚 SR LEGACY FOODS: ${srLegacyFoods.length} results`);
      if (srLegacyFoods.length > 0) {
        console.log(`📚 First SR Legacy: "${srLegacyFoods[0].description}" (FDC ${srLegacyFoods[0].fdcId})`);
      }
    } catch (e) {
      console.log(`❌ SR Legacy JSON parse error: ${e}`);
    }
  } else {
    const status = (srLegacyResponse as any).status || 'unknown';
    if (status === 401) {
      console.error(`🚨 USDA_API_KEY_INVALID: SR Legacy API returned 401 — key may need rotation`);
    }
    console.log(`⚠️ SR Legacy Foods fetch failed - status: ${status}`);
  }
  
  if (brandedResponse.ok) {
    try {
      const data = await (brandedResponse as Response).json();
      brandedFoods = data.foods || [];
      console.log(`🏷️ BRANDED FOODS: ${brandedFoods.length} results`);
    } catch (e) {
      console.log(`❌ Branded JSON parse error: ${e}`);
    }
  } else {
    const status = (brandedResponse as any).status || 'unknown';
    if (status === 401) {
      console.error(`🚨 USDA_API_KEY_INVALID: Branded API returned 401 — key may need rotation`);
    }
    console.log(`⚠️ Branded Foods fetch failed - status: ${status}`);
  }
  
  // Combine all foods. Order doesn't matter here — `rankSearchResults` reorders
  // by data type / exactness / popularity. Foundation goes first only because
  // it lets the iOS render the most-trusted result fastest while the rest of
  // the array is being processed.
  const allFoods = [...foundationFoods, ...srLegacyFoods, ...brandedFoods, ...offFoods];

  // Deduplicate by fdcId (USDA fdcIds are positive ints; OFF synthetic fdcIds
  // are negative — both unique within their own set, and crossover is
  // impossible by construction).
  const seenFdcIds = new Set<number>();
  const usdaFoods = allFoods.filter(food => {
    if (seenFdcIds.has(food.fdcId)) return false;
    seenFdcIds.add(food.fdcId);
    return true;
  });

  const usdaData = {
    foods: usdaFoods,
    totalHits: usdaFoods.length
  };

  console.log(`📊 Combined results: ${usdaData.foods?.length || 0} total (${foundationFoods.length} Foundation, ${srLegacyFoods.length} SR Legacy, ${brandedFoods.length} Branded, ${offFoods.length} OFF)`);

  // Step 3: Cache the results in our database
  if (usdaData.foods && usdaData.foods.length > 0) {
    const cachedFoodIds = await cacheUSDAFoods(supabase, usdaData.foods);
    
    // Return cached foods with full data and smart ranking
    const { data: cachedFoods } = await supabase
      .from("food_items")
      .select("*")
      .in("id", cachedFoodIds);

    // Apply intelligent ranking on results (prioritizing Foundation Foods)
    const rankedFoods = rankSearchResults(cachedFoods || [], query);
    
    // Transform database rows to API format (camelCase with foodNutrients array)
    const transformedFoods = rankedFoods.map(transformToApiFormat);
    
    // Cache the search query with ranked IDs (created_at resets TTL on re-fetch)
    const rankedIds = rankedFoods.map((f: any) => f.id);
    await supabase
      .from("food_search_cache")
      .upsert({
        search_query: query,
        normalized_query: normalizedQuery,
        result_ids: rankedIds,
        result_count: rankedIds.length,
        search_count: 1,
        last_searched_at: new Date().toISOString(),
        created_at: new Date().toISOString()
      }, {
        onConflict: "normalized_query"
      });

    return new Response(
      JSON.stringify({
        source: "usda",
        foods: transformedFoods,
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
async function handleDetails(supabase: any, params: FoodDetailsRequest, corsHeaders: Record<string, string>) {
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
    // Transform to API format before returning
    const transformedFood = transformToApiFormat(cachedFood);
    return new Response(
      JSON.stringify({ source: "cache", food: transformedFood }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Fetch from USDA API with full nutrient data
  const usdaUrl = `${USDA_BASE_URL}/food/${fdcId}?format=full&api_key=${USDA_API_KEY}`;
  const usdaResponse = await fetch(usdaUrl);

  if (!usdaResponse.ok) {
    if (usdaResponse.status === 401) {
      console.error(`🚨 USDA_API_KEY_INVALID: Details API returned 401 for fdcId ${fdcId} — key may need rotation`);
    }
    throw new Error(`USDA API error: ${usdaResponse.status} ${usdaResponse.statusText}`);
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

    // Transform to API format before returning
    const transformedFood = transformToApiFormat(updatedFood);
    return new Response(
      JSON.stringify({ source: "usda", food: transformedFood }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  return new Response(
    JSON.stringify({ error: "Failed to cache food details" }),
    { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ============================================================================
// BARCODE HANDLER (Open Food Facts)
// ============================================================================
// Camera-based barcode scan from `Fit33/BarcodeScannerView.swift` lands here.
// Strategy:
//   1. Cache hit on `food_items.barcode` → return immediately (no network).
//   2. OFF lookup → cache row in `food_items` keyed by synthetic negative
//      fdcId (so the existing cache infrastructure works untouched) AND by
//      `barcode` UNIQUE INDEX. Future scans of the same code are cache hits.
//   3. Not-found → return `{ found: false }` so iOS can show the
//      "not in database — search by name?" fallback UX with the code prefilled.
//
// Validation: barcode is digits only (8/12/13/14 chars cover EAN-8, UPC-A,
// EAN-13, ITF-14). Reject anything else early — saves an OFF round-trip and
// stops obvious garbage from poisoning the cache.
async function handleBarcode(supabase: any, params: BarcodeRequest, corsHeaders: Record<string, string>) {
  const raw = (params.barcode || "").toString().trim();
  const barcode = raw.replace(/\D/g, "");
  if (!barcode || ![8, 12, 13, 14].includes(barcode.length)) {
    return new Response(
      JSON.stringify({ error: "Invalid barcode", code: "INVALID_BARCODE", found: false }),
      { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  console.log(`🔎 Barcode lookup: ${barcode}`);

  // Step 1: cache hit by barcode column
  const { data: cachedFood } = await supabase
    .from("food_items")
    .select("*")
    .eq("barcode", barcode)
    .maybeSingle();

  if (cachedFood) {
    console.log(`✅ Cache hit for barcode ${barcode} (food_id=${cachedFood.id})`);
    // Bump search_count via RPC if available (best-effort, non-blocking).
    try { await supabase.rpc("increment_food_search_count_by_id", { p_food_id: cachedFood.id }); } catch {}
    const transformedFood = transformToApiFormat(cachedFood);
    return new Response(
      JSON.stringify({ source: "cache", found: true, food: transformedFood }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Step 2: OFF lookup
  const offResult = await fetchOFFByBarcode(barcode);
  if (!offResult.found || !offResult.food) {
    return new Response(
      JSON.stringify({ source: "off", found: false, barcode }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  // Step 3: cache and return
  const cachedIds = await cacheUSDAFoods(supabase, [offResult.food]);
  if (cachedIds.length === 0) {
    // OFF gave us a row but persistence failed (e.g. race on UNIQUE barcode).
    // Re-read and return what's there rather than returning `found: false` —
    // the user did get a hit, just the write didn't land cleanly.
    const { data: refetched } = await supabase
      .from("food_items")
      .select("*")
      .eq("barcode", barcode)
      .maybeSingle();
    if (refetched) {
      return new Response(
        JSON.stringify({ source: "off", found: true, food: transformToApiFormat(refetched) }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    return new Response(
      JSON.stringify({ error: "Cache write failed", found: false, barcode }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }

  const { data: insertedFood } = await supabase
    .from("food_items")
    .select("*")
    .eq("id", cachedIds[0])
    .single();

  return new Response(
    JSON.stringify({ source: "off", found: true, food: transformToApiFormat(insertedFood) }),
    { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
  );
}

// ============================================================================
// CACHE FOOD HANDLER
// ============================================================================
async function handleCacheFood(supabase: any, params: any, corsHeaders: Record<string, string>) {
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
// HELPER: TRANSFORM DATABASE ROW TO API FORMAT
// ============================================================================
// Transforms snake_case database rows to camelCase format expected by iOS app
// This ensures nutrition data displays correctly (per 100g values)
function transformToApiFormat(dbRow: any): any {
  // Build foodNutrients array from flat columns (per 100g)
  // These values come directly from USDA and are always per 100g
  const foodNutrients: any[] = [];
  
  if (dbRow.calories !== null && dbRow.calories !== undefined) {
    foodNutrients.push({ nutrientId: 1008, nutrientName: "Energy", nutrientNumber: "208", unitName: "KCAL", value: dbRow.calories });
  }
  if (dbRow.protein !== null && dbRow.protein !== undefined) {
    foodNutrients.push({ nutrientId: 1003, nutrientName: "Protein", nutrientNumber: "203", unitName: "G", value: dbRow.protein });
  }
  if (dbRow.carbohydrates !== null && dbRow.carbohydrates !== undefined) {
    foodNutrients.push({ nutrientId: 1005, nutrientName: "Carbohydrate, by difference", nutrientNumber: "205", unitName: "G", value: dbRow.carbohydrates });
  }
  if (dbRow.total_fat !== null && dbRow.total_fat !== undefined) {
    foodNutrients.push({ nutrientId: 1004, nutrientName: "Total lipid (fat)", nutrientNumber: "204", unitName: "G", value: dbRow.total_fat });
  }
  if (dbRow.saturated_fat !== null && dbRow.saturated_fat !== undefined) {
    foodNutrients.push({ nutrientId: 1258, nutrientName: "Fatty acids, total saturated", nutrientNumber: "606", unitName: "G", value: dbRow.saturated_fat });
  }
  if (dbRow.fiber !== null && dbRow.fiber !== undefined) {
    foodNutrients.push({ nutrientId: 1079, nutrientName: "Fiber, total dietary", nutrientNumber: "291", unitName: "G", value: dbRow.fiber });
  }
  if (dbRow.sugar !== null && dbRow.sugar !== undefined) {
    foodNutrients.push({ nutrientId: 2000, nutrientName: "Sugars, total including NLEA", nutrientNumber: "269", unitName: "G", value: dbRow.sugar });
  }
  if (dbRow.sodium !== null && dbRow.sodium !== undefined) {
    foodNutrients.push({ nutrientId: 1093, nutrientName: "Sodium, Na", nutrientNumber: "307", unitName: "MG", value: dbRow.sodium });
  }
  if (dbRow.cholesterol !== null && dbRow.cholesterol !== undefined) {
    foodNutrients.push({ nutrientId: 1253, nutrientName: "Cholesterol", nutrientNumber: "601", unitName: "MG", value: dbRow.cholesterol });
  }
  if (dbRow.calcium !== null && dbRow.calcium !== undefined) {
    foodNutrients.push({ nutrientId: 1087, nutrientName: "Calcium, Ca", nutrientNumber: "301", unitName: "MG", value: dbRow.calcium });
  }
  if (dbRow.iron !== null && dbRow.iron !== undefined) {
    foodNutrients.push({ nutrientId: 1089, nutrientName: "Iron, Fe", nutrientNumber: "303", unitName: "MG", value: dbRow.iron });
  }
  if (dbRow.vitamin_c !== null && dbRow.vitamin_c !== undefined) {
    foodNutrients.push({ nutrientId: 1162, nutrientName: "Vitamin C, total ascorbic acid", nutrientNumber: "401", unitName: "MG", value: dbRow.vitamin_c });
  }

  // Transform portions from database format 
  // Portions include measures like "1 cup", "1 RACC", etc. with gram weights
  // Format matches what iOS CloudFoodPortion expects
  const portions = dbRow.portions || [];
  const foodPortions = portions
    .filter((p: any) => p && p.gramWeight) // Only include valid portions
    .map((p: any) => ({
      id: p.id || 0,
      amount: p.amount || 1,
      unit: p.unit || "serving",
      gramWeight: p.gramWeight || 100,
      portionDescription: p.description ? `${p.amount || 1} ${p.unit || "serving"} (${p.description})` : `${p.amount || 1} ${p.unit || "serving"}`,
      description: p.description || null
    }));

  return {
    fdcId: dbRow.fdc_id,
    description: dbRow.description || dbRow.name,
    dataType: dbRow.data_type,
    brandName: dbRow.brand_name,
    brandOwner: dbRow.brand_owner,
    foodCategory: dbRow.category,
    // Surface OFF metadata to iOS so the badge renders + ODbL attribution
    // shows on the FoodDetailsView footer when source = 'off' (license req).
    source: dbRow.source || "usda",
    barcode: dbRow.barcode || null,
    imageUrl: dbRow.image_url || null,
    // IMPORTANT: servingSize for Foundation/SR Legacy foods is always 100g
    // The nutrition values are per 100g from USDA
    servingSize: dbRow.serving_size || 100,
    servingSizeUnit: dbRow.serving_unit || "g",
    householdServingFullText: dbRow.household_serving,
    // Nutrition per 100g
    foodNutrients: foodNutrients,
    // Also include direct values for iOS compatibility
    calories: dbRow.calories,
    protein: dbRow.protein,
    carbohydrates: dbRow.carbohydrates,
    totalFat: dbRow.total_fat,
    saturatedFat: dbRow.saturated_fat,
    fiber: dbRow.fiber,
    sugar: dbRow.sugar,
    sodium: dbRow.sodium,
    cholesterol: dbRow.cholesterol,
    calcium: dbRow.calcium,
    iron: dbRow.iron,
    vitaminC: dbRow.vitamin_c,
    // Portions for serving size options (iOS reads 'portions' field)
    portions: foodPortions
  };
}

// ============================================================================
// HELPER: RANK SEARCH RESULTS
// ============================================================================
// Ranks foods to prioritize:
// 1. EXACT MATCHES first
// 2. Foundation Foods from USDA (most accurate, lab-verified nutrition data)
// 3. SR Legacy Foods
// 4. Generic/unbranded foods over branded
function rankSearchResults(foods: any[], query: string): any[] {
  const normalizedQuery = normalizeForMatching(query);
  
  // Log data types for debugging
  const dataTypeCounts: { [key: string]: number } = {};
  foods.forEach(f => {
    const dt = f.data_type || f.dataType || "Unknown";
    dataTypeCounts[dt] = (dataTypeCounts[dt] || 0) + 1;
  });
  console.log(`📊 Data type distribution: ${JSON.stringify(dataTypeCounts)}`);
  
  const sorted = foods.sort((a, b) => {
    const scoreA = calculateFoodScore(a, normalizedQuery, query);
    const scoreB = calculateFoodScore(b, normalizedQuery, query);
    return scoreA - scoreB; // Lower score = better (higher priority)
  });
  
  // Log top 5 results
  console.log(`🔝 Top 5 results:`);
  sorted.slice(0, 5).forEach((f, i) => {
    const name = f.name || f.description;
    const dt = f.data_type || f.dataType;
    const score = calculateFoodScore(f, normalizedQuery, query);
    console.log(`   ${i + 1}. "${name}" (${dt}) score: ${score}`);
  });
  
  return sorted;
}

// Normalize text for matching (remove punctuation, extra spaces, lowercase)
function normalizeForMatching(text: string): string {
  return text
    .toLowerCase()
    .replace(/[,;:'"]/g, " ")  // Replace punctuation with spaces
    .replace(/\s+/g, " ")      // Collapse multiple spaces
    .trim();
}

function calculateFoodScore(food: any, normalizedQuery: string, originalQuery: string): number {
  let score = 0;
  // Handle both snake_case (database) and camelCase (USDA API) field names
  const name = (food.name || food.description || "").toLowerCase();
  const normalizedName = normalizeForMatching(name);
  const brandName = (food.brand_name || food.brandName || "").toLowerCase();
  const brandOwner = (food.brand_owner || food.brandOwner || "").toLowerCase();
  const dataType = food.data_type || food.dataType || "";
  const category = (food.category || food.foodCategory || "").toLowerCase();
  const isGeneric = !brandName && !brandOwner;
  
  // Debug logging for Foundation foods
  if (dataType === "Foundation") {
    console.log(`🌿 FOUNDATION FOOD: "${name}" (dataType: ${dataType})`);
  }
  
  // =========================================================================
  // TIER 1: EXACT MATCH (most important - appears FIRST regardless of data type)
  // =========================================================================
  // Check for exact match (ignoring punctuation differences)
  if (normalizedName === normalizedQuery) {
    score -= 1000000; // Absolute highest priority for exact match
    console.log(`🎯 EXACT MATCH: "${name}" for query "${originalQuery}"`);
  }
  // Check if name starts with query (e.g., "Almond butter, creamy" starts with "almond butter")
  else if (normalizedName.startsWith(normalizedQuery)) {
    score -= 500000; // Very high priority for starts-with match
  }
  // Check if all query words appear in the name
  else {
    const queryWords = normalizedQuery.split(" ").filter(w => w.length > 1);
    const nameWords = normalizedName.split(" ");
    const allWordsMatch = queryWords.every(qw => 
      nameWords.some(nw => nw.includes(qw) || qw.includes(nw))
    );
    if (allWordsMatch) {
      score -= 100000; // Good match - all words found
    }
  }
  
  // =========================================================================
  // TIER 2: DATA TYPE (Foundation Foods from USDA are most accurate)
  // =========================================================================
  // Ordering rationale (lower score = better):
  //   Foundation (USDA lab-verified)            -50000
  //   SR Legacy  (USDA, slightly older method)  -40000
  //   Survey FNDDS (USDA composite)             -10000
  //   OFF (Open Food Facts — packaged products)  +5000  ← below USDA whole foods,
  //                                                       ABOVE USDA Branded which
  //                                                       is mostly low-quality
  //                                                       UPC dumps.
  //   Branded (USDA Branded)                    +30000
  //
  // OFF beats USDA Branded because OFF's `unique_scans_n` (popularity) is a
  // far better quality signal than the random USDA Branded grab-bag, and OFF
  // has nutrient-completeness scoring that USDA Branded doesn't expose.
  if (dataType === "Foundation") {
    score -= 50000; // Foundation foods = lab-verified, most accurate
  } else if (dataType === "SR Legacy") {
    score -= 40000; // SR Legacy = still high quality USDA data
  } else if (dataType === "Survey (FNDDS)") {
    score -= 10000; // Survey data = decent quality
  } else if (dataType === "OFF") {
    score += 5000; // Open Food Facts = packaged products, below whole foods
  } else if (dataType === "Branded") {
    score += 30000; // Branded = lowest priority
  }
  
  // =========================================================================
  // TIER 3: GENERIC vs BRANDED preference
  // =========================================================================
  if (isGeneric) {
    score -= 20000; // Strongly prefer generic foods
  } else {
    score += 20000; // Penalize branded foods
  }
  
  // =========================================================================
  // TIER 4: Name quality signals
  // =========================================================================
  // Prefer simpler, shorter names (likely more generic/standard)
  const wordCount = name.split(/[\s,]+/).length;
  score += wordCount * 50;
  
  // Prefer cooked/prepared versions for proteins & grains (what people actually eat & track)
  // Raw versions rank lower since users typically log what they consume
  const cookedTerms = ["cooked", "grilled", "baked", "roasted", "steamed", "boiled", "poached", "sauteed"];
  const rawTerms = [", raw", "uncooked", "unprepared"];
  const isProteinOrGrain = ["chicken", "turkey", "beef", "pork", "salmon", "fish", "rice", "pasta", "oat", "egg"].some(t => name.includes(t));

  if (isProteinOrGrain) {
    if (cookedTerms.some(t => name.includes(t))) {
      score -= 8000; // Cooked forms rank higher for proteins/grains
    } else if (rawTerms.some(t => name.includes(t))) {
      score += 3000; // Raw forms rank lower
    }
  } else if (name.includes(", raw") && isGeneric) {
    // For fruits/veggies, raw is the common form — slight boost
    score -= 2000;
  }
  
  // Category relevance boost
  if (category && normalizedQuery.split(" ").some(w => category.includes(w))) {
    score -= 2000;
  }
  
  // =========================================================================
  // TIER 5: Usage/popularity signals (ALL users combined)
  // =========================================================================
  // log_count tracks how many times ALL users have logged this food
  // search_count tracks how many times this food appeared in searches
  // This ensures globally popular foods (chicken breast, rice, eggs) rank highest
  const logCount = food.log_count || 0;
  const searchCount = food.search_count || 0;

  if (logCount > 50) {
    score -= 15000; // Very popular food across all users
  } else if (logCount > 10) {
    score -= 8000;  // Moderately popular
  } else if (logCount > 0) {
    score -= 3000;  // Has been logged before
  }

  // Search frequency is a weaker signal but still useful
  score -= Math.min(searchCount * 0.5, 5000);
  
  return score;
}

// ============================================================================
// HELPER: CACHE USDA FOODS
// ============================================================================
function prepareFoodRow(food: any): any {
  const nutrients = food.foodNutrients || [];
  const getNutrient = (number: string) => {
    const nutrient = nutrients.find((n: any) => 
      (n.nutrientNumber === number || n.nutrient?.number === number)
    );
    return nutrient ? (nutrient.value || nutrient.amount || 0) : 0;
  };

  const portions = food.foodPortions?.map((p: any) => ({
    id: p.id,
    amount: p.amount,
    unit: p.measureUnit?.name || p.measureUnit?.abbreviation || "serving",
    gramWeight: p.gramWeight,
    description: p.modifier
  })) || [];

  // OFF rows carry the synthetic-fdcId metadata on `_off*` keys (see
  // `_shared/openFoodFacts.ts::transformOFFToUSDAShape`). USDA rows have no
  // `_offBarcode`, so `source` defaults to `'usda'` (matches the column
  // default in `20260801_food_items_off_barcode.sql`).
  const isOFF = !!food._offBarcode;

  return {
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
    portions: portions,
    barcode: isOFF ? food._offBarcode : null,
    source: isOFF ? "off" : "usda",
    image_url: isOFF ? food._offImageUrl : null,
  };
}

async function cacheUSDAFoods(supabase: any, foods: any[]): Promise<number[]> {
  // Prepare all rows up-front so we can attempt a single batch upsert
  const rows = foods
    .map(f => { try { return prepareFoodRow(f); } catch { return null; } })
    .filter(Boolean);

  if (rows.length === 0) return [];

  // Attempt batch upsert (single round-trip)
  try {
    const { data: batchResult, error } = await supabase
      .from("food_items")
      .upsert(rows, { onConflict: "fdc_id", returning: "representation" })
      .select("id");

    if (!error && batchResult) {
      const ids = batchResult.map((r: any) => r.id);
      console.log(`✅ Batch-cached ${ids.length} foods`);
      return ids;
    }
    console.warn(`⚠️ Batch upsert failed (${error?.message}), falling back to per-item`);
  } catch (e) {
    console.warn(`⚠️ Batch upsert threw (${e}), falling back to per-item`);
  }

  // Fallback: per-item upsert (preserves partial success)
  const cachedIds: number[] = [];
  for (const row of rows) {
    try {
      const { data: upsertedFood, error } = await supabase
        .from("food_items")
        .upsert(row, { onConflict: "fdc_id", returning: "representation" })
        .select("id")
        .single();

      if (error) {
        console.error(`Error caching food ${row.fdc_id}:`, error);
      } else if (upsertedFood) {
        cachedIds.push(upsertedFood.id);
      }
    } catch (error) {
      console.error(`Error processing food ${row.fdc_id}:`, error);
    }
  }

  console.log(`✅ Cached ${cachedIds.length} foods (per-item fallback)`);
  return cachedIds;
}






