import { useQuery } from '@tanstack/react-query'
import { listItems, type ItemSummary } from '../lib/api'
import { cn } from '../lib/utils'

interface ItemListProps {
  query: string
  archived: boolean
  selectedId: string | null
  onSelect: (id: string) => void
}

function formatDate(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso.replace(' ', 'T'))
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' })
}

function ItemRow({
  item,
  selected,
  onSelect,
}: {
  item: ItemSummary
  selected: boolean
  onSelect: () => void
}) {
  return (
    <button
      onClick={onSelect}
      className={cn(
        'w-full text-left px-4 py-3 border-b transition-colors hover:bg-muted',
        selected && 'bg-muted'
      )}
    >
      <div className="flex items-baseline justify-between gap-3">
        <h3 className="font-medium text-sm leading-tight line-clamp-2">{item.title}</h3>
        <span className="text-xs text-muted-foreground shrink-0">
          {formatDate(item.published_at || item.promoted_at)}
        </span>
      </div>
      {item.author && (
        <div className="text-xs text-muted-foreground mt-1">{item.author}</div>
      )}
      {item.summary && (
        <p className="text-xs text-muted-foreground mt-2 line-clamp-2">{item.summary}</p>
      )}
    </button>
  )
}

export function ItemList({ query, archived, selectedId, onSelect }: ItemListProps) {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['items', { q: query, archived }],
    queryFn: () => listItems({ q: query || undefined, archived }),
  })

  if (isLoading) {
    return <div className="p-4 text-sm text-muted-foreground">Loading…</div>
  }
  if (isError) {
    return (
      <div className="p-4 text-sm text-red-600">
        Failed to load: {(error as Error).message}
      </div>
    )
  }

  const items = data?.items ?? []
  if (items.length === 0) {
    return (
      <div className="p-4 text-sm text-muted-foreground">
        {query
          ? `No items match "${query}".`
          : archived
            ? 'No archived items.'
            : 'No items yet. Promote something from DataPoints to see it here.'}
      </div>
    )
  }

  return (
    <div className="divide-y">
      <div className="px-4 py-2 text-xs text-muted-foreground">
        {data?.total} item{data?.total === 1 ? '' : 's'}
      </div>
      {items.map((item) => (
        <ItemRow
          key={item.id}
          item={item}
          selected={item.id === selectedId}
          onSelect={() => onSelect(item.id)}
        />
      ))}
    </div>
  )
}
