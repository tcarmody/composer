import { useEffect, useRef, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  addCollectionMember,
  createCollection,
  listCollections,
} from '../lib/api'

interface Props {
  itemId: string
}

export function AddToCollectionButton({ itemId }: Props) {
  const qc = useQueryClient()
  const [open, setOpen] = useState(false)
  const [newName, setNewName] = useState('')
  const [flash, setFlash] = useState<string | null>(null)
  const wrapRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  const { data: collections } = useQuery({
    queryKey: ['collections'],
    queryFn: listCollections,
    enabled: open,
  })

  const addMutation = useMutation({
    mutationFn: (collectionId: string) =>
      addCollectionMember(collectionId, {
        member_type: 'item',
        member_id: itemId,
      }),
    onSuccess: (outline) => {
      qc.invalidateQueries({ queryKey: ['collections'] })
      qc.invalidateQueries({ queryKey: ['collection', outline.collection.id] })
      setFlash(`Added to "${outline.collection.name}"`)
      setTimeout(() => setFlash(null), 2000)
      setOpen(false)
    },
  })

  const createMutation = useMutation({
    mutationFn: async (name: string) => {
      const c = await createCollection({ name })
      return addCollectionMember(c.id, {
        member_type: 'item',
        member_id: itemId,
      })
    },
    onSuccess: (outline) => {
      qc.invalidateQueries({ queryKey: ['collections'] })
      qc.invalidateQueries({ queryKey: ['collection', outline.collection.id] })
      setFlash(`Added to "${outline.collection.name}"`)
      setTimeout(() => setFlash(null), 2000)
      setNewName('')
      setOpen(false)
    },
  })

  const submitNew = () => {
    const trimmed = newName.trim()
    if (!trimmed) return
    createMutation.mutate(trimmed)
  }

  return (
    <div className="relative" ref={wrapRef}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="text-xs border px-3 py-1 rounded-md hover:bg-muted"
      >
        Add to collection
      </button>
      {flash && !open && (
        <div className="absolute right-0 top-full mt-1 text-xs text-green-700 whitespace-nowrap">
          {flash}
        </div>
      )}
      {open && (
        <div className="absolute right-0 top-full mt-1 w-64 border rounded-md bg-background shadow-md z-10">
          <div className="max-h-56 overflow-y-auto">
            {collections && collections.length > 0 ? (
              <ul className="divide-y">
                {collections.map((c) => (
                  <li key={c.id}>
                    <button
                      onClick={() => addMutation.mutate(c.id)}
                      disabled={addMutation.isPending}
                      className="w-full text-left text-sm px-3 py-2 hover:bg-muted disabled:opacity-50"
                    >
                      <div className="font-medium leading-tight">{c.name}</div>
                      <div className="text-xs text-muted-foreground">
                        {c.member_count} item
                        {c.member_count === 1 ? '' : 's'}
                      </div>
                    </button>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="text-xs text-muted-foreground p-3">
                No collections yet.
              </div>
            )}
          </div>
          <div className="border-t p-2 flex gap-1">
            <input
              autoFocus
              value={newName}
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') submitNew()
              }}
              placeholder="New collection…"
              className="flex-1 text-sm px-2 py-1 rounded-md border bg-background focus:outline-none focus:ring-1 focus:ring-foreground/20"
            />
            <button
              onClick={submitNew}
              disabled={!newName.trim() || createMutation.isPending}
              className="text-xs px-2 py-1 rounded-md border hover:bg-muted disabled:opacity-50"
            >
              Create
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
