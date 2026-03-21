import { NextRequest, NextResponse } from 'next/server'
import { verifyAdmin } from '@/lib/verify-admin'

const GITHUB_TOKEN = process.env.GITHUB_TOKEN || ''
const GITHUB_OWNER = process.env.GITHUB_REPO_OWNER || ''
const GITHUB_REPO = process.env.GITHUB_REPO_NAME || ''
const GITHUB_API = 'https://api.github.com'

async function githubFetch(path: string, options: RequestInit = {}) {
  const res = await fetch(`${GITHUB_API}${path}`, {
    ...options,
    headers: {
      'Authorization': `Bearer ${GITHUB_TOKEN}`,
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`GitHub API ${res.status}: ${body}`)
  }
  return res.json()
}

function correctFilePath(guessedPath: string): string[] {
  const filename = guessedPath.split('/').pop() || guessedPath
  const candidates = [
    guessedPath,
    `Fit33/${filename}`,
    `admin-cms/src/${guessedPath}`,
    filename,
  ]
  if (guessedPath.includes('/Services/')) candidates.push(`Fit33/${filename}`)
  if (guessedPath.includes('/Views/')) candidates.push(`Fit33/${filename}`)
  if (guessedPath.includes('/Models/')) candidates.push(`Fit33/${filename}`)
  if (guessedPath.startsWith('supabase/')) candidates.push(guessedPath)

  return [...new Set(candidates)]
}

async function findFileOnGitHub(filePath: string, branch: string): Promise<{ content: string; sha: string; path: string } | null> {
  const candidates = correctFilePath(filePath)

  for (const candidate of candidates) {
    try {
      const file = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${candidate}?ref=${branch}`)
      return {
        content: Buffer.from(file.content, 'base64').toString('utf-8'),
        sha: file.sha,
        path: candidate,
      }
    } catch {
      continue
    }
  }

  const filename = filePath.split('/').pop() || filePath
  try {
    const search = await githubFetch(`/search/code?q=filename:${encodeURIComponent(filename)}+repo:${GITHUB_OWNER}/${GITHUB_REPO}`)
    if (search.items?.length > 0) {
      const actualPath = search.items[0].path
      const file = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${actualPath}?ref=${branch}`)
      return {
        content: Buffer.from(file.content, 'base64').toString('utf-8'),
        sha: file.sha,
        path: actualPath,
      }
    }
  } catch {
    // Search failed, give up
  }

  return null
}

function applyDiff(currentContent: string, codeDiff: string): string | null {
  const diffLines = codeDiff.split('\n')
  const oldLines: string[] = []
  const newLines: string[] = []
  for (const line of diffLines) {
    if (line.startsWith('---') || line.startsWith('+++') || line.startsWith('@@') || line.startsWith('diff ')) continue
    if (line.startsWith('-')) oldLines.push(line.slice(1))
    else if (line.startsWith('+')) newLines.push(line.slice(1))
  }

  if (oldLines.length > 0) {
    const oldBlock = oldLines.join('\n')
    const newBlock = newLines.join('\n')
    if (currentContent.includes(oldBlock)) {
      return currentContent.replace(oldBlock, newBlock)
    }
    const oldTrimmed = oldLines.map(l => l.trim()).join('\n')
    const contentLines = currentContent.split('\n')
    const contentTrimmed = contentLines.map(l => l.trim()).join('\n')
    if (contentTrimmed.includes(oldTrimmed)) {
      const startIdx = contentTrimmed.indexOf(oldTrimmed)
      const beforeLines = contentTrimmed.slice(0, startIdx).split('\n').length - 1
      const replacedLines = contentLines.slice()
      replacedLines.splice(beforeLines, oldLines.length, ...newLines)
      return replacedLines.join('\n')
    }
  }

  return null
}

// Single suggestion PR
export async function POST(req: NextRequest) {
  try {
    const adminAuth = await verifyAdmin(req)
    if (!adminAuth.valid) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    }

    if (!GITHUB_TOKEN || !GITHUB_OWNER || !GITHUB_REPO) {
      return NextResponse.json(
        { error: 'GitHub integration not configured. Set GITHUB_TOKEN, GITHUB_REPO_OWNER, and GITHUB_REPO_NAME in .env.local' },
        { status: 500 },
      )
    }

    const body = await req.json()

    if (body.batch && Array.isArray(body.suggestions)) {
      return handleBatchPR(body.suggestions, body.session_id)
    }

    const { suggestion_id, title, description, file_path, code_diff, session_id } = body

    if (!file_path || !code_diff) {
      return NextResponse.json({ error: 'Missing file_path or code_diff' }, { status: 400 })
    }

    const branchName = `fix/dev-log-${(session_id || 'unknown').slice(0, 8)}-${Date.now()}`

    const repo = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}`)
    const defaultBranch = repo.default_branch || 'main'
    const ref = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/ref/heads/${defaultBranch}`)
    const baseSha = ref.object.sha

    await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/refs`, {
      method: 'POST',
      body: JSON.stringify({ ref: `refs/heads/${branchName}`, sha: baseSha }),
    })

    const fileResult = await findFileOnGitHub(file_path, branchName)
    if (!fileResult) {
      return NextResponse.json({ error: `File not found in repo. Tried: ${correctFilePath(file_path).join(', ')}` }, { status: 404 })
    }

    const newContent = applyDiff(fileResult.content, code_diff)
    if (!newContent) {
      return NextResponse.json({
        error: `Could not apply diff to ${fileResult.path} — the code Claude suggested doesn't match the current file content. The suggestion is still useful as a pointer to the issue.`
      }, { status: 400 })
    }

    await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${fileResult.path}`, {
      method: 'PUT',
      body: JSON.stringify({
        message: `fix: ${title}\n\nAuto-generated from dev session log analysis.\nSession: ${session_id || 'unknown'}`,
        content: Buffer.from(newContent).toString('base64'),
        sha: fileResult.sha,
        branch: branchName,
      }),
    })

    const pr = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/pulls`, {
      method: 'POST',
      body: JSON.stringify({
        title: `[Dev Log Fix] ${title}`,
        body: `## Auto-Generated Fix\n\n${description}\n\n**File:** \`${fileResult.path}\`\n**Session:** ${session_id || 'N/A'}\n**Suggestion ID:** ${suggestion_id || 'N/A'}\n\n---\n*This PR was auto-generated by Claude from a dev session log analysis. Review carefully before merging.*`,
        head: branchName,
        base: defaultBranch,
        draft: true,
      }),
    })

    return NextResponse.json({
      pr_url: pr.html_url,
      pr_number: pr.number,
      branch: branchName,
      resolved_path: fileResult.path,
    })
  } catch (err) {
    console.error('GitHub PR error:', err)
    return NextResponse.json(
      { error: err instanceof Error ? err.message : 'PR creation failed' },
      { status: 500 },
    )
  }
}

async function handleBatchPR(
  suggestions: Array<{ suggestion_id: string; title: string; description: string; file_path: string; code_diff: string }>,
  sessionId: string
) {
  const branchName = `fix/dev-log-batch-${(sessionId || 'unknown').slice(0, 8)}-${Date.now()}`

  const repo = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}`)
  const defaultBranch = repo.default_branch || 'main'
  const ref = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/ref/heads/${defaultBranch}`)
  const baseSha = ref.object.sha

  await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/git/refs`, {
    method: 'POST',
    body: JSON.stringify({ ref: `refs/heads/${branchName}`, sha: baseSha }),
  })

  const applied: string[] = []
  const failed: string[] = []

  for (const s of suggestions) {
    if (!s.file_path || !s.code_diff) {
      failed.push(`${s.title}: missing file_path or code_diff`)
      continue
    }

    const fileResult = await findFileOnGitHub(s.file_path, branchName)
    if (!fileResult) {
      failed.push(`${s.title}: file not found (${s.file_path})`)
      continue
    }

    const newContent = applyDiff(fileResult.content, s.code_diff)
    if (!newContent) {
      failed.push(`${s.title}: diff could not be applied to ${fileResult.path}`)
      continue
    }

    try {
      const freshFile = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${fileResult.path}?ref=${branchName}`)
      await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/contents/${fileResult.path}`, {
        method: 'PUT',
        body: JSON.stringify({
          message: `fix: ${s.title}\n\nAuto-generated from dev session log analysis.`,
          content: Buffer.from(newContent).toString('base64'),
          sha: freshFile.sha,
          branch: branchName,
        }),
      })
      applied.push(`${s.title} (${fileResult.path})`)
    } catch (err) {
      failed.push(`${s.title}: commit failed — ${err instanceof Error ? err.message : 'unknown error'}`)
    }
  }

  if (applied.length === 0) {
    return NextResponse.json({
      error: `No suggestions could be applied.\n\n${failed.map(f => `- ${f}`).join('\n')}`,
    }, { status: 400 })
  }

  const prBody = [
    '## Auto-Generated Batch Fix',
    '',
    `**Session:** ${sessionId || 'N/A'}`,
    `**Applied:** ${applied.length} of ${suggestions.length} suggestions`,
    '',
    '### Applied',
    ...applied.map(a => `- ${a}`),
    '',
    ...(failed.length > 0 ? ['### Could not apply', ...failed.map(f => `- ${f}`), ''] : []),
    '---',
    '*This PR was auto-generated by Claude from a dev session log analysis. Review carefully before merging.*',
  ].join('\n')

  const pr = await githubFetch(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/pulls`, {
    method: 'POST',
    body: JSON.stringify({
      title: `[Dev Log Batch Fix] ${applied.length} suggestions from session ${(sessionId || '').slice(0, 8)}`,
      body: prBody,
      head: branchName,
      base: defaultBranch,
      draft: true,
    }),
  })

  return NextResponse.json({
    pr_url: pr.html_url,
    pr_number: pr.number,
    branch: branchName,
    applied: applied.length,
    failed: failed.length,
    details: { applied, failed },
  })
}
