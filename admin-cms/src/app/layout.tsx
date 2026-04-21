import type { Metadata } from 'next'
import { headers } from 'next/headers'
import './globals.css'

export const metadata: Metadata = {
  title: 'Fit33 Admin CMS',
  description: 'Internal admin dashboard for Fit33 — user & exercise management',
}

// CSP nonce plumbing: `src/middleware.ts` generates a fresh nonce per request
// and stashes it on the `x-nonce` request header. Awaiting `headers()` here
// does two things: (1) it tells Next 15 to render the layout dynamically
// instead of at build time, which is the ONLY way the framework will auto-
// attach the nonce to its bootstrap/hydration <script> tags, and (2) it
// surfaces the nonce so we can forward it to any <Script> tags we add later.
// Without this, `script-src 'strict-dynamic' 'nonce-...'` blocks every inline
// script Next emits because none of them carry the matching nonce attribute.
export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Read (but don't need to use) the nonce — the act of reading headers()
  // marks this layout as dynamic, which is what enables the auto-nonce.
  await headers()

  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  )
}
