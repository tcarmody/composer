import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { createDraft, listDrafts, type Draft } from '../lib/api'
import { cn } from '../lib/utils'

interface Props {
  selectedId: string | null
  onSelect: (id: string) => void
}

export function DraftsList({ selectedId, onSelect }: Props) {
  const qc = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['drafts'],
    queryFn: () => listDrafts(),
  })

  const createMutation = useMutation({
    mutationFn: () => createDraft({ body: '' }),
    onSuccess: (draft) => {
      qc.invalidateQueries({ queryKey: ['drafts'] })
      onSelect(draft.id)
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
          + New draft
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
        {data && data.drafts.length === 0 && (
          <div className="p-4 text-sm text-muted-foreground">
            No drafts yet.
          </div>
        )}
        {data && data.drafts.length > 0 && (
          <ul className="divide-y">
            {data.drafts.map((d) => (
              <DraftRow
                key={d.id}
                draft={d}
                selected={d.id === selectedId}
                onSelect={() => onSelect(d.id)}
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

function displayTitle(draft: Draft): string {
  if (draft.title && draft.title.trim()) return draft.title
  const first = draft.body.split('\n')[0] ?? ''
  const stripped = stripMarkdownPrefix(first)
  return stripped || 'Untitled draft'
}

function previewBody(draft: Draft): string {
  const lines = draft.body.split('\n')
  const skip = draft.title && draft.title.trim() ? 0 : 1
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

function StatusBadge({ status }: { status: Draft['status'] }) {
  const styles =
    status === 'final'
      ? 'bg-green-600/15 text-green-700'
      : 'bg-orange-500/15 text-orange-700'
  const label = status === 'final' ? 'Final' : 'Draft'
  return (
    <span
      className={cn(
        'text-[10px] font-semibold uppercase tracking-wide px-1.5 py-0.5 rounded-full',
        styles
      )}
    >
      {label}
    </span>
  )
}

function DraftRow({
  draft,
  selected,
  onSelect,
}: {
  draft: Draft
  selected: boolean
  onSelect: () => void
}) {
  const preview = previewBody(draft)
  return (
    <li>
      <button
        onClick={onSelect}
        className={cn(
          'w-full text-left px-4 py-3 hover:bg-muted transition-colors',
          selected && 'bg-muted'
        )}
      >
        <div className="flex items-start gap-2">
          <div className="font-medium text-sm leading-tight flex-1 truncate">
            {displayTitle(draft)}
          </div>
          <StatusBadge status={draft.status} />
        </div>
        {preview && (
          <div className="text-xs text-muted-foreground mt-1 line-clamp-2">
            {preview}
          </div>
        )}
        <div className="text-xs text-muted-foreground mt-1">
          {formatDate(draft.updated_at)}
        </div>
      </button>
    </li>
  )
}
