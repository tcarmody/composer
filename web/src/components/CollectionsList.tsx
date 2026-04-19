import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  createCollection,
  listCollections,
  type Collection,
} from '../lib/api'
import { cn } from '../lib/utils'

interface Props {
  selectedId: string | null
  onSelect: (id: string) => void
}

export function CollectionsList({ selectedId, onSelect }: Props) {
  const qc = useQueryClient()
  const [creating, setCreating] = useState(false)
  const [newName, setNewName] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['collections'],
    queryFn: listCollections,
  })

  const createMutation = useMutation({
    mutationFn: (name: string) => createCollection({ name }),
    onSuccess: (c) => {
      qc.invalidateQueries({ queryKey: ['collections'] })
      onSelect(c.id)
      setCreating(false)
      setNewName('')
    },
  })

  const submit = () => {
    const trimmed = newName.trim()
    if (!trimmed) return
    createMutation.mutate(trimmed)
  }

  return (
    <>
      <div className="p-3 border-b">
        {creating ? (
          <div className="flex gap-1">
            <input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') submit()
                if (e.key === 'Escape') {
                  setCreating(false)
                  setNewName('')
                }
              }}
              placeholder="Collection name"
              className="flex-1 text-sm px-2 py-1 rounded-md border bg-background focus:outline-none focus:ring-1 focus:ring-foreground/20"
            />
            <button
              onClick={submit}
              disabled={!newName.trim() || createMutation.isPending}
              className="text-xs px-2 py-1 rounded-md border hover:bg-muted disabled:opacity-50"
            >
              Add
            </button>
          </div>
        ) : (
          <button
            onClick={() => setCreating(true)}
            className="w-full text-sm px-3 py-1.5 rounded-md border hover:bg-muted"
          >
            + New collection
          </button>
        )}
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
        {data && data.length === 0 && (
          <div className="p-4 text-sm text-muted-foreground">
            No collections yet.
          </div>
        )}
        {data && data.length > 0 && (
          <ul className="divide-y">
            {data.map((c) => (
              <CollectionRow
                key={c.id}
                collection={c}
                selected={c.id === selectedId}
                onSelect={() => onSelect(c.id)}
              />
            ))}
          </ul>
        )}
      </div>
    </>
  )
}

function CollectionRow({
  collection,
  selected,
  onSelect,
}: {
  collection: Collection
  selected: boolean
  onSelect: () => void
}) {
  return (
    <li>
      <button
        onClick={onSelect}
        className={cn(
          'w-full text-left px-4 py-3 hover:bg-muted transition-colors',
          selected && 'bg-muted'
        )}
      >
        <div className="font-medium text-sm leading-tight">{collection.name}</div>
        <div className="text-xs text-muted-foreground mt-1">
          {collection.member_count} item
          {collection.member_count === 1 ? '' : 's'}
        </div>
      </button>
    </li>
  )
}
