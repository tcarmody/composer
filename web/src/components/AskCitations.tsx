import type { Citation } from '../lib/api'
import { cn } from '../lib/utils'

interface Props {
  citations: Citation[]
  vectorSearchUsed: boolean
  selectedCitationId: string | null
  onSelect: (c: Citation) => void
}

export function AskCitations({
  citations,
  vectorSearchUsed,
  selectedCitationId,
  onSelect,
}: Props) {
  return (
    <>
      <header className="px-4 py-3 border-b flex items-center justify-between">
        <h2 className="text-sm font-semibold">Sources</h2>
        {citations.length > 0 && (
          <span className="text-xs text-muted-foreground rounded-full bg-muted px-2 py-0.5">
            {citations.length}
          </span>
        )}
      </header>

      {citations.length === 0 ? (
        <div className="flex-1 flex items-center justify-center p-6 text-center">
          <div className="text-xs text-muted-foreground max-w-[200px]">
            Ask a question to see cited passages from your archive.
          </div>
        </div>
      ) : (
        <div className="flex-1 overflow-y-auto">
          <ul className="divide-y">
            {citations.map((c) => (
              <CitationRow
                key={c.chunk_id}
                citation={c}
                selected={c.chunk_id === selectedCitationId}
                onSelect={() => onSelect(c)}
              />
            ))}
          </ul>
        </div>
      )}

      {citations.length > 0 && (
        <footer className="border-t px-4 py-2 text-xs text-muted-foreground flex items-center gap-2">
          <span
            className={cn(
              'inline-block w-1.5 h-1.5 rounded-full',
              vectorSearchUsed ? 'bg-green-600' : 'bg-muted-foreground/40'
            )}
          />
          {vectorSearchUsed ? 'Hybrid search' : 'BM25 only'}
        </footer>
      )}
    </>
  )
}

function sourceTypeLabel(type: string): string {
  switch (type) {
    case 'item':
      return 'Item'
    case 'note':
      return 'Note'
    case 'draft':
      return 'Draft'
    default:
      return type
  }
}

function displayHost(url: string | null): string | null {
  if (!url) return null
  try {
    return new URL(url).host
  } catch {
    return url
  }
}

function CitationRow({
  citation,
  selected,
  onSelect,
}: {
  citation: Citation
  selected: boolean
  onSelect: () => void
}) {
  const host = displayHost(citation.source_url)
  return (
    <li>
      <button
        onClick={onSelect}
        className={cn(
          'w-full text-left px-4 py-3 hover:bg-muted transition-colors',
          selected && 'bg-muted'
        )}
      >
        <div className="flex items-baseline gap-2 mb-1">
          <span className="text-xs font-semibold text-foreground">
            [{citation.index}]
          </span>
          <span className="text-[10px] uppercase tracking-wide text-muted-foreground">
            {sourceTypeLabel(citation.source_type)}
          </span>
        </div>
        <div className="font-medium text-sm leading-tight line-clamp-2">
          {citation.source_title ?? 'Untitled'}
        </div>
        <p className="text-xs text-muted-foreground mt-1 line-clamp-4">
          {citation.snippet}
        </p>
        {citation.source_url && (
          <div className="mt-2">
            <a
              href={citation.source_url}
              target="_blank"
              rel="noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="text-xs text-muted-foreground hover:underline truncate block"
            >
              {host ?? citation.source_url}
            </a>
          </div>
        )}
      </button>
    </li>
  )
}
