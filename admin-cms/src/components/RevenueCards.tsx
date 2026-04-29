// Shared cards + helpers for the Revenue tab pages.
// Owner: MONETIZATION_AGENT.md (visual contract for /revenue/*).

export function formatCents(cents: number | undefined | null): string {
  if (cents === undefined || cents === null) return '—'
  return `$${(cents / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`
}

export function formatDateTime(iso: string | null | undefined): string {
  if (!iso) return '—'
  try {
    const d = new Date(iso)
    return d.toLocaleString(undefined, { dateStyle: 'medium', timeStyle: 'short' })
  } catch {
    return iso
  }
}

export function formatRelative(iso: string | null | undefined): string {
  if (!iso) return '—'
  try {
    const t = new Date(iso).getTime()
    const diff = Date.now() - t
    const sec = Math.floor(diff / 1000)
    if (sec < 60) return `${sec}s ago`
    const min = Math.floor(sec / 60)
    if (min < 60) return `${min}m ago`
    const hr = Math.floor(min / 60)
    if (hr < 24) return `${hr}h ago`
    const day = Math.floor(hr / 24)
    if (day < 30) return `${day}d ago`
    return formatDateTime(iso)
  } catch {
    return '—'
  }
}

export function KpiCard({
  label,
  value,
  delta,
  deltaFormat,
  color,
}: {
  label: string
  value: number | string
  delta?: number | null
  deltaFormat?: 'cents' | 'count'
  color: string
}) {
  const showDelta = delta !== null && delta !== undefined && delta !== 0
  const deltaPositive = (delta ?? 0) > 0
  const deltaLabel = showDelta
    ? deltaFormat === 'cents'
      ? `${deltaPositive ? '+' : ''}$${((delta ?? 0) / 100).toFixed(2)}`
      : `${deltaPositive ? '+' : ''}${delta}`
    : null

  return (
    <div className="card">
      <div className="flex items-center gap-3">
        <div
          className="w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0"
          style={{ background: `${color}18`, color }}
        >
          ●
        </div>
        <div className="flex-1 min-w-0">
          <div className="text-xs font-medium" style={{ color: 'var(--text-secondary)' }}>
            {label}
          </div>
          <div className="text-xl font-bold truncate" style={{ color: 'var(--text-primary)' }}>
            {typeof value === 'number' ? value.toLocaleString() : value}
          </div>
          {deltaLabel && (
            <div
              className="text-xs font-medium mt-0.5"
              style={{ color: deltaPositive ? '#22c55e' : '#ef4444' }}
            >
              {deltaLabel} vs yesterday
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export function SignalCard({
  label,
  value,
  note,
}: {
  label: string
  value: number | string
  note: string
}) {
  return (
    <div className="card">
      <div className="text-xs font-medium mb-1" style={{ color: 'var(--text-secondary)' }}>
        {label}
      </div>
      <div className="text-xl font-bold mb-2" style={{ color: 'var(--text-primary)' }}>
        {typeof value === 'number' ? value.toLocaleString() : value}
      </div>
      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
        {note}
      </div>
    </div>
  )
}

// Friendly label + color for a subscription status enum value.
export function statusBadge(status: string): { label: string; color: string } {
  switch (status) {
    case 'active':        return { label: 'Active',        color: '#22c55e' }
    case 'in_trial':      return { label: 'Trial',         color: '#3b82f6' }
    case 'grace_period':  return { label: 'Grace',         color: '#f59e0b' }
    case 'paused':        return { label: 'Paused',        color: '#a855f7' }
    case 'pending':       return { label: 'Pending',       color: '#6b7280' }
    case 'expired':       return { label: 'Expired',       color: '#6b7280' }
    case 'revoked':       return { label: 'Revoked',       color: '#ef4444' }
    default:              return { label: status,          color: '#6b7280' }
  }
}

// Friendly label for a subscription tier enum.
export function tierLabel(tier: string): string {
  switch (tier) {
    case 'pro_monthly':  return 'Pro Monthly'
    case 'pro_yearly':   return 'Pro Yearly'
    case 'pro_lifetime': return 'Pro Lifetime'
    case 'comp':         return 'Comp'
    case 'free':         return 'Free'
    default:             return tier
  }
}

// Friendly label + color for a grant kind.
export function grantKindBadge(kind: string): { label: string; color: string } {
  switch (kind) {
    case 'comp_grant':       return { label: 'Comp Grant',      color: '#22c55e' }
    case 'comp_revoke':      return { label: 'Comp Revoke',     color: '#ef4444' }
    case 'trial_extension':  return { label: 'Trial Extended',  color: '#3b82f6' }
    case 'refund':           return { label: 'Refund',          color: '#f59e0b' }
    case 'refund_ack':       return { label: 'Refund Ack',      color: '#f59e0b' }
    case 'note':             return { label: 'Note',            color: '#6b7280' }
    default:                 return { label: kind,              color: '#6b7280' }
  }
}
