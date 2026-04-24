import { useCallback, useMemo, useRef, useState } from 'react'
import {
  streamChat,
  type ChatHistoryMessage,
  type ChatSourceType,
  type Citation,
} from '../lib/api'
import { AskTranscript, type Turn } from './AskTranscript'
import { AskCitations } from './AskCitations'

type Scope = 'all' | 'items' | 'notes' | 'drafts'

const SCOPE_LABELS: Record<Scope, string> = {
  all: 'All',
  items: 'Library',
  notes: 'Notes',
  drafts: 'Drafts',
}

function scopeToSourceTypes(scope: Scope): ChatSourceType[] | null {
  switch (scope) {
    case 'all':
      return null
    case 'items':
      return ['item']
    case 'notes':
      return ['note']
    case 'drafts':
      return ['draft']
  }
}

function newId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) {
    return crypto.randomUUID()
  }
  return `turn-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`
}

export function Ask() {
  const [turns, setTurns] = useState<Turn[]>([])
  const [input, setInput] = useState('')
  const [scope, setScope] = useState<Scope>('all')
  const [focusedTurnId, setFocusedTurnId] = useState<string | null>(null)
  const [selectedCitationId, setSelectedCitationId] = useState<string | null>(
    null
  )
  const abortRef = useRef<AbortController | null>(null)

  const isStreaming = useMemo(() => {
    const last = turns[turns.length - 1]
    return last?.state === 'streaming'
  }, [turns])

  const focusedTurn = useMemo(() => {
    if (focusedTurnId) {
      const match = turns.find((t) => t.id === focusedTurnId)
      if (match) return match
    }
    return turns[turns.length - 1] ?? null
  }, [focusedTurnId, turns])

  const patchTurn = useCallback(
    (id: string, updater: (t: Turn) => Turn) => {
      setTurns((prev) => prev.map((t) => (t.id === id ? updater(t) : t)))
    },
    []
  )

  const ask = useCallback(async () => {
    const query = input.trim()
    if (!query || isStreaming) return

    const history: ChatHistoryMessage[] = turns.flatMap((t) =>
      t.state === 'done' && t.answer
        ? [
            { role: 'user' as const, content: t.question },
            { role: 'assistant' as const, content: t.answer },
          ]
        : []
    )

    const turnId = newId()
    const turn: Turn = {
      id: turnId,
      question: query,
      answer: '',
      citations: [],
      vectorSearchUsed: false,
      state: 'streaming',
    }

    setTurns((prev) => [...prev, turn])
    setInput('')
    setSelectedCitationId(null)
    setFocusedTurnId(null)

    const controller = new AbortController()
    abortRef.current = controller

    try {
      const stream = streamChat({
        query,
        sourceTypes: scopeToSourceTypes(scope),
        history,
        signal: controller.signal,
      })
      for await (const event of stream) {
        if (controller.signal.aborted) break
        switch (event.type) {
          case 'citations':
            patchTurn(turnId, (t) => ({
              ...t,
              citations: event.citations,
              vectorSearchUsed: event.vector_search_used,
            }))
            break
          case 'delta':
            patchTurn(turnId, (t) => ({ ...t, answer: t.answer + event.text }))
            break
          case 'done':
            patchTurn(turnId, (t) => ({ ...t, state: 'done' }))
            break
          case 'error':
            patchTurn(turnId, (t) => ({
              ...t,
              state: 'error',
              error: event.message,
            }))
            break
        }
      }
      patchTurn(turnId, (t) =>
        t.state === 'streaming' ? { ...t, state: 'done' } : t
      )
    } catch (err) {
      if (controller.signal.aborted) {
        patchTurn(turnId, (t) =>
          t.state === 'streaming' ? { ...t, state: 'done' } : t
        )
      } else {
        const message = err instanceof Error ? err.message : 'Request failed'
        patchTurn(turnId, (t) => ({ ...t, state: 'error', error: message }))
      }
    } finally {
      if (abortRef.current === controller) abortRef.current = null
    }
  }, [input, isStreaming, patchTurn, scope, turns])

  const cancel = useCallback(() => {
    abortRef.current?.abort()
  }, [])

  const reset = useCallback(() => {
    abortRef.current?.abort()
    setTurns([])
    setInput('')
    setSelectedCitationId(null)
    setFocusedTurnId(null)
  }, [])

  const onCitationTap = useCallback(
    (turnId: string, index: number) => {
      setFocusedTurnId(turnId)
      const turn = turns.find((t) => t.id === turnId)
      const hit = turn?.citations.find((c) => c.index === index)
      if (hit) setSelectedCitationId(hit.chunk_id)
    },
    [turns]
  )

  const onSelectCitation = useCallback((c: Citation) => {
    setSelectedCitationId(c.chunk_id)
  }, [])

  return (
    <div className="flex h-[calc(100vh-65px)]">
      <section className="flex-1 min-w-0 flex flex-col">
        <AskTranscript
          turns={turns}
          focusedTurnId={focusedTurn?.id ?? null}
          onCitationTap={onCitationTap}
        />
        <InputBar
          input={input}
          onInput={setInput}
          scope={scope}
          onScope={setScope}
          isStreaming={isStreaming}
          hasTurns={turns.length > 0}
          onAsk={ask}
          onCancel={cancel}
          onReset={reset}
        />
      </section>
      <aside className="w-[340px] border-l flex flex-col shrink-0">
        <AskCitations
          citations={focusedTurn?.citations ?? []}
          vectorSearchUsed={focusedTurn?.vectorSearchUsed ?? false}
          selectedCitationId={selectedCitationId}
          onSelect={onSelectCitation}
        />
      </aside>
    </div>
  )
}

function InputBar({
  input,
  onInput,
  scope,
  onScope,
  isStreaming,
  hasTurns,
  onAsk,
  onCancel,
  onReset,
}: {
  input: string
  onInput: (v: string) => void
  scope: Scope
  onScope: (s: Scope) => void
  isStreaming: boolean
  hasTurns: boolean
  onAsk: () => void
  onCancel: () => void
  onReset: () => void
}) {
  const canAsk = input.trim().length > 0 && !isStreaming

  return (
    <div className="border-t p-3 flex items-start gap-2">
      <select
        value={scope}
        onChange={(e) => onScope(e.target.value as Scope)}
        disabled={isStreaming}
        className="text-sm border rounded-md px-2 py-1.5 bg-background disabled:opacity-50"
      >
        {(Object.keys(SCOPE_LABELS) as Scope[]).map((s) => (
          <option key={s} value={s}>
            {SCOPE_LABELS[s]}
          </option>
        ))}
      </select>
      <textarea
        value={input}
        onChange={(e) => onInput(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault()
            if (canAsk) onAsk()
          }
        }}
        placeholder="Ask a question about your archive…"
        rows={1}
        disabled={isStreaming}
        className="flex-1 text-sm px-3 py-1.5 rounded-md border bg-background resize-none focus:outline-none focus:ring-1 focus:ring-foreground/20 disabled:opacity-60"
      />
      {isStreaming ? (
        <button
          onClick={onCancel}
          className="text-sm px-3 py-1.5 rounded-md border hover:bg-muted text-red-600"
        >
          Stop
        </button>
      ) : (
        <button
          onClick={onAsk}
          disabled={!canAsk}
          className="text-sm px-3 py-1.5 rounded-md border hover:bg-muted disabled:opacity-50"
        >
          Ask
        </button>
      )}
      {hasTurns && !isStreaming && (
        <button
          onClick={onReset}
          className="text-sm px-2 py-1.5 rounded-md border hover:bg-muted text-muted-foreground"
          title="Clear conversation"
        >
          Clear
        </button>
      )}
    </div>
  )
}
