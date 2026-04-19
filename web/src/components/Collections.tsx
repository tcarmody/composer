import { useState } from 'react'
import { CollectionsList } from './CollectionsList'
import { CollectionDetail } from './CollectionDetail'

export function Collections() {
  const [selectedId, setSelectedId] = useState<string | null>(null)

  return (
    <div className="flex h-[calc(100vh-65px)]">
      <aside className="w-[320px] border-r flex flex-col">
        <CollectionsList
          selectedId={selectedId}
          onSelect={setSelectedId}
        />
      </aside>
      <main className="flex-1 overflow-y-auto">
        <CollectionDetail
          collectionId={selectedId}
          onDeleted={() => setSelectedId(null)}
        />
      </main>
    </div>
  )
}
