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
