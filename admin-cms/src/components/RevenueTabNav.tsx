'use client'

// Shared Revenue tab navigation (Phase 3 — MON-10/11/12).
// Renders the same five sub-tabs across /revenue, /revenue/subscribers,
// /revenue/transactions, /revenue/grants, /revenue/experiments. Using
// Next.js <Link> instead of in-state activeTab gives shareable URLs and
// matches how every other top-level admin tab works (Users, Bugs, etc.).
//
// Owner: MONETIZATION_AGENT.md (invariant 27 — sub-tab nav contract).

import Link from 'next/link'
import { usePathname } from 'next/navigation'

export type RevenueTabId = 'overview' | 'subscribers' | 'transactions' | 'grants' | 'experiments'

interface RevenueTab {
  id: RevenueTabId
  label: string
  icon: string
  href: string
  phaseGate: string
}

export const REVENUE_TABS: RevenueTab[] = [
  { id: 'overview',     label: 'Overview',     icon: '💰', href: '/revenue',              phaseGate: 'Phase 2' },
  { id: 'subscribers',  label: 'Subscribers',  icon: '👥', href: '/revenue/subscribers',  phaseGate: 'Phase 3' },
  { id: 'transactions', label: 'Transactions', icon: '🧾', href: '/revenue/transactions', phaseGate: 'Phase 3' },
  { id: 'grants',       label: 'Grants',       icon: '🎁', href: '/revenue/grants',       phaseGate: 'Phase 4' },
  { id: 'experiments',  label: 'Experiments',  icon: '🧪', href: '/revenue/experiments',  phaseGate: 'Phase 5' },
]

export default function RevenueTabNav() {
  const pathname = usePathname()

  return (
    <nav className="flex gap-2 border-b mt-4" style={{ borderColor: 'var(--border)' }}>
      {REVENUE_TABS.map((tab) => {
        const isActive = pathname === tab.href
        return (
          <Link
            key={tab.id}
            href={tab.href}
            className="px-4 py-2.5 text-sm font-medium border-b-2 transition-colors"
            style={{
              borderColor: isActive ? 'var(--accent)' : 'transparent',
              color: isActive ? 'var(--accent)' : 'var(--text-secondary)',
            }}
          >
            <span className="mr-2">{tab.icon}</span>
            {tab.label}
          </Link>
        )
      })}
    </nav>
  )
}

export function RevenueHeader({
  subtitle,
}: {
  subtitle?: string
}) {
  return (
    <header className="mb-6">
      <div className="flex items-center justify-between mb-2">
        <div>
          <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Revenue</h1>
          <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
            {subtitle || (
              <>
                Subscriptions, IAP, ad revenue, comp grants. Owner:{' '}
                <code style={{ color: 'var(--accent)' }}>MONETIZATION_AGENT.md</code>
              </>
            )}
          </p>
        </div>
      </div>
      <RevenueTabNav />
    </header>
  )
}
