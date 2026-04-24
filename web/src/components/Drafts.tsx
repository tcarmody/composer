import { useState } from 'react'
import { DraftsList } from './DraftsList'
import { DraftEditor } from './DraftEditor'

export function Drafts() {
  const [selectedId, setSelectedId] = useState<string | null>(null)

  return (
    <div className="flex h-[calc(100vh-65px)]">
      <aside className="w-[320px] border-r flex flex-col">
        <DraftsList selectedId={selectedId} onSelect={setSelectedId} />
      </aside>
      <main className="flex-1 overflow-hidden flex">
        <DraftEditor
          draftId={selectedId}
          onDeleted={() => setSelectedId(null)}
        />
      </main>
    </div>
  )
}
