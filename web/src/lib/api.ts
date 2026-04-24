const API_KEY = import.meta.env.VITE_COMPOSER_API_KEY ?? ''

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

async function apiRequest<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json')
  }
  if (API_KEY) headers.set('X-API-Key', API_KEY)

  const res = await fetch(`/api${path}`, { ...init, headers })
  if (!res.ok) {
    const body = await res.text().catch(() => res.statusText)
    throw new ApiError(res.status, body || res.statusText)
  }
  if (res.status === 204) return undefined as T
  return res.json() as Promise<T>
}

export const api = {
  get: <T>(path: string) => apiRequest<T>(path),
  post: <T>(path: string, body: unknown) =>
    apiRequest<T>(path, { method: 'POST', body: JSON.stringify(body) }),
  patch: <T>(path: string, body: unknown) =>
    apiRequest<T>(path, { method: 'PATCH', body: JSON.stringify(body) }),
  delete: <T>(path: string) => apiRequest<T>(path, { method: 'DELETE' }),
}

// ─── health ───────────────────────────────────────────

export interface HealthResponse {
  status: string
  version: string
  schema_version: number
  auth_enabled: boolean
  ingest_auth_enabled: boolean
}

export const getHealth = () => api.get<HealthResponse>('/v1/health')

// ─── items ────────────────────────────────────────────

export interface RelatedLink {
  url: string
  title?: string | null
  score?: number | null
}

export interface ItemSummary {
  id: string
  source: string
  url: string | null
  title: string
  author: string | null
  published_at: string | null
  promoted_at: string
  summary: string | null
  key_points: string[]
  keywords: string[]
  archived_at: string | null
}

export interface Item extends ItemSummary {
  source_ref: string | null
  content: string | null
  related_links: RelatedLink[]
  metadata: Record<string, unknown>
}

export interface ItemList {
  items: ItemSummary[]
  total: number
  limit: number
  offset: number
}

export interface ListItemsParams {
  q?: string
  archived?: boolean | null
  limit?: number
  offset?: number
}

export function listItems(params: ListItemsParams = {}): Promise<ItemList> {
  const qs = new URLSearchParams()
  if (params.q) qs.set('q', params.q)
  if (params.archived === null) qs.set('archived', '')
  else if (params.archived !== undefined) qs.set('archived', String(params.archived))
  if (params.limit !== undefined) qs.set('limit', String(params.limit))
  if (params.offset !== undefined) qs.set('offset', String(params.offset))
  const query = qs.toString()
  return api.get<ItemList>(`/items${query ? `?${query}` : ''}`)
}

export const getItem = (id: string) => api.get<Item>(`/items/${id}`)

export const setItemArchived = (id: string, archived: boolean) =>
  api.patch<Item>(`/items/${id}`, { archived })

export const deleteItem = (id: string) => api.delete<void>(`/items/${id}`)

// ─── notes ────────────────────────────────────────────

export interface Note {
  id: string
  title: string | null
  body: string
  created_at: string
  updated_at: string
}

export interface NoteList {
  notes: Note[]
  total: number
}

export const listNotes = (limit = 100, offset = 0) =>
  api.get<NoteList>(`/notes?limit=${limit}&offset=${offset}`)

export const getNote = (id: string) => api.get<Note>(`/notes/${id}`)

export const createNote = (body: { title?: string | null; body?: string }) =>
  api.post<Note>('/notes', body)

export const patchNote = (
  id: string,
  body: { title?: string | null; body?: string }
) => api.patch<Note>(`/notes/${id}`, body)

export const deleteNote = (id: string) => api.delete<void>(`/notes/${id}`)

// ─── drafts ───────────────────────────────────────────

export type DraftStatus = 'wip' | 'final'

export interface Draft {
  id: string
  title: string | null
  body: string
  status: DraftStatus
  created_at: string
  updated_at: string
}

export interface DraftList {
  drafts: Draft[]
  total: number
}

export const listDrafts = (limit = 100, offset = 0) =>
  api.get<DraftList>(`/drafts?limit=${limit}&offset=${offset}`)

export const getDraft = (id: string) => api.get<Draft>(`/drafts/${id}`)

export const createDraft = (body: {
  title?: string | null
  body?: string
  status?: DraftStatus
}) => api.post<Draft>('/drafts', body)

export const patchDraft = (
  id: string,
  body: {
    title?: string | null
    body?: string
    status?: DraftStatus
  }
) => api.patch<Draft>(`/drafts/${id}`, body)

export const deleteDraft = (id: string) => api.delete<void>(`/drafts/${id}`)

// ─── collections ──────────────────────────────────────

export type MemberType = 'item' | 'note' | 'draft'

export interface Collection {
  id: string
  name: string
  description: string | null
  created_at: string
  member_count: number
}

export interface OutlineItemPayload {
  id: string
  title: string | null
  author: string | null
  summary: string | null
  published_at: string | null
  archived: boolean
}

export interface OutlineNotePayload {
  id: string
  title: string | null
  body: string
  updated_at: string | null
}

export interface OutlineNode {
  member_type: MemberType
  member_id: string
  position: number
  item: OutlineItemPayload | null
  note: OutlineNotePayload | null
}

export interface Outline {
  collection: Collection
  members: OutlineNode[]
}

export const listCollections = () => api.get<Collection[]>('/collections')

export const createCollection = (body: {
  name: string
  description?: string | null
}) => api.post<Collection>('/collections', body)

export const getCollection = (id: string) =>
  api.get<Outline>(`/collections/${id}`)

export const patchCollection = (
  id: string,
  body: { name?: string | null; description?: string | null }
) => api.patch<Collection>(`/collections/${id}`, body)

export const deleteCollection = (id: string) =>
  api.delete<void>(`/collections/${id}`)

export const addCollectionMember = (
  id: string,
  body: { member_type: MemberType; member_id: string }
) => api.post<Outline>(`/collections/${id}/members`, body)

export const createInlineNote = (
  id: string,
  body: { title?: string | null; body?: string }
) => api.post<Outline>(`/collections/${id}/notes`, body)

export const removeCollectionMember = (
  id: string,
  memberType: MemberType,
  memberId: string
) => api.delete<void>(`/collections/${id}/members/${memberType}/${memberId}`)

export const reorderCollection = (
  id: string,
  members: Array<[MemberType, string]>
) => api.post<Outline>(`/collections/${id}/reorder`, { members })

// ─── chat ─────────────────────────────────────────────

export type ChatSourceType = 'item' | 'note' | 'draft'

export interface Citation {
  index: number
  chunk_id: string
  source_type: string
  source_id: string
  source_title: string | null
  source_url: string | null
  chunk_index: number
  snippet: string
}

export type ChatStreamEvent =
  | { type: 'citations'; citations: Citation[]; vector_search_used: boolean }
  | { type: 'delta'; text: string }
  | { type: 'done'; stop_reason: string | null }
  | { type: 'error'; message: string }

export interface ChatHistoryMessage {
  role: 'user' | 'assistant'
  content: string
}

export interface StreamChatParams {
  query: string
  sourceTypes?: ChatSourceType[] | null
  limit?: number
  history?: ChatHistoryMessage[]
  signal?: AbortSignal
}

export async function* streamChat(
  params: StreamChatParams
): AsyncGenerator<ChatStreamEvent> {
  const headers = new Headers({
    'Content-Type': 'application/json',
    Accept: 'text/event-stream',
  })
  if (API_KEY) headers.set('X-API-Key', API_KEY)

  const body: Record<string, unknown> = {
    query: params.query,
    limit: params.limit ?? 8,
  }
  if (params.sourceTypes && params.sourceTypes.length > 0) {
    body.source_types = params.sourceTypes
  }
  if (params.history && params.history.length > 0) {
    body.history = params.history
  }

  const res = await fetch('/api/v1/chat', {
    method: 'POST',
    headers,
    body: JSON.stringify(body),
    signal: params.signal,
  })

  if (!res.ok || !res.body) {
    const text = await res.text().catch(() => res.statusText)
    throw new ApiError(res.status, text || res.statusText)
  }

  const reader = res.body.getReader()
  const decoder = new TextDecoder()
  let buffer = ''

  try {
    while (true) {
      const { done, value } = await reader.read()
      if (done) break
      buffer += decoder.decode(value, { stream: true })
      // SSE records are separated by a blank line (\n\n)
      let sep = buffer.indexOf('\n\n')
      while (sep >= 0) {
        const record = buffer.slice(0, sep)
        buffer = buffer.slice(sep + 2)
        const event = parseSseRecord(record)
        if (event) yield event
        sep = buffer.indexOf('\n\n')
      }
    }
  } finally {
    reader.releaseLock()
  }
}

function parseSseRecord(record: string): ChatStreamEvent | null {
  let name: string | null = null
  let data = ''
  for (const raw of record.split('\n')) {
    const line = raw.replace(/\r$/, '')
    if (line.startsWith('event:')) {
      name = line.slice('event:'.length).trim()
    } else if (line.startsWith('data:')) {
      const chunk = line.slice('data:'.length).trim()
      data = data ? `${data}\n${chunk}` : chunk
    }
  }
  if (!name || !data) return null
  let json: Record<string, unknown>
  try {
    json = JSON.parse(data)
  } catch {
    return null
  }
  switch (name) {
    case 'citations':
      return {
        type: 'citations',
        citations: (json.citations as Citation[]) ?? [],
        vector_search_used: Boolean(json.vector_search_used),
      }
    case 'delta':
      return { type: 'delta', text: (json.text as string) ?? '' }
    case 'done':
      return {
        type: 'done',
        stop_reason: (json.stop_reason as string | null) ?? null,
      }
    case 'error':
      return {
        type: 'error',
        message: (json.message as string) ?? 'Unknown error',
      }
    default:
      return null
  }
}
