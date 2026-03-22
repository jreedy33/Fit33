import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!
const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!

export async function GET() {
  try {
    const supabase = createClient(supabaseUrl, supabaseAnonKey)

    const { data: categories, error: catError } = await supabase
      .from('faq_categories')
      .select('id, slug, name, icon, display_order')
      .order('display_order')

    if (catError) return NextResponse.json({ error: catError.message }, { status: 500 })

    const { data: entries, error: entryError } = await supabase
      .from('faq_entries')
      .select('entry_id, category_id, question, answer, channel, display_order')
      .eq('status', 'published')
      .order('display_order')

    if (entryError) return NextResponse.json({ error: entryError.message }, { status: 500 })

    const grouped = (categories || []).map(cat => ({
      slug: cat.slug,
      name: cat.name,
      icon: cat.icon,
      entries: (entries || [])
        .filter(e => e.category_id === cat.id)
        .map(e => ({
          entry_id: e.entry_id,
          question: e.question,
          answer: e.answer,
          channel: e.channel,
        })),
    })).filter(cat => cat.entries.length > 0)

    return NextResponse.json(
      { categories: grouped },
      {
        headers: {
          'Cache-Control': 'public, s-maxage=60, stale-while-revalidate=300',
          'Access-Control-Allow-Origin': '*',
        },
      },
    )
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'Internal server error' },
      { status: 500 },
    )
  }
}
