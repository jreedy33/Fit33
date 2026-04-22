// Supabase Edge Function: github-pr-webhook
// -----------------------------------------------------------------------------
// Phase 4 of the Bug Intelligence Pipeline. GitHub fires this edge function
// on every pull_request event. We only care about:
//
//   action: "closed"
//   pull_request.merged: true
//   pull_request.body contains "Suggestion ID: <uuid>"
//
// When those three conditions hold, we close the feedback loop:
//   1. bug_intelligence_reports.review_status  → 'merged'
//      + github_pr_number + github_pr_merged_at + feedback_applied_at
//   2. bug_intelligence_fingerprints.status    → 'resolved'
//      + resolution_pr_url
//   3. If report.suggested_todo was set → append to MASTER_TODO (future Phase 4.1)
//   4. If report.pain_point_candidate was set → append to pain registry (future)
//
// SECURITY
//   GitHub signs every webhook with HMAC-SHA-256 using a shared secret,
//   delivered in `X-Hub-Signature-256: sha256=<hex>`. We verify this
//   signature in constant time before doing anything. If the signature
//   is wrong we return 401 and log the rejection.
//
// SECRETS required (edge function env)
//   GITHUB_WEBHOOK_SECRET  — same string configured in the GitHub webhook UI
//   SUPABASE_SERVICE_ROLE_KEY, SUPABASE_URL  — standard
//
// DEPLOY
//   supabase functions deploy github-pr-webhook --no-verify-jwt
//
//   IMPORTANT: --no-verify-jwt is REQUIRED because GitHub does not send a
//   Supabase JWT. The HMAC signature IS the auth, and we verify it manually.
//
// WEBHOOK REGISTRATION
//   gh api -X POST /repos/jreedy33/Fit33/hooks -f name=web \
//     -f active=true -f events[]=pull_request \
//     -f config.url=https://ehooeghabzefgoqzugrc.supabase.co/functions/v1/github-pr-webhook \
//     -f config.content_type=json \
//     -f config.secret="$GITHUB_WEBHOOK_SECRET" \
//     -f config.insecure_ssl=0
// -----------------------------------------------------------------------------

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// GitHub sends webhooks server-to-server with no Origin header, so we don't
// need CORS. Return a minimal header set for good measure.
const RESPONSE_HEADERS = { "Content-Type": "application/json" };

// -----------------------------------------------------------------------------
// HMAC verification — constant-time per GitHub's docs
// https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries
// -----------------------------------------------------------------------------

async function verifyGithubSignature(rawBody: string, signature: string, secret: string): Promise<boolean> {
    if (!signature || !signature.startsWith("sha256=")) return false;
    const provided = signature.slice("sha256=".length);

    const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
    );
    const sigBuf = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody));
    const expected = Array.from(new Uint8Array(sigBuf))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("");

    if (expected.length !== provided.length) return false;
    let diff = 0;
    for (let i = 0; i < expected.length; i++) {
        diff |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
    }
    return diff === 0;
}

// -----------------------------------------------------------------------------
// PR body parsing — extract Report ID (the bug_intelligence_reports.id UUID)
// from the PR body. The admin CMS github-pr route writes the ID in the
// "Suggestion ID: <uuid>" format today. We also accept "Report-Id:" and
// "Fingerprint:" as future-proof aliases.
// -----------------------------------------------------------------------------

function extractReportId(body: string): string | null {
    if (!body) return null;
    const patterns = [
        /\bSuggestion ID:\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b/i,
        /\bReport[- ]?Id:\s*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b/i,
    ];
    for (const re of patterns) {
        const m = body.match(re);
        if (m) return m[1];
    }
    return null;
}

function extractFingerprint(body: string): string | null {
    if (!body) return null;
    const m = body.match(/\bFingerprint:\s*([0-9a-f]{32})\b/i);
    return m ? m[1] : null;
}

// -----------------------------------------------------------------------------
// Entry point
// -----------------------------------------------------------------------------

serve(async (req) => {
    // GitHub only sends POST, ignore everything else so attackers can't fish
    // our internals with GET / OPTIONS.
    if (req.method !== "POST") {
        return new Response("Method not allowed", { status: 405 });
    }

    const secret = Deno.env.get("GITHUB_WEBHOOK_SECRET");
    if (!secret) {
        console.error("github-pr-webhook: GITHUB_WEBHOOK_SECRET not configured");
        return new Response(
            JSON.stringify({ error: "Webhook secret not configured" }),
            { status: 500, headers: RESPONSE_HEADERS },
        );
    }

    const rawBody = await req.text();
    const signature = req.headers.get("X-Hub-Signature-256") ?? "";
    const ok = await verifyGithubSignature(rawBody, signature, secret);
    if (!ok) {
        console.warn("github-pr-webhook: invalid signature — rejecting");
        return new Response(
            JSON.stringify({ error: "Invalid signature" }),
            { status: 401, headers: RESPONSE_HEADERS },
        );
    }

    const event = req.headers.get("X-GitHub-Event");
    // GitHub sends a `ping` event immediately after webhook registration.
    // Acknowledge it so the UI shows a green checkmark.
    if (event === "ping") {
        return new Response(
            JSON.stringify({ message: "pong" }),
            { status: 200, headers: RESPONSE_HEADERS },
        );
    }

    if (event !== "pull_request") {
        return new Response(
            JSON.stringify({ message: `Ignored event: ${event}` }),
            { status: 200, headers: RESPONSE_HEADERS },
        );
    }

    let payload: {
        action?: string;
        pull_request?: {
            number?: number;
            html_url?: string;
            merged?: boolean;
            merged_at?: string;
            title?: string;
            body?: string;
        };
    };
    try {
        payload = JSON.parse(rawBody);
    } catch {
        return new Response(
            JSON.stringify({ error: "Invalid JSON payload" }),
            { status: 400, headers: RESPONSE_HEADERS },
        );
    }

    const action = payload.action;
    const pr = payload.pull_request;
    if (action !== "closed" || !pr || !pr.merged) {
        return new Response(
            JSON.stringify({ message: `Ignored action: ${action}, merged=${pr?.merged}` }),
            { status: 200, headers: RESPONSE_HEADERS },
        );
    }

    const reportId = extractReportId(pr.body ?? "");
    const fingerprint = extractFingerprint(pr.body ?? "");
    if (!reportId && !fingerprint) {
        return new Response(
            JSON.stringify({
                message: "PR merged but no BugIntel marker in body — ignoring",
                pr_number: pr.number,
            }),
            { status: 200, headers: RESPONSE_HEADERS },
        );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // --- Resolve report + fingerprint ---------------------------------------
    let resolvedReportId = reportId;
    let resolvedFingerprint = fingerprint;

    if (resolvedReportId && !resolvedFingerprint) {
        const { data } = await supabase
            .from("bug_intelligence_reports")
            .select("fingerprint")
            .eq("id", resolvedReportId)
            .maybeSingle();
        if (data) resolvedFingerprint = (data as { fingerprint: string }).fingerprint;
    }

    if (!resolvedReportId && resolvedFingerprint) {
        // Fingerprint-only PR — update the most recent pending report for this fingerprint.
        const { data } = await supabase
            .from("bug_intelligence_reports")
            .select("id")
            .eq("fingerprint", resolvedFingerprint)
            .in("review_status", ["pending", "approved"])
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle();
        if (data) resolvedReportId = (data as { id: string }).id;
    }

    // --- Update report -------------------------------------------------------
    let reportUpdated = false;
    if (resolvedReportId) {
        const { error } = await supabase
            .from("bug_intelligence_reports")
            .update({
                review_status: "merged",
                pr_url: pr.html_url,
                github_pr_number: pr.number,
                github_pr_merged_at: pr.merged_at ?? new Date().toISOString(),
                feedback_applied_at: new Date().toISOString(),
            })
            .eq("id", resolvedReportId);
        if (error) {
            console.error("github-pr-webhook: report update failed", error);
        } else {
            reportUpdated = true;
        }
    }

    // --- Update fingerprint --------------------------------------------------
    // Only mark resolved when no other pending report for this fingerprint
    // is still under review — so if Claude generated two candidate reports
    // for the same bug and we merge one, the other's status stays pending.
    let fingerprintResolved = false;
    if (resolvedFingerprint) {
        const { data: otherReports } = await supabase
            .from("bug_intelligence_reports")
            .select("id, review_status")
            .eq("fingerprint", resolvedFingerprint);
        const hasOtherOpen = (otherReports ?? []).some((r: { id: string; review_status: string }) =>
            r.id !== resolvedReportId && r.review_status === "pending"
        );

        const updatePayload: Record<string, unknown> = {
            resolution_pr_url: pr.html_url,
            updated_at: new Date().toISOString(),
        };
        if (!hasOtherOpen) {
            updatePayload.status = "resolved";
        }

        const { error } = await supabase
            .from("bug_intelligence_fingerprints")
            .update(updatePayload)
            .eq("fingerprint", resolvedFingerprint);
        if (error) {
            console.error("github-pr-webhook: fingerprint update failed", error);
        } else {
            fingerprintResolved = !hasOtherOpen;
        }
    }

    return new Response(
        JSON.stringify({
            message: "Webhook processed",
            pr_number: pr.number,
            report_id: resolvedReportId,
            fingerprint: resolvedFingerprint,
            report_updated: reportUpdated,
            fingerprint_resolved: fingerprintResolved,
        }),
        { status: 200, headers: RESPONSE_HEADERS },
    );
});
