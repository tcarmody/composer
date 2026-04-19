import { useEffect, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import {
  DndContext,
  PointerSensor,
  closestCenter,
  useSensor,
  useSensors,
  type DragEndEvent,
} from '@dnd-kit/core'
import {
  SortableContext,
  arrayMove,
  useSortable,
  verticalListSortingStrategy,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import {
  createInlineNote,
  deleteCollection,
  getCollection,
  removeCollectionMember,
  reorderCollection,
  type MemberType,
  type OutlineNode,
} from '../lib/api'

interface Props {
  collectionId: string | null
  onDeleted: () => void
}

const nodeKey = (n: OutlineNode) => `${n.member_type}:${n.member_id}`

export function CollectionDetail({ collectionId, onDeleted }: Props) {
  const qc = useQueryClient()
  const [localOrder, setLocalOrder] = useState<OutlineNode[] | null>(null)

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['collection', collectionId],
    queryFn: () => getCollection(collectionId!),
    enabled: Boolean(collectionId),
  })

  useEffect(() => {
    setLocalOrder(null)
  }, [collectionId])

  const reorderMutation = useMutation({
    mutationFn: (members: Array<[MemberType, string]>) =>
      reorderCollection(collectionId!, members),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collection', collectionId] })
      qc.invalidateQueries({ queryKey: ['collections'] })
    },
  })

  const addNoteMutation = useMutation({
    mutationFn: (body: string) =>
      createInlineNote(collectionId!, { body }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collection', collectionId] })
      qc.invalidateQueries({ queryKey: ['collections'] })
    },
  })

  const removeMutation = useMutation({
    mutationFn: ({ type, id }: { type: MemberType; id: string }) =>
      removeCollectionMember(collectionId!, type, id),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collection', collectionId] })
      qc.invalidateQueries({ queryKey: ['collections'] })
    },
  })

  const deleteMutation = useMutation({
    mutationFn: () => deleteCollection(collectionId!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['collections'] })
      onDeleted()
    },
  })

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } })
  )

  if (!collectionId) {
    return (
      <div className="p-8 text-sm text-muted-foreground">
        Select a collection, or create a new one.
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

  const members = localOrder ?? data.members
  const ids = members.map(nodeKey)

  const onDragEnd = (ev: DragEndEvent) => {
    const { active, over } = ev
    if (!over || active.id === over.id) return
    const oldIdx = ids.indexOf(String(active.id))
    const newIdx = ids.indexOf(String(over.id))
    if (oldIdx < 0 || newIdx < 0) return
    const next = arrayMove(members, oldIdx, newIdx)
    setLocalOrder(next)
    reorderMutation.mutate(
      next.map((m) => [m.member_type, m.member_id] as [MemberType, string])
    )
  }

  return (
    <div className="p-8 max-w-3xl space-y-6">
      <header className="space-y-2">
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-semibold leading-tight">
              {data.collection.name}
            </h1>
            {data.collection.description && (
              <p className="text-sm text-muted-foreground mt-1">
                {data.collection.description}
              </p>
            )}
          </div>
          <button
            onClick={() => {
              if (confirm(`Delete "${data.collection.name}"?`))
                deleteMutation.mutate()
            }}
            className="text-xs border px-3 py-1 rounded-md hover:bg-muted text-red-600"
          >
            Delete
          </button>
        </div>
        <div className="text-xs text-muted-foreground">
          {data.collection.member_count} item
          {data.collection.member_count === 1 ? '' : 's'}
        </div>
      </header>

      {members.length === 0 ? (
        <div className="text-sm text-muted-foreground border border-dashed rounded-md p-8 text-center">
          Empty collection. Add items from the Library, or create an inline note
          below.
        </div>
      ) : (
        <DndContext
          sensors={sensors}
          collisionDetection={closestCenter}
          onDragEnd={onDragEnd}
        >
          <SortableContext items={ids} strategy={verticalListSortingStrategy}>
            <ol className="space-y-2">
              {members.map((m) => (
                <SortableRow
                  key={nodeKey(m)}
                  node={m}
                  onRemove={() =>
                    removeMutation.mutate({
                      type: m.member_type,
                      id: m.member_id,
                    })
                  }
                />
              ))}
            </ol>
          </SortableContext>
        </DndContext>
      )}

      <InlineNoteForm
        onSubmit={(body) => addNoteMutation.mutate(body)}
        pending={addNoteMutation.isPending}
      />
    </div>
  )
}

function SortableRow({
  node,
  onRemove,
}: {
  node: OutlineNode
  onRemove: () => void
}) {
  const {
    attributes,
    listeners,
    setNodeRef,
    transform,
    transition,
    isDragging,
  } = useSortable({ id: nodeKey(node) })

  const style = {
    transform: CSS.Transform.toString(transform),
    transition,
    opacity: isDragging ? 0.5 : 1,
  }

  return (
    <li
      ref={setNodeRef}
      style={style}
      className="border rounded-md bg-background flex items-stretch"
    >
      <button
        {...attributes}
        {...listeners}
        aria-label="Drag handle"
        className="px-2 flex items-center text-muted-foreground hover:bg-muted cursor-grab active:cursor-grabbing rounded-l-md"
      >
        ⋮⋮
      </button>
      <div className="flex-1 p-3 min-w-0">
        {node.member_type === 'item' && node.item && (
          <>
            <div className="text-xs uppercase tracking-wide text-muted-foreground mb-0.5">
              Item{node.item.archived ? ' · archived' : ''}
            </div>
            <div className="font-medium text-sm leading-tight">
              {node.item.title ?? '(untitled)'}
            </div>
            {node.item.summary && (
              <p className="text-xs text-muted-foreground mt-1 line-clamp-2">
                {node.item.summary}
              </p>
            )}
          </>
        )}
        {node.member_type === 'note' && node.note && (
          <>
            <div className="text-xs uppercase tracking-wide text-muted-foreground mb-0.5">
              Note
            </div>
            {node.note.title && (
              <div className="font-medium text-sm leading-tight">
                {node.note.title}
              </div>
            )}
            <p className="text-sm whitespace-pre-wrap">{node.note.body}</p>
          </>
        )}
      </div>
      <button
        onClick={onRemove}
        className="px-3 text-xs text-muted-foreground hover:text-red-600 hover:bg-muted rounded-r-md"
        aria-label="Remove from collection"
      >
        ✕
      </button>
    </li>
  )
}

function InlineNoteForm({
  onSubmit,
  pending,
}: {
  onSubmit: (body: string) => void
  pending: boolean
}) {
  const [body, setBody] = useState('')
  const submit = () => {
    const trimmed = body.trim()
    if (!trimmed) return
    onSubmit(trimmed)
    setBody('')
  }
  return (
    <div className="border-t pt-4 space-y-2">
      <div className="text-xs uppercase tracking-wide text-muted-foreground">
        Add inline note
      </div>
      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) submit()
        }}
        placeholder="Jot a thought…  (⌘/Ctrl-Enter to submit)"
        rows={3}
        className="w-full text-sm px-3 py-2 rounded-md border bg-background focus:outline-none focus:ring-1 focus:ring-foreground/20"
      />
      <div className="flex justify-end">
        <button
          onClick={submit}
          disabled={!body.trim() || pending}
          className="text-xs border px-3 py-1 rounded-md hover:bg-muted disabled:opacity-50"
        >
          Add note
        </button>
      </div>
    </div>
  )
}
