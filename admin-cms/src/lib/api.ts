// Helper for making authenticated admin API calls

export async function adminApi(action: string, params: Record<string, unknown> = {}) {
  const token = sessionStorage.getItem('admin_token')
  if (!token) {
    window.location.href = '/login'
    throw new Error('Not authenticated')
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
