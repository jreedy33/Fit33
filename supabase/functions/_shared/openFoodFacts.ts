// ============================================================================
// SHARED — OPEN FOOD FACTS HELPERS
// ============================================================================
// Open Food Facts (OFF) — https://world.openfoodfacts.org/
//
// Free, open, no auth, no rate-limit headers, ~3M products globally — the
// best-in-class data source for **packaged / branded foods with barcodes**.
// USDA Foundation/SR Legacy still wins for whole foods; this is the second
// pillar of food search after the 2026-04-30 auth fix.
//
// Why a shared helper (not inline in usda-food-search/index.ts):
//   - barcode lookup (FoodSearchView toolbar scan) hits exactly the same OFF
//     endpoint, so co-locating with the search fan-out keeps the field-name
//     translation in ONE place. If `nutriments.sodium_100g` ever changes shape
//     in the OFF API, only this file changes.
//   - the rest of the edge function stays USDA-shape — `prepareFoodRow()` and
//     `transformToApiFormat()` keep working unchanged.
//
// License: data is ODbL — attribution required wherever it is shown to users.
// We surface this with a "Data: Open Food Facts" footer on FoodDetailsView when
// the row's `source = 'off'`.
// ============================================================================

const OFF_BASE_URL = "https://world.openfoodfacts.org";

// User-Agent is REQUIRED by the OFF API. They will rate-limit / block requests
// with default Deno UA. Format per OFF docs: "<App>/<Version> (<contact>)".
const OFF_USER_AGENT = "Fit33/1.38 (https://fit33.app)";

// USDA fdcId space is positive int32 (currently up to ~2.5B for branded).
// We assign OFF rows a SYNTHETIC NEGATIVE fdcId derived from the numeric
// barcode so the existing `food_items.fdc_id UNIQUE` upsert path keeps
// working unchanged. iOS treats fdcId as opaque, and the new `barcode` column
// is what drives the actual barcode→product lookup index.
//
// Negative space is safe: USDA never issues negative ids, and the absolute
// value of a 13-digit barcode (max 9_999_999_999_999) fits in JS Number's
// 2^53 safe-integer range AND in Postgres BIGINT. We migrate `fdc_id` to
// BIGINT in `20260801_food_items_off_barcode.sql` for headroom.
export function syntheticFdcIdForBarcode(barcode: string): number {
  const digits = barcode.replace(/\D/g, "");
  if (digits.length === 0) return 0;
  // Negative so it can never collide with a real USDA fdcId.
  return -1 * Number(digits);
}

// ----------------------------------------------------------------------------
// PRODUCT (BARCODE) LOOKUP
// ----------------------------------------------------------------------------

export interface OFFProductLookupResult {
  found: boolean;
  // USDA-shape food (camelCase, foodNutrients array) ready to feed into
  // prepareFoodRow() / transformToApiFormat().
  food: any | null;
  source: "off";
}

export async function fetchOFFByBarcode(
  barcode: string,
): Promise<OFFProductLookupResult> {
  // OFF v2 product endpoint. `fields` keeps the response small — we only need
  // the descriptor + nutriments + a few ranking signals.
  const fields = [
    "code",
    "product_name",
    "product_name_en",
    "generic_name",
    "brands",
    "brand_owner",
    "categories_tags",
    "categories",
    "serving_size",
    "serving_quantity",
    "image_url",
    "image_front_url",
    "image_small_url",
    "nutriments",
    "nutriment_data_completeness",
    "completeness",
    "popularity_key",
    "unique_scans_n",
    "nutrition_grades",
  ].join(",");

  const url = `${OFF_BASE_URL}/api/v2/product/${encodeURIComponent(barcode)}.json?fields=${fields}`;

  console.log(`🥫 OFF barcode lookup: ${barcode}`);

  let response: Response;
  try {
    response = await fetch(url, {
      headers: { "User-Agent": OFF_USER_AGENT, "Accept": "application/json" },
    });
  } catch (e) {
    console.log(`❌ OFF barcode fetch threw: ${e}`);
    return { found: false, food: null, source: "off" };
  }

  if (!response.ok) {
    console.log(`⚠️ OFF barcode HTTP ${response.status}`);
    return { found: false, food: null, source: "off" };
  }

  const data = await response.json().catch(() => null);
  if (!data || data.status !== 1 || !data.product) {
    // status: 0 = not found. Don't error — just return empty so the iOS
    // scanner can fall through to "Not found, search by name?" UX.
    console.log(`🔎 OFF barcode ${barcode} not found (status=${data?.status})`);
    return { found: false, food: null, source: "off" };
  }

  const food = transformOFFToUSDAShape(data.product);
  if (!food) return { found: false, food: null, source: "off" };
  return { found: true, food, source: "off" };
}

// ----------------------------------------------------------------------------
// SEARCH (BY QUERY STRING)
// ----------------------------------------------------------------------------

export async function searchOFF(query: string, pageSize: number = 25): Promise<any[]> {
  const trimmed = query.trim();
  if (trimmed.length < 3) return []; // mirror USDA min-length

  // CGI search endpoint. v1 search-as-you-type API does not return nutriments,
  // so we use the legacy CGI search which gives us the full product blob.
  // `sort_by=popularity` puts heavy-scanned items first — the same items
  // users would reach for in a typeahead.
  const params = new URLSearchParams({
    search_terms: trimmed,
    search_simple: "1",
    action: "process",
    json: "1",
    page_size: String(Math.min(pageSize, 50)),
    page: "1",
    sort_by: "popularity",
    fields: [
      "code",
      "product_name",
      "product_name_en",
      "generic_name",
      "brands",
      "brand_owner",
      "categories_tags",
      "categories",
      "serving_size",
      "serving_quantity",
      "image_small_url",
      "nutriments",
      "nutriment_data_completeness",
      "completeness",
      "popularity_key",
      "unique_scans_n",
    ].join(","),
  });

  const url = `${OFF_BASE_URL}/cgi/search.pl?${params.toString()}`;
  console.log(`🥫 OFF search: "${trimmed}"`);

  let response: Response;
  try {
    response = await fetch(url, {
      headers: { "User-Agent": OFF_USER_AGENT, "Accept": "application/json" },
    });
  } catch (e) {
    console.log(`❌ OFF search fetch threw: ${e}`);
    return [];
  }

  if (!response.ok) {
    console.log(`⚠️ OFF search HTTP ${response.status}`);
    return [];
  }

  const data = await response.json().catch(() => null);
  const products = (data?.products || []) as any[];

  // Only keep products with a barcode AND at least some nutrition data —
  // anything missing both is a partial OFF entry that would render as
  // "0 cal / 0 protein" on the iOS card and look broken.
  const usable = products.filter((p) => {
    if (!p?.code) return false;
    const n = p.nutriments || {};
    return (
      typeof n["energy-kcal_100g"] === "number" ||
      typeof n["energy-kcal_serving"] === "number" ||
      typeof n["proteins_100g"] === "number" ||
      typeof n["carbohydrates_100g"] === "number"
    );
  });

  console.log(
    `🥫 OFF returned ${products.length} products, ${usable.length} usable (have nutriments)`
  );

  return usable
    .map((p) => transformOFFToUSDAShape(p))
    .filter((f: any) => f !== null);
}

// ----------------------------------------------------------------------------
// SHAPE TRANSLATOR — OFF product → USDA-shaped food
// ----------------------------------------------------------------------------
// Returns `null` if the row can't be safely converted (missing barcode, etc.)
// so the caller can drop it without throwing.
//
// Field-name notes (OFF → USDA):
//   product_name              → description
//   brands (comma-sep)        → brandName / brandOwner
//   categories                → foodCategory
//   serving_quantity (g)      → servingSize (always 100 for our nutrient row)
//   nutriments[<key>_100g]    → foodNutrients[i].value (per 100g)
//
// Unit conversions (CRITICAL):
//   OFF stores micronutrients in **grams**; USDA standard is **milligrams**.
//   - sodium_100g (g)      × 1000 → 307 (mg)
//   - cholesterol_100g (g) × 1000 → 601 (mg)
//   - calcium_100g (g)     × 1000 → 301 (mg)
//   - iron_100g (g)        × 1000 → 303 (mg)
//   - vitamin-c_100g (g)   × 1000 → 401 (mg)
//   Skipping these conversions makes a single Coca-Cola row report "43 mg
//   sodium" when it should be "43 mg" → silently looks correct because both
//   are 43, but a Doritos row would report "0.6 mg sodium" instead of 600 mg
//   and the daily-sodium quest would look broken. Test with a high-sodium
//   product after any change here.
// ----------------------------------------------------------------------------
function transformOFFToUSDAShape(p: any): any | null {
  const barcode = String(p.code || "").trim();
  if (!barcode) return null;

  const name = (
    p.product_name_en ||
    p.product_name ||
    p.generic_name ||
    `Product ${barcode}`
  ).toString().trim();

  if (!name) return null;

  const brand = (p.brands || "").toString().split(",")[0]?.trim() || null;
  const brandOwner = (p.brand_owner || brand || null);
  const category = Array.isArray(p.categories_tags) && p.categories_tags.length > 0
    ? String(p.categories_tags[0]).replace(/^en:/, "").replace(/-/g, " ")
    : (p.categories || "").toString().split(",")[0]?.trim() || null;

  const n = p.nutriments || {};

  // Helper — guard against `null`, `undefined`, `""`, and NaN.
  const num = (v: any): number | undefined => {
    if (v === null || v === undefined || v === "") return undefined;
    const n = Number(v);
    return Number.isFinite(n) ? n : undefined;
  };
  const g = (key: string) => num(n[`${key}_100g`]);
  const mgFromG = (key: string) => {
    const v = num(n[`${key}_100g`]);
    return v !== undefined ? v * 1000 : undefined;
  };

  const calories = num(n["energy-kcal_100g"])
    ?? (num(n["energy_100g"]) !== undefined ? num(n["energy_100g"])! / 4.184 : undefined); // kJ→kcal fallback
  const protein = g("proteins");
  const carbs = g("carbohydrates");
  const fat = g("fat");
  const satFat = g("saturated-fat");
  const fiber = g("fiber") ?? g("fibers");
  const sugar = g("sugars");
  const sodium = mgFromG("sodium")
    ?? (mgFromG("salt") !== undefined ? mgFromG("salt")! * 0.4 : undefined); // salt→sodium = ÷ 2.5
  const cholesterol = mgFromG("cholesterol");
  const calcium = mgFromG("calcium");
  const iron = mgFromG("iron");
  const vitC = mgFromG("vitamin-c");

  // Build USDA-shaped foodNutrients array. Same nutrient numbers + units the
  // existing `prepareFoodRow()` knows how to read.
  const foodNutrients: any[] = [];
  const push = (number: string, name: string, unit: string, value: number | undefined) => {
    if (value === undefined) return;
    foodNutrients.push({ nutrientNumber: number, nutrientName: name, unitName: unit, value });
  };
  push("208", "Energy", "KCAL", calories);
  push("203", "Protein", "G", protein);
  push("205", "Carbohydrate, by difference", "G", carbs);
  push("204", "Total lipid (fat)", "G", fat);
  push("606", "Fatty acids, total saturated", "G", satFat);
  push("291", "Fiber, total dietary", "G", fiber);
  push("269", "Sugars, total including NLEA", "G", sugar);
  push("307", "Sodium, Na", "MG", sodium);
  push("601", "Cholesterol", "MG", cholesterol);
  push("301", "Calcium, Ca", "MG", calcium);
  push("303", "Iron, Fe", "MG", iron);
  push("401", "Vitamin C, total ascorbic acid", "MG", vitC);

  // Serving portion. OFF often gives "30 g (about 11 chips)" as a free-form
  // string in `serving_size`, plus a numeric `serving_quantity` in grams.
  const servingQuantity = num(p.serving_quantity);
  const servingDescription = (p.serving_size || "").toString().trim() || null;
  const portions: any[] = [];
  if (servingQuantity && servingQuantity > 0) {
    portions.push({
      id: 1,
      amount: 1,
      unit: "serving",
      gramWeight: servingQuantity,
      description: servingDescription,
    });
  }
  // Always include a 100g portion so the per-100g values render directly.
  portions.push({
    id: 0,
    amount: 100,
    unit: "g",
    gramWeight: 100,
    description: null,
  });

  return {
    fdcId: syntheticFdcIdForBarcode(barcode),
    description: brand ? `${name}, ${brand}` : name,
    dataType: "OFF", // dataType used by ranker — see calculateFoodScore()
    brandName: brand,
    brandOwner,
    foodCategory: category,
    servingSize: 100,
    servingSizeUnit: "g",
    householdServingFullText: servingDescription,
    foodNutrients,
    foodPortions: portions,
    // Carry the OFF-specific fields through so prepareFoodRow can persist
    // them to `food_items.barcode` + `food_items.source`.
    _offBarcode: barcode,
    _offSource: "off",
    _offPopularity: num(p.unique_scans_n) ?? num(p.popularity_key) ?? 0,
    _offCompleteness: num(p.nutriment_data_completeness) ?? num(p.completeness) ?? 0,
    _offImageUrl: p.image_small_url || p.image_url || p.image_front_url || null,
  };
}
