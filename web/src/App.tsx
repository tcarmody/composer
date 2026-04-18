import { useQuery } from '@tanstack/react-query'
import { getHealth } from './lib/api'
import { Layout } from './components/Layout'

function HealthBadge() {
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['health'],
    queryFn: getHealth,
    refetchInterval: 10_000,
  })

  if (isLoading) {
    return <span className="text-sm text-muted-foreground">checking backend…</span>
  }
  if (isError) {
    return (
      <span className="text-sm text-red-600">
        backend unreachable: {(error as Error).message}
      </span>
    )
  }
  return (
    <div className="text-sm text-muted-foreground">
      <span className="text-green-600">●</span> backend {data!.status} · v{data!.version} ·
      schema v{data!.schema_version}
    </div>
  )
}

export default function App() {
  return (
    <Layout>
      <div className="space-y-4">
        <h2 className="text-2xl font-semibold">Workbench</h2>
        <p className="text-muted-foreground">
          Phase 0 skeleton. Promote something from DataPoints and it will appear here.
        </p>
        <HealthBadge />
      </div>
    </Layout>
  )
}
