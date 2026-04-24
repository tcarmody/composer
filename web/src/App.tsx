import { useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { getHealth } from './lib/api'
import { Library } from './components/Library'
import { Collections } from './components/Collections'
import { Notes } from './components/Notes'
import { Ask } from './components/Ask'
import { cn } from './lib/utils'

type View = 'library' | 'collections' | 'notes' | 'ask'

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
              <span className="text-muted-foreground">Publish</span>
            </nav>
          </div>
          <div className="text-xs text-muted-foreground">
            <HealthBadge />
          </div>
        </div>
      </header>
      {view === 'library' && <Library />}
      {view === 'collections' && <Collections />}
      {view === 'notes' && <Notes />}
      {view === 'ask' && <Ask />}
    </div>
  )
}
