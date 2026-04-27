import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { ArrowLeft } from 'lucide-react'
import {
  clearLLMKey,
  getLLMKeys,
  setLLMKeys,
  type LLMKeyStatus,
} from '../lib/api'

interface Props {
  onClose: () => void
}

interface KeyDef {
  name: string
  label: string
  placeholder: string
  description: string
}

const KEYS: KeyDef[] = [
  {
    name: 'anthropic',
    label: 'Anthropic',
    placeholder: 'sk-ant-…',
    description: 'Powers draft Assist, item summaries, and Ask chat.',
  },
  {
    name: 'openai',
    label: 'OpenAI',
    placeholder: 'sk-…',
    description: 'Optional. Reserved for OpenAI-backed features.',
  },
  {
    name: 'voyage',
    label: 'Voyage',
    placeholder: 'pa-…',
    description: 'Powers vector search embeddings.',
  },
]

export function Settings({ onClose }: Props) {
  const qc = useQueryClient()
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['llm-keys'],
    queryFn: getLLMKeys,
  })

  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const [feedback, setFeedback] = useState<{ message: string; ok: boolean } | null>(
    null
  )

  const setDraft = (name: string, value: string) =>
    setDrafts((d) => ({ ...d, [name]: value }))

  const saveMutation = useMutation({
    mutationFn: (name: string) =>
      setLLMKeys({ [name]: drafts[name] ?? '' }),
    onSuccess: (resp, name) => {
      qc.setQueryData(['llm-keys'], resp)
      setDrafts((d) => ({ ...d, [name]: '' }))
      setFeedback({ message: 'Saved.', ok: true })
    },
    onError: (err: Error) =>
      setFeedback({ message: err.message, ok: false }),
  })

  const clearMutation = useMutation({
    mutationFn: (name: string) => clearLLMKey(name),
    onSuccess: (resp) => {
      qc.setQueryData(['llm-keys'], resp)
      setFeedback({ message: 'Cleared.', ok: true })
    },
    onError: (err: Error) =>
      setFeedback({ message: err.message, ok: false }),
  })

  const working = saveMutation.isPending || clearMutation.isPending
  const pendingName =
    saveMutation.isPending
      ? saveMutation.variables
      : clearMutation.isPending
        ? clearMutation.variables
        : null

  return (
    <div className="flex-1 overflow-y-auto">
      <div className="max-w-2xl mx-auto px-6 py-8">
        <div className="flex items-center gap-3 mb-8">
          <button
            onClick={onClose}
            className="text-sm text-muted-foreground hover:text-foreground flex items-center gap-1"
          >
            <ArrowLeft size={14} />
            Back
          </button>
          <h2 className="text-xl font-semibold tracking-tight">Settings</h2>
        </div>

        <section className="space-y-4">
          <div>
            <h3 className="font-medium">LLM Keys</h3>
            <p className="text-xs text-muted-foreground mt-1">
              Stored on the backend at{' '}
              <code className="font-mono">data/secrets.json</code> with mode 0600.
              UI-set keys override environment variables.
            </p>
          </div>

          {isLoading && (
            <div className="text-sm text-muted-foreground">Loading…</div>
          )}
          {isError && (
            <div className="text-sm text-red-600">
              Failed to load: {(error as Error).message}
            </div>
          )}

          {data &&
            KEYS.map((k) => (
              <KeyRow
                key={k.name}
                def={k}
                status={data.keys[k.name]}
                draft={drafts[k.name] ?? ''}
                onDraft={(value) => setDraft(k.name, value)}
                onSave={() => {
                  setFeedback(null)
                  saveMutation.mutate(k.name)
                }}
                onClear={() => {
                  setFeedback(null)
                  clearMutation.mutate(k.name)
                }}
                pending={pendingName === k.name}
                disableAll={working}
              />
            ))}

          {feedback && (
            <div
              className={
                feedback.ok ? 'text-xs text-green-700' : 'text-xs text-red-600'
              }
            >
              {feedback.message}
            </div>
          )}
        </section>
      </div>
    </div>
  )
}

interface KeyRowProps {
  def: KeyDef
  status: LLMKeyStatus | undefined
  draft: string
  onDraft: (value: string) => void
  onSave: () => void
  onClear: () => void
  pending: boolean
  disableAll: boolean
}

function KeyRow({
  def,
  status,
  draft,
  onDraft,
  onSave,
  onClear,
  pending,
  disableAll,
}: KeyRowProps) {
  const statusLabel = !status
    ? 'Loading…'
    : !status.set
      ? 'Not configured'
      : status.source === 'file'
        ? 'Set via UI'
        : status.source === 'env'
          ? 'Set via environment'
          : 'Set'

  const statusColor = !status?.set ? 'text-orange-600' : 'text-green-700'

  return (
    <div className="border rounded-md p-4 space-y-3">
      <div className="flex items-center justify-between">
        <div>
          <div className="font-medium text-sm">{def.label}</div>
          <div className="text-xs text-muted-foreground mt-0.5">
            {def.description}
          </div>
        </div>
        <div className={`text-xs ${statusColor} shrink-0 ml-3`}>
          {statusLabel}
        </div>
      </div>
      <input
        type="password"
        autoComplete="off"
        spellCheck={false}
        placeholder={def.placeholder}
        value={draft}
        onChange={(e) => onDraft(e.target.value)}
        className="w-full text-sm border rounded-md px-3 py-1.5 bg-transparent focus:outline-none focus:ring-1 focus:ring-foreground/20"
      />
      <div className="flex items-center gap-2">
        <button
          onClick={onSave}
          disabled={!draft.trim() || disableAll}
          className="text-xs border px-3 py-1 rounded-md hover:bg-muted disabled:opacity-50"
        >
          {pending && draft.trim() ? 'Saving…' : 'Save'}
        </button>
        {status?.source === 'file' && (
          <button
            onClick={onClear}
            disabled={disableAll}
            className="text-xs border px-3 py-1 rounded-md hover:bg-muted text-red-600 disabled:opacity-50"
          >
            {pending && !draft.trim() ? 'Clearing…' : 'Clear'}
          </button>
        )}
      </div>
    </div>
  )
}
