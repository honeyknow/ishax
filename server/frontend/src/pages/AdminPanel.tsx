import { useEffect, useState } from 'react'
import { api } from '../api/client'
import { Shield, Users, Database, Cpu, HardDrive, MemoryStick, Trash2, Eye, RefreshCw, Activity } from 'lucide-react'

interface Tenant {
  id: string
  email: string
  db_filename: string
  created_at: number
  last_login: number | null
  is_active: number
  agent_count: number
  db_size_bytes: number
}

interface SystemStats {
  cpu: number
  ram: number
  disk: number
}

interface Props {
  /** Called when admin clicks "View Dashboard" for a tenant */
  onImpersonate: (tenantId: string, email: string) => void
}

function fmtBytes(b: number): string {
  if (b < 1024) return `${b} B`
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(1)} KB`
  if (b < 1024 * 1024 * 1024) return `${(b / 1024 / 1024).toFixed(1)} MB`
  return `${(b / 1024 / 1024 / 1024).toFixed(2)} GB`
}

function fmtDate(epoch: number | null): string {
  if (!epoch) return '—'
  return new Date(epoch * 1000).toLocaleString()
}

function UsageBar({ value, color }: { value: number; color: string }) {
  const pct = Math.min(100, Math.max(0, value))
  const danger = pct > 85
  const warn = pct > 65
  const barColor = danger ? '#ef4444' : warn ? '#f59e0b' : color
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
      <div style={{ flex: 1, height: 6, background: 'var(--bg-4)', borderRadius: 99, overflow: 'hidden' }}>
        <div style={{ width: `${pct}%`, height: '100%', background: barColor, borderRadius: 99, transition: 'width 0.5s' }} />
      </div>
      <span style={{ fontSize: 12, fontWeight: 700, color: barColor, minWidth: 36, textAlign: 'right' }}>{pct.toFixed(0)}%</span>
    </div>
  )
}

export default function AdminPanel({ onImpersonate }: Props) {
  const [tenants, setTenants] = useState<Tenant[]>([])
  const [sysStats, setSysStats] = useState<SystemStats | null>(null)
  const [loading, setLoading] = useState(true)
  const [purging, setPurging] = useState<string | null>(null)
  const [error, setError] = useState('')
  const [confirmPurge, setConfirmPurge] = useState<string | null>(null)

  const load = async () => {
    setLoading(true)
    setError('')
    try {
      const [tenantsRes, healthRes] = await Promise.all([
        api.adminGetTenants(),
        api.getHealth(),
      ])
      setTenants(tenantsRes)
      if (healthRes.system_stats) setSysStats(healthRes.system_stats)
    } catch (e: unknown) {
      setError('Failed to load admin data. Are you authenticated as admin?')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const handlePurge = async (tenantId: string) => {
    if (confirmPurge !== tenantId) { setConfirmPurge(tenantId); return }
    setPurging(tenantId)
    try {
      await api.adminPurgeTenant(tenantId)
      setTenants(prev => prev.filter(t => t.id !== tenantId))
    } catch {
      alert('Failed to purge tenant.')
    } finally {
      setPurging(null)
      setConfirmPurge(null)
    }
  }

  const totalAgents = tenants.reduce((s, t) => s + t.agent_count, 0)
  const totalDbSize = tenants.reduce((s, t) => s + t.db_size_bytes, 0)
  const activeTenants = tenants.filter(t => t.is_active).length

  return (
    <div style={{ padding: '20px 24px', overflowY: 'auto', height: '100%', display: 'flex', flexDirection: 'column', gap: 20 }}>

      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <Shield size={20} color="var(--accent)" />
          <div>
            <div style={{ fontSize: 18, fontWeight: 900, color: 'var(--text-1)' }}>Master Admin Panel</div>
            <div style={{ fontSize: 12, color: 'var(--text-3)' }}>God's Eye View — all tenants, all data</div>
          </div>
        </div>
        <button
          onClick={load}
          style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '6px 12px', background: 'var(--bg-3)', border: '1px solid var(--border)', borderRadius: 8, cursor: 'pointer', color: 'var(--text-2)', fontSize: 13 }}
        >
          <RefreshCw size={13} style={{ animation: loading ? 'spin 1s linear infinite' : 'none' }} />
          Refresh
        </button>
      </div>

      {error && (
        <div style={{ padding: '10px 14px', background: 'var(--crit-bg)', border: '1px solid rgba(204,0,0,0.2)', borderRadius: 8, color: 'var(--crit)', fontSize: 13 }}>
          {error}
        </div>
      )}

      {/* Summary cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 12 }}>
        <StatCard icon={<Users size={16} color="var(--accent)" />} label="Active Tenants" value={String(activeTenants)} sub={`${tenants.length} total`} />
        <StatCard icon={<Activity size={16} color="#22c55e" />} label="Total Agents" value={String(totalAgents)} sub="non-revoked" />
        <StatCard icon={<Database size={16} color="var(--high)" />} label="Total DB Size" value={fmtBytes(totalDbSize)} sub="all tenants combined" />
      </div>

      {/* Server Hardware Stats */}
      <div style={{ background: 'var(--bg-2)', border: '1px solid var(--border)', borderRadius: 12, padding: 16 }}>
        <div style={{ fontSize: 13, fontWeight: 700, color: 'var(--text-2)', marginBottom: 14, display: 'flex', alignItems: 'center', gap: 6 }}>
          <Cpu size={14} color="var(--text-3)" />
          Server Hardware Specs
        </div>
        {sysStats ? (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 14 }}>
            <HardwareStat icon={<Cpu size={13} />} label="CPU Usage" value={sysStats.cpu} />
            <HardwareStat icon={<MemoryStick size={13} />} label="RAM Usage" value={sysStats.ram} color="#a78bfa" />
            <HardwareStat icon={<HardDrive size={13} />} label="Disk Usage" value={sysStats.disk} color="#f59e0b" />
          </div>
        ) : (
          <div style={{ fontSize: 13, color: 'var(--text-3)', padding: '8px 0' }}>
            Hardware stats not available. The <code style={{ color: 'var(--accent)' }}>psutil</code> module must be installed on the server and the <code style={{ color: 'var(--accent)' }}>/health</code> endpoint must include <code>system_stats</code>.
          </div>
        )}
        <div style={{ marginTop: 12, paddingTop: 12, borderTop: '1px solid var(--border)', display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          <SpecBadge label="Max Tenants" value="~10–20" />
          <SpecBadge label="Min RAM Required" value="2 GB" />
          <SpecBadge label="Retention Policy" value="1–14 days" />
        </div>
      </div>

      {/* Tenants Table */}
      <div style={{ background: 'var(--bg-2)', border: '1px solid var(--border)', borderRadius: 12, overflow: 'hidden' }}>
        <div style={{ padding: '12px 16px', borderBottom: '1px solid var(--border)', fontSize: 13, fontWeight: 700, color: 'var(--text-2)', display: 'flex', alignItems: 'center', gap: 6 }}>
          <Users size={14} color="var(--text-3)" />
          Registered Tenants
        </div>
        {loading ? (
          <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-3)', fontSize: 13 }}>Loading...</div>
        ) : tenants.length === 0 ? (
          <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-3)', fontSize: 13 }}>No tenants registered yet.</div>
        ) : (
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
            <thead>
              <tr style={{ background: 'var(--bg-3)' }}>
                {['Email', 'Status', 'Agents', 'DB Size', 'Last Login', 'Actions'].map(h => (
                  <th key={h} style={{ padding: '8px 14px', textAlign: 'left', color: 'var(--text-3)', fontWeight: 600, fontSize: 11, letterSpacing: '0.5px', textTransform: 'uppercase' }}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {tenants.map((t, i) => (
                <tr
                  key={t.id}
                  style={{ borderTop: i === 0 ? 'none' : '1px solid var(--border)', background: 'transparent' }}
                >
                  <td style={{ padding: '10px 14px', color: 'var(--text-1)', fontWeight: 600, maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{t.email}</td>
                  <td style={{ padding: '10px 14px' }}>
                    <span style={{
                      padding: '2px 8px', borderRadius: 4, fontSize: 11, fontWeight: 700,
                      background: t.is_active ? 'rgba(34,197,94,0.1)' : 'rgba(239,68,68,0.1)',
                      color: t.is_active ? '#22c55e' : '#ef4444',
                    }}>
                      {t.is_active ? 'ACTIVE' : 'BANNED'}
                    </span>
                  </td>
                  <td style={{ padding: '10px 14px', color: 'var(--text-2)', fontWeight: 700 }}>{t.agent_count}</td>
                  <td style={{ padding: '10px 14px', color: 'var(--text-2)' }}>{fmtBytes(t.db_size_bytes)}</td>
                  <td style={{ padding: '10px 14px', color: 'var(--text-3)', fontSize: 12 }}>{fmtDate(t.last_login)}</td>
                  <td style={{ padding: '10px 14px' }}>
                    <div style={{ display: 'flex', gap: 6 }}>
                      {/* View Dashboard (Impersonate) */}
                      <button
                        onClick={() => onImpersonate(t.id, t.email)}
                        title="View their dashboard"
                        style={actionBtn('var(--accent)')}
                      >
                        <Eye size={13} />
                        View
                      </button>
                      {/* Export DB */}
                      <button
                        onClick={() => api.adminExportTenantDb(t.id)}
                        title="Download their raw SQLite DB file"
                        style={actionBtn('#22c55e')}
                      >
                        <Database size={13} />
                        Export DB
                      </button>
                      {/* Purge */}
                      <button
                        onClick={() => handlePurge(t.id)}
                        disabled={purging === t.id}
                        title={confirmPurge === t.id ? 'Click again to confirm — IRREVERSIBLE' : 'Permanently delete tenant and their data'}
                        style={actionBtn(confirmPurge === t.id ? '#ef4444' : '#e57373')}
                      >
                        <Trash2 size={13} />
                        {confirmPurge === t.id ? 'Confirm?' : 'Purge'}
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

function StatCard({ icon, label, value, sub }: { icon: React.ReactNode; label: string; value: string; sub: string }) {
  return (
    <div style={{ background: 'var(--bg-2)', border: '1px solid var(--border)', borderRadius: 10, padding: '14px 16px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
        {icon}
        <span style={{ fontSize: 11, color: 'var(--text-3)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '0.5px' }}>{label}</span>
      </div>
      <div style={{ fontSize: 24, fontWeight: 900, color: 'var(--text-1)', lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: 11, color: 'var(--text-3)', marginTop: 4 }}>{sub}</div>
    </div>
  )
}

function HardwareStat({ icon, label, value, color = '#22c55e' }: { icon: React.ReactNode; label: string; value: number; color?: string }) {
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginBottom: 6, color: 'var(--text-3)', fontSize: 12 }}>
        {icon}
        {label}
      </div>
      <UsageBar value={value} color={color} />
    </div>
  )
}

function SpecBadge({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '4px 0' }}>
      <span style={{ fontSize: 11, color: 'var(--text-3)' }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-2)' }}>{value}</span>
    </div>
  )
}

function actionBtn(color: string): React.CSSProperties {
  return {
    display: 'inline-flex', alignItems: 'center', gap: 4,
    padding: '4px 9px', borderRadius: 6, fontSize: 12, fontWeight: 600,
    background: `${color}18`, border: `1px solid ${color}40`,
    color, cursor: 'pointer',
  }
}
