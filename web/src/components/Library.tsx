import { useState } from 'react'
import { ItemList } from './ItemList'
import { ItemDetail } from './ItemDetail'
import { cn } from '../lib/utils'

export function Library() {
  const [query, setQuery] = useState('')
  const [archived, setArchived] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)

  return (
    <div className="flex h-[calc(100vh-65px)]">
      <aside className="w-[380px] border-r flex flex-col">
        <div className="p-3 border-b space-y-2">
          <input
            type="search"
            placeholder="Search items…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="w-full text-sm px-3 py-1.5 rounded-md border bg-background focus:outline-none focus:ring-1 focus:ring-foreground/20"
          />
          <div className="flex gap-1 text-xs">
            <button
              onClick={() => setArchived(false)}
              className={cn(
                'px-2 py-1 rounded-md border',
                !archived && 'bg-muted'
              )}
            >
              Active
            </button>
            <button
              onClick={() => setArchived(true)}
              className={cn(
                'px-2 py-1 rounded-md border',
                archived && 'bg-muted'
              )}
            >
              Archived
            </button>
          </div>
        </div>
        <div className="flex-1 overflow-y-auto">
          <ItemList
            query={query}
            archived={archived}
            selectedId={selectedId}
            onSelect={setSelectedId}
          />
        </div>
      </aside>
      <main className="flex-1 overflow-y-auto">
        <ItemDetail itemId={selectedId} />
      </main>
    </div>
  )
}
