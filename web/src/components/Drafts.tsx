import { DraftsList } from './DraftsList'
import { DraftEditor } from './DraftEditor'

interface Props {
  selectedId: string | null
  onSelect: (id: string | null) => void
  focusRequest?: number
}

export function Drafts({ selectedId, onSelect, focusRequest }: Props) {
  return (
    <div className="flex h-[calc(100vh-65px)]">
      <aside className="w-[320px] border-r flex flex-col">
        <DraftsList selectedId={selectedId} onSelect={onSelect} />
      </aside>
      <main className="flex-1 overflow-hidden flex">
        <DraftEditor
          draftId={selectedId}
          onDeleted={() => onSelect(null)}
          focusRequest={focusRequest}
        />
      </main>
    </div>
  )
}
