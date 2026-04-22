import { NextResponse } from 'next/server'
import { z, ZodError, ZodType } from 'zod'

// Q2-86 (Sprint 9 2026-04-28): Central Zod schemas + helpers for Admin CMS
// API routes. Before Sprint 9, routes parsed `await req.json()` directly and
// did ad-hoc presence checks (`if (!email || !password)`), which meant:
//  - Malformed JSON threw an un-surfaced `SyntaxError` caught by the
//    catch-all 500.
//  - Type coercion surprises (e.g. boolean where string expected) only
//    surfaced when Supabase rejected them later, leaking internal errors.
//  - Unknown / extra fields silently passed through.
//
// `parseJson(req, schema)` returns a discriminated result so callers can
// short-circuit with a 400 that includes a compact field-level error map
// without repeating the same try/catch boilerplate everywhere.

export type ParseResult<T> =
    | { ok: true; data: T }
    | { ok: false; response: NextResponse }

export async function parseJson<T>(
    req: Request,
    schema: ZodType<T>,
): Promise<ParseResult<T>> {
    let raw: unknown
    try {
        raw = await req.json()
    } catch {
        return {
            ok: false,
            response: NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 }),
        }
    }

    const parsed = schema.safeParse(raw)
    if (!parsed.success) {
        return {
            ok: false,
            response: NextResponse.json(
                {
                    error: 'Validation failed',
                    issues: flattenZodIssues(parsed.error),
                },
                { status: 400 },
            ),
        }
    }

    return { ok: true, data: parsed.data }
}

function flattenZodIssues(error: ZodError): Record<string, string> {
    const out: Record<string, string> = {}
    for (const issue of error.issues) {
        const path = issue.path.length > 0 ? issue.path.join('.') : '_root'
        if (!(path in out)) out[path] = issue.message
    }
    return out
}

// MARK: - Shared primitives

const emailSchema = z.string().trim().toLowerCase().email('Must be a valid email')
const nonEmptyString = z.string().min(1, 'Required')

// MARK: - Route schemas

export const loginSchema = z.object({
    email: emailSchema,
    password: z.string().min(1, 'Password required'),
})

export const verifyMfaSchema = z.object({
    factor_id: nonEmptyString,
    code: z.string().regex(/^\d{6}$/, 'Code must be 6 digits'),
    temp_token: nonEmptyString,
    temp_refresh: nonEmptyString,
    temp_expires: z.number().int().nonnegative().optional(),
})

export const aiChatSchema = z.object({
    messages: z
        .array(
            z.object({
                role: z.enum(['user', 'assistant']),
                content: z.string().min(1).max(20000),
            }),
        )
        .min(1)
        .max(50),
    conversationId: z.string().uuid().optional(),
    fetchData: z.boolean().optional(),
})

// Single suggestion PR.
export const githubPrSingleSchema = z.object({
    suggestion_id: z.string().max(100).optional(),
    title: nonEmptyString.max(200),
    description: z.string().max(10000).optional().default(''),
    file_path: nonEmptyString.max(500),
    code_diff: nonEmptyString.max(500000),
    session_id: z.string().max(100).optional(),
})

// Batch PR — multiple suggestions bundled into a single branch.
export const githubPrBatchSchema = z.object({
    batch: z.literal(true),
    session_id: z.string().max(100).optional(),
    suggestions: z
        .array(
            z.object({
                suggestion_id: z.string().max(100).optional(),
                title: nonEmptyString.max(200),
                description: z.string().max(10000).optional().default(''),
                file_path: nonEmptyString.max(500),
                code_diff: nonEmptyString.max(500000),
            }),
        )
        .min(1)
        .max(20),
})

export const githubPrSchema = z.union([githubPrBatchSchema, githubPrSingleSchema])

export const devLogAnalysisSchema = z.object({
    session_id: nonEmptyString.max(100),
})

// Admin router dispatcher — the `/api/admin` route uses a single POST with an
// action field that switches between 80+ different sub-actions. Writing a
// schema per sub-action is impractical; instead we enforce the envelope here
// and rely on per-action code to validate its own params. Zod still guards
// the most important invariant: that `action` is a non-empty string.
export const adminEnvelopeSchema = z
    .object({
        action: z.string().min(1).max(100),
    })
    .passthrough()
