import { useCallback, useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { getHealth } from './lib/api'
import { Library } from './components/Library'
import { Collections } from './components/Collections'
import { Notes } from './components/Notes'
import { Ask } from './components/Ask'
import { Drafts } from './components/Drafts'
import type { QuoteKind } from './components/ItemDetail'
import { cn } from './lib/utils'

type View = 'library' | 'collections' | 'notes' | 'ask' | 'publish'

function HealthBadge() {
  const { data, isError } = useQuery({
    queryKey: ['health'],
    queryFn: getHealth,
    refetchInterval: 10_000,
  })

  if (isError) {
    return <span className="text-red-600">● backend unreachable</span>
  }
  if (!data) {
    return <span>checking…</span>
  }
  return (
    <span>
      <span className="text-green-600">●</span> {data.status} · v{data.version}
    </span>
  )
}

export default function App() {
  const [view, setView] = useState<View>('library')
  const [notesSelectedId, setNotesSelectedId] = useState<string | null>(null)
  const [draftsSelectedId, setDraftsSelectedId] = useState<string | null>(null)
  const [notesFocusNonce, setNotesFocusNonce] = useState(0)
  const [draftsFocusNonce, setDraftsFocusNonce] = useState(0)
  const qc = useQueryClient()

  const onQuoteCreated = useCallback(
    (kind: QuoteKind, id: string) => {
      if (kind === 'note') {
        qc.invalidateQueries({ queryKey: ['notes'] })
        setNotesSelectedId(id)
        setView('notes')
        setNotesFocusNonce((n) => n + 1)
      } else {
        qc.invalidateQueries({ queryKey: ['drafts'] })
        setDraftsSelectedId(id)
        setView('publish')
        setDraftsFocusNonce((n) => n + 1)
      }
    },
    [qc]
  )

  return (
    <div className="h-screen flex flex-col">
      <header className="border-b shrink-0">
        <div className="px-6 py-3 flex items-center justify-between">
          <div className="flex items-baseline gap-6">
            <h1 className="text-lg font-semibold tracking-tight">Composer</h1>
            <nav className="flex gap-4 text-sm">
              <button
                onClick={() => setView('library')}
                className={cn(
                  'transition-colors',
                  view === 'library'
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                )}
              >
                Library
              </button>
              <button
                onClick={() => setView('collections')}
                className={cn(
                  'transition-colors',
                  view === 'collections'
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                )}
              >
                Collections
              </button>
              <button
                onClick={() => setView('notes')}
                className={cn(
                  'transition-colors',
                  view === 'notes'
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                )}
              >
                Notes
              </button>
              <button
                onClick={() => setView('ask')}
                className={cn(
                  'transition-colors',
                  view === 'ask'
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                )}
              >
                Ask
              </button>
              <button
                onClick={() => setView('publish')}
                className={cn(
                  'transition-colors',
                  view === 'publish'
                    ? 'text-foreground'
                    : 'text-muted-foreground hover:text-foreground'
                )}
              >
                Publish
              </button>
            </nav>
          </div>
          <div className="text-xs text-muted-foreground">
            <HealthBadge />
          </div>
        </div>
      </header>
      {view === 'library' && <Library onQuoteCreated={onQuoteCreated} />}
      {view === 'collections' && <Collections />}
      {view === 'notes' && (
        <Notes
          selectedId={notesSelectedId}
          onSelect={setNotesSelectedId}
          focusRequest={notesFocusNonce}
        />
      )}
      {view === 'ask' && <Ask />}
      {view === 'publish' && (
        <Drafts
          selectedId={draftsSelectedId}
          onSelect={setDraftsSelectedId}
          focusRequest={draftsFocusNonce}
        />
      )}
    </div>
  )
}
