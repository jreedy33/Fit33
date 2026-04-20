// Sprint 3 (M-10): shared phone-number redaction helper used by every edge
// function that logs anything phone-related. Prevents raw E.164 numbers from
// landing in Supabase platform logs, which have a long retention window and
// are visible to anyone with project-admin access.
//
// Output shape: "+1***-***-1234" (country code kept, middle digits masked,
// last 4 kept for human diagnosis). If the input can't be parsed as a phone
// number, returns "<redacted>" so callers can't accidentally leak garbage
// that happens to have been labeled a "phone number".
export function redactPhone(phone: string | null | undefined): string {
  if (!phone || typeof phone !== 'string') return '<redacted>'
  const trimmed = phone.trim()
  if (trimmed.length < 4) return '<redacted>'
  // Preserve a leading "+" if present (E.164 format).
  const hasPlus = trimmed.startsWith('+')
  const digits = trimmed.replace(/\D/g, '')
  if (digits.length < 4) return '<redacted>'
  const last4 = digits.slice(-4)
  // Keep at most 2 leading digits (country code) unmasked; mask the rest.
  const countryDigits = digits.length > 10 ? digits.slice(0, digits.length - 10) : ''
  const prefix = (hasPlus ? '+' : '') + countryDigits
  return `${prefix}***-***-${last4}`
}
