import { useEffect, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { deleteNote, getNote, patchNote } from '../lib/api'

interface Props {
  noteId: string | null
  onDeleted: () => void
  focusRequest?: number
}

const AUTOSAVE_DELAY_MS = 1200

export function NoteEditor({ noteId, onDeleted, focusRequest }: Props) {
  const qc = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['note', noteId],
    queryFn: () => getNote(noteId!),
    enabled: Boolean(noteId),
  })

  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const [savedAt, setSavedAt] = useState<Date | null>(null)
  const loadedRef = useRef<{ id: string; title: string; body: string } | null>(
    null
  )
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)
  const lastFocusHandledRef = useRef<number | undefined>(undefined)

  useEffect(() => {
    if (!data) {
      loadedRef.current = null
      setTitle('')
      setBody('')
      setSavedAt(null)
      return
    }
    loadedRef.current = {
      id: data.id,
      title: data.title ?? '',
      body: data.body,
    }
    setTitle(data.title ?? '')
    setBody(data.body)
    setSavedAt(null)
  }, [data])

  const patchMutation = useMutation({
    mutationFn: (payload: { title: string | null; body: string }) =>
      patchNote(noteId!, payload),
    onSuccess: (updated) => {
      loadedRef.current = {
        id: updated.id,
        title: updated.title ?? '',
        body: updated.body,
      }
      setSavedAt(new Date())
      qc.setQueryData(['note', updated.id], updated)
      qc.invalidateQueries({ queryKey: ['notes'] })
    },
  })

  const deleteMutation = useMutation({
    mutationFn: () => deleteNote(noteId!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['notes'] })
      qc.removeQueries({ queryKey: ['note', noteId] })
      onDeleted()
    },
  })

  useEffect(() => {
    if (!noteId || !loadedRef.current || loadedRef.current.id !== noteId) return
    const loaded = loadedRef.current
    const isDirty = title !== loaded.title || body !== loaded.body
    if (!isDirty) return

    if (timerRef.current) clearTimeout(timerRef.current)
    timerRef.current = setTimeout(() => {
      patchMutation.mutate({ title: title || null, body })
    }, AUTOSAVE_DELAY_MS)

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [title, body, noteId, patchMutation])

  useEffect(() => {
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
    }
  }, [])

  useEffect(() => {
    if (focusRequest === undefined) return
    if (lastFocusHandledRef.current === focusRequest) return
    if (!data || data.id !== noteId) return
    const el = textareaRef.current
    if (!el) return
    lastFocusHandledRef.current = focusRequest
    el.focus()
    const end = el.value.length
    el.setSelectionRange(end, end)
  }, [focusRequest, data, noteId])

  if (!noteId) {
    return (
      <div className="p-8 text-sm text-muted-foreground">
        Select a note, or create a new one.
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
    !!loaded && (title !== loaded.title || body !== loaded.body)

  return (
    <div className="flex flex-col h-full max-w-3xl w-full mx-auto">
      <header className="p-6 pb-3 border-b flex items-start justify-between gap-4">
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          placeholder="Untitled note"
          className="flex-1 text-2xl font-semibold leading-tight bg-transparent focus:outline-none placeholder:text-muted-foreground/50"
        />
        <div className="flex items-center gap-3 shrink-0">
          <SaveStatus
            isDirty={isDirty}
            isSaving={patchMutation.isPending}
            savedAt={savedAt}
            hasError={patchMutation.isError}
          />
          <button
            onClick={() => {
              if (confirm('Delete this note?')) deleteMutation.mutate()
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
