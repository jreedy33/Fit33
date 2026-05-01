import Foundation

/// `CommonFoodDensities` — per-food override table for volumetric → gram
/// unit conversions in the food logger.
///
/// **Why this file exists.** The 2026-04-30 nutrition pipeline audit found
/// that `FoodDetailsView.ServingUnit.cups` was hardcoded to `240.0`g (the
/// volume of one US cup of WATER). For any food where 1 cup ≠ 240 g of edible
/// mass, the calorie math overcounts (or undercounts) by the density gap:
///
///     • Cooked white rice    → 158 g/cup  (240 g over-counts by  +52%)
///     • Rolled oats (dry)    →  81 g/cup  (240 g over-counts by +196%)
///     • Spinach (raw)        →  30 g/cup  (240 g over-counts by +700%)
///     • All-purpose flour    → 125 g/cup  (240 g over-counts by  +92%)
///     • Almonds (whole)      → 143 g/cup  (240 g over-counts by  +68%)
///
/// USDA FoodData Central ships per-food `foodPortions` arrays with the
/// correct gram weight for each measure (e.g. "1 cup, NLEA serving = 158 g")
/// and the app DOES surface them as quick-tap "Quick Portions" chips, but
/// the **dropdown unit picker** ("g / oz / cup / tbsp / tsp / ml") falls
/// back to the hardcoded volume when the user picks `cups` from the menu.
/// This file fixes that fallback for the foods where it matters.
///
/// **Design.** Two-stage lookup:
///   1. Exact category match (USDA categories like "Cereal Grains and Pasta")
///   2. Substring match on the lowercased food name (e.g. "rice" → 158 g/cup)
///
/// We deliberately keep the table small. The ground truth is the USDA
/// portions array on each food — when present, FoodDetailsView prefers a
/// `food.portions` entry over both this table AND the volumetric default.
/// This table only kicks in when:
///   - the food has no portions (e.g. local hardcoded foods, OFF rows
///     without `serving_quantity`), AND
///   - the user picks a volumetric unit from the dropdown.
///
/// **Adding new entries.** Source values from USDA FoodData Central
/// "Standard Reference Legacy" gram weights for the canonical preparation
/// (cooked vs raw matters). Cite the FDC ID in the inline comment.
///
/// **Units we override.** Currently only `cup`, `tbsp`, `tsp` (the three
/// volumetric units that vary most by density). `ml` stays 1 g/ml (water
/// is a fine default for liquids; oils/syrups are within ±10%). `oz` is
/// always 28.3495 g (mass, not volume).
enum CommonFoodDensities {

    // MARK: - Public API

    /// Returns the food-specific gram weight per 1 of `unit`, or `nil` if
    /// no override applies (caller falls back to `ServingUnit.gramsPerUnit`).
    static func gramsPerUnit(
        _ unit: String,
        foodName: String,
        category: String? = nil
    ) -> Double? {
        switch unit.lowercased() {
        case "cup", "cups":
            return gramsPerCup(foodName: foodName, category: category)
        case "tbsp", "tablespoon", "tablespoons":
            return gramsPerTablespoon(foodName: foodName, category: category)
        case "tsp", "teaspoon", "teaspoons":
            return gramsPerTeaspoon(foodName: foodName, category: category)
        default:
            return nil
        }
    }

    // MARK: - Cup (volumetric → mass) lookups

    /// One US cup = 236.588 mL. Default fallback is 240 g (water/milk),
    /// returned via `nil` so callers use their own default.
    private static func gramsPerCup(foodName: String, category: String?) -> Double? {
        let n = foodName.lowercased()
        let c = (category ?? "").lowercased()

        // ───────────────────────────────────────────────────────────
        // Liquids — keep ~240 g/cup default (water, milk, juice, etc.)
        // Override only for thick liquids materially denser than water.
        // ───────────────────────────────────────────────────────────
        if n.contains("honey")            { return 340 } // ~21g/tbsp × 16
        if n.contains("maple syrup")      { return 322 }
        if n.contains("molasses")         { return 337 }
        if n.contains("peanut butter")    { return 258 }
        if n.contains("almond butter")    { return 250 }
        if n.contains("greek yogurt")     { return 245 }

        // ───────────────────────────────────────────────────────────
        // Grains — cooked vs uncooked matters dramatically.
        // ───────────────────────────────────────────────────────────
        if n.contains("rice") {
            if n.contains("uncooked") || n.contains("dry") || n.contains("raw") { return 185 }
            return 158 // cooked white/brown rice (USDA FDC 169704)
        }
        if n.contains("quinoa") {
            if n.contains("uncooked") || n.contains("dry") { return 170 }
            return 185 // cooked
        }
        if n.contains("couscous") {
            return n.contains("dry") ? 173 : 173
        }
        if n.contains("oat") {
            // "rolled oats", "old fashioned oats", "instant oats", "oatmeal"
            if n.contains("cooked") || n.contains("oatmeal") { return 234 } // cooked porridge
            return 81 // dry rolled oats
        }
        if n.contains("pasta") || n.contains("spaghetti") || n.contains("macaroni")
            || n.contains("penne") || n.contains("rotini") || n.contains("fusilli") {
            return n.contains("dry") ? 100 : 140 // cooked
        }
        if n.contains("noodle") {
            return 160 // cooked egg noodles
        }
        if n.contains("flour") {
            if n.contains("almond") || n.contains("coconut") { return 96 }
            return 125 // all-purpose / wheat flour
        }
        if n.contains("sugar") {
            if n.contains("brown") { return 213 } // packed
            if n.contains("powdered") || n.contains("confectioner") { return 120 }
            return 200 // granulated white
        }
        if n.contains("cornmeal") || n.contains("corn meal") { return 122 }
        if n.contains("bread crumb") || n.contains("breadcrumb") { return 108 }

        // ───────────────────────────────────────────────────────────
        // Cereals — most are very airy.
        // ───────────────────────────────────────────────────────────
        if c.contains("breakfast cereal") || n.contains("cereal") {
            if n.contains("granola") || n.contains("muesli") { return 110 }
            if n.contains("flake") { return 30 }       // corn flakes, bran flakes
            if n.contains("puff") || n.contains("rice krispie") { return 14 }
            return 40 // generic cereal
        }

        // ───────────────────────────────────────────────────────────
        // Vegetables — wildly variable, dominated by water content.
        // ───────────────────────────────────────────────────────────
        if c.contains("vegetable") || n.contains("spinach") || n.contains("lettuce")
            || n.contains("kale") || n.contains("arugula") {
            if n.contains("spinach") || n.contains("arugula") { return 30 }  // raw leafy
            if n.contains("lettuce") || n.contains("kale") { return 36 }
            if n.contains("broccoli") { return n.contains("raw") ? 91 : 156 }
            if n.contains("cauliflower") { return n.contains("raw") ? 100 : 124 }
            if n.contains("carrot") { return n.contains("raw") ? 128 : 156 }
            if n.contains("tomato") { return n.contains("chopped") ? 180 : 149 }
            if n.contains("cucumber") { return 119 }
            if n.contains("bell pepper") || n.contains("pepper") { return 149 }
            if n.contains("onion") { return n.contains("chopped") ? 160 : 110 }
            if n.contains("mushroom") { return n.contains("sliced") ? 70 : 96 }
            if n.contains("zucchini") || n.contains("squash") { return 124 }
            if n.contains("corn") { return 165 } // kernels
            if n.contains("pea") || n.contains("green peas") { return 160 }
            // Fallback for unknown raw chopped vegetables — use a leafy/light avg
            return 90
        }

        // ───────────────────────────────────────────────────────────
        // Fruits (fresh, chopped/diced).
        // ───────────────────────────────────────────────────────────
        if c.contains("fruit") {
            if n.contains("strawberr") { return n.contains("sliced") ? 166 : 144 }
            if n.contains("blueberr")  { return 148 }
            if n.contains("raspberr")  { return 123 }
            if n.contains("blackberr") { return 144 }
            if n.contains("grape")     { return 151 }
            if n.contains("pineapple") { return 165 }
            if n.contains("watermelon"){ return 152 }
            if n.contains("banana")    { return 150 } // sliced or mashed
            if n.contains("apple")     { return 125 } // chopped
            if n.contains("mango")     { return 165 }
            if n.contains("peach")     { return 154 }
            return 150 // generic chopped fruit
        }

        // ───────────────────────────────────────────────────────────
        // Proteins — chopped/diced/shredded volume.
        // ───────────────────────────────────────────────────────────
        if n.contains("chicken") || n.contains("turkey") {
            if n.contains("chopped") || n.contains("diced") || n.contains("shredded") {
                return 140 // cooked, diced (USDA FDC 171477)
            }
        }
        if n.contains("beef") || n.contains("ground beef") {
            if n.contains("crumble") || n.contains("ground") { return 220 } // cooked, crumbled
        }
        if n.contains("tuna") && n.contains("flake") { return 150 }
        if n.contains("egg") {
            if n.contains("scrambled") { return 220 }
            if n.contains("white")     { return 243 }
            if n.contains("yolk")      { return 243 }
        }

        // ───────────────────────────────────────────────────────────
        // Beans, legumes, nuts, seeds.
        // ───────────────────────────────────────────────────────────
        if n.contains("black bean") || n.contains("kidney bean") || n.contains("pinto bean")
            || n.contains("garbanzo") || n.contains("chickpea") {
            return 170 // cooked
        }
        if n.contains("lentil") { return 198 } // cooked
        if n.contains("almond") { return n.contains("sliced") ? 92 : 143 }
        if n.contains("walnut") { return n.contains("chopped") ? 117 : 100 }
        if n.contains("pecan")  { return n.contains("chopped") ? 109 : 99 }
        if n.contains("cashew") { return 137 }
        if n.contains("peanut") && !n.contains("butter") { return 146 }
        if n.contains("pistachio") { return 123 }
        if n.contains("chia seed") { return 168 }
        if n.contains("flax") { return 168 }
        if n.contains("sunflower") && n.contains("seed") { return 140 }
        if n.contains("pumpkin") && n.contains("seed") { return 129 }

        // ───────────────────────────────────────────────────────────
        // Cheese, dairy solids — denser than milk.
        // ───────────────────────────────────────────────────────────
        if n.contains("cheddar") || (n.contains("cheese") && (n.contains("shred") || n.contains("grate"))) {
            return 113
        }
        if n.contains("parmesan") && n.contains("grate") { return 100 }
        if n.contains("mozzarella") && n.contains("shred") { return 113 }
        if n.contains("ricotta") { return 246 }
        if n.contains("cottage cheese") { return 226 }
        if n.contains("ice cream") { return 132 }

        // ───────────────────────────────────────────────────────────
        // No override → caller uses 240g (water/milk) default.
        // ───────────────────────────────────────────────────────────
        return nil
    }

    // MARK: - Tablespoon / Teaspoon — weight-by-density refinements.

    /// Default tbsp = 15 g (water). Overrides for dense or airy items.
    private static func gramsPerTablespoon(foodName: String, category: String?) -> Double? {
        let n = foodName.lowercased()
        if n.contains("honey")          { return 21 }
        if n.contains("maple syrup")    { return 20 }
        if n.contains("molasses")       { return 20 }
        if n.contains("peanut butter")  { return 16 }
        if n.contains("almond butter")  { return 16 }
        if n.contains("butter") && !n.contains("nut")    { return 14 } // dairy butter
        if n.contains("oil") || n.contains("olive oil")  { return 14 } // ~0.92 g/mL × 15
        if n.contains("flour")          { return 8 }
        if n.contains("sugar") && n.contains("brown")    { return 13 }
        if n.contains("sugar")          { return 12 }
        if n.contains("cocoa powder")   { return 5 }
        if n.contains("cinnamon")       { return 8 }
        if n.contains("salt")           { return 18 } // table salt is dense
        if n.contains("vanilla extract") || n.contains("vanilla") { return 13 }
        if n.contains("mayo") || n.contains("mayonnaise") { return 14 }
        if n.contains("ketchup")        { return 17 }
        if n.contains("mustard")        { return 15 }
        if n.contains("soy sauce")      { return 16 }
        if n.contains("vinegar")        { return 15 }
        if n.contains("yogurt")         { return 15 }
        if n.contains("chia seed") || n.contains("flax") { return 10 }
        return nil
    }

    /// Default tsp = 5 g (water). Overrides for dense ingredients (especially
    /// the salt one — a "tsp salt" reads as 6 g not 5 g, which shifts
    /// sodium from "below limit" to "over limit" on quest checks).
    private static func gramsPerTeaspoon(foodName: String, category: String?) -> Double? {
        let n = foodName.lowercased()
        if n.contains("salt")           { return 6 }   // table salt
        if n.contains("baking powder")  { return 4 }
        if n.contains("baking soda")    { return 4.6 }
        if n.contains("sugar") && n.contains("brown") { return 4.5 }
        if n.contains("sugar")          { return 4 }
        if n.contains("flour")          { return 2.6 }
        if n.contains("cinnamon")       { return 2.6 }
        if n.contains("cocoa powder")   { return 1.7 }
        if n.contains("oil")            { return 4.6 } // 0.92 × 5
        if n.contains("vanilla")        { return 4 }
        if n.contains("honey")          { return 7 }
        return nil
    }
}
