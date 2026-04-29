'use client'

// /revenue/experiments — paywall A/B test results.
// Owner: MONETIZATION_AGENT.md (invariant 27 — Experiments tab; Phase 5 deliverable).
//
// The `paywall_experiments` and `paywall_experiment_assignments` tables
// are deployed (Phase 1a) but no experiments have been seeded yet. This
// page renders the contract so the nav link works and the build sequence
// stays visible. Real experiment results render here in Phase 5.

import AdminShell from '@/components/AdminShell'
import { RevenueHeader } from '@/components/RevenueTabNav'

export default function ExperimentsPage() {
  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <RevenueHeader subtitle="Paywall A/B experiments. Schema deployed; assignment RPC + experiment runner ship in Phase 5." />

        <div className="card text-center py-16">
          <div className="text-5xl mb-4">🧪</div>
          <div className="text-lg font-semibold mb-1" style={{ color: 'var(--text-primary)' }}>
            Experiments — coming in Phase 5
          </div>
          <div className="text-sm mb-3 max-w-lg mx-auto" style={{ color: 'var(--text-secondary)' }}>
            Tables are live. Phase 5 wires the assignment RPC, the iOS paywall variant
            renderer, and the result aggregator. Each variant gates on n_assigned ≥ 200
            and a 95% Bayesian credible-interval before declaring a winner.
          </div>
          <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
            See <code style={{ color: 'var(--accent)' }}>MONETIZATION_AGENT.md</code> §
            Phased Rollout — Phase 5.
          </div>
        </div>
      </div>
    </AdminShell>
  )
}
