import { useEffect, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  deleteDraft,
  getDraft,
  patchDraft,
  type Draft,
  type DraftStatus,
} from '../lib/api'
import { cn } from '../lib/utils'

interface Props {
  draftId: string | null
  onDeleted: () => void
  focusRequest?: number
}

const AUTOSAVE_DELAY_MS = 1200

export function DraftEditor({ draftId, onDeleted, focusRequest }: Props) {
  const qc = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['draft', draftId],
    queryFn: () => getDraft(draftId!),
    enabled: Boolean(draftId),
  })

  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [status, setStatus] = useState<DraftStatus>('wip')
  const [savedAt, setSavedAt] = useState<Date | null>(null)
  const loadedRef = useRef<{
    id: string
    title: string
    body: string
    status: DraftStatus
  } | null>(null)
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const lastFocusHandledRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    if (!data) {
      loadedRef.current = null
      setTitle('')
      setBody('')
      setStatus('wip')
      setSavedAt(null)
      return
    }
    loadedRef.current = {
      id: data.id,
      title: data.title ?? '',
      body: data.body,
      status: data.status,
    }
    setTitle(data.title ?? '')
    setBody(data.body)
    setStatus(data.status)
    setSavedAt(null)
  }, [data])

  const patchMutation = useMutation({
    mutationFn: (payload: {
      title: string | null
      body: string
      status: DraftStatus
    }) => patchDraft(draftId!, payload),
    onSuccess: (updated) => {
      loadedRef.current = {
        id: updated.id,
        title: updated.title ?? '',
        body: updated.body,
        status: updated.status,
      }
      setSavedAt(new Date())
      qc.setQueryData(['draft', updated.id], updated)
      qc.invalidateQueries({ queryKey: ['drafts'] })
    },
  })

  const deleteMutation = useMutation({
    mutationFn: () => deleteDraft(draftId!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['drafts'] })
      qc.removeQueries({ queryKey: ['draft', draftId] })
      onDeleted()
    },
  })

  useEffect(() => {
    if (!draftId || !loadedRef.current || loadedRef.current.id !== draftId)
      return
    const loaded = loadedRef.current
    const isDirty =
      title !== loaded.title ||
      body !== loaded.body ||
      status !== loaded.status
    if (!isDirty) return

    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      patchMutation.mutate({ title: title || null, body, status })
    }, AUTOSAVE_DELAY_MS)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [title, body, status, draftId, patchMutation])

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [])

  useEffect(() => {
    if (focusRequest === undefined) return
    if (lastFocusHandledRef.current === focusRequest) return
    if (!data || data.id !== draftId) return
    const el = textareaRef.current
    if (!el) return
    lastFocusHandledRef.current = focusRequest
    el.focus()
    const end = el.value.length
    el.setSelectionRange(end, end)
  }, [focusRequest, data, draftId])

  if (!draftId) {
    return (
      <div className="p-8 text-sm text-muted-foreground">
        Select a draft, or start a new one.
      </div>
    )
  }
  if (isLoading) {
    return <div className="p-8 text-sm text-muted-foreground">Loading…</div>
  }
  if (isError) {
    return (
      <div className="p-8 text-sm text-red-600">
        Failed to load: {(error as Error).message}
      </div>
    )
  }
  if (!data) return null

  const loaded = loadedRef.current
  const isDirty =
    !!loaded &&
    (title !== loaded.title ||
      body !== loaded.body ||
      status !== loaded.status)

  return (
    <div className="flex flex-col h-full max-w-3xl w-full mx-auto">
      <header className="p-6 pb-3 border-b space-y-3">
        <div className="flex items-start justify-between gap-4">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Untitled draft"
            className="flex-1 text-2xl font-semibold leading-tight bg-transparent focus:outline-none placeholder:text-muted-foreground/50"
          />
          <div className="flex items-center gap-2 shrink-0">
            <SaveStatus
              isDirty={isDirty}
              isSaving={patchMutation.isPending}
              savedAt={savedAt}
              hasError={patchMutation.isError}
            />
          </div>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <StatusPicker value={status} onChange={setStatus} />
          <div className="flex-1" />
          <ExportMenu draft={data} currentBody={body} currentTitle={title} />
          <button
            onClick={() => {
              if (confirm('Delete this draft?')) deleteMutation.mutate()
            }}
            disabled={deleteMutation.isPending}
            className="text-xs border px-3 py-1 rounded-md hover:bg-muted text-red-600 disabled:opacity-50"
          >
            Delete
          </button>
        </div>
      </header>
      <textarea
        ref={textareaRef}
        value={body}
        onChange={(e) => setBody(e.target.value)}
        placeholder="Start writing in markdown…"
        className="flex-1 w-full p-6 text-sm font-mono leading-relaxed bg-transparent resize-none focus:outline-none"
      />
    </div>
  )
}

function StatusPicker({
  value,
  onChange,
}: {
  value: DraftStatus
  onChange: (s: DraftStatus) => void
}) {
  return (
    <div className="inline-flex rounded-md border text-xs overflow-hidden">
      {(['wip', 'final'] as DraftStatus[]).map((s) => (
        <button
          key={s}
          onClick={() => onChange(s)}
          className={cn(
            'px-3 py-1 transition-colors',
            value === s
              ? 'bg-foreground text-background'
              : 'bg-background hover:bg-muted'
          )}
        >
          {s === 'wip' ? 'Draft' : 'Final'}
        </button>
      ))}
    </div>
  )
}

function SaveStatus({
  isDirty,
  isSaving,
  savedAt,
  hasError,
}: {
  isDirty: boolean
  isSaving: boolean
  savedAt: Date | null
  hasError: boolean
}) {
  if (hasError) {
    return <span className="text-xs text-red-600">save failed</span>
  }
  if (isSaving) {
    return <span className="text-xs text-muted-foreground">Saving…</span>
  }
  if (isDirty) {
    return <span className="text-xs text-muted-foreground">Unsaved</span>
  }
  if (savedAt) {
    return <span className="text-xs text-muted-foreground">Saved</span>
  }
  return null
}

function safeFilename(title: string, ext: string): string {
  const base = title.trim() || 'Untitled'
  const safe = base
    .replace(/[^A-Za-z0-9 _-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
  return `${safe || 'Untitled'}.${ext}`
}

function buildMarkdown(title: string, body: string): string {
  const trimmed = title.trim()
  if (trimmed && !body.startsWith('# ')) {
    return `# ${trimmed}\n\n${body}`
  }
  return body
}

function download(filename: string, contents: string, mime: string) {
  const blob = new Blob([contents], { type: `${mime};charset=utf-8` })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  document.body.appendChild(a)
  a.click()
  document.body.removeChild(a)
  URL.revokeObjectURL(url)
}

function ExportMenu({
  draft,
  currentBody,
  currentTitle,
}: {
  draft: Draft
  currentBody: string
  currentTitle: string
}) {
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false)
    }
    const onEsc = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setOpen(false)
    }
    window.addEventListener('mousedown', onClick)
    window.addEventListener('keydown', onEsc)
    return () => {
      window.removeEventListener('mousedown', onClick)
      window.removeEventListener('keydown', onEsc)
    }
  }, [open])

  const effectiveTitle = currentTitle || draft.title || ''
  const markdown = buildMarkdown(effectiveTitle, currentBody)

  const copyMarkdown = async () => {
    await navigator.clipboard.writeText(markdown)
    setOpen(false)
  }

  const downloadMarkdown = () => {
    download(
      safeFilename(effectiveTitle, 'md'),
      markdown,
      'text/markdown'
    )
    setOpen(false)
  }

  return (
    <div ref={ref} className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="text-xs border px-3 py-1 rounded-md hover:bg-muted"
      >
        Export ▾
      </button>
      {open && (
        <div className="absolute right-0 top-full mt-1 z-10 w-56 rounded-md border bg-background shadow-md text-sm py-1">
          <button
            onClick={copyMarkdown}
            className="w-full text-left px-3 py-1.5 hover:bg-muted"
          >
            Copy as Markdown
          </button>
          <button
            onClick={downloadMarkdown}
            className="w-full text-left px-3 py-1.5 hover:bg-muted"
          >
            Download .md
          </button>
        </div>
      )}
    </div>
  )
}
