import { useEffect, useState, useCallback } from 'react'
import { Shield, AlertTriangle, RefreshCw } from 'lucide-react'
import { api, type Alert } from '../api/client'
import Button from './Button'

interface Props {
  selectedId: string | null
  onSelect: (alert: Alert) => void
}

function sevClass(score: number): string {
  if (score >= 9) return 'crit'
  if (score >= 7) return 'high'
  if (score >= 5) return 'med'
  return 'low'
}

function sevLabel(score: number): string {
  if (score >= 9) return 'Critical'
  if (score >= 7) return 'High'
  if (score >= 5) return 'Medium'
  return 'Low'
}

function relTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime()
  const mins = Math.floor(diff / 60000)
  if (mins < 1) return 'just now'
  if (mins < 60) return `${mins}m ago`
  if (mins < 1440) return `${Math.floor(mins / 60)}h ago`
  return `${Math.floor(mins / 1440)}d ago`
}

function alertImage(alert: Alert): string | null {
  const img = alert.process_chain?.self?.image
  if (typeof img !== 'string' || !img) return null
  return img.split(/[/\\]/).pop() ?? null
}

function alertCmdLine(alert: Alert): string | null {
  const cmd = alert.process_chain?.self?.command_line
  if (typeof cmd !== 'string' || !cmd) return null
  return cmd.length > 60 ? `${cmd.slice(0, 60)}...` : cmd
}

function alertMeta(alert: Alert): string {
  return [
    alert.host_id,
    alert.source_layer,
    alert.event_id ? `EID ${alert.event_id}` : null,
  ].filter(Boolean).join(' | ')
}

export default function AlertQueue({ selectedId, onSelect }: Props) {
  const [alerts, setAlerts] = useState<Alert[]>([])
  const [totalAlerts, setTotalAlerts] = useState<number>(0)
  const [loading, setLoading] = useState(true)
  const [lastRefresh, setLastRefresh] = useState<Date>(new Date())
  const [limit, setLimit] = useState<number>(100)

  const [copiedId, setCopiedId] = useState<string | null>(null)

  const load = useCallback(async () => {
    try {
      const data = await api.getAlerts({ limit })
      setAlerts(data.alerts)
      setTotalAlerts(data.total)
      setLastRefresh(new Date())
    } catch {
      // Backend may still be starting.
    } finally {
      setLoading(false)
    }
  }, [limit])

  useEffect(() => { load() }, [load])
  useEffect(() => {
    const t = setInterval(load, 2000)
    return () => clearInterval(t)
  }, [load])

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: 'var(--bg)', overflow: 'hidden' }}>
      <div style={{
        padding: '12px 14px',
        borderBottom: '1px solid var(--border)',
        display: 'flex', alignItems: 'center', gap: 7,
        flexShrink: 0,
      }}>
        <AlertTriangle size={14} color="var(--crit)" />
        <span style={{ fontSize: 13, fontWeight: 700, color: 'var(--text)' }}>Live Alerts</span>
        <span style={{
          background: totalAlerts > 0 ? 'var(--crit-bg)' : 'var(--bg-3)',
          border: `1px solid ${totalAlerts > 0 ? 'rgba(204,0,0,0.2)' : 'var(--border)'}`,
          color: totalAlerts > 0 ? 'var(--crit)' : 'var(--text-3)',
          borderRadius: 99, padding: '1px 7px', fontSize: 11, fontWeight: 600,
        }}>{totalAlerts}</span>
      </div>


      <div className="scroll-y" style={{ flex: 1 }}>
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 32 }}>
            <div className="spinner" />
          </div>
        ) : alerts.length === 0 ? (
          <div className="empty-state">
            <Shield size={36} />
            <h3>No alerts detected</h3>
            <p>The system is monitoring real telemetry. Alerts will appear here when a rule fires.</p>
          </div>
        ) : (
          alerts.map(alert => {
            const sev = sevClass(alert.severity_score)
            const selected = alert.alert_id === selectedId
            const image = alertImage(alert)
            const cmd = alertCmdLine(alert)
            return (
              <div
                key={alert.alert_id}
                id={`alert-${alert.alert_id}`}
                onClick={() => onSelect(alert)}
                style={{
                  padding: '10px 14px',
                  borderBottom: '1px solid var(--border)',
                  cursor: 'pointer',
                  background: selected ? 'var(--bg-3)' : 'transparent',
                  borderLeft: `3px solid var(--${sev})`,
                  transition: 'all 0.12s',
                  position: 'relative',
                  opacity: alert.suppressed ? 0.55 : 1,
                }}
              >
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 8 }}>
                  <div style={{ paddingTop: 4, flexShrink: 0 }}>
                    <div className={`sev-dot sev-dot-${sev}`} />
                  </div>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <p style={{ fontSize: 12, fontWeight: 600, color: 'var(--text)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', marginBottom: 4 }}>
                      {alert.rule_name}
                    </p>
                    {image && (
                      <p style={{ fontSize: 11, color: 'var(--text-2)', marginBottom: 3, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontFamily: "'Courier New', monospace" }}>
                        {image}
                      </p>
                    )}
                    {cmd && (
                      <p style={{ fontSize: 10, color: 'var(--text-3)', marginBottom: 4, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', fontFamily: "'Courier New', monospace" }}>
                        {cmd}
                      </p>
                    )}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 5, flexWrap: 'wrap' }}>
                      <span className={`badge badge-${sev}`}>{sevLabel(alert.severity_score)}</span>
                      <span 
                        onClick={(e) => {
                          e.stopPropagation()
                          navigator.clipboard.writeText(alert.alert_id)
                          setCopiedId(alert.alert_id)
                          setTimeout(() => setCopiedId(null), 2000)
                        }}
                        title={`Click to copy Alert ID: ${alert.alert_id}`} 
                        style={{ 
                          fontSize: 10, fontWeight: 700, padding: '1px 6px', borderRadius: 4, 
                          background: copiedId === alert.alert_id ? 'var(--info)' : 'var(--bg-3)', 
                          color: copiedId === alert.alert_id ? '#fff' : 'var(--text-2)', 
                          border: '1px solid var(--border)', fontFamily: 'monospace', cursor: 'pointer',
                          transition: 'all 0.2s ease'
                        }}
                      >
                        {copiedId === alert.alert_id ? 'Copied ✓' : `Alert ID ${alert.alert_id}`}
                      </span>
                      {alert.technique_id && <span className="tag">{alert.technique_id}</span>}
                      {alert.suppressed && (
                        <span style={{ fontSize: 9, fontWeight: 700, padding: '1px 5px', borderRadius: 3, background: 'var(--bg-3)', color: 'var(--text-3)', border: '1px solid var(--border)', textTransform: 'uppercase' }}>
                          Suppressed
                        </span>
                      )}
                    </div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 5, gap: 8 }}>
                      <span style={{ fontSize: 10, color: 'var(--text-3)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                        {alertMeta(alert)}
                      </span>
                      <span style={{ fontSize: 10, color: 'var(--text-3)', flexShrink: 0 }}>
                        {relTime(alert.created_at)}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            )
          })
        )}
      </div>

      <div style={{
        padding: '8px 14px',
        borderTop: '1px solid var(--border)',
        background: 'var(--bg-2)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 6,
        flexShrink: 0
      }}>
        <span style={{ fontSize: 10, color: 'var(--text-3)' }}>Show:</span>
        {[10, 20, 50, 100].map(val => (
          <button
            key={val}
            onClick={() => setLimit(val)}
            style={{
              background: limit === val ? 'var(--bg-3)' : 'transparent',
              color: limit === val ? 'var(--text)' : 'var(--text-3)',
              border: `1px solid ${limit === val ? 'var(--border)' : 'transparent'}`,
              borderRadius: 4,
              padding: '2px 6px',
              fontSize: 10,
              fontWeight: limit === val ? 600 : 500,
              cursor: 'pointer',
              transition: 'all 0.15s ease'
            }}
          >
            {val}
          </button>
        ))}
        <input
          type="number"
          value={limit}
          onChange={e => setLimit(Math.max(1, parseInt(e.target.value) || 100))}
          style={{
            width: 44,
            background: 'transparent',
            color: 'var(--text)',
            border: '1px solid var(--border)',
            borderRadius: 4,
            padding: '1px 4px',
            fontSize: 10,
            textAlign: 'center',
            outline: 'none'
          }}
          title="Custom Limit"
        />
      </div>
    </div>
  )
}
