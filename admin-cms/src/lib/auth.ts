// Admin email whitelist check
export function isAdminEmail(email: string): boolean {
  const allowedEmails = (process.env.ADMIN_EMAILS || '')
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean)

  return allowedEmails.includes(email.toLowerCase())
}
