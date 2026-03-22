'use client'

import { useEffect, useState, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'

type Category = {
  id: string; slug: string; name: string; icon: string
  display_order: number; entry_count: number
}
type Entry = {
  id: string; entry_id: string; category_id: string; question: string; answer: string
  keywords: string[]; channel: string; status: string; display_order: number
  auto_generated: boolean; source_commit: string | null; updated_at: string
  faq_categories: { slug: string; name: string } | null
}

async function adminAction(action: string, params: Record<string, unknown> = {}) {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })
  return res.json()
}

const statusColors: Record<string, { bg: string; text: string }> = {
  published: { bg: '#22c55e22', text: '#22c55e' },
  draft: { bg: '#f59e0b22', text: '#f59e0b' },
  archived: { bg: '#6b728022', text: '#6b7280' },
}

export default function FAQPage() {
  const [categories, setCategories] = useState<Category[]>([])
  const [entries, setEntries] = useState<Entry[]>([])
  const [selectedCat, setSelectedCat] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState('all')
  const [search, setSearch] = useState('')
  const [loading, setLoading] = useState(true)
  const [editingEntry, setEditingEntry] = useState<string | null>(null)
  const [showAddEntry, setShowAddEntry] = useState(false)
  const [showAddCat, setShowAddCat] = useState(false)

  const [newEntry, setNewEntry] = useState({ entry_id: '', question: '', answer: '', channel: 'both', status: 'draft' })
  const [newCat, setNewCat] = useState({ name: '', slug: '', icon: '' })

  const loadCategories = useCallback(async () => {
    const data = await adminAction('get_faq_categories')
    setCategories(data.categories || [])
  }, [])

  const loadEntries = useCallback(async () => {
    const params: Record<string, unknown> = {}
    if (selectedCat) params.category_id = selectedCat
    if (statusFilter !== 'all') params.status = statusFilter
    if (search.trim()) params.search = search.trim()
    const data = await adminAction('get_faq_entries', params)
    setEntries(data.entries || [])
    setLoading(false)
  }, [selectedCat, statusFilter, search])

  useEffect(() => { loadCategories() }, [loadCategories])
  useEffect(() => { loadEntries() }, [loadEntries])

  const draftCount = entries.filter(e => e.status === 'draft' && e.auto_generated).length
  const totalDrafts = entries.filter(e => e.status === 'draft').length

  async function handleUpdateEntry(id: string, updates: Record<string, unknown>) {
    await adminAction('update_faq_entry', { id, ...updates })
    loadEntries()
  }

  async function handleDeleteEntry(id: string) {
    if (!confirm('Delete this FAQ entry?')) return
    await adminAction('delete_faq_entry', { id })
    loadEntries()
    loadCategories()
  }

  async function handlePublish(id: string) {
    await adminAction('publish_faq_entry', { id })
    loadEntries()
  }

  async function handleBulkPublish() {
    if (!confirm(`Publish all ${totalDrafts} draft entries?`)) return
    await adminAction('bulk_publish_faq_entries')
    loadEntries()
  }

  async function handleCreateEntry() {
    if (!newEntry.entry_id || !newEntry.question || !newEntry.answer || !selectedCat) return
    await adminAction('create_faq_entry', { ...newEntry, category_id: selectedCat })
    setNewEntry({ entry_id: '', question: '', answer: '', channel: 'both', status: 'draft' })
    setShowAddEntry(false)
    loadEntries()
    loadCategories()
  }

  async function handleCreateCategory() {
    if (!newCat.name || !newCat.slug) return
    await adminAction('create_faq_category', {
      ...newCat, display_order: categories.length + 1,
    })
    setNewCat({ name: '', slug: '', icon: '' })
    setShowAddCat(false)
    loadCategories()
  }

  async function handleDeleteCategory(id: string) {
    const cat = categories.find(c => c.id === id)
    if (!confirm(`Delete category "${cat?.name}"? (Only works if empty)`)) return
    const res = await adminAction('delete_faq_category', { id })
    if (res.error) alert(res.error)
    else {
      if (selectedCat === id) setSelectedCat(null)
      loadCategories()
    }
  }

  return (
    <AdminShell>
      <div style={{ padding: 32, maxWidth: 1400, margin: '0 auto' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 8 }}>
          <h1 style={{ fontSize: 24, fontWeight: 700 }}>FAQ Manager</h1>
          <span style={{ fontSize: 13, color: 'var(--text-muted)' }}>
            {entries.length} entries across {categories.length} categories
          </span>
        </div>
        <p style={{ color: 'var(--text-muted)', marginBottom: 20, fontSize: 14 }}>
          Manage FAQ content for the help center and in-app FAQ. Changes reflect on the public FAQ API immediately.
        </p>

        {/* Draft Review Banner */}
        {totalDrafts > 0 && (
          <div style={{
            background: '#f59e0b15', border: '1px solid #f59e0b44', borderRadius: 10,
            padding: '12px 20px', marginBottom: 20, display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          }}>
            <div>
              <span style={{ fontWeight: 600, fontSize: 14 }}>
                {totalDrafts} draft{totalDrafts !== 1 ? 's' : ''} pending
              </span>
              {draftCount > 0 && (
                <span style={{ fontSize: 12, color: 'var(--text-muted)', marginLeft: 8 }}>
                  ({draftCount} auto-generated from commits)
                </span>
              )}
            </div>
            <button
              onClick={handleBulkPublish}
              style={{
                padding: '6px 16px', borderRadius: 8, background: '#f59e0b', color: '#000',
                fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer',
              }}
            >
              Publish All Drafts
            </button>
          </div>
        )}

        <div style={{ display: 'grid', gridTemplateColumns: '260px 1fr', gap: 20 }}>
          {/* Category Sidebar */}
          <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 16, border: '1px solid var(--border)', maxHeight: '75vh', overflow: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
              <h2 style={{ fontSize: 14, fontWeight: 600 }}>Categories</h2>
              <button
                onClick={() => setShowAddCat(!showAddCat)}
                style={{ fontSize: 18, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', lineHeight: 1 }}
                title="Add Category"
              >+</button>
            </div>

            {showAddCat && (
              <div style={{ marginBottom: 12, padding: 10, background: 'var(--bg-primary)', borderRadius: 8 }}>
                <input
                  value={newCat.name} onChange={e => setNewCat({ ...newCat, name: e.target.value, slug: e.target.value.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/-$/, '') })}
                  placeholder="Category name" style={{ width: '100%', padding: '6px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-secondary)', color: 'var(--text-primary)', fontSize: 12, marginBottom: 6 }}
                />
                <input
                  value={newCat.icon} onChange={e => setNewCat({ ...newCat, icon: e.target.value })}
                  placeholder="Icon (emoji)" style={{ width: '100%', padding: '6px 8px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-secondary)', color: 'var(--text-primary)', fontSize: 12, marginBottom: 6 }}
                />
                <div style={{ display: 'flex', gap: 6 }}>
                  <button onClick={handleCreateCategory} style={{ flex: 1, padding: '6px', borderRadius: 6, background: 'var(--accent)', color: 'white', fontSize: 12, fontWeight: 600, border: 'none', cursor: 'pointer' }}>Add</button>
                  <button onClick={() => setShowAddCat(false)} style={{ padding: '6px 10px', borderRadius: 6, background: 'var(--bg-secondary)', color: 'var(--text-muted)', fontSize: 12, border: '1px solid var(--border)', cursor: 'pointer' }}>Cancel</button>
                </div>
              </div>
            )}

            <button
              onClick={() => { setSelectedCat(null); setStatusFilter('all') }}
              style={{
                display: 'flex', justifyContent: 'space-between', width: '100%', textAlign: 'left',
                padding: '8px 10px', borderRadius: 8, marginBottom: 2, border: 'none', cursor: 'pointer',
                background: !selectedCat ? 'rgba(37, 99, 235, 0.12)' : 'transparent', color: 'var(--text-primary)', fontSize: 13,
              }}
            >
              <span>All Categories</span>
              <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>{categories.reduce((s, c) => s + c.entry_count, 0)}</span>
            </button>

            {categories.map(cat => (
              <div key={cat.id} style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
                <button
                  onClick={() => setSelectedCat(cat.id)}
                  style={{
                    flex: 1, display: 'flex', justifyContent: 'space-between', textAlign: 'left',
                    padding: '8px 10px', borderRadius: 8, marginBottom: 2, border: 'none', cursor: 'pointer',
                    background: selectedCat === cat.id ? 'rgba(37, 99, 235, 0.12)' : 'transparent',
                    color: 'var(--text-primary)', fontSize: 13,
                  }}
                >
                  <span>{cat.icon} {cat.name}</span>
                  <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>{cat.entry_count}</span>
                </button>
                <button
                  onClick={() => handleDeleteCategory(cat.id)}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', fontSize: 11, padding: 4, opacity: 0.5 }}
                  title="Delete category"
                >&times;</button>
              </div>
            ))}
          </div>

          {/* Main Content */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
            {/* Toolbar */}
            <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap' }}>
              {['all', 'published', 'draft', 'archived'].map(s => (
                <button
                  key={s}
                  onClick={() => setStatusFilter(s)}
                  style={{
                    padding: '6px 14px', borderRadius: 8, fontSize: 12, fontWeight: 600, border: 'none', cursor: 'pointer',
                    background: statusFilter === s ? 'var(--accent)' : 'var(--bg-secondary)',
                    color: statusFilter === s ? 'white' : 'var(--text-muted)',
                  }}
                >{s.charAt(0).toUpperCase() + s.slice(1)}</button>
              ))}
              <input
                value={search} onChange={e => setSearch(e.target.value)}
                placeholder="Search questions..."
                style={{
                  marginLeft: 'auto', padding: '6px 12px', borderRadius: 8, border: '1px solid var(--border)',
                  background: 'var(--bg-secondary)', color: 'var(--text-primary)', fontSize: 13, minWidth: 200,
                }}
              />
              {selectedCat && (
                <button
                  onClick={() => setShowAddEntry(!showAddEntry)}
                  style={{
                    padding: '6px 16px', borderRadius: 8, background: 'var(--accent)', color: 'white',
                    fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer',
                  }}
                >+ Add Entry</button>
              )}
            </div>

            {/* Add Entry Form */}
            {showAddEntry && selectedCat && (
              <div style={{ background: 'var(--bg-secondary)', borderRadius: 12, padding: 20, border: '1px solid var(--accent)' }}>
                <h3 style={{ fontSize: 14, fontWeight: 600, marginBottom: 12 }}>New FAQ Entry</h3>
                <div style={{ display: 'grid', gridTemplateColumns: '120px 1fr', gap: 10, alignItems: 'start' }}>
                  <label style={{ fontSize: 12, color: 'var(--text-muted)', paddingTop: 8 }}>Entry ID</label>
                  <input
                    value={newEntry.entry_id} onChange={e => setNewEntry({ ...newEntry, entry_id: e.target.value })}
                    placeholder="e.g. WK-13" style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
                  />
                  <label style={{ fontSize: 12, color: 'var(--text-muted)', paddingTop: 8 }}>Question</label>
                  <input
                    value={newEntry.question} onChange={e => setNewEntry({ ...newEntry, question: e.target.value })}
                    placeholder="How do I...?" style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
                  />
                  <label style={{ fontSize: 12, color: 'var(--text-muted)', paddingTop: 8 }}>Answer</label>
                  <textarea
                    value={newEntry.answer} onChange={e => setNewEntry({ ...newEntry, answer: e.target.value })}
                    placeholder="The answer..." rows={3} style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13, resize: 'vertical' }}
                  />
                  <label style={{ fontSize: 12, color: 'var(--text-muted)', paddingTop: 8 }}>Channel</label>
                  <select
                    value={newEntry.channel} onChange={e => setNewEntry({ ...newEntry, channel: e.target.value })}
                    style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
                  >
                    <option value="both">Web + App</option>
                    <option value="web">Web Only</option>
                    <option value="app">App Only</option>
                  </select>
                  <label style={{ fontSize: 12, color: 'var(--text-muted)', paddingTop: 8 }}>Status</label>
                  <select
                    value={newEntry.status} onChange={e => setNewEntry({ ...newEntry, status: e.target.value })}
                    style={{ padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
                  >
                    <option value="draft">Draft</option>
                    <option value="published">Published</option>
                  </select>
                </div>
                <div style={{ display: 'flex', gap: 8, marginTop: 12, justifyContent: 'flex-end' }}>
                  <button onClick={() => setShowAddEntry(false)} style={{ padding: '6px 14px', borderRadius: 8, background: 'var(--bg-primary)', color: 'var(--text-muted)', fontSize: 13, border: '1px solid var(--border)', cursor: 'pointer' }}>Cancel</button>
                  <button onClick={handleCreateEntry} style={{ padding: '6px 14px', borderRadius: 8, background: 'var(--accent)', color: 'white', fontWeight: 600, fontSize: 13, border: 'none', cursor: 'pointer' }}>Create Entry</button>
                </div>
              </div>
            )}

            {/* Entries List */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {loading ? (
                <p style={{ color: 'var(--text-muted)', fontSize: 13, padding: 20, textAlign: 'center' }}>Loading...</p>
              ) : entries.length === 0 ? (
                <p style={{ color: 'var(--text-muted)', fontSize: 13, padding: 20, textAlign: 'center' }}>
                  {selectedCat ? 'No entries in this category.' : 'Select a category or search to see entries.'}
                </p>
              ) : entries.map(entry => {
                const isEditing = editingEntry === entry.id
                const sc = statusColors[entry.status] || statusColors.draft
                return (
                  <div key={entry.id} style={{
                    background: 'var(--bg-secondary)', borderRadius: 10, border: '1px solid var(--border)',
                    padding: '14px 18px', transition: 'border-color 0.15s',
                    ...(entry.auto_generated && entry.status === 'draft' ? { borderColor: '#f59e0b44' } : {}),
                  }}>
                    {/* Header Row */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: isEditing ? 12 : 0 }}>
                      <span style={{
                        fontSize: 10, fontWeight: 700, fontFamily: 'monospace', padding: '2px 6px',
                        borderRadius: 4, background: 'var(--bg-primary)', color: 'var(--text-muted)',
                      }}>{entry.entry_id}</span>
                      <span style={{
                        fontSize: 10, fontWeight: 600, padding: '2px 8px', borderRadius: 4,
                        background: sc.bg, color: sc.text,
                      }}>{entry.status}</span>
                      {entry.auto_generated && (
                        <span style={{ fontSize: 10, color: '#a855f7', fontWeight: 600 }}>auto-generated</span>
                      )}
                      {entry.faq_categories && !selectedCat && (
                        <span style={{ fontSize: 10, color: 'var(--text-muted)' }}>{entry.faq_categories.name}</span>
                      )}
                      <span style={{ flex: 1 }} />
                      {entry.status === 'draft' && (
                        <button onClick={() => handlePublish(entry.id)} style={{
                          padding: '3px 10px', borderRadius: 6, background: '#22c55e22', color: '#22c55e',
                          fontSize: 11, fontWeight: 600, border: 'none', cursor: 'pointer',
                        }}>Publish</button>
                      )}
                      <button onClick={() => setEditingEntry(isEditing ? null : entry.id)} style={{
                        padding: '3px 10px', borderRadius: 6, background: 'var(--bg-primary)',
                        color: 'var(--text-muted)', fontSize: 11, fontWeight: 600, border: '1px solid var(--border)', cursor: 'pointer',
                      }}>{isEditing ? 'Close' : 'Edit'}</button>
                      <button onClick={() => handleDeleteEntry(entry.id)} style={{
                        padding: '3px 8px', borderRadius: 6, background: 'transparent',
                        color: '#ef4444', fontSize: 11, border: 'none', cursor: 'pointer', opacity: 0.6,
                      }}>&times;</button>
                    </div>

                    {/* Question (always visible) */}
                    {!isEditing && (
                      <div style={{ marginTop: 6 }}>
                        <div style={{ fontSize: 14, fontWeight: 600, marginBottom: 4 }}>{entry.question}</div>
                        <div style={{ fontSize: 12, color: 'var(--text-muted)', lineHeight: 1.5 }}>{entry.answer}</div>
                      </div>
                    )}

                    {/* Edit Form */}
                    {isEditing && (
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                        <div>
                          <label style={{ fontSize: 11, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>Question</label>
                          <input
                            defaultValue={entry.question}
                            onBlur={e => { if (e.target.value !== entry.question) handleUpdateEntry(entry.id, { question: e.target.value }) }}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13 }}
                          />
                        </div>
                        <div>
                          <label style={{ fontSize: 11, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>Answer</label>
                          <textarea
                            defaultValue={entry.answer}
                            onBlur={e => { if (e.target.value !== entry.answer) handleUpdateEntry(entry.id, { answer: e.target.value }) }}
                            rows={4}
                            style={{ width: '100%', padding: '8px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 13, resize: 'vertical' }}
                          />
                        </div>
                        <div style={{ display: 'flex', gap: 12 }}>
                          <div style={{ flex: 1 }}>
                            <label style={{ fontSize: 11, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>Channel</label>
                            <select
                              defaultValue={entry.channel}
                              onChange={e => handleUpdateEntry(entry.id, { channel: e.target.value })}
                              style={{ width: '100%', padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 12 }}
                            >
                              <option value="both">Web + App</option>
                              <option value="web">Web Only</option>
                              <option value="app">App Only</option>
                            </select>
                          </div>
                          <div style={{ flex: 1 }}>
                            <label style={{ fontSize: 11, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>Status</label>
                            <select
                              defaultValue={entry.status}
                              onChange={e => handleUpdateEntry(entry.id, { status: e.target.value })}
                              style={{ width: '100%', padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 12 }}
                            >
                              <option value="draft">Draft</option>
                              <option value="published">Published</option>
                              <option value="archived">Archived</option>
                            </select>
                          </div>
                          <div style={{ flex: 1 }}>
                            <label style={{ fontSize: 11, color: 'var(--text-muted)', display: 'block', marginBottom: 4 }}>Entry ID</label>
                            <input
                              defaultValue={entry.entry_id}
                              onBlur={e => { if (e.target.value !== entry.entry_id) handleUpdateEntry(entry.id, { entry_id: e.target.value }) }}
                              style={{ width: '100%', padding: '6px 10px', borderRadius: 6, border: '1px solid var(--border)', background: 'var(--bg-primary)', color: 'var(--text-primary)', fontSize: 12, fontFamily: 'monospace' }}
                            />
                          </div>
                        </div>
                        {entry.source_commit && (
                          <div style={{ fontSize: 11, color: 'var(--text-muted)' }}>
                            Source commit: <code style={{ fontFamily: 'monospace' }}>{entry.source_commit.slice(0, 8)}</code>
                          </div>
                        )}
                      </div>
                    )}
                  </div>
                )
              })}
            </div>
          </div>
        </div>
      </div>
    </AdminShell>
  )
}
