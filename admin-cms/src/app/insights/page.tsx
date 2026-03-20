'use client'

import { useEffect, useState, useRef, useCallback } from 'react'
import AdminShell from '@/components/AdminShell'
import { adminApi } from '@/lib/api'

// ═══════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════

interface Insight {
  id: string
  insight_type: string
  category: string
  title: string
  body: string
  data_snapshot: Record<string, unknown>
  priority: string
  status: string
  model_used: string
  generated_at: string
}

interface ChatMessage {
  role: 'user' | 'assistant'
  content: string
}

interface Conversation {
  id: string
  title: string
  created_at: string
  updated_at: string
}

// ═══════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════

const PRIORITY_COLORS: Record<string, string> = {
  high: '#ef4444',
  medium: '#f59e0b',
  low: '#6b7280',
}

const CATEGORY_COLORS: Record<string, string> = {
  retention: '#8b5cf6',
  exercises: '#22c55e',
  onboarding: '#3b82f6',
  engagement: '#f59e0b',
  workouts: '#06b6d4',
  social: '#ec4899',
  general: '#6b7280',
}

const QUICK_ASKS = [
  'What are the top user retention trends?',
  'Which exercises are most popular this week?',
  'Where is onboarding drop-off highest?',
  'What should we build or improve next?',
  'How is social engagement trending?',
  'Give me a full platform health summary.',
]

function timeAgo(iso: string) {
  const diff = Date.now() - new Date(iso).getTime()
  const minutes = Math.floor(diff / 60000)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

// ═══════════════════════════════════════════════════
// MAIN PAGE
// ═══════════════════════════════════════════════════

export default function InsightsPage() {
  const [activeTab, setActiveTab] = useState<'insights' | 'chat'>('chat')

  return (
    <AdminShell>
      <div className="p-6 max-w-7xl mx-auto h-full flex flex-col">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: 'var(--text-primary)' }}>
              AI Insights Hub
            </h1>
            <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
              AI-powered analytics and product intelligence
            </p>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => setActiveTab('chat')}
              className="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              style={{
                background: activeTab === 'chat' ? 'var(--accent)' : 'transparent',
                color: activeTab === 'chat' ? 'white' : 'var(--text-secondary)',
                border: activeTab === 'chat' ? 'none' : '1px solid var(--border)',
              }}
            >
              Chat with Claude
            </button>
            <button
              onClick={() => setActiveTab('insights')}
              className="px-4 py-2 rounded-lg text-sm font-medium transition-colors"
              style={{
                background: activeTab === 'insights' ? 'var(--accent)' : 'transparent',
                color: activeTab === 'insights' ? 'white' : 'var(--text-secondary)',
                border: activeTab === 'insights' ? 'none' : '1px solid var(--border)',
              }}
            >
              Saved Insights
            </button>
          </div>
        </div>

        {activeTab === 'insights' ? <InsightsPanel /> : <ChatPanel />}
      </div>
    </AdminShell>
  )
}

// ═══════════════════════════════════════════════════
// SAVED INSIGHTS PANEL
// ═══════════════════════════════════════════════════

function InsightsPanel() {
  const [insights, setInsights] = useState<Insight[]>([])
  const [loading, setLoading] = useState(true)
  const [generating, setGenerating] = useState(false)
  const [filter, setFilter] = useState<string>('all')
  const [expandedId, setExpandedId] = useState<string | null>(null)

  const loadInsights = useCallback(async () => {
    try {
      const params: Record<string, unknown> = { limit: 50 }
      if (filter !== 'all' && filter !== 'high') params.category = filter
      if (filter === 'high') params.priority = 'high'

      const data = await adminApi('get_ai_insights', params)
      let filtered = data.insights || []
      if (filter === 'high') {
        filtered = filtered.filter((i: Insight) => i.priority === 'high')
      }
      setInsights(filtered)
    } catch (err) {
      console.error('Failed to load insights:', err)
    } finally {
      setLoading(false)
    }
  }, [filter])

  useEffect(() => { loadInsights() }, [loadInsights])

  async function generateInsights() {
    setGenerating(true)
    try {
      await adminApi('trigger_insights_generation')
      await loadInsights()
    } catch (err) {
      console.error('Failed to generate insights:', err)
    } finally {
      setGenerating(false)
    }
  }

  async function markRead(id: string) {
    try {
      await adminApi('update_insight_status', { id, newStatus: 'read' })
      setInsights(prev => prev.map(i => i.id === id ? { ...i, status: 'read' } : i))
    } catch (err) {
      console.error('Failed to update insight:', err)
    }
  }

  const filters = ['all', 'high', 'retention', 'exercises', 'onboarding', 'engagement', 'workouts', 'social']

  return (
    <div className="flex-1 flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div className="flex gap-2 flex-wrap">
          {filters.map(f => (
            <button
              key={f}
              onClick={() => setFilter(f)}
              className="px-3 py-1.5 rounded-full text-xs font-medium transition-colors"
              style={{
                background: filter === f ? 'rgba(37, 99, 235, 0.15)' : 'var(--bg-secondary)',
                color: filter === f ? 'var(--accent)' : 'var(--text-secondary)',
                border: `1px solid ${filter === f ? 'var(--accent)' : 'var(--border)'}`,
              }}
            >
              {f === 'all' ? 'All' : f === 'high' ? 'High Priority' : f.charAt(0).toUpperCase() + f.slice(1)}
            </button>
          ))}
        </div>
        <button
          onClick={generateInsights}
          disabled={generating}
          className="px-4 py-2 rounded-lg text-sm font-semibold transition-colors"
          style={{
            background: generating ? 'var(--bg-secondary)' : 'var(--accent)',
            color: generating ? 'var(--text-muted)' : 'white',
          }}
        >
          {generating ? 'Generating...' : 'Generate New Insights'}
        </button>
      </div>

      {loading ? (
        <div className="flex justify-center py-20">
          <div className="spinner" style={{ width: 32, height: 32 }} />
        </div>
      ) : insights.length === 0 ? (
        <div className="text-center py-20" style={{ color: 'var(--text-muted)' }}>
          <p className="text-4xl mb-4">🧠</p>
          <p className="font-semibold mb-2">No insights yet</p>
          <p className="text-sm">Click &quot;Generate New Insights&quot; to analyze your platform data</p>
        </div>
      ) : (
        <div className="grid gap-3">
          {insights.map(insight => (
            <div
              key={insight.id}
              className="card cursor-pointer transition-all"
              style={{
                borderLeft: `3px solid ${PRIORITY_COLORS[insight.priority] || '#6b7280'}`,
                opacity: insight.status === 'archived' ? 0.5 : 1,
              }}
              onClick={() => {
                setExpandedId(expandedId === insight.id ? null : insight.id)
                if (insight.status === 'new') markRead(insight.id)
              }}
            >
              <div className="flex items-start justify-between gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 mb-1 flex-wrap">
                    <span
                      className="px-2 py-0.5 rounded-full text-xs font-medium"
                      style={{
                        background: `${CATEGORY_COLORS[insight.category] || '#6b7280'}22`,
                        color: CATEGORY_COLORS[insight.category] || '#6b7280',
                      }}
                    >
                      {insight.category}
                    </span>
                    <span
                      className="px-2 py-0.5 rounded-full text-xs font-medium"
                      style={{
                        background: `${PRIORITY_COLORS[insight.priority]}22`,
                        color: PRIORITY_COLORS[insight.priority],
                      }}
                    >
                      {insight.priority}
                    </span>
                    {insight.status === 'new' && (
                      <span className="w-2 h-2 rounded-full" style={{ background: 'var(--accent)' }} />
                    )}
                  </div>
                  <h3 className="font-semibold text-sm" style={{ color: 'var(--text-primary)' }}>
                    {insight.title}
                  </h3>
                  {expandedId !== insight.id && (
                    <p className="text-xs mt-1 line-clamp-2" style={{ color: 'var(--text-secondary)' }}>
                      {insight.body}
                    </p>
                  )}
                </div>
                <span className="text-xs shrink-0" style={{ color: 'var(--text-muted)' }}>
                  {timeAgo(insight.generated_at)}
                </span>
              </div>

              {expandedId === insight.id && (
                <div className="mt-3 pt-3" style={{ borderTop: '1px solid var(--border)' }}>
                  <p className="text-sm whitespace-pre-wrap" style={{ color: 'var(--text-primary)', lineHeight: 1.6 }}>
                    {insight.body}
                  </p>
                  <div className="mt-3 flex items-center gap-3">
                    <span className="text-xs" style={{ color: 'var(--text-muted)' }}>
                      {insight.model_used} &middot; {insight.insight_type}
                    </span>
                  </div>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ═══════════════════════════════════════════════════
// CHAT PANEL
// ═══════════════════════════════════════════════════

function ChatPanel() {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [isStreaming, setIsStreaming] = useState(false)
  const [conversationId, setConversationId] = useState<string | null>(null)
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [showHistory, setShowHistory] = useState(false)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    loadConversations()
  }, [])

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  async function loadConversations() {
    try {
      const data = await adminApi('get_chat_history')
      setConversations(data.conversations || [])
    } catch (err) {
      console.error('Failed to load conversations:', err)
    }
  }

  async function loadConversation(id: string) {
    try {
      const data = await adminApi('get_chat_conversation', { conversationId: id })
      if (data.conversation) {
        setMessages(data.conversation.messages || [])
        setConversationId(id)
        setShowHistory(false)
      }
    } catch (err) {
      console.error('Failed to load conversation:', err)
    }
  }

  function startNewChat() {
    setMessages([])
    setConversationId(null)
    setShowHistory(false)
    inputRef.current?.focus()
  }

  async function sendMessage(text?: string) {
    const messageText = text || input.trim()
    if (!messageText || isStreaming) return

    const userMessage: ChatMessage = { role: 'user', content: messageText }
    const newMessages = [...messages, userMessage]
    setMessages(newMessages)
    setInput('')
    setIsStreaming(true)

    try {
      const res = await fetch('/api/ai-chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          messages: newMessages,
          conversationId,
          fetchData: true,
        }),
      })

      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.error || 'Chat request failed')
      }

      const reader = res.body?.getReader()
      if (!reader) throw new Error('No response stream')

      const decoder = new TextDecoder()
      let assistantContent = ''

      setMessages(prev => [...prev, { role: 'assistant', content: '' }])

      while (true) {
        const { done, value } = await reader.read()
        if (done) break

        const chunk = decoder.decode(value)
        const lines = chunk.split('\n')

        for (const line of lines) {
          if (!line.startsWith('data: ')) continue
          try {
            const data = JSON.parse(line.slice(6))
            if (data.text) {
              assistantContent += data.text
              setMessages(prev => {
                const updated = [...prev]
                updated[updated.length - 1] = { role: 'assistant', content: assistantContent }
                return updated
              })
            }
            if (data.conversationId) {
              setConversationId(data.conversationId)
            }
            if (data.done) {
              loadConversations()
            }
          } catch {
            // skip malformed SSE lines
          }
        }
      }
    } catch (err) {
      console.error('Chat error:', err)
      setMessages(prev => [
        ...prev.filter(m => !(m.role === 'assistant' && m.content === '')),
        { role: 'assistant', content: `Error: ${err instanceof Error ? err.message : 'Something went wrong'}` },
      ])
    } finally {
      setIsStreaming(false)
    }
  }

  function handleKeyDown(e: React.KeyboardEvent) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  return (
    <div className="flex-1 flex gap-4" style={{ minHeight: 0, height: 'calc(100vh - 180px)' }}>
      {/* Conversation History Sidebar */}
      {showHistory && (
        <div
          className="w-64 shrink-0 rounded-xl overflow-y-auto flex flex-col"
          style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}
        >
          <div className="p-3 flex items-center justify-between" style={{ borderBottom: '1px solid var(--border)' }}>
            <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>History</span>
            <button onClick={() => setShowHistory(false)} className="text-xs" style={{ color: 'var(--text-muted)' }}>
              Close
            </button>
          </div>
          <div className="flex-1 overflow-y-auto p-2 space-y-1">
            {conversations.map(conv => (
              <button
                key={conv.id}
                onClick={() => loadConversation(conv.id)}
                className="w-full text-left px-3 py-2 rounded-lg text-xs transition-colors"
                style={{
                  background: conversationId === conv.id ? 'rgba(37,99,235,0.12)' : 'transparent',
                  color: conversationId === conv.id ? 'var(--accent)' : 'var(--text-secondary)',
                }}
              >
                <div className="font-medium truncate">{conv.title}</div>
                <div style={{ color: 'var(--text-muted)' }}>{timeAgo(conv.updated_at)}</div>
              </button>
            ))}
            {conversations.length === 0 && (
              <p className="text-xs text-center py-4" style={{ color: 'var(--text-muted)' }}>No conversations yet</p>
            )}
          </div>
        </div>
      )}

      {/* Chat Main Area */}
      <div className="flex-1 flex flex-col rounded-xl overflow-hidden" style={{ background: 'var(--bg-secondary)', border: '1px solid var(--border)' }}>
        {/* Chat Header */}
        <div className="flex items-center justify-between px-4 py-3" style={{ borderBottom: '1px solid var(--border)' }}>
          <div className="flex items-center gap-3">
            <button
              onClick={() => setShowHistory(!showHistory)}
              className="text-sm px-2 py-1 rounded"
              style={{ color: 'var(--text-secondary)' }}
              title="Chat history"
            >
              ☰
            </button>
            <span className="text-sm font-semibold" style={{ color: 'var(--text-primary)' }}>
              Chat with Claude
            </span>
            <span className="text-xs px-2 py-0.5 rounded-full" style={{ background: '#22c55e22', color: '#22c55e' }}>
              Live Data
            </span>
          </div>
          <button
            onClick={startNewChat}
            className="text-xs px-3 py-1.5 rounded-lg font-medium"
            style={{ background: 'rgba(37,99,235,0.1)', color: 'var(--accent)' }}
          >
            + New Chat
          </button>
        </div>

        {/* Messages Area */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 && (
            <div className="flex flex-col items-center justify-center h-full gap-6">
              <div className="text-center">
                <p className="text-4xl mb-3">🧠</p>
                <h3 className="text-lg font-semibold" style={{ color: 'var(--text-primary)' }}>
                  Fit33 Product Analyst
                </h3>
                <p className="text-sm mt-1" style={{ color: 'var(--text-secondary)' }}>
                  Ask anything about your platform data. Claude pulls live metrics to answer.
                </p>
              </div>
              <div className="grid grid-cols-2 gap-2 max-w-lg w-full">
                {QUICK_ASKS.map((q, i) => (
                  <button
                    key={i}
                    onClick={() => sendMessage(q)}
                    className="text-left px-3 py-2.5 rounded-lg text-xs transition-colors"
                    style={{
                      background: 'var(--bg-primary)',
                      color: 'var(--text-secondary)',
                      border: '1px solid var(--border)',
                    }}
                  >
                    {q}
                  </button>
                ))}
              </div>
            </div>
          )}

          {messages.map((msg, i) => (
            <div key={i} className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}>
              <div
                className="max-w-[80%] px-4 py-3 rounded-2xl text-sm"
                style={{
                  background: msg.role === 'user' ? 'var(--accent)' : 'var(--bg-primary)',
                  color: msg.role === 'user' ? 'white' : 'var(--text-primary)',
                  border: msg.role === 'assistant' ? '1px solid var(--border)' : 'none',
                  lineHeight: 1.6,
                  whiteSpace: 'pre-wrap',
                }}
              >
                {msg.content || (
                  <span className="inline-flex gap-1">
                    <span className="animate-pulse">●</span>
                    <span className="animate-pulse" style={{ animationDelay: '0.2s' }}>●</span>
                    <span className="animate-pulse" style={{ animationDelay: '0.4s' }}>●</span>
                  </span>
                )}
              </div>
            </div>
          ))}
          <div ref={messagesEndRef} />
        </div>

        {/* Input Area */}
        <div className="px-4 py-3" style={{ borderTop: '1px solid var(--border)' }}>
          <div className="flex gap-2 items-end">
            <textarea
              ref={inputRef}
              value={input}
              onChange={e => setInput(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Ask about retention, exercises, onboarding, engagement..."
              rows={1}
              className="flex-1 resize-none rounded-xl px-4 py-3 text-sm outline-none"
              style={{
                background: 'var(--bg-primary)',
                color: 'var(--text-primary)',
                border: '1px solid var(--border)',
                maxHeight: 120,
              }}
            />
            <button
              onClick={() => sendMessage()}
              disabled={!input.trim() || isStreaming}
              className="px-4 py-3 rounded-xl text-sm font-semibold transition-colors shrink-0"
              style={{
                background: input.trim() && !isStreaming ? 'var(--accent)' : 'var(--bg-primary)',
                color: input.trim() && !isStreaming ? 'white' : 'var(--text-muted)',
                border: '1px solid var(--border)',
              }}
            >
              {isStreaming ? '...' : 'Send'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
