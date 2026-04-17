// Shared CORS + auth helpers for Fit33 edge functions.
//
// Produces a locked-down set of headers instead of `Access-Control-Allow-Origin: *`.
// Only the iOS app (via supabase-swift, which does NOT send Origin) and our
// known admin/web properties are allowed. Anything else gets no CORS allowance
// so cross-origin browsers are blocked at the preflight.
//
// Usage:
//   import { buildCorsHeaders, requireUserAuth, requireServiceRole } from "../_shared/cors.ts"
//   const corsHeaders = buildCorsHeaders(req)
//
// The iOS supabase-swift SDK does NOT set the Origin header, so CORS checks
// are inert for native callers — this only matters for browser/webview callers
// (admin CMS, website).

const ALLOWED_ORIGINS = new Set<string>([
  "https://admin.doublethr33s.com",
  "https://doublethr33s.com",
  "https://www.doublethr33s.com",
  "https://fit33.app",
  "https://www.fit33.app",
  // Local dev
  "http://localhost:3000",
  "http://localhost:3001",
  "http://127.0.0.1:3000",
]);

export function buildCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allow = ALLOWED_ORIGINS.has(origin) ? origin : "";
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-cron-key, x-moderation-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

export function isAllowedOrigin(req: Request): boolean {
  const origin = req.headers.get("Origin");
  // Native apps (supabase-swift / Deno server-to-server) send no Origin header.
  // Treat "no Origin" as allowed. Browser callers must be on the allowlist.
  if (!origin) return true;
  return ALLOWED_ORIGINS.has(origin);
}

// =============================================================================
// AUTH HELPERS
// =============================================================================

export interface AuthResult {
  userId: string | null;
  isServiceRole: boolean;
}

/**
 * Require ANY valid auth: a Supabase user JWT or the service role key.
 * Returns 401 Response on failure (callers should early-return).
 */
export async function requireUserAuth(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  corsHeaders: Record<string, string>,
): Promise<{ ok: true; auth: AuthResult } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: "Missing authorization" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      ),
    };
  }

  const token = authHeader.replace("Bearer ", "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (token === serviceKey) {
    return { ok: true, auth: { userId: null, isServiceRole: true } };
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      ),
    };
  }

  return { ok: true, auth: { userId: user.id, isServiceRole: false } };
}

/**
 * Require service-role OR an email in the admin allowlist (table: ai_insights_admin_emails).
 * Used for endpoints that dump cross-user aggregates (generate-ai-insights).
 */
export async function requireServiceOrAdminEmail(
  req: Request,
  // deno-lint-ignore no-explicit-any
  supabase: any,
  corsHeaders: Record<string, string>,
  adminTable: string = "ai_insights_admin_emails",
): Promise<{ ok: true; auth: AuthResult } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: "Missing authorization" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      ),
    };
  }

  const token = authHeader.replace("Bearer ", "");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  if (token === serviceKey) {
    return { ok: true, auth: { userId: null, isServiceRole: true } };
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user || !user.email) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      ),
    };
  }

  const { data: adminRow } = await supabase
    .from(adminTable)
    .select("email")
    .eq("email", user.email.toLowerCase())
    .maybeSingle();

  if (!adminRow) {
    return {
      ok: false,
      response: new Response(
        JSON.stringify({ error: "Forbidden" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      ),
    };
  }

  return { ok: true, auth: { userId: user.id, isServiceRole: false } };
}

/**
 * Verify a shared-secret webhook header (used for DB webhooks -> edge function).
 * Uses timing-safe comparison to resist timing attacks.
 */
export function verifyWebhookSecret(req: Request, envVar: string): boolean {
  const expected = Deno.env.get(envVar) ?? "";
  const provided = req.headers.get("x-moderation-secret") ?? "";
  if (!expected || !provided) return false;
  if (expected.length !== provided.length) return false;
  // Constant-time compare
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  }
  return diff === 0;
}
