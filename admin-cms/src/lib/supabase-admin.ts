import { createClient } from '@supabase/supabase-js'

// Server-side admin client with service_role key - bypasses RLS
// NEVER expose this to the client
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL!
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY!

  if (!url || !serviceKey || serviceKey === 'YOUR_SERVICE_ROLE_KEY_HERE') {
    throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY. Get it from Supabase Dashboard > Settings > API')
  }

  return createClient(url, serviceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  })
}
