import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Fit33 Admin CMS',
  description: 'Internal admin dashboard for Fit33 — user & exercise management',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="antialiased">{children}</body>
    </html>
  )
}
