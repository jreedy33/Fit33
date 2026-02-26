// Helper for making authenticated admin API calls

// Check if the session token is expired or about to expire
function isTokenExpiring(): boolean {
  const expiresAt = sessionStorage.getItem('admin_expires_at')
  if (!expiresAt) return false
  // Refresh if within 5 minutes of expiry
  return Date.now() / 1000 > Number(expiresAt) - 300
}

// Refresh the session token using the refresh token
async function refreshSession(): Promise<boolean> {
  const refreshToken = sessionStorage.getItem('admin_refresh')
  if (!refreshToken) return false

  try {
    const { createClient } = await import('@supabase/supabase-js')
    const supabase = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    )

    const { data, error } = await supabase.auth.refreshSession({ refresh_token: refreshToken })
    if (error || !data.session) return false

    sessionStorage.setItem('admin_token', data.session.access_token)
    sessionStorage.setItem('admin_refresh', data.session.refresh_token)
    sessionStorage.setItem('admin_expires_at', String(data.session.expires_at))
    return true
  } catch {
    return false
  }
}

export async function adminApi(action: string, params: Record<string, unknown> = {}) {
  let token = sessionStorage.getItem('admin_token')
  if (!token) {
    window.location.href = '/login'
    throw new Error('Not authenticated')
  }

  // Auto-refresh if token is about to expire
  if (isTokenExpiring()) {
    const refreshed = await refreshSession()
    if (refreshed) {
      token = sessionStorage.getItem('admin_token')
    }
  }

  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`,
    },
    body: JSON.stringify({ action, ...params }),
  })

  if (res.status === 401) {
    // Try one refresh before giving up
    const refreshed = await refreshSession()
    if (refreshed) {
      const retryToken = sessionStorage.getItem('admin_token')
      const retryRes = await fetch('/api/admin', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${retryToken}`,
        },
        body: JSON.stringify({ action, ...params }),
      })
      if (retryRes.ok) {
        return await retryRes.json()
      }
    }

    sessionStorage.clear()
    window.location.href = '/login'
    throw new Error('Session expired')
  }

  const data = await res.json()

  if (!res.ok) {
    throw new Error(data.error || 'API request failed')
  }

  return data
}

export function logout() {
  sessionStorage.clear()
  window.location.href = '/login'
}
