const API_KEY = import.meta.env.VITE_COMPOSER_API_KEY ?? ''

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

export async function apiFetch<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers)
  headers.set('Content-Type', 'application/json')
  if (API_KEY) headers.set('X-API-Key', API_KEY)

  const res = await fetch(`/api${path}`, { ...init, headers })
  if (!res.ok) {
    const body = await res.text().catch(() => res.statusText)
    throw new ApiError(res.status, body || res.statusText)
  }
  return res.json() as Promise<T>
}

export interface HealthResponse {
  status: string
  version: string
  schema_version: number
  auth_enabled: boolean
  ingest_auth_enabled: boolean
}

export function getHealth() {
  return apiFetch<HealthResponse>('/v1/health')
}
