import { useQuery } from '@tanstack/react-query'
import { getHealth } from './lib/api'
import { Library } from './components/Library'

function HealthBadge() {
  const { data, isError } = useQuery({
    queryKey: ['health'],
    queryFn: getHealth,
    refetchInterval: 10_000,
  })

  if (isError) {
    return <span className="text-red-600">● backend unreachable</span>
  }
  if (!data) {
    return <span>checking…</span>
  }
  return (
    <span>
      <span className="text-green-600">●</span> {data.status} · v{data.version}
    </span>
  )
}

export default function App() {
  return (
    <div className="h-screen flex flex-col">
      <header className="border-b shrink-0">
        <div className="px-6 py-3 flex items-center justify-between">
          <div className="flex items-baseline gap-6">
            <h1 className="text-lg font-semibold tracking-tight">Composer</h1>
            <nav className="flex gap-4 text-sm text-muted-foreground">
              <span className="text-foreground">Library</span>
              <span>Ask</span>
              <span>Arrange</span>
              <span>Publish</span>
            </nav>
          </div>
          <div className="text-xs text-muted-foreground">
            <HealthBadge />
          </div>
        </div>
      </header>
      <Library />
    </div>
  )
}
