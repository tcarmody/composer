import { useEffect, useRef, type ReactNode } from 'react'
import type { Citation } from '../lib/api'
import { cn } from '../lib/utils'

export interface Turn {
  id: string
  question: string
  answer: string
  citations: Citation[]
  vectorSearchUsed: boolean
  state: 'streaming' | 'done' | 'error'
  error?: string
}

interface Props {
  turns: Turn[]
  focusedTurnId: string | null
  onCitationTap: (turnId: string, index: number) => void
}

export function AskTranscript({ turns, focusedTurnId, onCitationTap }: Props) {
  const scrollRef = useRef<HTMLDivElement>(null)
  const lastAnswer = turns[turns.length - 1]?.answer ?? ''
  const lastId = turns[turns.length - 1]?.id ?? null

  useEffect(() => {
    const el = scrollRef.current
    if (!el) return
    el.scrollTo({ top: el.scrollHeight, behavior: 'smooth' })
  }, [lastAnswer, lastId, turns.length])

  if (turns.length === 0) {
    return (
      <div
        ref={scrollRef}
        className="flex-1 overflow-y-auto flex items-center justify-center p-12"
      >
        <EmptyState />
      </div>
    )
  }

  return (
    <div ref={scrollRef} className="flex-1 overflow-y-auto">
      <div className="max-w-3xl mx-auto px-6 py-8 space-y-8">
        {turns.map((turn) => (
          <TurnView
            key={turn.id}
            turn={turn}
            isFocused={turn.id === focusedTurnId}
            onCitationTap={(index) => onCitationTap(turn.id, index)}
          />
        ))}
      </div>
    </div>
  )
}

function EmptyState() {
  return (
    <div className="max-w-md text-center space-y-3">
      <div className="text-3xl text-muted-foreground">✦</div>
      <h2 className="text-lg font-medium">Ask your archive</h2>
      <p className="text-sm text-muted-foreground">
        Questions are answered from your items, notes, and drafts. Every claim
        is grounded in a cited source.
      </p>
    </div>
  )
}

function TurnView({
  turn,
  isFocused,
  onCitationTap,
}: {
  turn: Turn
  isFocused: boolean
  onCitationTap: (index: number) => void
}) {
  const indices = new Set(turn.citations.map((c) => c.index))
  return (
    <div className={cn('space-y-3', !isFocused && 'opacity-70')}>
      <div className="flex justify-end">
        <div className="max-w-[80%] rounded-2xl bg-muted px-4 py-2 text-sm whitespace-pre-wrap">
          {turn.question}
        </div>
      </div>
      <div className="text-sm leading-relaxed">
        {turn.answer === '' && turn.state === 'streaming' ? (
          <div className="text-muted-foreground italic">Searching…</div>
        ) : (
          <AnswerText
            text={turn.answer}
            indices={indices}
            onCitationTap={onCitationTap}
          />
        )}
        {turn.state === 'error' && (
          <div className="mt-3 text-sm text-red-600">
            {turn.error ?? 'Something went wrong.'}
          </div>
        )}
      </div>
    </div>
  )
}

const CITATION_RE = /\[(\d+(?:\s*,\s*\d+)*)\]/g

function AnswerText({
  text,
  indices,
  onCitationTap,
}: {
  text: string
  indices: Set<number>
  onCitationTap: (index: number) => void
}) {
  const parts: ReactNode[] = []
  let cursor = 0
  let match: RegExpExecArray | null
  CITATION_RE.lastIndex = 0
  while ((match = CITATION_RE.exec(text)) !== null) {
    const numbers = match[1]
      .split(',')
      .map((s) => Number(s.trim()))
      .filter((n) => Number.isFinite(n))
    const first = numbers[0]
    if (first === undefined || !indices.has(first)) continue

    if (match.index > cursor) {
      parts.push(text.slice(cursor, match.index))
    }
    parts.push(
      <button
        key={`cite-${match.index}`}
        type="button"
        onClick={() => onCitationTap(first)}
        className="text-foreground font-medium hover:underline"
      >
        {match[0]}
      </button>
    )
    cursor = match.index + match[0].length
  }
  if (cursor < text.length) parts.push(text.slice(cursor))

  return <div className="whitespace-pre-wrap">{parts}</div>
}
