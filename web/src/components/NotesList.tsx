import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { createNote, listNotes, type Note } from '../lib/api'
import { cn } from '../lib/utils'

interface Props {
  selectedId: string | null
  onSelect: (id: string) => void
}

export function NotesList({ selectedId, onSelect }: Props) {
  const qc = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['notes'],
    queryFn: () => listNotes(),
  })

  const createMutation = useMutation({
    mutationFn: () => createNote({ body: '' }),
    onSuccess: (note) => {
      qc.invalidateQueries({ queryKey: ['notes'] })
      onSelect(note.id)
    },
  })

  return (
    <>
      <div className="p-3 border-b">
        <button
          onClick={() => createMutation.mutate()}
          disabled={createMutation.isPending}
          className="w-full text-sm px-3 py-1.5 rounded-md border hover:bg-muted disabled:opacity-50"
        >
          + New note
        </button>
      </div>
      <div className="flex-1 overflow-y-auto">
        {isLoading && (
          <div className="p-4 text-sm text-muted-foreground">Loading…</div>
        )}
        {isError && (
          <div className="p-4 text-sm text-red-600">
            Failed to load: {(error as Error).message}
          </div>
        )}
        {data && data.notes.length === 0 && (
          <div className="p-4 text-sm text-muted-foreground">
            No notes yet.
          </div>
        )}
        {data && data.notes.length > 0 && (
          <ul className="divide-y">
            {data.notes.map((n) => (
              <NoteRow
                key={n.id}
                note={n}
                selected={n.id === selectedId}
                onSelect={() => onSelect(n.id)}
              />
            ))}
          </ul>
        )}
      </div>
    </>
  )
}

function stripMarkdownPrefix(line: string): string {
  for (const prefix of ['### ', '## ', '# ', '> ', '- ', '* ']) {
    if (line.startsWith(prefix)) return line.slice(prefix.length).trim()
  }
  return line.trim()
}

function displayTitle(note: Note): string {
  if (note.title && note.title.trim()) return note.title
  const first = note.body.split('\n')[0] ?? ''
  const stripped = stripMarkdownPrefix(first)
  return stripped || 'Untitled note'
}

function previewBody(note: Note): string {
  const lines = note.body.split('\n')
  const skip = note.title && note.title.trim() ? 0 : 1
  const line = lines.slice(skip).find((l) => l.trim())
  return line ? stripMarkdownPrefix(line) : ''
}

function formatDate(iso: string): string {
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return ''
  return d.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric',
  })
}

function NoteRow({
  note,
  selected,
  onSelect,
}: {
  note: Note
  selected: boolean
  onSelect: () => void
}) {
  const preview = previewBody(note)
  return (
    <li>
      <button
        onClick={onSelect}
        className={cn(
          'w-full text-left px-4 py-3 hover:bg-muted transition-colors',
          selected && 'bg-muted'
        )}
      >
        <div className="font-medium text-sm leading-tight truncate">
          {displayTitle(note)}
        </div>
        {preview && (
          <div className="text-xs text-muted-foreground mt-1 line-clamp-2">
            {preview}
          </div>
        )}
        <div className="text-xs text-muted-foreground mt-1">
          {formatDate(note.updated_at)}
        </div>
      </button>
    </li>
  )
}
