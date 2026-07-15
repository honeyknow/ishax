import { useEffect, useState } from 'react'
import { Activity, Bell, Database, GitBranch, Settings, Terminal, Sparkles, Shield } from 'lucide-react'
import { api, type HealthStatus, type Stats } from '../api/client'
import type { View } from '../App'
import Button from './Button'
import AccountMenu from './AccountMenu'

interface UserIdentity {
  email: string
  role: 'admin' | 'user'
  tenant: Record<string, unknown> | null
}

interface Props {
  view: View
  onViewChange: (v: View) => void
  onToggleAI?: () => void
  user?: UserIdentity | null
  onSignOut?: () => void
  isAdmin?: boolean
  impersonating?: string | null
  onStopImpersonating?: () => void
}

const NAV: { id: View; label: string; icon: typeof Activity; adminOnly?: boolean }[] = [
  { id: 'overview',  label: 'Overview',     icon: Activity },
  { id: 'hunt',      label: 'Threat Hunt',  icon: GitBranch },
  { id: 'firehose',  label: 'Firehose',     icon: Terminal },
  { id: 'rules',     label: 'Rules Engine', icon: Settings },
  { id: 'admin',     label: 'Admin',        icon: Shield, adminOnly: true },
]

function statusTone(status?: HealthStatus['status']): string {
  if (status === 'healthy')  return '#22C55E'
  if (status === 'degraded') return 'var(--high)'
  return 'var(--text-3)'
}

function statusLabel(status?: HealthStatus['status']): string {
  if (!status) return 'Unknown'
  return status.replace('_', ' ').toUpperCase()
}

export default function Topbar({
  view, onViewChange, onToggleAI,
  user, onSignOut, isAdmin,
  impersonating, onStopImpersonating,
}: Props) {
  const [stats,  setStats]  = useState<Stats | null>(null)
  const [health, setHealth] = useState<HealthStatus | null>(null)

  useEffect(() => {
    const load = async () => {
      try {
        const [s, h] = await Promise.all([api.getStats(), api.getHealth()])
        setStats(s)
        setHealth(h)
      } catch {
        // backend may still be starting
      }
    }
    load()
    const t = setInterval(load, 15000)
    return () => clearInterval(t)
  }, [])

  const rc = stats?.row_counts ?? {}
  const totalAlerts = rc.alerts ?? 0
  const totalEvents = (rc.process_events ?? 0) + (rc.network_events ?? 0) + (rc.file_events ?? 0) + (rc.registry_events ?? 0) + (rc.amsi_events ?? 0)

  // Filter nav tabs based on role
  const visibleNav = NAV.filter(n => !n.adminOnly || isAdmin)

  return (
    <div className="topbar">
      {/* Logo */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        paddingRight: 20, borderRight: '1px solid var(--border)', marginRight: 8, minWidth: 0,
      }}>
        <div style={{
          width: 30, height: 30, borderRadius: 6, background: 'var(--accent)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          <span style={{ color: '#fff', fontSize: 11, fontWeight: 900, letterSpacing: '0.5px' }}>IX</span>
        </div>
        <div style={{ minWidth: 0 }}>
          <div style={{ fontSize: 14, fontWeight: 900, letterSpacing: '1px', color: 'var(--accent)', lineHeight: 1 }}>
            ISHA-X
          </div>
          <div style={{ fontSize: 9, color: 'var(--text-3)', letterSpacing: '2px', lineHeight: 1, marginTop: 2 }}>
            EDR
          </div>
        </div>
      </div>

      {/* Navigation */}
      <nav style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 8px' }}>
        {visibleNav.map(n => {
          const active = view === n.id
          const adminTab = n.id === 'admin'
          return (
            <Button
              key={n.id}
              variant="ghost"
              onClick={() => onViewChange(n.id)}
              icon={<n.icon size={16} />}
              active={active}
              style={{
                padding: '8px 16px',
                borderRadius: 8,
                fontSize: 13,
                fontWeight: 600,
                background: active
                  ? (adminTab ? 'rgba(99,102,241,0.2)' : 'var(--bg-4)')
                  : 'transparent',
                color: active
                  ? (adminTab ? 'var(--accent)' : '#fff')
                  : (adminTab ? 'var(--accent)' : 'var(--text-2)'),
                border: adminTab ? `1px solid ${active ? 'rgba(99,102,241,0.4)' : 'rgba(99,102,241,0.15)'}` : 'none',
                transition: 'all 0.15s ease',
              }}
            >
              {n.label}
            </Button>
          )
        })}
      </nav>

      <div style={{ flex: 1 }} />

      {/* Right side: status pills + AccountMenu */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>

        {/* Health status */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '4px 10px',
          background: health?.status === 'healthy' ? 'rgba(34,197,94,0.12)' : health?.status === 'degraded' ? 'var(--high-bg)' : 'var(--bg-3)',
          border: `1px solid ${health?.status === 'healthy' ? 'rgba(34,197,94,0.25)' : health?.status === 'degraded' ? 'rgba(245,158,11,0.25)' : 'var(--border)'}`,
          borderRadius: 99,
        }}>
          <div style={{
            width: 6, height: 6, borderRadius: '50%',
            background: statusTone(health?.status),
            animation: health?.status === 'healthy' ? 'pulse 2s infinite' : 'none',
          }} />
          <span style={{ fontSize: 12, fontWeight: 700, color: health?.status === 'healthy' ? '#22C55E' : health?.status === 'degraded' ? 'var(--high)' : 'var(--text-3)' }}>
            {statusLabel(health?.status)}
          </span>
          <span style={{ fontSize: 12, color: 'var(--text-3)' }}>
            {health?.lag_seconds != null ? `${health.lag_seconds}s lag` : 'lag n/a'}
          </span>
        </div>

        {/* Alert count pill */}
        {totalAlerts > 0 && (
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6,
            padding: '4px 10px',
            background: 'var(--crit-bg)', border: '1px solid rgba(204,0,0,0.2)', borderRadius: 99,
          }}>
            <Bell size={11} color="var(--crit)" />
            <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--crit)' }}>
              {totalAlerts.toLocaleString()} alerts
            </span>
          </div>
        )}

        {/* Events count pill */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          padding: '4px 10px',
          background: 'var(--bg-3)', border: '1px solid var(--border)', borderRadius: 99,
        }}>
          <Database size={11} color="var(--text-3)" />
          <span style={{ fontSize: 12, color: 'var(--text-3)' }}>Events</span>
          <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-2)' }}>
            {totalEvents.toLocaleString()}
          </span>
        </div>

        {/* Ask AI button */}
        {onToggleAI && (
          <Button
            variant="custom"
            customColor="var(--accent)"
            onClick={onToggleAI}
            style={{ padding: '6px 12px', borderRadius: 99, fontSize: 12, marginLeft: 4 }}
            icon={<Sparkles size={14} />}
          >
            Ask AI
          </Button>
        )}

        {/* Account Menu — shown only when user is loaded */}
        {user && (
          <AccountMenu
            email={user.email}
            role={user.role}
            onSignOut={onSignOut}
          />
        )}
      </div>
    </div>
  )
}
