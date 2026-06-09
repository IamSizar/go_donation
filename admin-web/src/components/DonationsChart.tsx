import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

type Point = {
  date: string
  completed_amount: string
  pending_amount: string
  count: number
}

type Props = {
  data: Point[]
  loading?: boolean
}

export default function DonationsChart({ data, loading }: Props) {
  if (loading) return <div className="muted">Loading chart…</div>
  if (data.length === 0) return <div className="muted">No data.</div>

  const points = data.map((p) => ({
    date: p.date.slice(5), // MM-DD
    completed: parseFloat(p.completed_amount) || 0,
    pending: parseFloat(p.pending_amount) || 0,
  }))

  return (
    <div style={{ width: '100%', height: 220 }}>
      <ResponsiveContainer>
        <AreaChart data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="gradCompleted" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#10b981" stopOpacity={0.6} />
              <stop offset="100%" stopColor="#10b981" stopOpacity={0.05} />
            </linearGradient>
            <linearGradient id="gradPending" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#6366f1" stopOpacity={0.5} />
              <stop offset="100%" stopColor="#6366f1" stopOpacity={0.05} />
            </linearGradient>
          </defs>
          <CartesianGrid stroke="#2a2d3a" strokeDasharray="3 3" />
          <XAxis dataKey="date" stroke="#9ca3af" tickLine={false} />
          <YAxis stroke="#9ca3af" tickLine={false} width={48} />
          <Tooltip
            contentStyle={{
              background: '#161821',
              border: '1px solid #2a2d3a',
              borderRadius: 8,
            }}
            labelStyle={{ color: '#fff' }}
            formatter={(v) => (typeof v === 'number' ? v.toLocaleString() : String(v))}
          />
          <Area
            type="monotone"
            dataKey="completed"
            stroke="#10b981"
            fill="url(#gradCompleted)"
            strokeWidth={2}
            name="Completed"
          />
          <Area
            type="monotone"
            dataKey="pending"
            stroke="#6366f1"
            fill="url(#gradPending)"
            strokeWidth={2}
            name="Pending"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}
