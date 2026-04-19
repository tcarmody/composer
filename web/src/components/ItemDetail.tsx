import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  deleteItem,
  getItem,
  setItemArchived,
  type Item,
} from '../lib/api'
import { AddToCollectionButton } from './AddToCollectionButton'

interface ItemDetailProps {
  itemId: string | null
}

function formatDateTime(iso: string | null): string {
  if (!iso) return ''
  const d = new Date(iso.replace(' ', 'T'))
  if (Number.isNaN(d.getTime())) return iso
  return d.toLocaleString()
}

export function ItemDetail({ itemId }: ItemDetailProps) {
  const qc = useQueryClient()

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['item', itemId],
    queryFn: () => getItem(itemId!),
    enabled: Boolean(itemId),
  })

  const archiveMutation = useMutation({
    mutationFn: ({ id, archived }: { id: string; archived: boolean }) =>
      setItemArchived(id, archived),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['item', itemId] })
      qc.invalidateQueries({ queryKey: ['items'] })
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteItem(id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['items'] })
    },
  })

  if (!itemId) {
    return (
      <div className="p-8 text-sm text-muted-foreground">
        Select an item from the library to see its contents.
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

  const item: Item = data
  const isArchived = Boolean(item.archived_at)

  return (
    <article className="p-8 space-y-6 max-w-3xl">
      <header className="space-y-2">
        <div className="flex items-center justify-between gap-4">
          <div className="text-xs text-muted-foreground uppercase tracking-wide">
            {item.source}
            {item.source_ref ? ` · ${item.source_ref}` : ''}
            {isArchived ? ' · archived' : ''}
          </div>
          <div className="flex gap-2">
            <AddToCollectionButton itemId={item.id} />
            <button
              onClick={() =>
                archiveMutation.mutate({ id: item.id, archived: !isArchived })
              }
              className="text-xs border px-3 py-1 rounded-md hover:bg-muted"
            >
              {isArchived ? 'Unarchive' : 'Archive'}
            </button>
            <button
              onClick={() => {
                if (confirm(`Delete "${item.title}"?`)) {
                  deleteMutation.mutate(item.id)
                }
              }}
              className="text-xs border px-3 py-1 rounded-md hover:bg-muted text-red-600"
            >
              Delete
            </button>
          </div>
        </div>
        <h1 className="text-2xl font-semibold leading-tight">{item.title}</h1>
        <div className="text-sm text-muted-foreground">
          {item.author && <span>{item.author}</span>}
          {item.author && item.published_at && <span> · </span>}
          {item.published_at && <span>{formatDateTime(item.published_at)}</span>}
          {item.url && (
            <>
              {' · '}
              <a
                href={item.url}
                target="_blank"
                rel="noreferrer noopener"
                className="underline hover:no-underline"
              >
                original
              </a>
            </>
          )}
        </div>
      </header>

      {item.summary && (
        <section className="space-y-1">
          <h2 className="text-xs uppercase tracking-wide text-muted-foreground">
            Summary
          </h2>
          <p className="text-sm leading-relaxed">{item.summary}</p>
        </section>
      )}

      {item.key_points.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-xs uppercase tracking-wide text-muted-foreground">
            Key points
          </h2>
          <ul className="list-disc list-outside pl-5 space-y-1 text-sm">
            {item.key_points.map((kp, i) => (
              <li key={i}>{kp}</li>
            ))}
          </ul>
        </section>
      )}

      {item.keywords.length > 0 && (
        <section className="flex flex-wrap gap-2">
          {item.keywords.map((kw) => (
            <span
              key={kw}
              className="text-xs bg-muted text-muted-foreground px-2 py-0.5 rounded-full"
            >
              {kw}
            </span>
          ))}
        </section>
      )}

      {item.content && (
        <section className="space-y-2">
          <h2 className="text-xs uppercase tracking-wide text-muted-foreground">
            Full text
          </h2>
          <div className="text-sm leading-relaxed whitespace-pre-wrap">
            {item.content}
          </div>
        </section>
      )}

      {item.related_links.length > 0 && (
        <section className="space-y-2">
          <h2 className="text-xs uppercase tracking-wide text-muted-foreground">
            Related
          </h2>
          <ul className="space-y-1 text-sm">
            {item.related_links.map((rl, i) => (
              <li key={i}>
                <a
                  href={rl.url}
                  target="_blank"
                  rel="noreferrer noopener"
                  className="underline hover:no-underline"
                >
                  {rl.title || rl.url}
                </a>
              </li>
            ))}
          </ul>
        </section>
      )}
    </article>
  )
}
