'use client'

import { useEffect, useState } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

interface FeatureFlag {
  id: string
  key: string
  description: string | null
  enabled: boolean
  rollout_percentage: number
  platform: string
  min_app_version: string | null
  metadata: Record<string, unknown>
  created_by: string | null
  updated_by: string | null
  created_at: string
  updated_at: string
}

interface AuditEntry {
  id: string
  action: string
  admin_email: string | null
  target_id: string | null
  details: Record<string, unknown>
  created_at: string
}

export default function FlagsPage() {
  const [flags, setFlags] = useState<FeatureFlag[]>([])
  const [history, setHistory] = useState<AuditEntry[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<'flags' | 'history'>('flags')
  const [showCreate, setShowCreate] = useState(false)
  const [editingMeta, setEditingMeta] = useState<string | null>(null)
  const [metaJson, setMetaJson] = useState('')
  const [saving, setSaving] = useState<string | null>(null)

  const [newFlag, setNewFlag] = useState({
    key: '', description: '', enabled: false,
    rollout_percentage: 100, platform: 'all', min_app_version: '',
  })

  useEffect(() => { loadFlags() }, [])

  async function loadFlags() {
    try {
      setLoading(true)
      const data = await adminApi('get_feature_flags')
      setFlags(data.flags || [])
    } catch (err) { console.error('Failed to load flags:', err) }
    finally { setLoading(false) }
  }

  async function loadHistory() {
    try {
      const data = await adminApi('get_feature_flag_history')
      setHistory(data.history || [])
    } catch (err) { console.error('Failed to load history:', err) }
  }

  async function toggleFlag(flag: FeatureFlag) {
    setSaving(flag.id)
    try {
      await adminApi('update_feature_flag', { flag_id: flag.id, enabled: !flag.enabled })
      setFlags(prev => prev.map(f => f.id === flag.id ? { ...f, enabled: !f.enabled } : f))
    } catch (err) { console.error('Toggle failed:', err) }
    finally { setSaving(null) }
  }

  async function updateRollout(flagId: string, pct: number) {
    setSaving(flagId)
    try {
      await adminApi('update_feature_flag', { flag_id: flagId, rollout_percentage: pct })
      setFlags(prev => prev.map(f => f.id === flagId ? { ...f, rollout_percentage: pct } : f))
    } catch (err) { console.error('Rollout update failed:', err) }
    finally { setSaving(null) }
  }

  async function createFlag() {
    if (!newFlag.key.trim()) return
    setSaving('new')
    try {
      await adminApi('create_feature_flag', {
        key: newFlag.key, description: newFlag.description,
        enabled: newFlag.enabled, rollout_percentage: newFlag.rollout_percentage,
        platform: newFlag.platform,
        min_app_version: newFlag.min_app_version || null,
      })
      setShowCreate(false)
      setNewFlag({ key: '', description: '', enabled: false, rollout_percentage: 100, platform: 'all', min_app_version: '' })
      await loadFlags()
    } catch (err) { console.error('Create failed:', err) }
    finally { setSaving(null) }
  }

  async function deleteFlag(flagId: string) {
    if (!confirm('Delete this feature flag?')) return
    try {
      await adminApi('delete_feature_flag', { flag_id: flagId })
      setFlags(prev => prev.filter(f => f.id !== flagId))
    } catch (err) { console.error('Delete failed:', err) }
  }

  async function saveMetadata(flagId: string) {
    try {
      const parsed = JSON.parse(metaJson)
      await adminApi('update_feature_flag', { flag_id: flagId, metadata: parsed })
      setFlags(prev => prev.map(f => f.id === flagId ? { ...f, metadata: parsed } : f))
      setEditingMeta(null)
    } catch { alert('Invalid JSON') }
  }

  function timeAgo(iso: string) {
    const diff = Date.now() - new Date(iso).getTime()
    const m = Math.floor(diff / 60000)
    if (m < 60) return `${m}m ago`
    const h = Math.floor(m / 60)
    if (h < 24) return `${h}h ago`
    return `${Math.floor(h / 24)}d ago`
  }

  const enabledFlags = flags.filter(f => f.enabled)
  const disabledFlags = flags.filter(f => !f.enabled)
  const tabs = [
    { key: 'flags' as const, label: `Flags (${flags.length})` },
    { key: 'history' as const, label: 'Change History' },
  ]

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>Feature Flags</h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              Toggle features, control rollout, manage kill switches
            </p>
          </div>
          <div className="flex gap-2">
            <button onClick={loadFlags} className="btn btn-ghost text-sm">Refresh</button>
            <button onClick={() => setShowCreate(true)} className="btn btn-primary text-sm">+ New Flag</button>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 mb-6 p-1 rounded-lg" style={{ background: 'var(--bg-tertiary)' }}>
          {tabs.map(t => (
            <button key={t.key} onClick={() => { if (t.key === 'history') loadHistory(); setActiveTab(t.key) }}
              className="px-4 py-2 rounded-md text-sm font-medium"
              style={{ background: activeTab === t.key ? 'var(--bg-secondary)' : 'transparent', color: activeTab === t.key ? 'var(--text-primary)' : 'var(--text-muted)' }}>
              {t.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="flex justify-center py-20"><div className="spinner" style={{ width: 32, height: 32 }} /></div>
        ) : activeTab === 'flags' ? (
          <>
            {/* Create Dialog */}
            {showCreate && (
              <div className="card mb-6" style={{ borderColor: 'var(--accent)', borderWidth: 2 }}>
                <h3 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Create Feature Flag</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                  <div>
                    <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Key (slug)</label>
                    <input type="text" placeholder="enable_social_feed" value={newFlag.key}
                      onChange={e => setNewFlag(p => ({ ...p, key: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_') }))} />
                  </div>
                  <div>
                    <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Description</label>
                    <input type="text" placeholder="Enable the social feed tab" value={newFlag.description}
                      onChange={e => setNewFlag(p => ({ ...p, description: e.target.value }))} />
                  </div>
                  <div>
                    <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Platform</label>
                    <select value={newFlag.platform} onChange={e => setNewFlag(p => ({ ...p, platform: e.target.value }))}>
                      <option value="all">All</option>
                      <option value="ios">iOS</option>
                      <option value="android">Android</option>
                    </select>
                  </div>
                  <div>
                    <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Min App Version</label>
                    <input type="text" placeholder="2.1.0 (optional)" value={newFlag.min_app_version}
                      onChange={e => setNewFlag(p => ({ ...p, min_app_version: e.target.value }))} />
                  </div>
                  <div>
                    <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Rollout %</label>
                    <div className="flex items-center gap-3">
                      <input type="range" min={0} max={100} value={newFlag.rollout_percentage}
                        onChange={e => setNewFlag(p => ({ ...p, rollout_percentage: Number(e.target.value) }))}
                        className="flex-1" style={{ accentColor: 'var(--accent)' }} />
                      <span className="text-sm font-mono w-10 text-right" style={{ color: 'var(--text-primary)' }}>{newFlag.rollout_percentage}%</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 pt-5">
                    <label className="text-xs font-medium" style={{ color: 'var(--text-secondary)' }}>Enabled on create</label>
                    <button onClick={() => setNewFlag(p => ({ ...p, enabled: !p.enabled }))}
                      className="w-10 h-5 rounded-full relative" style={{ background: newFlag.enabled ? 'var(--success)' : 'var(--bg-tertiary)' }}>
                      <div className="w-4 h-4 rounded-full bg-white absolute top-0.5 transition-all"
                        style={{ left: newFlag.enabled ? 22 : 2 }} />
                    </button>
                  </div>
                </div>
                <div className="flex gap-2 justify-end">
                  <button onClick={() => setShowCreate(false)} className="btn btn-ghost text-sm">Cancel</button>
                  <button onClick={createFlag} className="btn btn-primary text-sm" disabled={!newFlag.key.trim() || saving === 'new'}>
                    {saving === 'new' ? 'Creating...' : 'Create Flag'}
                  </button>
                </div>
              </div>
            )}

            {/* Enabled Flags */}
            {enabledFlags.length > 0 && (
              <div className="mb-6">
                <h2 className="text-sm font-semibold uppercase tracking-wider mb-3" style={{ color: 'var(--success)' }}>
                  Active ({enabledFlags.length})
                </h2>
                <div className="space-y-3">
                  {enabledFlags.map(flag => <FlagCard key={flag.id} flag={flag} saving={saving} onToggle={toggleFlag}
                    onRollout={updateRollout} onDelete={deleteFlag} editingMeta={editingMeta} metaJson={metaJson}
                    setEditingMeta={setEditingMeta} setMetaJson={setMetaJson} saveMetadata={saveMetadata} timeAgo={timeAgo} />)}
                </div>
              </div>
            )}

            {/* Disabled Flags */}
            {disabledFlags.length > 0 && (
              <div>
                <h2 className="text-sm font-semibold uppercase tracking-wider mb-3" style={{ color: 'var(--text-muted)' }}>
                  Disabled ({disabledFlags.length})
                </h2>
                <div className="space-y-3">
                  {disabledFlags.map(flag => <FlagCard key={flag.id} flag={flag} saving={saving} onToggle={toggleFlag}
                    onRollout={updateRollout} onDelete={deleteFlag} editingMeta={editingMeta} metaJson={metaJson}
                    setEditingMeta={setEditingMeta} setMetaJson={setMetaJson} saveMetadata={saveMetadata} timeAgo={timeAgo} />)}
                </div>
              </div>
            )}

            {flags.length === 0 && (
              <div className="card text-center py-16">
                <p className="text-lg mb-2" style={{ color: 'var(--text-muted)' }}>No feature flags yet</p>
                <button onClick={() => setShowCreate(true)} className="btn btn-primary text-sm">Create your first flag</button>
              </div>
            )}
          </>
        ) : (
          /* History tab */
          <div className="card">
            <h3 className="text-lg font-semibold mb-4" style={{ color: 'var(--text-primary)' }}>Flag Change History</h3>
            {history.length === 0 ? (
              <p className="text-sm py-8 text-center" style={{ color: 'var(--text-muted)' }}>No flag changes recorded yet</p>
            ) : (
              <div className="space-y-3">
                {history.map(h => (
                  <div key={h.id} className="flex items-start gap-3 p-3 rounded-lg" style={{ background: 'var(--bg-tertiary)' }}>
                    <div className="w-2 h-2 rounded-full mt-2 shrink-0" style={{
                      background: h.action.includes('create') ? 'var(--success)' : h.action.includes('delete') ? 'var(--danger)' : 'var(--warning)'
                    }} />
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <span className="badge badge-neutral">{h.action.replace('_feature_flag', '')}</span>
                        <span className="text-xs" style={{ color: 'var(--text-muted)' }}>{h.admin_email || 'Unknown'}</span>
                      </div>
                      {h.target_id && <p className="text-xs font-mono" style={{ color: 'var(--text-secondary)' }}>Target: {h.target_id}</p>}
                    </div>
                    <span className="text-xs shrink-0" style={{ color: 'var(--text-muted)' }}>{timeAgo(h.created_at)}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </AdminShell>
  )
}

function FlagCard({ flag, saving, onToggle, onRollout, onDelete, editingMeta, metaJson, setEditingMeta, setMetaJson, saveMetadata, timeAgo }: {
  flag: FeatureFlag; saving: string | null
  onToggle: (f: FeatureFlag) => void; onRollout: (id: string, pct: number) => void; onDelete: (id: string) => void
  editingMeta: string | null; metaJson: string
  setEditingMeta: (id: string | null) => void; setMetaJson: (s: string) => void; saveMetadata: (id: string) => void
  timeAgo: (iso: string) => string
}) {
  return (
    <div className="card">
      <div className="flex items-start justify-between gap-4">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="font-mono text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>{flag.key}</span>
            <span className={`badge ${flag.platform === 'ios' ? 'badge-info' : flag.platform === 'android' ? 'badge-success' : 'badge-neutral'}`}>
              {flag.platform}
            </span>
            {flag.min_app_version && <span className="badge badge-neutral">v{flag.min_app_version}+</span>}
          </div>
          {flag.description && <p className="text-sm mb-2" style={{ color: 'var(--text-secondary)' }}>{flag.description}</p>}

          <div className="flex items-center gap-4 mt-3">
            <div className="flex items-center gap-2">
              <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Rollout:</span>
              <input type="range" min={0} max={100} value={flag.rollout_percentage}
                onChange={e => onRollout(flag.id, Number(e.target.value))}
                className="w-32" style={{ accentColor: 'var(--accent)' }} />
              <span className="text-xs font-mono w-10" style={{ color: 'var(--text-primary)' }}>{flag.rollout_percentage}%</span>
            </div>
            <span className="text-xs" style={{ color: 'var(--text-muted)' }}>Updated {timeAgo(flag.updated_at)}</span>
          </div>
        </div>

        <div className="flex items-center gap-3 shrink-0">
          <button onClick={() => { setEditingMeta(editingMeta === flag.id ? null : flag.id); setMetaJson(JSON.stringify(flag.metadata || {}, null, 2)) }}
            className="btn btn-ghost text-xs">{editingMeta === flag.id ? 'Close' : 'Config'}</button>
          <button onClick={() => onToggle(flag)} disabled={saving === flag.id}
            className="w-12 h-6 rounded-full relative cursor-pointer" style={{ background: flag.enabled ? 'var(--success)' : 'var(--bg-tertiary)', border: '1px solid var(--border)' }}>
            <div className="w-5 h-5 rounded-full bg-white absolute top-0.5 transition-all" style={{ left: flag.enabled ? 24 : 2 }} />
          </button>
          <button onClick={() => onDelete(flag.id)} className="text-xs px-2 py-1 rounded" style={{ color: 'var(--danger)' }}>Delete</button>
        </div>
      </div>

      {editingMeta === flag.id && (
        <div className="mt-4 pt-4" style={{ borderTop: '1px solid var(--border)' }}>
          <label className="text-xs font-medium mb-1 block" style={{ color: 'var(--text-secondary)' }}>Metadata (JSON)</label>
          <textarea rows={5} className="font-mono text-xs w-full" value={metaJson}
            onChange={e => setMetaJson(e.target.value)} style={{ background: 'var(--bg-tertiary)', border: '1px solid var(--border)', color: 'var(--text-primary)', padding: 12, borderRadius: 8 }} />
          <div className="flex justify-end gap-2 mt-2">
            <button onClick={() => setEditingMeta(null)} className="btn btn-ghost text-xs">Cancel</button>
            <button onClick={() => saveMetadata(flag.id)} className="btn btn-primary text-xs">Save Config</button>
          </div>
        </div>
      )}
    </div>
  )
}
