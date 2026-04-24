import { useState } from 'react'
import { NotesList } from './NotesList'
import { NoteEditor } from './NoteEditor'

export function Notes() {
  const [selectedId, setSelectedId] = useState<string | null>(null)

  return (
    <div className="flex h-[calc(100vh-65px)]">
      <aside className="w-[320px] border-r flex flex-col">
        <NotesList selectedId={selectedId} onSelect={setSelectedId} />
      </aside>
      <main className="flex-1 overflow-hidden flex">
        <NoteEditor
          noteId={selectedId}
          onDeleted={() => setSelectedId(null)}
        />
      </main>
    </div>
  )
}
