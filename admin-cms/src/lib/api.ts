// Authenticated admin API calls — tokens are in httpOnly cookies (sent automatically)

async function refreshSession(): Promise<boolean> {
  try {
    const res = await fetch('/api/auth/refresh', { method: 'POST' })
    return res.ok
  } catch {
    return false
  }
}

export async function adminApi(action: string, params: Record<string, unknown> = {}) {
  const res = await fetch('/api/admin', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action, ...params }),
  })

  if (res.status === 401) {
    const refreshed = await refreshSession()
    if (refreshed) {
      const retryRes = await fetch('/api/admin', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action, ...params }),
      })
      if (retryRes.ok) {
        return await retryRes.json()
      }
    }

    window.location.href = '/login'
    throw new Error('Session expired')
  }

  const data = await res.json()

  if (!res.ok) {
    throw new Error(data.error || 'API request failed')
  }

  return data
}

export async function logout() {
  await fetch('/api/auth/logout', { method: 'POST' })
  window.location.href = '/login'
}
