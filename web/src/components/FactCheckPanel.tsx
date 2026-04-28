import { useEffect, useRef, useState } from 'react'
import {
  streamFactCheck,
  type FactCheckExtractedClaim,
  type FactCheckSource,
  type FactCheckVerdict,
} from '../lib/api'
import { cn } from '../lib/utils'

interface ClaimState extends FactCheckExtractedClaim {
  status: 'pending' | 'verified' | 'failed'
  verdict?: FactCheckVerdict
  explanation?: string
  suggested_correction?: string | null
  sources?: FactCheckSource[]
  error?: string
}

interface Props {
  draftId: string
  selection: string | null
  onClose: () => void
  onLocate: (offset: number, length: number) => void
}

export function FactCheckPanel({
  draftId,
  selection,
  onClose,
  onLocate,
}: Props) {
  const [claims, setClaims] = useState<ClaimState[] | null>(null)
  const [phase, setPhase] = useState<'extracting' | 'verifying' | 'done' | 'error'>(
    'extracting'
  )
  const [topError, setTopError] = useState<string | null>(null)
  const abortRef = useRef<AbortController | null>(null)

  useEffect(() => {
    const controller = new AbortController()
    abortRef.current = controller
    let cancelled = false

    const run = async () => {
      try {
        for await (const ev of streamFactCheck({
          draftId,
          selection,
          signal: controller.signal,
        })) {
          if (cancelled) break
          if (ev.type === 'extracted') {
            setClaims(
              ev.claims.map((c) => ({ ...c, status: 'pending' as const }))
            )
            setPhase('verifying')
          } else if (ev.type === 'verdict') {
            setClaims((prev) =>
              prev
                ? prev.map((c) =>
                    c.id === ev.claim_id
                      ? {
                          ...c,
                          status: 'verified' as const,
                          verdict: ev.verdict,
                          explanation: ev.explanation,
                          suggested_correction: ev.suggested_correction,
                          sources: ev.sources,
                        }
                      : c
                  )
                : prev
            )
          } else if (ev.type === 'error') {
            if (ev.claim_id) {
              setClaims((prev) =>
                prev
                  ? prev.map((c) =>
                      c.id === ev.claim_id
                        ? { ...c, status: 'failed' as const, error: ev.message }
                        : c
                    )
                  : prev
              )
            } else {
              setTopError(ev.message)
              setPhase('error')
            }
          } else if (ev.type === 'done') {
            setPhase('done')
          }
        }
      } catch (e) {
        if (cancelled) return
        if ((e as Error).name === 'AbortError') return
        setTopError((e as Error).message)
        setPhase('error')
      }
    }
    run()
    return () => {
      cancelled = true
      controller.abort()
    }
  }, [draftId, selection])

  const headerLabel =
    phase === 'extracting'
      ? 'Reading the passage…'
      : phase === 'verifying'
        ? `Verifying ${claims?.filter((c) => c.status === 'pending').length ?? 0} of ${claims?.length ?? 0}`
        : phase === 'error'
          ? 'Fact-check failed'
          : `Done — ${claims?.length ?? 0} claim${claims?.length === 1 ? '' : 's'}`

  return (
    <aside className="w-96 shrink-0 border-l flex flex-col h-full bg-background">
      <header className="px-4 py-3 border-b flex items-center justify-between gap-2">
        <div className="min-w-0">
          <div className="text-sm font-semibold">Fact-check</div>
          <div className="text-xs text-muted-foreground truncate">
            {selection ? 'selected passage' : 'whole draft'} · {headerLabel}
          </div>
        </div>
        <button
          onClick={onClose}
          className="text-xs border px-2 py-1 rounded-md hover:bg-muted"
          aria-label="Close fact-check panel"
        >
          ✕
        </button>
      </header>
      <div className="flex-1 overflow-y-auto p-3 space-y-2">
        {topError && (
          <div className="text-xs text-red-600 border border-red-200 rounded-md p-3">
            {topError}
          </div>
        )}
        {!claims && !topError && (
          <div className="text-xs text-muted-foreground p-3">
            Looking for verifiable claims…
          </div>
        )}
        {claims?.length === 0 && phase === 'done' && (
          <div className="text-xs text-muted-foreground p-3">
            No verifiable claims found in this passage.
          </div>
        )}
        {claims?.map((c) => (
          <ClaimCard key={c.id} claim={c} onLocate={onLocate} />
        ))}
      </div>
    </aside>
  )
}

function ClaimCard({
  claim,
  onLocate,
}: {
  claim: ClaimState
  onLocate: (offset: number, length: number) => void
}) {
  const locatable =
    claim.offset !== null && claim.length !== null && claim.length !== undefined
  const verdict = claim.verdict
  const tone = verdictTone(claim.status, verdict)
  return (
    <article className={cn('border rounded-md p-3 text-sm space-y-2', tone.border)}>
      <div className="flex items-start gap-2">
        <VerdictBadge status={claim.status} verdict={verdict} />
        <button
          disabled={!locatable}
          onClick={() =>
            locatable && onLocate(claim.offset as number, claim.length as number)
          }
          className={cn(
            'flex-1 text-left leading-snug',
            locatable
              ? 'hover:underline cursor-pointer'
              : 'cursor-default text-muted-foreground'
          )}
          title={locatable ? 'Jump to claim in draft' : 'Could not locate in draft'}
        >
          “{claim.claim}”
        </button>
      </div>
      {claim.status === 'pending' && (
        <div className="text-xs text-muted-foreground">Searching the web…</div>
      )}
      {claim.status === 'failed' && (
        <div className="text-xs text-red-600">
          {claim.error || 'Verification failed.'}
        </div>
      )}
      {claim.status === 'verified' && claim.explanation && (
        <p className="text-xs text-muted-foreground leading-relaxed">
          {claim.explanation}
        </p>
      )}
      {claim.status === 'verified' && claim.suggested_correction && (
        <div className="text-xs border-l-2 border-amber-400 pl-2 py-1">
          <div className="font-medium text-amber-700">Suggested correction</div>
          <div className="text-foreground">{claim.suggested_correction}</div>
        </div>
      )}
      {claim.sources && claim.sources.length > 0 && (
        <ul className="text-xs space-y-1 pt-1">
          {claim.sources.slice(0, 4).map((s, i) => (
            <li key={i} className="leading-snug">
              <a
                href={s.url}
                target="_blank"
                rel="noreferrer"
                className="text-blue-600 hover:underline"
              >
                {s.title}
              </a>
              {s.snippet && (
                <div className="text-muted-foreground line-clamp-2">
                  {s.snippet}
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
    </article>
  )
}

function VerdictBadge({
  status,
  verdict,
}: {
  status: ClaimState['status']
  verdict: FactCheckVerdict | undefined
}) {
  if (status === 'pending') {
    return (
      <span className="text-base mt-0.5" aria-label="Verifying">
        ⋯
      </span>
    )
  }
  if (status === 'failed') {
    return (
      <span className="text-base mt-0.5" aria-label="Failed" title="Failed">
        ⚠︎
      </span>
    )
  }
  const map: Record<FactCheckVerdict, { label: string; symbol: string }> = {
    supported: { label: 'Supported', symbol: '✓' },
    contradicted: { label: 'Contradicted', symbol: '✗' },
    unverified: { label: 'Unverified', symbol: '?' },
    needs_context: { label: 'Needs context', symbol: '!' },
  }
  const v = verdict ? map[verdict] : map.unverified
  return (
    <span
      className={cn(
        'text-xs font-medium px-1.5 py-0.5 rounded mt-0.5 shrink-0',
        verdictPillTone(verdict)
      )}
      title={v.label}
    >
      {v.symbol}
    </span>
  )
}

function verdictTone(
  status: ClaimState['status'],
  verdict: FactCheckVerdict | undefined
): { border: string } {
  if (status === 'pending') return { border: 'border-border' }
  if (status === 'failed') return { border: 'border-red-200' }
  switch (verdict) {
    case 'supported':
      return { border: 'border-green-200' }
    case 'contradicted':
      return { border: 'border-red-300' }
    case 'needs_context':
      return { border: 'border-amber-200' }
    default:
      return { border: 'border-border' }
  }
}

function verdictPillTone(v: FactCheckVerdict | undefined): string {
  switch (v) {
    case 'supported':
      return 'bg-green-100 text-green-800'
    case 'contradicted':
      return 'bg-red-100 text-red-800'
    case 'needs_context':
      return 'bg-amber-100 text-amber-800'
    default:
      return 'bg-muted text-muted-foreground'
  }
}
