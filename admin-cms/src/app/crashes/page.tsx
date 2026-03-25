'use client'

import { useState, useEffect, useCallback, useRef } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ═══════════════════════════════════════════════════
// Types
// ═══════════════════════════════════════════════════

interface CrashReport {
  id: string
  user_id: string | null
  user_email: string | null
  user_name: string | null
  report_type: string
  severity: string
  error_message: string
  error_domain: string | null
  error_code: string | null
  stack_trace: string | null
  fingerprint: string
  breadcrumbs: Array<{ action: string; screen: string; timestamp: string }> | null
  device_model: string | null
  os_version: string | null
  app_version: string | null
  build_number: string | null
  current_screen: string | null
  memory_usage_mb: number | null
  free_memory_mb: number | null
  battery_level: number | null
  is_low_power_mode: boolean
  network_type: string | null
  session_id: string | null
  session_duration_seconds: number | null
  actions_before_crash: number | null
  additional_context: Record<string, string> | null
  session_log_snippet: string | null
  status: string
  admin_notes: string | null
  resolved_at: string | null
  resolved_by: string | null
  occurred_at: string
  uploaded_at: string
  created_at: string
}

interface BugReport {
  id: string
  user_id: string | null
  user_name: string | null
  user_email: string | null
  description: string
  expected_behavior: string | null
  reproduces_every_time: boolean
  screenshot_base64: string | null
  device_model: string | null
  os_version: string | null
  app_version: string | null
  screen_name: string | null
  additional_info: string | null
  session_log: string | null
  status: string
  created_at: string
}

interface TopIssue {
  fingerprint: string
  count: number
  message: string
  severity: string
  domain: string
  latest: string
  status: string
}

interface VersionGroup {
  version: string
  crashes: CrashReport[]
  firstSeenFingerprints: Set<string>
  newIssueCount: number
}

function parseVersion(v: string): number[] {
  return v.replace(/^v/, '').split('.').map(n => parseInt(n, 10) || 0)
}

function compareVersions(a: string, b: string): number {
  const pa = parseVersion(a)
  const pb = parseVersion(b)
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const diff = (pa[i] || 0) - (pb[i] || 0)
    if (diff !== 0) return diff
  }
  return 0
}

function buildVersionGroups(crashes: CrashReport[]): { groups: VersionGroup[]; firstSeenMap: Map<string, string> } {
  const fingerprintFirstVersion = new Map<string, string>()

  for (const c of crashes) {
    if (!c.app_version || !c.fingerprint) continue
    const existing = fingerprintFirstVersion.get(c.fingerprint)
    if (!existing || compareVersions(c.app_version, existing) < 0) {
      fingerprintFirstVersion.set(c.fingerprint, c.app_version)
    }
  }

  const byVersion = new Map<string, CrashReport[]>()
  for (const c of crashes) {
    const v = c.app_version || 'unknown'
    if (!byVersion.has(v)) byVersion.set(v, [])
    byVersion.get(v)!.push(c)
  }

  const allVersions = [...byVersion.keys()].sort((a, b) => compareVersions(b, a))

  const groups: VersionGroup[] = allVersions.map(version => {
    const vCrashes = byVersion.get(version)!
    const firstSeenFingerprints = new Set<string>()
    for (const c of vCrashes) {
      if (c.fingerprint && fingerprintFirstVersion.get(c.fingerprint) === version) {
        firstSeenFingerprints.add(c.fingerprint)
      }
    }
    return {
      version,
      crashes: vCrashes,
      firstSeenFingerprints,
      newIssueCount: firstSeenFingerprints.size,
    }
  })

  return { groups, firstSeenMap: fingerprintFirstVersion }
}

interface Overview {
  total_crash_reports: number
  total_bug_reports: number
  affected_users: number
  status_counts: Record<string, number>
  severity_counts: Record<string, number>
  type_counts: Record<string, number>
  domain_counts: Record<string, number>
  version_counts: Record<string, number>
  top_issues: TopIssue[]
  daily_trend: Array<{ date: string; count: number }>
  recent_reports: CrashReport[]
  bug_reports: BugReport[]
}

// Auto-refresh intervals
const REFRESH_INTERVALS: { label: string; ms: number }[] = [
  { label: 'Off', ms: 0 },
  { label: '30s', ms: 30000 },
  { label: '1m', ms: 60000 },
  { label: '5m', ms: 300000 },
]

// ═══════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════

const SEVERITY_COLORS: Record<string, string> = {
  fatal: '#ef4444',
  critical: '#f97316',
  high: '#eab308',
  medium: '#3b82f6',
  low: '#6b7280',
}

const STATUS_COLORS: Record<string, string> = {
  new: '#ef4444',
  investigating: '#f97316',
  identified: '#eab308',
  resolved: '#22c55e',
  wont_fix: '#6b7280',
  duplicate: '#8b5cf6',
}

const TYPE_ICONS: Record<string, string> = {
  fatal_signal: '💀',
  crash: '💥',
  critical: '🔥',
  error: '❌',
  warning: '⚠️',
}

function timeAgo(dateStr: string): string {
  const now = new Date()
  const date = new Date(dateStr)
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000)
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 30) return `${days}d ago`
  return date.toLocaleDateString()
}

function formatDuration(seconds: number | null): string {
  if (!seconds) return '—'
  if (seconds < 60) return `${seconds}s`
  const mins = Math.floor(seconds / 60)
  const secs = seconds % 60
  return `${mins}m ${secs}s`
}

// ═══════════════════════════════════════════════════
// Main Component
// ═══════════════════════════════════════════════════

export default function CrashesPage() {
  const [activeTab, setActiveTab] = useState<'overview' | 'crashes' | 'bugs' | 'versions'>('overview')
  const [overview, setOverview] = useState<Overview | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Crash list state
  const [crashReports, setCrashReports] = useState<CrashReport[]>([])
  const [crashFilter, setCrashFilter] = useState({
    status: '',
    severity: '',
    report_type: '',
    search: '',
  })
  const [crashLoading, setCrashLoading] = useState(false)

  // Bug report state
  const [bugReports, setBugReports] = useState<BugReport[]>([])

  // Detail view
  const [selectedCrash, setSelectedCrash] = useState<CrashReport | null>(null)
  const [selectedBug, setSelectedBug] = useState<BugReport | null>(null)

  // Selected crashes for bulk actions
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  // Date range filter (applies to both crashes and bugs)
  const [dateRange, setDateRange] = useState('all')

  // Auto-refresh
  const [refreshInterval, setRefreshInterval] = useState(0)
  const refreshTimerRef = useRef<ReturnType<typeof setInterval> | null>(null)
  const [lastRefreshed, setLastRefreshed] = useState<Date>(new Date())

  // Confirm dialog
  const [confirmDialog, setConfirmDialog] = useState<{
    message: string
    onConfirm: () => void
  } | null>(null)

  // Claude analysis
  const [analyzing, setAnalyzing] = useState(false)
  const [analysisDownloaded, setAnalysisDownloaded] = useState(false)

  // ─── Data Loading ─────────────────────────────────────────

  const loadOverview = useCallback(async () => {
    try {
      setLoading(true)
      const data = await adminApi('get_crash_overview')
      setOverview(data)
      setBugReports(data.bug_reports || [])
      setError(null)
      setLastRefreshed(new Date())
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load overview')
    } finally {
      setLoading(false)
    }
  }, [])

  const loadCrashes = useCallback(async () => {
    try {
      setCrashLoading(true)
      const params: Record<string, unknown> = { limit: 200 }
      if (crashFilter.status) params.status = crashFilter.status
      if (crashFilter.severity) params.severity = crashFilter.severity
      if (crashFilter.report_type) params.report_type = crashFilter.report_type
      if (crashFilter.search) params.search = crashFilter.search
      const data = await adminApi('get_crash_reports', params)
      setCrashReports(data.crash_reports || [])
      setLastRefreshed(new Date())
    } catch (err) {
      console.error('Failed to load crashes:', err)
    } finally {
      setCrashLoading(false)
    }
  }, [crashFilter])

  const loadBugs = useCallback(async () => {
    try {
      const data = await adminApi('get_bug_reports', { limit: 200 })
      setBugReports(data.bug_reports || [])
    } catch (err) {
      console.error('Failed to load bug reports:', err)
    }
  }, [])

  useEffect(() => {
    loadOverview()
  }, [loadOverview])

  // All crashes for version grouping
  const [allCrashesForVersions, setAllCrashesForVersions] = useState<CrashReport[]>([])
  const [versionLoading, setVersionLoading] = useState(false)

  const loadAllCrashesForVersions = useCallback(async () => {
    try {
      setVersionLoading(true)
      const data = await adminApi('get_crash_reports', { limit: 500 })
      setAllCrashesForVersions(data.crash_reports || [])
    } catch (err) {
      console.error('Failed to load crashes for version view:', err)
    } finally {
      setVersionLoading(false)
    }
  }, [])

  useEffect(() => {
    if (activeTab === 'crashes') loadCrashes()
    if (activeTab === 'bugs') loadBugs()
    if (activeTab === 'versions') loadAllCrashesForVersions()
  }, [activeTab, loadCrashes, loadBugs, loadAllCrashesForVersions])

  // Auto-refresh timer
  useEffect(() => {
    if (refreshTimerRef.current) clearInterval(refreshTimerRef.current)
    if (refreshInterval > 0) {
      refreshTimerRef.current = setInterval(() => {
        if (activeTab === 'overview') loadOverview()
        else if (activeTab === 'crashes') loadCrashes()
        else if (activeTab === 'bugs') loadBugs()
      }, refreshInterval)
    }
    return () => {
      if (refreshTimerRef.current) clearInterval(refreshTimerRef.current)
    }
  }, [refreshInterval, activeTab, loadOverview, loadCrashes, loadBugs])

  // ─── Actions ─────────────────────────────────────────

  const updateCrashStatus = async (id: string, status: string) => {
    try {
      await adminApi('update_crash_report', { id, status })
      if (activeTab === 'overview') await loadOverview()
      else await loadCrashes()
      if (selectedCrash?.id === id) {
        setSelectedCrash(prev => prev ? { ...prev, status } : null)
      }
    } catch (err) {
      console.error('Failed to update crash status:', err)
    }
  }

  const updateCrashNotes = async (id: string, notes: string) => {
    try {
      await adminApi('update_crash_report', { id, admin_notes: notes })
    } catch (err) {
      console.error('Failed to update notes:', err)
    }
  }

  const bulkUpdateStatus = async (status: string) => {
    if (selectedIds.size === 0) return
    try {
      await adminApi('bulk_update_crash_reports', { ids: Array.from(selectedIds), status })
      setSelectedIds(new Set())
      await loadCrashes()
    } catch (err) {
      console.error('Failed to bulk update:', err)
    }
  }

  const deleteCrashReport = async (id: string) => {
    try {
      await adminApi('delete_crash_report', { id })
      if (selectedCrash?.id === id) setSelectedCrash(null)
      if (activeTab === 'overview') await loadOverview()
      else await loadCrashes()
    } catch (err) {
      console.error('Failed to delete crash report:', err)
    }
  }

  const bulkDeleteCrashes = async () => {
    if (selectedIds.size === 0) return
    try {
      await adminApi('bulk_delete_crash_reports', { ids: Array.from(selectedIds) })
      setSelectedIds(new Set())
      await loadCrashes()
    } catch (err) {
      console.error('Failed to bulk delete:', err)
    }
  }

  const deleteResolvedCrashes = async () => {
    try {
      await adminApi('delete_resolved_crash_reports')
      await loadOverview()
      if (activeTab === 'crashes') await loadCrashes()
    } catch (err) {
      console.error('Failed to delete resolved:', err)
    }
  }

  const deleteBugReport = async (id: string) => {
    try {
      await adminApi('delete_bug_report', { id })
      if (selectedBug?.id === id) setSelectedBug(null)
      await loadBugs()
      if (activeTab === 'overview') await loadOverview()
    } catch (err) {
      console.error('Failed to delete bug report:', err)
    }
  }

  const updateBugStatus = async (id: string, status: string) => {
    try {
      await adminApi('update_bug_report', { id, status })
      await loadBugs()
      if (selectedBug?.id === id) {
        setSelectedBug(prev => prev ? { ...prev, status } : null)
      }
    } catch (err) {
      console.error('Failed to update bug status:', err)
    }
  }

  const loadCrashDetail = async (id: string) => {
    try {
      const data = await adminApi('get_crash_report_detail', { id })
      setSelectedCrash(data.crash_report)
    } catch (err) {
      console.error('Failed to load crash detail:', err)
    }
  }

  // ─── .md Export (selected or all) ────────────────────────

  const exportCrashesMD = () => {
    const allSource = filteredCrashReports
    const source = selectedIds.size > 0 ? allSource.filter(r => selectedIds.has(r.id)) : allSource
    if (source.length === 0) return

    const lines = [
      '# Crash & Bug Reports Export',
      '',
      `**Date:** ${new Date().toISOString().split('T')[0]}`,
      `**Reports exported:** ${source.length}${selectedIds.size > 0 ? ` (${selectedIds.size} selected)` : ' (all)'}`,
      '',
      '---',
      '',
      '## Instructions',
      '',
      'Drag this file into Cursor and ask: "Fix all the issues in this report."',
      '',
      '---',
      '',
    ]

    for (const r of source) {
      lines.push(`## ${r.report_type.toUpperCase()} — ${r.error_message?.slice(0, 100) || 'Unknown Error'}`)
      lines.push('')
      lines.push(`**Severity:** ${r.severity} | **Status:** ${r.status}`)
      lines.push(`**ID:** \`${r.id}\``)
      lines.push(`**Occurred:** ${r.occurred_at}`)
      lines.push(`**Uploaded:** ${r.uploaded_at}`)
      lines.push('')

      lines.push('### Details')
      lines.push('')
      lines.push(`- **Report Type:** ${r.report_type}`)
      lines.push(`- **Error Domain:** ${r.error_domain || '—'}`)
      lines.push(`- **Error Code:** ${r.error_code || '—'}`)
      lines.push(`- **Fingerprint:** \`${r.fingerprint}\``)
      lines.push(`- **Current Screen:** ${r.current_screen || 'Unknown'}`)
      lines.push(`- **Session Duration:** ${r.session_duration_seconds ? `${Math.floor(r.session_duration_seconds / 60)}m ${r.session_duration_seconds % 60}s` : '—'}`)
      lines.push(`- **Actions Before Crash:** ${r.actions_before_crash ?? '—'}`)
      lines.push(`- **Session ID:** ${r.session_id || '—'}`)
      lines.push('')

      lines.push('### Device Context')
      lines.push('')
      lines.push(`- **Device:** ${r.device_model || 'Unknown'}`)
      lines.push(`- **OS:** ${r.os_version || 'Unknown'}`)
      lines.push(`- **App Version:** ${r.app_version || '?'}${r.build_number ? ` (${r.build_number})` : ''}`)
      lines.push(`- **Memory Usage:** ${r.memory_usage_mb ? `${r.memory_usage_mb.toFixed(1)} MB` : '—'}`)
      lines.push(`- **Free Memory:** ${r.free_memory_mb ? `${r.free_memory_mb.toFixed(1)} MB` : '—'}`)
      lines.push(`- **Battery:** ${r.battery_level != null ? `${r.battery_level}%` : '—'}`)
      lines.push(`- **Low Power Mode:** ${r.is_low_power_mode ? 'Yes' : 'No'}`)
      lines.push(`- **Network:** ${r.network_type || 'Unknown'}`)
      lines.push('')

      lines.push('### User Context')
      lines.push('')
      lines.push(`- **Name:** ${r.user_name || 'Anonymous'}`)
      lines.push(`- **Email:** ${r.user_email || '—'}`)
      lines.push(`- **User ID:** ${r.user_id || '—'}`)
      lines.push('')

      if (r.breadcrumbs && r.breadcrumbs.length > 0) {
        lines.push(`### Breadcrumbs (${r.breadcrumbs.length} actions)`)
        lines.push('')
        for (const b of r.breadcrumbs) {
          lines.push(`- \`${b.timestamp}\` [${b.screen}] ${b.action}`)
        }
        lines.push('')
      }

      if (r.stack_trace) {
        lines.push('### Stack Trace')
        lines.push('')
        lines.push('```')
        lines.push(r.stack_trace)
        lines.push('```')
        lines.push('')
      }

      if (r.additional_context && Object.keys(r.additional_context).length > 0) {
        lines.push('### Additional Context')
        lines.push('')
        for (const [key, val] of Object.entries(r.additional_context)) {
          lines.push(`- **${key}:** ${val}`)
        }
        lines.push('')
      }

      if (r.session_log_snippet) {
        lines.push('### Session Log')
        lines.push('')
        lines.push('```')
        lines.push(r.session_log_snippet)
        lines.push('```')
        lines.push('')
      }

      if (r.admin_notes) {
        lines.push('### Admin Notes')
        lines.push('')
        lines.push(r.admin_notes)
        lines.push('')
      }

      if (r.resolved_at) {
        lines.push(`*Resolved at ${r.resolved_at}${r.resolved_by ? ` by ${r.resolved_by}` : ''}*`)
        lines.push('')
      }

      lines.push('---')
      lines.push('')
    }

    const content = lines.join('\n')
    const blob = new Blob([content], { type: 'text/markdown' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `crash-reports-${new Date().toISOString().slice(0, 10)}.md`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(url)
  }

  // ─── Claude Analysis & .md Download ─────────────────

  const analyzeCrashesWithClaude = async () => {
    const allCrashes = filteredCrashReports
    const allBugs = filteredBugReports
    const source = selectedIds.size > 0 ? allCrashes.filter(r => selectedIds.has(r.id)) : allCrashes
    const bugs = allBugs
    if (source.length === 0 && bugs.length === 0) { alert('No reports to analyze. Select crashes or adjust the date range.'); return }

    setAnalyzing(true)
    try {
      const crashSummary = source.slice(0, 30).map(c => ({
        id: c.id.slice(0, 8),
        type: c.report_type,
        severity: c.severity,
        status: c.status,
        error: c.error_message,
        domain: c.error_domain,
        screen: c.current_screen,
        device: c.device_model,
        os: c.os_version,
        app_version: c.app_version,
        user: c.user_name || c.user_email || c.user_id?.slice(0, 8),
        stack_preview: c.stack_trace?.slice(0, 300) || null,
        breadcrumbs: c.breadcrumbs?.slice(-5) || null,
        session_log: c.session_log_snippet?.slice(0, 500) || null,
        memory_mb: c.memory_usage_mb,
        session_duration: c.session_duration_seconds,
        occurred: c.occurred_at,
      }))

      const bugSummary = bugs.slice(0, 20).map(b => ({
        id: b.id.slice(0, 8),
        status: b.status,
        description: b.description?.slice(0, 300),
        user: b.user_name || b.user_email || b.user_id?.slice(0, 8),
        device: b.device_model,
        app_version: b.app_version,
        created: b.created_at,
      }))

      const prompt = `Analyze these crash reports and bug reports from the Fit33 iOS fitness app. For each significant issue:
1. Identify the root cause from the error message and stack trace
2. Rate priority (P0-P3) based on severity x frequency x user impact  
3. Suggest the specific Swift file and fix approach
4. Map related bug reports to crashes where they describe the same issue
5. Group related crashes by root cause (not just fingerprint)

Crash Reports (${source.length} total, showing ${crashSummary.length}):
${JSON.stringify(crashSummary, null, 2)}

Bug Reports (${bugs.length} total, showing ${bugSummary.length}):
${JSON.stringify(bugSummary, null, 2)}

Respond with structured analysis: prioritized issues, root causes, fix suggestions, and crash-to-bug mappings.`

      const res = await fetch('/api/ai-chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: [{ role: 'user', content: prompt }], fetchData: false }),
      })

      let analysisText = ''
      const reader = res.body?.getReader()
      const decoder = new TextDecoder()
      if (reader) {
        while (true) {
          const { done, value } = await reader.read()
          if (done) break
          const chunk = decoder.decode(value)
          for (const line of chunk.split('\n')) {
            if (line.startsWith('data: ')) {
              try {
                const parsed = JSON.parse(line.slice(6))
                if (parsed.text) analysisText += parsed.text
              } catch { /* skip */ }
            }
          }
        }
      }

      // Build the .md report
      const lines = [
        '# Crash & Bug Report — Claude Analysis',
        '',
        `**Date:** ${new Date().toISOString().split('T')[0]}`,
        `**Crash reports analyzed:** ${source.length}`,
        `**Bug reports analyzed:** ${bugs.length}`,
        `**Severity breakdown:** ${Object.entries(overview?.severity_counts || {}).map(([k, v]) => `${k}: ${v}`).join(', ')}`,
        `**Status breakdown:** ${Object.entries(overview?.status_counts || {}).map(([k, v]) => `${k}: ${v}`).join(', ')}`,
        '',
        '---',
        '',
        '## Instructions',
        '',
        'Drag this file into Cursor and ask: "Fix all the issues in this report."',
        '',
        '---',
        '',
        '## Claude Analysis',
        '',
        analysisText,
        '',
        '---',
        '',
        '## Raw Crash Data',
        '',
      ]

      for (const c of source.slice(0, 20)) {
        lines.push(`### ${c.report_type.toUpperCase()} — ${c.error_message?.slice(0, 80) || 'Unknown'}`)
        lines.push('')
        lines.push(`- **ID:** \`${c.id.slice(0, 8)}\``)
        lines.push(`- **Severity:** ${c.severity} | **Status:** ${c.status}`)
        lines.push(`- **Screen:** ${c.current_screen || 'Unknown'} | **Domain:** ${c.error_domain || 'Unknown'}`)
        lines.push(`- **Device:** ${c.device_model || '?'} | **OS:** ${c.os_version || '?'} | **App:** ${c.app_version || '?'}`)
        lines.push(`- **User:** ${c.user_name || c.user_email || c.user_id?.slice(0, 8) || 'Anonymous'}`)
        if (c.memory_usage_mb) lines.push(`- **Memory:** ${c.memory_usage_mb}MB used, ${c.free_memory_mb || '?'}MB free`)
        if (c.session_duration_seconds) lines.push(`- **Session duration:** ${Math.round(c.session_duration_seconds / 60)}min`)
        lines.push(`- **Occurred:** ${c.occurred_at}`)
        lines.push('')
        if (c.stack_trace) {
          lines.push('**Stack trace:**')
          lines.push('```')
          lines.push(c.stack_trace.slice(0, 1000))
          lines.push('```')
          lines.push('')
        }
        if (c.breadcrumbs && c.breadcrumbs.length > 0) {
          lines.push('**Breadcrumbs (last 5):**')
          for (const b of c.breadcrumbs.slice(-5)) {
            lines.push(`- \`${b.timestamp}\` [${b.screen}] ${b.action}`)
          }
          lines.push('')
        }
        if (c.session_log_snippet) {
          lines.push('**Session log:**')
          lines.push('```')
          lines.push(c.session_log_snippet.slice(0, 500))
          lines.push('```')
          lines.push('')
        }
        lines.push('---')
        lines.push('')
      }

      if (bugs.length > 0) {
        lines.push('## User Bug Reports')
        lines.push('')
        for (const b of bugs.slice(0, 15)) {
          lines.push(`- **\`${b.id.slice(0, 8)}\`** [${b.status}] ${b.description?.slice(0, 150) || 'No description'} — *${b.user_name || b.user_email || 'Anonymous'}* (${b.device_model || '?'}, v${b.app_version || '?'})`)
        }
        lines.push('')
      }

      const content = lines.join('\n')
      const blob = new Blob([content], { type: 'text/markdown' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `crash-analysis-report-${new Date().toISOString().split('T')[0]}.md`
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      URL.revokeObjectURL(url)
      setAnalysisDownloaded(true)
    } catch (err) {
      alert(`Analysis failed: ${err}`)
    }
    setAnalyzing(false)
  }

  // ─── Date Range Filtering ───────────────────────────

  const DATE_RANGES: { label: string; value: string; ms: number }[] = [
    { label: 'All Time', value: 'all', ms: 0 },
    { label: 'Last 1 Hour', value: '1h', ms: 3600000 },
    { label: 'Last 6 Hours', value: '6h', ms: 21600000 },
    { label: 'Last 24 Hours', value: '24h', ms: 86400000 },
    { label: 'Last 7 Days', value: '7d', ms: 604800000 },
    { label: 'Last 30 Days', value: '30d', ms: 2592000000 },
  ]

  function filterByDate<T extends { created_at: string }>(items: T[]): T[] {
    if (dateRange === 'all') return items
    const range = DATE_RANGES.find(r => r.value === dateRange)
    if (!range || range.ms === 0) return items
    const cutoff = new Date(Date.now() - range.ms)
    return items.filter(item => new Date(item.created_at) >= cutoff)
  }

  const filteredCrashReports = filterByDate(crashReports)
  const filteredBugReports = filterByDate(bugReports)

  // ─── Render ─────────────────────────────────────────

  if (selectedCrash) {
    return (
      <AdminShell>
        <CrashDetailView
          crash={selectedCrash}
          onBack={() => setSelectedCrash(null)}
          onUpdateStatus={(status) => updateCrashStatus(selectedCrash.id, status)}
          onUpdateNotes={(notes) => updateCrashNotes(selectedCrash.id, notes)}
          onDelete={() => {
            setConfirmDialog({
              message: 'Delete this crash report? This cannot be undone.',
              onConfirm: () => { deleteCrashReport(selectedCrash.id); setConfirmDialog(null) }
            })
          }}
        />
      </AdminShell>
    )
  }

  if (selectedBug) {
    return (
      <AdminShell>
        <BugDetailView
          bug={selectedBug}
          onBack={() => setSelectedBug(null)}
          onUpdateStatus={(status) => updateBugStatus(selectedBug.id, status)}
          onDelete={() => {
            setConfirmDialog({
              message: 'Delete this bug report? This cannot be undone.',
              onConfirm: () => { deleteBugReport(selectedBug.id); setConfirmDialog(null) }
            })
          }}
        />
      </AdminShell>
    )
  }

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400, margin: '0 auto' }}>
        {/* Confirm Dialog */}
        {confirmDialog && (
          <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: 'rgba(0,0,0,0.5)' }}>
            <div className="rounded-xl p-6 max-w-sm w-full mx-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <p className="text-sm mb-4" style={{ color: 'var(--text-primary)' }}>{confirmDialog.message}</p>
              <div className="flex gap-2 justify-end">
                <button
                  onClick={() => setConfirmDialog(null)}
                  className="text-sm px-4 py-2 rounded-lg"
                  style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)' }}
                >
                  Cancel
                </button>
                <button
                  onClick={confirmDialog.onConfirm}
                  className="text-sm px-4 py-2 rounded-lg"
                  style={{ background: '#ef4444', color: 'white' }}
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              🛡️ Crashes & Bug Reports
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-muted)' }}>
              Real-time error monitoring, crash detection, and user-reported bugs
              {refreshInterval > 0 && (
                <span className="ml-2 inline-flex items-center gap-1">
                  <span className="inline-block w-1.5 h-1.5 rounded-full animate-pulse" style={{ background: '#22c55e' }} />
                  Auto-refreshing
                </span>
              )}
            </p>
          </div>
          <div className="flex items-center gap-2">
            {/* Auto-refresh dropdown */}
            <select
              value={refreshInterval}
              onChange={e => setRefreshInterval(Number(e.target.value))}
              className="text-xs rounded-lg px-2 py-2"
              style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              title="Auto-refresh interval"
            >
              {REFRESH_INTERVALS.map(opt => (
                <option key={opt.ms} value={opt.ms}>🔄 {opt.label}</option>
              ))}
            </select>
            {/* Date Range */}
            <select
              value={dateRange}
              onChange={e => { setDateRange(e.target.value); setAnalysisDownloaded(false) }}
              className="text-sm rounded-lg px-3 py-2"
              style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              title="Filter by time range"
            >
              {DATE_RANGES.map(r => (
                <option key={r.value} value={r.value}>🕐 {r.label}</option>
              ))}
            </select>
            {/* Analyze with Claude */}
            <button
              onClick={analyzeCrashesWithClaude}
              disabled={analyzing}
              className="text-sm px-3 py-2 rounded-lg"
              style={{ background: analysisDownloaded ? '#4b5563' : '#7c3aed', border: 'none', color: 'white', fontWeight: 600, cursor: analyzing ? 'wait' : 'pointer', opacity: analyzing ? 0.6 : 1 }}
              title={selectedIds.size > 0 ? `Analyze ${selectedIds.size} selected with Claude` : 'Analyze all visible crashes with Claude'}
            >
              {analyzing ? '⏳ Analyzing...' : analysisDownloaded ? '✓ Report Downloaded' : `🧠 Analyze${selectedIds.size > 0 ? ` (${selectedIds.size})` : ''}`}
            </button>
            {/* Export .md */}
            <button
              onClick={exportCrashesMD}
              className="text-sm px-3 py-2 rounded-lg"
              style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-secondary)' }}
              title={selectedIds.size > 0 ? `Export ${selectedIds.size} selected reports as .md` : 'Export all reports as .md'}
            >
              📥 Export{selectedIds.size > 0 ? ` (${selectedIds.size})` : ''} .md
            </button>
            {/* Clean up resolved */}
            {overview && (overview.status_counts['resolved'] || 0) + (overview.status_counts['wont_fix'] || 0) + (overview.status_counts['duplicate'] || 0) > 0 && (
              <button
                onClick={() => setConfirmDialog({
                  message: `Delete all resolved/won't fix/duplicate crash reports? This cannot be undone.`,
                  onConfirm: () => { deleteResolvedCrashes(); setConfirmDialog(null) }
                })}
                className="text-sm px-3 py-2 rounded-lg"
                style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}
                title="Delete all resolved crash reports"
              >
                🗑️ Clean Up
              </button>
            )}
            <button
              onClick={() => { loadOverview(); if (activeTab === 'crashes') loadCrashes(); if (activeTab === 'bugs') loadBugs() }}
              className="text-sm px-4 py-2 rounded-lg"
              style={{ background: 'var(--accent)', color: 'white' }}
            >
              ↻ Refresh
            </button>
          </div>
        </div>

        {/* Last refreshed indicator */}
        <div className="text-xs mb-4" style={{ color: 'var(--text-muted)' }}>
          Last refreshed: {lastRefreshed.toLocaleTimeString()}
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 p-1 rounded-lg" style={{ background: 'var(--bg-secondary)', display: 'inline-flex' }}>
          {(['overview', 'versions', 'crashes', 'bugs'] as const).map(tab => (
            <button
              key={tab}
              onClick={() => setActiveTab(tab)}
              className="px-4 py-2 rounded-md text-sm font-medium transition-all"
              style={{
                background: activeTab === tab ? 'var(--accent)' : 'transparent',
                color: activeTab === tab ? 'white' : 'var(--text-secondary)',
              }}
            >
              {tab === 'overview' ? '📊 Overview' : tab === 'versions' ? '📦 By Version' : tab === 'crashes' ? '💥 Crash Reports' : '🐛 Bug Reports'}
            </button>
          ))}
        </div>

        {loading && activeTab === 'overview' ? (
          <div className="text-center py-20" style={{ color: 'var(--text-muted)' }}>Loading...</div>
        ) : error ? (
          <div className="text-center py-20" style={{ color: '#ef4444' }}>{error}</div>
        ) : activeTab === 'overview' && overview ? (
          <OverviewTab
            overview={overview}
            onViewCrash={(id) => loadCrashDetail(id)}
            onViewBug={(bug) => setSelectedBug(bug)}
            onViewFingerprint={(fp) => {
              setCrashFilter(prev => ({ ...prev, search: '' }))
              setActiveTab('crashes')
              setTimeout(() => {
                setCrashFilter(prev => ({ ...prev, search: fp }))
              }, 100)
            }}
            onSwitchToVersions={() => setActiveTab('versions')}
          />
        ) : activeTab === 'versions' ? (
          <VersionGroupTab
            crashes={allCrashesForVersions}
            loading={versionLoading}
            onViewCrash={(id) => loadCrashDetail(id)}
          />
        ) : activeTab === 'crashes' ? (
          <CrashListTab
            crashes={filteredCrashReports}
            loading={crashLoading}
            filter={crashFilter}
            onFilterChange={setCrashFilter}
            onViewCrash={(id) => loadCrashDetail(id)}
            selectedIds={selectedIds}
            onToggleSelect={(id) => {
              setSelectedIds(prev => {
                const next = new Set(prev)
                if (next.has(id)) next.delete(id)
                else next.add(id)
                return next
              })
            }}
            onSelectAll={(ids) => setSelectedIds(new Set(ids))}
            onClearSelection={() => setSelectedIds(new Set())}
            onBulkUpdate={bulkUpdateStatus}
            onBulkDelete={() => setConfirmDialog({
              message: `Delete ${selectedIds.size} selected crash reports? This cannot be undone.`,
              onConfirm: () => { bulkDeleteCrashes(); setConfirmDialog(null) }
            })}
          />
        ) : activeTab === 'bugs' ? (
          <BugListTab
            bugs={filteredBugReports}
            onViewBug={(bug) => setSelectedBug(bug)}
            onUpdateStatus={updateBugStatus}
            onDelete={(id) => setConfirmDialog({
              message: 'Delete this bug report? This cannot be undone.',
              onConfirm: () => { deleteBugReport(id); setConfirmDialog(null) }
            })}
          />
        ) : null}
      </div>
    </AdminShell>
  )
}

// ═══════════════════════════════════════════════════
// Overview Tab
// ═══════════════════════════════════════════════════

function OverviewTab({ overview, onViewCrash, onViewBug, onViewFingerprint, onSwitchToVersions }: {
  overview: Overview
  onViewCrash: (id: string) => void
  onViewBug: (bug: BugReport) => void
  onViewFingerprint: (fp: string) => void
  onSwitchToVersions: () => void
}) {
  const hasData = overview.total_crash_reports > 0 || overview.total_bug_reports > 0

  // Compute crash-free rate (last 7 days)
  const last7Days = overview.daily_trend.slice(-7)
  const daysWithCrashes = last7Days.filter(d => d.count > 0).length
  const crashFreeRate = last7Days.length > 0 ? Math.round(((last7Days.length - daysWithCrashes) / last7Days.length) * 100) : 100

  // Compute MTTR (Mean Time To Resolution) from resolved reports
  const resolvedCount = overview.status_counts['resolved'] || 0

  // Unique crash types (fingerprints)
  const uniqueIssues = overview.top_issues.length

  // Open (unresolved) count
  const unresolvedCount = (overview.status_counts['new'] || 0) + (overview.status_counts['investigating'] || 0) + (overview.status_counts['identified'] || 0)

  // Crashes in last 24h
  const today = overview.daily_trend.length > 0 ? overview.daily_trend[overview.daily_trend.length - 1]?.count || 0 : 0

  return (
    <div className="space-y-6">
      {/* Stat Cards - Primary */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <StatCard
          label="Crash Reports"
          value={overview.total_crash_reports}
          icon="💥"
          color="#ef4444"
        />
        <StatCard
          label="Bug Reports"
          value={overview.total_bug_reports}
          icon="🐛"
          color="#f97316"
        />
        <StatCard
          label="Affected Users"
          value={overview.affected_users}
          icon="👥"
          color="#eab308"
        />
        <StatCard
          label="Unresolved"
          value={unresolvedCount}
          icon="🔴"
          color="#ef4444"
        />
      </div>

      {/* Stat Cards - Secondary (health metrics) */}
      {hasData && (
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <StatCard
            label="Crash-Free Days (7d)"
            value={crashFreeRate}
            icon="🟢"
            color="#22c55e"
            suffix="%"
          />
          <StatCard
            label="Today"
            value={today}
            icon="📅"
            color={today > 0 ? '#ef4444' : '#22c55e'}
          />
          <StatCard
            label="Unique Issues"
            value={uniqueIssues}
            icon="🔍"
            color="#8b5cf6"
          />
          <StatCard
            label="Resolved"
            value={resolvedCount}
            icon="✅"
            color="#22c55e"
          />
        </div>
      )}

      {!hasData ? (
        <div className="rounded-xl p-12 text-center" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <div className="text-4xl mb-4">🎉</div>
          <h3 className="text-lg font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>No Issues Detected</h3>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
            Crash reports will appear here automatically when the iOS app&apos;s CrashReportingService detects errors.
            <br />
            User-submitted bug reports from the rage shake reporter will also appear here.
          </p>
        </div>
      ) : (
        <>
          {/* Severity + Status Breakdown */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Severity Breakdown</h3>
              <div className="space-y-2">
                {Object.entries(overview.severity_counts).sort((a, b) => {
                  const order = ['fatal', 'critical', 'high', 'medium', 'low']
                  return order.indexOf(a[0]) - order.indexOf(b[0])
                }).map(([severity, count]) => (
                  <div key={severity} className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: SEVERITY_COLORS[severity] || '#6b7280' }} />
                      <span className="text-sm capitalize" style={{ color: 'var(--text-secondary)' }}>{severity}</span>
                    </div>
                    <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Status Breakdown</h3>
              <div className="space-y-2">
                {Object.entries(overview.status_counts).map(([status, count]) => (
                  <div key={status} className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: STATUS_COLORS[status] || '#6b7280' }} />
                      <span className="text-sm capitalize" style={{ color: 'var(--text-secondary)' }}>{status.replace('_', ' ')}</span>
                    </div>
                    <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Error Domain + App Version Breakdown */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {Object.keys(overview.domain_counts).length > 0 && (
              <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
                <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Errors by Domain</h3>
                <div className="space-y-2">
                  {Object.entries(overview.domain_counts).sort((a, b) => b[1] - a[1]).map(([domain, count]) => (
                    <div key={domain} className="flex items-center justify-between">
                      <span className="text-sm" style={{ color: 'var(--text-secondary)' }}>{domain}</span>
                      <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {Object.keys(overview.version_counts).length > 0 && (
              <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>Errors by App Version</h3>
                  <button
                    onClick={onSwitchToVersions}
                    className="text-xs hover:opacity-70"
                    style={{ color: 'var(--accent)' }}
                  >
                    View detailed breakdown →
                  </button>
                </div>
                <div className="space-y-2">
                  {Object.entries(overview.version_counts).sort((a, b) => compareVersions(b[0], a[0])).map(([version, count], i) => (
                    <div key={version} className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className="text-sm font-mono" style={{ color: 'var(--text-secondary)' }}>v{version}</span>
                        {i === 0 && (
                          <span className="text-xs px-1.5 py-0.5 rounded font-medium" style={{ background: 'var(--accent)', color: 'white' }}>
                            latest
                          </span>
                        )}
                      </div>
                      <span className="text-sm font-medium" style={{ color: 'var(--text-primary)' }}>{count}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Daily Trend (simple bar viz) */}
          {overview.daily_trend.some(d => d.count > 0) && (
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>Crash Trend (Last 30 Days)</h3>
              <div className="flex items-end gap-px" style={{ height: 80 }}>
                {overview.daily_trend.map((d, i) => {
                  const max = Math.max(...overview.daily_trend.map(x => x.count), 1)
                  const height = (d.count / max) * 100
                  return (
                    <div
                      key={i}
                      className="flex-1 rounded-t relative group"
                      style={{
                        height: `${Math.max(height, d.count > 0 ? 4 : 0)}%`,
                        background: d.count > 0 ? '#ef4444' : 'var(--border)',
                        minWidth: 2,
                      }}
                      title={`${d.date}: ${d.count} reports`}
                    />
                  )
                })}
              </div>
              <div className="flex justify-between mt-1">
                <span className="text-xs" style={{ color: 'var(--text-muted)' }}>30 days ago</span>
                <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Today</span>
              </div>
            </div>
          )}

          {/* Top Issues (grouped by fingerprint) */}
          {overview.top_issues.length > 0 && (
            <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
              <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
                🔥 Top Issues (Grouped by Error Fingerprint)
              </h3>
              <div className="space-y-2">
                {overview.top_issues.map((issue) => (
                  <button
                    key={issue.fingerprint}
                    className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
                    style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)' }}
                    onClick={() => onViewFingerprint(issue.fingerprint)}
                  >
                    <div className="flex items-center gap-2 shrink-0">
                      <div className="w-2.5 h-2.5 rounded-full" style={{ background: SEVERITY_COLORS[issue.severity] || '#6b7280' }} />
                      <span className="text-sm font-bold" style={{ color: 'var(--text-primary)' }}>×{issue.count}</span>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>{issue.message}</div>
                      <div className="text-xs" style={{ color: 'var(--text-muted)' }}>
                        {issue.domain} · {timeAgo(issue.latest)}
                      </div>
                    </div>
                    <span
                      className="text-xs px-2 py-0.5 rounded-full shrink-0"
                      style={{ background: STATUS_COLORS[issue.status] + '22', color: STATUS_COLORS[issue.status] }}
                    >
                      {issue.status}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Recent Reports */}
          <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
            <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
              ⚡ Recent Crash Reports
            </h3>
            {overview.recent_reports.length === 0 ? (
              <p className="text-sm text-center py-4" style={{ color: 'var(--text-muted)' }}>No crash reports yet</p>
            ) : (
              <div className="space-y-1">
                {overview.recent_reports.slice(0, 15).map(r => (
                  <CrashRow key={r.id} crash={r} onClick={() => onViewCrash(r.id)} />
                ))}
              </div>
            )}
          </div>

          {/* Recent Bug Reports */}
          <div className="rounded-xl p-5" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
            <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--text-primary)' }}>
              🐛 Recent Bug Reports (User-Submitted)
            </h3>
            {overview.bug_reports.length === 0 ? (
              <p className="text-sm text-center py-4" style={{ color: 'var(--text-muted)' }}>No bug reports yet</p>
            ) : (
              <div className="space-y-1">
                {overview.bug_reports.slice(0, 10).map(bug => (
                  <BugRow key={bug.id} bug={bug} onClick={() => onViewBug(bug)} />
                ))}
              </div>
            )}
          </div>
        </>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Version Group Tab
// ═══════════════════════════════════════════════════

function VersionGroupTab({ crashes, loading, onViewCrash }: {
  crashes: CrashReport[]
  loading: boolean
  onViewCrash: (id: string) => void
}) {
  const [collapsedVersions, setCollapsedVersions] = useState<Set<string>>(new Set())

  if (loading) {
    return <div className="text-center py-20" style={{ color: 'var(--text-muted)' }}>Loading version data...</div>
  }

  if (crashes.length === 0) {
    return (
      <div className="text-center py-12 rounded-xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}>
        <div className="text-3xl mb-2">🎉</div>
        No crash reports to group by version
      </div>
    )
  }

  const { groups, firstSeenMap } = buildVersionGroups(crashes)
  const latestVersion = groups.length > 0 ? groups[0].version : null

  const toggleVersion = (v: string) => {
    setCollapsedVersions(prev => {
      const next = new Set(prev)
      if (next.has(v)) next.delete(v)
      else next.add(v)
      return next
    })
  }

  const totalNewInLatest = latestVersion ? (groups.find(g => g.version === latestVersion)?.newIssueCount || 0) : 0

  return (
    <div className="space-y-4">
      {/* Summary bar */}
      <div className="flex flex-wrap gap-3 items-center">
        <span className="text-sm" style={{ color: 'var(--text-muted)' }}>
          {groups.length} version{groups.length !== 1 ? 's' : ''} · {crashes.length} total crashes
        </span>
        {latestVersion && totalNewInLatest > 0 && (
          <span className="text-xs px-2.5 py-1 rounded-full font-semibold" style={{ background: '#f9731622', color: '#f97316' }}>
            {totalNewInLatest} new issue{totalNewInLatest !== 1 ? 's' : ''} in v{latestVersion}
          </span>
        )}
      </div>

      {/* Version timeline */}
      {groups.map((group) => {
        const isCollapsed = collapsedVersions.has(group.version)
        const isLatest = group.version === latestVersion
        const severityCounts: Record<string, number> = {}
        for (const c of group.crashes) {
          severityCounts[c.severity] = (severityCounts[c.severity] || 0) + 1
        }

        const uniqueFingerprints = new Set(group.crashes.map(c => c.fingerprint))
        const carryoverCount = uniqueFingerprints.size - group.newIssueCount

        return (
          <div key={group.version} className="rounded-xl overflow-hidden" style={{ background: 'var(--bg-secondary)', border: `1px solid ${isLatest ? 'var(--accent)' : 'var(--border)'}` }}>
            {/* Version header */}
            <button
              onClick={() => toggleVersion(group.version)}
              className="w-full flex items-center gap-3 p-4 hover:opacity-80 transition-opacity"
            >
              <div className="flex items-center gap-2">
                <span style={{ color: 'var(--text-muted)', fontSize: 12 }}>{isCollapsed ? '▶' : '▼'}</span>
                <span className="text-base font-bold" style={{ color: 'var(--text-primary)' }}>
                  v{group.version}
                </span>
                {isLatest && (
                  <span className="text-xs px-2 py-0.5 rounded-full font-semibold" style={{ background: 'var(--accent)', color: 'white' }}>
                    LATEST
                  </span>
                )}
              </div>

              <div className="flex items-center gap-2 ml-auto">
                {group.newIssueCount > 0 && (
                  <span className="text-xs px-2 py-0.5 rounded-full font-semibold" style={{ background: '#f9731633', color: '#f97316' }}>
                    🆕 {group.newIssueCount} new
                  </span>
                )}
                {carryoverCount > 0 && (
                  <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: 'var(--bg-primary)', color: 'var(--text-muted)' }}>
                    {carryoverCount} recurring
                  </span>
                )}
                <span className="text-sm font-medium" style={{ color: 'var(--text-secondary)' }}>
                  {group.crashes.length} report{group.crashes.length !== 1 ? 's' : ''}
                </span>

                {/* Mini severity dots */}
                <div className="flex items-center gap-1 ml-2">
                  {Object.entries(severityCounts).sort((a, b) => {
                    const order = ['fatal', 'critical', 'high', 'medium', 'low']
                    return order.indexOf(a[0]) - order.indexOf(b[0])
                  }).map(([sev, count]) => (
                    <span
                      key={sev}
                      className="text-xs px-1.5 py-0.5 rounded"
                      style={{ background: (SEVERITY_COLORS[sev] || '#6b7280') + '22', color: SEVERITY_COLORS[sev] || '#6b7280' }}
                      title={`${sev}: ${count}`}
                    >
                      {count}
                    </span>
                  ))}
                </div>
              </div>
            </button>

            {/* Crash list for this version */}
            {!isCollapsed && (
              <div className="px-4 pb-4 space-y-1">
                {/* New issues first, then recurring */}
                {group.crashes
                  .sort((a, b) => {
                    const aNew = group.firstSeenFingerprints.has(a.fingerprint) ? 0 : 1
                    const bNew = group.firstSeenFingerprints.has(b.fingerprint) ? 0 : 1
                    if (aNew !== bNew) return aNew - bNew
                    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
                  })
                  .map(crash => (
                    <CrashRowVersioned
                      key={crash.id}
                      crash={crash}
                      isNewInVersion={group.firstSeenFingerprints.has(crash.fingerprint)}
                      firstSeenVersion={firstSeenMap.get(crash.fingerprint) || null}
                      currentVersion={group.version}
                      onClick={() => onViewCrash(crash.id)}
                    />
                  ))
                }
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}

function CrashRowVersioned({ crash, isNewInVersion, firstSeenVersion, currentVersion, onClick }: {
  crash: CrashReport
  isNewInVersion: boolean
  firstSeenVersion: string | null
  currentVersion: string
  onClick: () => void
}) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
      style={{ background: 'var(--bg-primary)', border: `1px solid ${isNewInVersion ? '#f9731644' : 'var(--border)'}` }}
    >
      <span className="text-lg shrink-0">{TYPE_ICONS[crash.report_type] || '❌'}</span>
      <div
        className="w-2.5 h-2.5 rounded-full shrink-0"
        style={{ background: SEVERITY_COLORS[crash.severity] || '#6b7280' }}
        title={crash.severity}
      />
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate flex items-center gap-2" style={{ color: 'var(--text-primary)' }}>
          {crash.error_message}
          {isNewInVersion && (
            <span className="text-xs px-1.5 py-0.5 rounded font-semibold shrink-0" style={{ background: '#f9731633', color: '#f97316' }}>
              NEW in v{currentVersion}
            </span>
          )}
          {!isNewInVersion && firstSeenVersion && (
            <span className="text-xs px-1.5 py-0.5 rounded shrink-0" style={{ background: 'var(--bg-secondary)', color: 'var(--text-muted)' }}>
              since v{firstSeenVersion}
            </span>
          )}
        </div>
        <div className="text-xs flex items-center gap-2 flex-wrap" style={{ color: 'var(--text-muted)' }}>
          {crash.error_domain && <span className="font-medium">{crash.error_domain}</span>}
          {crash.user_email && <span>· {crash.user_email}</span>}
          {crash.device_model && <span>· {crash.device_model}</span>}
          <span>· {timeAgo(crash.created_at)}</span>
        </div>
      </div>
      <span
        className="text-xs px-2 py-0.5 rounded-full shrink-0"
        style={{ background: STATUS_COLORS[crash.status] + '22', color: STATUS_COLORS[crash.status] }}
      >
        {crash.status}
      </span>
    </button>
  )
}

// ═══════════════════════════════════════════════════
// Crash List Tab
// ═══════════════════════════════════════════════════

function CrashListTab({
  crashes, loading, filter, onFilterChange, onViewCrash,
  selectedIds, onToggleSelect, onSelectAll, onClearSelection, onBulkUpdate, onBulkDelete
}: {
  crashes: CrashReport[]
  loading: boolean
  filter: { status: string; severity: string; report_type: string; search: string }
  onFilterChange: (filter: { status: string; severity: string; report_type: string; search: string }) => void
  onViewCrash: (id: string) => void
  selectedIds: Set<string>
  onToggleSelect: (id: string) => void
  onSelectAll: (ids: string[]) => void
  onClearSelection: () => void
  onBulkUpdate: (status: string) => void
  onBulkDelete: () => void
}) {
  return (
    <div className="space-y-4">
      {/* Filters */}
      <div className="flex flex-wrap items-center gap-3">
        <input
          type="text"
          placeholder="Search errors, users, domains..."
          value={filter.search}
          onChange={e => onFilterChange({ ...filter, search: e.target.value })}
          className="input text-sm flex-1"
          style={{ minWidth: 200, maxWidth: 400, background: 'var(--bg-secondary)', border: '1px solid var(--border)', borderRadius: 8, padding: '8px 12px', color: 'var(--text-primary)' }}
        />
        <select
          value={filter.status}
          onChange={e => onFilterChange({ ...filter, status: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Status</option>
          <option value="new">New</option>
          <option value="investigating">Investigating</option>
          <option value="identified">Identified</option>
          <option value="resolved">Resolved</option>
          <option value="wont_fix">Won&apos;t Fix</option>
          <option value="duplicate">Duplicate</option>
        </select>
        <select
          value={filter.severity}
          onChange={e => onFilterChange({ ...filter, severity: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Severity</option>
          <option value="fatal">Fatal</option>
          <option value="critical">Critical</option>
          <option value="high">High</option>
          <option value="medium">Medium</option>
          <option value="low">Low</option>
        </select>
        <select
          value={filter.report_type}
          onChange={e => onFilterChange({ ...filter, report_type: e.target.value })}
          className="text-sm rounded-lg px-3 py-2"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
        >
          <option value="">All Types</option>
          <option value="fatal_signal">Fatal Signal</option>
          <option value="crash">Crash</option>
          <option value="critical">Critical</option>
          <option value="error">Error</option>
          <option value="warning">Warning</option>
        </select>
      </div>

      {/* Bulk Actions */}
      {selectedIds.size > 0 && (
        <div className="flex items-center gap-3 p-3 rounded-lg" style={{ background: 'var(--accent)' + '15', border: '1px solid var(--accent)' + '33' }}>
          <span className="text-sm font-medium" style={{ color: 'var(--accent)' }}>
            {selectedIds.size} selected
          </span>
          <button onClick={() => onBulkUpdate('resolved')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#22c55e22', color: '#22c55e' }}>
            Mark Resolved
          </button>
          <button onClick={() => onBulkUpdate('investigating')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#f9731622', color: '#f97316' }}>
            Investigating
          </button>
          <button onClick={() => onBulkUpdate('duplicate')} className="text-xs px-3 py-1 rounded-md" style={{ background: '#8b5cf622', color: '#8b5cf6' }}>
            Duplicate
          </button>
          <button onClick={onBulkDelete} className="text-xs px-3 py-1 rounded-md" style={{ background: '#ef444422', color: '#ef4444' }}>
            🗑️ Delete
          </button>
          <button onClick={onClearSelection} className="text-xs ml-auto" style={{ color: 'var(--text-muted)' }}>
            Clear Selection
          </button>
        </div>
      )}

      {/* List */}
      {loading ? (
        <div className="text-center py-12" style={{ color: 'var(--text-muted)' }}>Loading crash reports...</div>
      ) : crashes.length === 0 ? (
        <div className="text-center py-12 rounded-xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}>
          <div className="text-3xl mb-2">🎉</div>
          No crash reports found{filter.search || filter.status || filter.severity || filter.report_type ? ' matching filters' : ''}
        </div>
      ) : (
        <div className="space-y-1">
          <div className="flex items-center gap-2 px-3 pb-2">
            <input
              type="checkbox"
              checked={selectedIds.size === crashes.length && crashes.length > 0}
              onChange={() => {
                if (selectedIds.size === crashes.length) onClearSelection()
                else onSelectAll(crashes.map(c => c.id))
              }}
              className="rounded"
            />
            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
              {crashes.length} reports
            </span>
          </div>
          {crashes.map(crash => (
            <div key={crash.id} className="flex items-center gap-2">
              <input
                type="checkbox"
                checked={selectedIds.has(crash.id)}
                onChange={() => onToggleSelect(crash.id)}
                className="ml-3 rounded"
              />
              <div className="flex-1">
                <CrashRow crash={crash} onClick={() => onViewCrash(crash.id)} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Bug List Tab
// ═══════════════════════════════════════════════════

function BugListTab({ bugs, onViewBug, onUpdateStatus, onDelete }: {
  bugs: BugReport[]
  onViewBug: (bug: BugReport) => void
  onUpdateStatus: (id: string, status: string) => void
  onDelete: (id: string) => void
}) {
  return (
    <div className="space-y-4">
      {bugs.length === 0 ? (
        <div className="text-center py-12 rounded-xl" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)', color: 'var(--text-muted)' }}>
          <div className="text-3xl mb-2">🐛</div>
          No user-submitted bug reports yet
        </div>
      ) : (
        <div className="space-y-1">
          <div className="text-xs px-3 pb-2" style={{ color: 'var(--text-muted)' }}>
            {bugs.length} bug report{bugs.length !== 1 ? 's' : ''}
          </div>
          {bugs.map(bug => (
            <div key={bug.id} className="flex items-center gap-2">
              <div className="flex-1">
                <BugRow bug={bug} onClick={() => onViewBug(bug)} />
              </div>
              <select
                value={bug.status}
                onChange={e => onUpdateStatus(bug.id, e.target.value)}
                className="text-xs rounded-md px-2 py-1 shrink-0"
                style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-primary)' }}
              >
                <option value="new">New</option>
                <option value="in_progress">In Progress</option>
                <option value="resolved">Resolved</option>
                <option value="closed">Closed</option>
              </select>
              <button
                onClick={() => onDelete(bug.id)}
                className="text-xs px-2 py-1 rounded-md shrink-0 hover:opacity-70"
                style={{ color: '#ef4444' }}
                title="Delete bug report"
              >
                🗑️
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Row Components
// ═══════════════════════════════════════════════════

function CrashRow({ crash, onClick }: { crash: CrashReport; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
      style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}
    >
      <span className="text-lg shrink-0">{TYPE_ICONS[crash.report_type] || '❌'}</span>
      <div
        className="w-2.5 h-2.5 rounded-full shrink-0"
        style={{ background: SEVERITY_COLORS[crash.severity] || '#6b7280' }}
        title={crash.severity}
      />
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>
          {crash.error_message}
        </div>
        <div className="text-xs flex items-center gap-2 flex-wrap" style={{ color: 'var(--text-muted)' }}>
          {crash.error_domain && <span className="font-medium">{crash.error_domain}</span>}
          {crash.user_email && <span>· {crash.user_email}</span>}
          {crash.device_model && <span>· {crash.device_model}</span>}
          {crash.app_version && <span>· v{crash.app_version}</span>}
          <span>· {timeAgo(crash.created_at)}</span>
        </div>
      </div>
      <span
        className="text-xs px-2 py-0.5 rounded-full shrink-0"
        style={{ background: STATUS_COLORS[crash.status] + '22', color: STATUS_COLORS[crash.status] }}
      >
        {crash.status}
      </span>
    </button>
  )
}

function BugRow({ bug, onClick }: { bug: BugReport; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className="w-full text-left flex items-center gap-3 p-3 rounded-lg hover:opacity-80 transition-opacity"
      style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}
    >
      <span className="text-lg shrink-0">🐛</span>
      <div className="flex-1 min-w-0">
        <div className="text-sm truncate" style={{ color: 'var(--text-primary)' }}>
          {bug.description}
        </div>
        <div className="text-xs flex items-center gap-2" style={{ color: 'var(--text-muted)' }}>
          {bug.user_name && <span>{bug.user_name}</span>}
          {bug.user_email && <span>· {bug.user_email}</span>}
          {bug.device_model && <span>· {bug.device_model}</span>}
          {bug.app_version && <span>· v{bug.app_version}</span>}
          <span>· {timeAgo(bug.created_at)}</span>
          {bug.screenshot_base64 && <span>📸</span>}
          {bug.session_log && <span>📋</span>}
        </div>
      </div>
      <span
        className="text-xs px-2 py-0.5 rounded-full shrink-0"
        style={{ background: STATUS_COLORS[bug.status] + '22', color: STATUS_COLORS[bug.status] || '#6b7280' }}
      >
        {bug.status}
      </span>
    </button>
  )
}

// ═══════════════════════════════════════════════════
// Stat Card
// ═══════════════════════════════════════════════════

function StatCard({ label, value, icon, color, suffix }: { label: string; value: number; icon: string; color: string; suffix?: string }) {
  return (
    <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
      <div className="flex items-center justify-between mb-2">
        <span className="text-lg">{icon}</span>
        <span className="text-2xl font-bold" style={{ color }}>{value}{suffix || ''}</span>
      </div>
      <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{label}</span>
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Crash Detail View
// ═══════════════════════════════════════════════════

function CrashDetailView({ crash, onBack, onUpdateStatus, onUpdateNotes, onDelete }: {
  crash: CrashReport
  onBack: () => void
  onUpdateStatus: (status: string) => void
  onUpdateNotes: (notes: string) => void
  onDelete: () => void
}) {
  const [notes, setNotes] = useState(crash.admin_notes || '')
  const [expandedSections, setExpandedSections] = useState<Set<string>>(new Set(['details', 'context']))

  const toggleSection = (section: string) => {
    setExpandedSections(prev => {
      const next = new Set(prev)
      if (next.has(section)) next.delete(section)
      else next.add(section)
      return next
    })
  }

  return (
    <div style={{ padding: 32, maxWidth: 1000, margin: '0 auto' }}>
      {/* Back + Header */}
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-sm hover:opacity-70"
          style={{ color: 'var(--accent)' }}
        >
          ← Back to list
        </button>
        <button
          onClick={onDelete}
          className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg hover:opacity-70"
          style={{ color: '#ef4444', background: '#ef444412', border: '1px solid #ef444433' }}
        >
          🗑️ Delete
        </button>
      </div>

      <div className="flex items-start justify-between mb-6">
        <div>
          <div className="flex items-center gap-3 mb-1">
            <span className="text-2xl">{TYPE_ICONS[crash.report_type] || '❌'}</span>
            <h1 className="text-xl font-bold" style={{ color: 'var(--text-primary)' }}>
              {crash.report_type === 'fatal_signal' ? 'Fatal Signal' : crash.report_type === 'crash' ? 'App Crash' : 'Error Report'}
            </h1>
            <span
              className="text-xs px-2.5 py-1 rounded-full font-medium"
              style={{ background: SEVERITY_COLORS[crash.severity] + '22', color: SEVERITY_COLORS[crash.severity] }}
            >
              {crash.severity}
            </span>
          </div>
          <p className="text-sm" style={{ color: 'var(--text-muted)' }}>
            {new Date(crash.occurred_at).toLocaleString()} · ID: {crash.id.slice(0, 8)}
          </p>
        </div>

        {/* Status Selector */}
        <select
          value={crash.status}
          onChange={e => onUpdateStatus(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 font-medium"
          style={{ background: STATUS_COLORS[crash.status] + '22', color: STATUS_COLORS[crash.status], border: '1px solid ' + STATUS_COLORS[crash.status] + '44' }}
        >
          <option value="new">🔴 New</option>
          <option value="investigating">🟠 Investigating</option>
          <option value="identified">🟡 Identified</option>
          <option value="resolved">🟢 Resolved</option>
          <option value="wont_fix">⚪ Won&apos;t Fix</option>
          <option value="duplicate">🟣 Duplicate</option>
        </select>
      </div>

      {/* Error Message */}
      <div className="rounded-xl p-4 mb-4" style={{ background: '#ef444415', border: '1px solid #ef444433' }}>
        <pre className="text-sm whitespace-pre-wrap break-words" style={{ color: '#ef4444', fontFamily: 'ui-monospace, monospace' }}>
          {crash.error_message}
        </pre>
      </div>

      {/* Details Section */}
      <CollapsibleSection title="📋 Details" id="details" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="Report Type" value={crash.report_type} />
          <Detail label="Error Domain" value={crash.error_domain || '—'} />
          <Detail label="Error Code" value={crash.error_code || '—'} />
          <Detail label="Fingerprint" value={crash.fingerprint.slice(0, 16)} mono />
          <Detail label="Current Screen" value={crash.current_screen || '—'} />
          <Detail label="Session Duration" value={formatDuration(crash.session_duration_seconds)} />
          <Detail label="Actions Before Crash" value={crash.actions_before_crash?.toString() || '—'} />
          <Detail label="Occurred At" value={new Date(crash.occurred_at).toLocaleString()} />
        </div>
      </CollapsibleSection>

      {/* Device Context */}
      <CollapsibleSection title="📱 Device Context" id="context" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="Device" value={crash.device_model || '—'} />
          <Detail label="OS" value={crash.os_version || '—'} />
          <Detail label="App Version" value={crash.app_version ? `v${crash.app_version} (${crash.build_number || '?'})` : '—'} />
          <Detail label="Memory Usage" value={crash.memory_usage_mb ? `${crash.memory_usage_mb.toFixed(1)} MB` : '—'} />
          <Detail label="Free Memory" value={crash.free_memory_mb ? `${crash.free_memory_mb.toFixed(1)} MB` : '—'} />
          <Detail label="Battery" value={crash.battery_level != null ? `${Math.round(crash.battery_level * 100)}%` : '—'} />
          <Detail label="Low Power Mode" value={crash.is_low_power_mode ? 'Yes' : 'No'} />
          <Detail label="Network" value={crash.network_type || '—'} />
        </div>
      </CollapsibleSection>

      {/* User Context */}
      <CollapsibleSection title="👤 User Context" id="user" expanded={expandedSections} onToggle={toggleSection}>
        <div className="grid grid-cols-2 gap-3 text-sm">
          <Detail label="User ID" value={crash.user_id || '—'} mono />
          <Detail label="Name" value={crash.user_name || '—'} />
          <Detail label="Email" value={crash.user_email || '—'} />
        </div>
      </CollapsibleSection>

      {/* Breadcrumbs */}
      {crash.breadcrumbs && crash.breadcrumbs.length > 0 && (
        <CollapsibleSection title={`🍞 Breadcrumbs (${crash.breadcrumbs.length} actions)`} id="breadcrumbs" expanded={expandedSections} onToggle={toggleSection}>
          <div className="space-y-1 max-h-64 overflow-y-auto">
            {crash.breadcrumbs.map((crumb, i) => (
              <div key={i} className="flex items-center gap-2 text-xs py-1" style={{ borderBottom: '1px solid var(--border)' }}>
                <span style={{ color: 'var(--text-muted)', minWidth: 40, textAlign: 'right' }}>#{i + 1}</span>
                <span className="font-medium" style={{ color: 'var(--text-primary)' }}>{crumb.action}</span>
                {crumb.screen && <span style={{ color: 'var(--text-muted)' }}>@ {crumb.screen}</span>}
                <span className="ml-auto" style={{ color: 'var(--text-muted)' }}>
                  {new Date(crumb.timestamp).toLocaleTimeString()}
                </span>
              </div>
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Stack Trace */}
      {crash.stack_trace && (
        <CollapsibleSection title="📚 Stack Trace" id="stack" expanded={expandedSections} onToggle={toggleSection}>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {crash.stack_trace}
          </pre>
        </CollapsibleSection>
      )}

      {/* Additional Context */}
      {crash.additional_context && Object.keys(crash.additional_context).length > 0 && (
        <CollapsibleSection title="🔍 Additional Context" id="additional" expanded={expandedSections} onToggle={toggleSection}>
          <div className="grid grid-cols-2 gap-3 text-sm">
            {Object.entries(crash.additional_context).map(([key, val]) => (
              <Detail key={key} label={key} value={val} />
            ))}
          </div>
        </CollapsibleSection>
      )}

      {/* Session Log Snippet */}
      {crash.session_log_snippet && (
        <CollapsibleSection title="📋 Session Log Snippet" id="sessionlog" expanded={expandedSections} onToggle={toggleSection}>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {crash.session_log_snippet}
          </pre>
        </CollapsibleSection>
      )}

      {/* Admin Notes */}
      <div className="rounded-xl p-4 mt-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
        <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📝 Admin Notes</h3>
        <textarea
          value={notes}
          onChange={e => setNotes(e.target.value)}
          placeholder="Add investigation notes, root cause, fix details..."
          className="w-full rounded-lg p-3 text-sm"
          style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-primary)', minHeight: 100, resize: 'vertical' }}
        />
        <button
          onClick={() => onUpdateNotes(notes)}
          className="mt-2 text-sm px-4 py-2 rounded-lg"
          style={{ background: 'var(--accent)', color: 'white' }}
        >
          Save Notes
        </button>
      </div>
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Bug Detail View
// ═══════════════════════════════════════════════════

function BugDetailView({ bug, onBack, onUpdateStatus, onDelete }: {
  bug: BugReport
  onBack: () => void
  onUpdateStatus: (status: string) => void
  onDelete: () => void
}) {
  return (
    <div style={{ padding: 32, maxWidth: 1000, margin: '0 auto' }}>
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 text-sm hover:opacity-70"
          style={{ color: 'var(--accent)' }}
        >
          ← Back to list
        </button>
        <button
          onClick={onDelete}
          className="flex items-center gap-1 text-xs px-3 py-1.5 rounded-lg hover:opacity-70"
          style={{ color: '#ef4444', background: '#ef444412', border: '1px solid #ef444433' }}
        >
          🗑️ Delete
        </button>
      </div>

      <div className="flex items-start justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold flex items-center gap-3" style={{ color: 'var(--text-primary)' }}>
            🐛 Bug Report
          </h1>
          <p className="text-sm mt-1" style={{ color: 'var(--text-muted)' }}>
            Submitted {new Date(bug.created_at).toLocaleString()} by {bug.user_name || bug.user_email || 'Anonymous'}
          </p>
        </div>
        <select
          value={bug.status}
          onChange={e => onUpdateStatus(e.target.value)}
          className="text-sm rounded-lg px-3 py-2 font-medium"
          style={{ background: STATUS_COLORS[bug.status] + '22', color: STATUS_COLORS[bug.status] || '#6b7280', border: '1px solid ' + (STATUS_COLORS[bug.status] || '#6b7280') + '44' }}
        >
          <option value="new">🔴 New</option>
          <option value="in_progress">🟠 In Progress</option>
          <option value="resolved">🟢 Resolved</option>
          <option value="closed">⚪ Closed</option>
        </select>
      </div>

      {/* Description */}
      <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
        <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Description</h3>
        <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.description}</p>
      </div>

      {bug.expected_behavior && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Expected Behavior</h3>
          <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.expected_behavior}</p>
        </div>
      )}

      {bug.additional_info && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>Additional Info</h3>
          <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-secondary)' }}>{bug.additional_info}</p>
        </div>
      )}

      {/* Device + User Info */}
      <div className="grid grid-cols-2 gap-3 mb-4">
        <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📱 Device Info</h3>
          <div className="space-y-1 text-sm">
            <Detail label="Device" value={bug.device_model || '—'} />
            <Detail label="OS" value={bug.os_version || '—'} />
            <Detail label="App Version" value={bug.app_version || '—'} />
            <Detail label="Screen" value={bug.screen_name || '—'} />
            <Detail label="Reproduces" value={bug.reproduces_every_time ? 'Every time' : 'Sometimes'} />
          </div>
        </div>
        <div className="rounded-xl p-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>👤 User</h3>
          <div className="space-y-1 text-sm">
            <Detail label="Name" value={bug.user_name || '—'} />
            <Detail label="Email" value={bug.user_email || '—'} />
            <Detail label="User ID" value={bug.user_id || '—'} mono />
          </div>
        </div>
      </div>

      {/* Screenshot */}
      {bug.screenshot_base64 && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📸 Screenshot</h3>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={`data:image/jpeg;base64,${bug.screenshot_base64}`}
            alt="Bug screenshot"
            className="rounded-lg max-h-96 object-contain"
            style={{ border: '1px solid var(--border)' }}
          />
        </div>
      )}

      {/* Session Log */}
      {bug.session_log && (
        <div className="rounded-xl p-4 mb-4" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
          <h3 className="text-sm font-semibold mb-2" style={{ color: 'var(--text-primary)' }}>📋 Session Log</h3>
          <pre
            className="text-xs whitespace-pre-wrap break-all p-3 rounded-lg overflow-x-auto max-h-96 overflow-y-auto"
            style={{ background: 'var(--bg-primary)', border: '1px solid var(--border)', color: 'var(--text-secondary)', fontFamily: 'ui-monospace, monospace' }}
          >
            {bug.session_log}
          </pre>
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// Shared UI Components
// ═══════════════════════════════════════════════════

function Detail({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <span className="text-xs block" style={{ color: 'var(--text-muted)' }}>{label}</span>
      <span className={`text-sm ${mono ? 'font-mono' : ''}`} style={{ color: 'var(--text-primary)' }}>{value}</span>
    </div>
  )
}

function CollapsibleSection({ title, id, expanded, onToggle, children }: {
  title: string
  id: string
  expanded: Set<string>
  onToggle: (id: string) => void
  children: React.ReactNode
}) {
  const isExpanded = expanded.has(id)
  return (
    <div className="rounded-xl mb-3 overflow-hidden" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
      <button
        onClick={() => onToggle(id)}
        className="w-full flex items-center justify-between p-4 text-sm font-semibold hover:opacity-80"
        style={{ color: 'var(--text-primary)' }}
      >
        {title}
        <span style={{ color: 'var(--text-muted)' }}>{isExpanded ? '▼' : '▶'}</span>
      </button>
      {isExpanded && (
        <div className="px-4 pb-4">
          {children}
        </div>
      )}
    </div>
  )
}
