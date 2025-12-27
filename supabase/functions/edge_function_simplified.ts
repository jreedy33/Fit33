// Built Simple - USDA Food Search Edge Function
// Copy this ENTIRE file into Supabase Edge Function editor

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const USDA_API_KEY = Deno.env.get("USDA_API_KEY")!
const USDA_BASE_URL = "https://api.nal.usda.gov/fdc/v1"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  // Handle CORS
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const { action, query, fdcId, pageSize = 100 } = await req.json()

    if (action === "search") {
      // Search USDA API
      const dataTypes = "Foundation,SR Legacy,Survey (FNDDS),Branded"
      const url = `${USDA_BASE_URL}/foods/search?query=${encodeURIComponent(query)}&dataType=${dataTypes}&pageSize=${pageSize}&api_key=${USDA_API_KEY}`
      
      const response = await fetch(url)
      const data = await response.json()
      
      return new Response(
        JSON.stringify({
          source: "usda",
          foods: data.foods || [],
          totalHits: data.totalHits || 0,
          query: query
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    } 
    
    else if (action === "details") {
      // Get food details
      const url = `${USDA_BASE_URL}/food/${fdcId}?api_key=${USDA_API_KEY}`
      
      const response = await fetch(url)
      const data = await response.json()
      
      return new Response(
        JSON.stringify({
          source: "usda",
          food: data
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }
    
    else {
      return new Response(
        JSON.stringify({ error: "Invalid action" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }
  } catch (error) {
    console.error("Error:", error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})

console.log("✅ USDA Food Search Edge Function is running!")






