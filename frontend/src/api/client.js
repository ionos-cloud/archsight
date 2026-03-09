const BASE = '/api/v1'

async function fetchJson(url) {
  const res = await fetch(url)
  if (!res.ok) {
    const err = await res.json().catch(() => ({ message: res.statusText }))
    throw new Error(err.message || res.statusText)
  }
  return res.json()
}

export function getKinds() {
  return fetchJson(`${BASE}/kinds`)
}

export function getKindInstances(kind, { limit = 50, offset = 0, output = 'complete' } = {}) {
  const params = new URLSearchParams({ limit, offset, output })
  return fetchJson(`${BASE}/kinds/${kind}?${params}`)
}

export function getKindFilters(kind) {
  return fetchJson(`${BASE}/kinds/${encodeURIComponent(kind)}/filters`)
}

export function getInstance(kind, name) {
  return fetchJson(`${BASE}/kinds/${encodeURIComponent(kind)}/instances/${encodeURIComponent(name)}`)
}

export function search(query, { limit = 200, offset = 0, output = 'complete' } = {}) {
  const params = new URLSearchParams({ q: query, limit, offset, output })
  return fetchJson(`${BASE}/search?${params}`)
}

export function searchCount(query) {
  const params = new URLSearchParams({ q: query, output: 'count' })
  return fetchJson(`${BASE}/search?${params}`)
}

export async function getInstanceDot(kind, name) {
  const res = await fetch(`/kinds/${encodeURIComponent(kind)}/instances/${encodeURIComponent(name)}/dot`)
  if (!res.ok) return null
  return res.text()
}

export async function getGlobalDot() {
  const res = await fetch('/dot')
  if (!res.ok) return null
  return res.text()
}

export async function getDoc(filename) {
  const res = await fetch(`${BASE}/docs/${filename}`)
  if (!res.ok) return null
  return res.text()
}

export async function executeAnalysis(instanceName) {
  const res = await fetch(`${BASE}/kinds/Analysis/instances/${encodeURIComponent(instanceName)}/execute`, {
    method: 'POST'
  })
  if (!res.ok) return null
  return res.json()
}

// Editor API

export function getEditorForm(kind) {
  return fetchJson(`${BASE}/editor/kinds/${encodeURIComponent(kind)}/form`)
}

export function getEditorEditForm(kind, name) {
  return fetchJson(`${BASE}/editor/kinds/${encodeURIComponent(kind)}/instances/${encodeURIComponent(name)}/form`)
}

export async function generateYaml(kind, data) {
  const res = await fetch(`${BASE}/editor/kinds/${encodeURIComponent(kind)}/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  return res.json()
}

export async function generateEditYaml(kind, name, data) {
  const res = await fetch(`${BASE}/editor/kinds/${encodeURIComponent(kind)}/instances/${encodeURIComponent(name)}/generate`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  })
  return res.json()
}

export async function reload() {
  const res = await fetch('/reload', { headers: { 'Accept': 'application/json' } })
  if (!res.ok) {
    const data = await res.json().catch(() => null)
    if (data?.error) return { error: data }
    throw new Error(res.statusText)
  }
  return { ok: true }
}

export async function saveYaml(kind, name, yaml, contentHash) {
  const res = await fetch(`${BASE}/editor/kinds/${encodeURIComponent(kind)}/instances/${encodeURIComponent(name)}/save`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ yaml, content_hash: contentHash }),
  })
  return res.json()
}
