import { useEffect, useState } from 'react'
import { Settings, Search, Shield, ChevronUp, ChevronDown, ExternalLink } from 'lucide-react'
import { api, type SigmaRule } from '../api/client'
import Button from '../components/Button'

function sevLabel(score: number): string {
  if (score >= 9) return 'Critical'
  if (score >= 7) return 'High'
  if (score >= 5) return 'Medium'
  return 'Low'
}

function sevClass(score: number): string {
  if (score >= 9) return 'crit'
  if (score >= 7) return 'high'
  if (score >= 5) return 'med'
  return 'low'
}

type SortKey = 'title' | 'severity' | 'logsource'
type SortDir = 'asc' | 'desc'

function Toggle({ enabled, onChange }: { enabled: boolean, onChange: (val: boolean) => void }) {
  return (
    <Button
      variant="ghost"
      onClick={() => onChange(!enabled)}
      title={enabled ? "Disable this rule" : "Enable this rule"}
      style={{
        width: 32, height: 18, borderRadius: 99,
        background: enabled ? 'var(--info)' : 'var(--border)',
        position: 'relative', cursor: 'pointer', transition: 'all 0.2s ease', padding: 0
      }}
    >
      <div style={{
        width: 14, height: 14, borderRadius: '50%', background: '#fff',
        position: 'absolute', top: 2, left: enabled ? 16 : 2, transition: 'all 0.2s ease',
        boxShadow: 'var(--shadow-sm)'
      }} />
    </Button>
  )
}

export default function RulesEngine() {
  const [rules, setRules]       = useState<SigmaRule[]>([])
  const [loading, setLoading]   = useState(true)
  const [search, setSearch]     = useState('')
  const [sortKey, setSortKey]   = useState<SortKey>('severity')
  const [sortDir, setSortDir]   = useState<SortDir>('desc')

  useEffect(() => {
    api.getRules()
      .then(d => setRules(d.rules ?? []))
      .catch(() => null)
      .finally(() => setLoading(false))
  }, [])

  const handleSort = (key: SortKey) => {
    if (sortKey === key) setSortDir(d => d === 'asc' ? 'desc' : 'asc')
    else { setSortKey(key); setSortDir('asc') }
  }

  const handleToggle = (ruleId: string, newState: boolean) => {
    setRules(prev => prev.map(r => r.rule_id === ruleId ? { ...r, enabled: newState } : r))
    api.toggleRule(ruleId, newState).catch(() => {
      // Revert on failure
      setRules(prev => prev.map(r => r.rule_id === ruleId ? { ...r, enabled: !newState } : r))
    })
  }

  const SortIcon = ({ k }: { k: SortKey }) => {
    if (sortKey !== k) return <ChevronUp size={10} style={{ opacity: 0.2 }} />
    return sortDir === 'asc'
      ? <ChevronUp size={10} style={{ opacity: 0.8 }} />
      : <ChevronDown size={10} style={{ opacity: 0.8 }} />
  }

  const enabledCount  = rules.filter(r => r.enabled !== false).length
  const disabledCount = rules.length - enabledCount

  const visibleRules = rules
    .filter(r =>
      r.title.toLowerCase().includes(search.toLowerCase()) ||
      (r.technique_ids ?? []).some(t => t.toLowerCase().includes(search.toLowerCase())) ||
      (r.logsource ?? '').toLowerCase().includes(search.toLowerCase())
    )
    .sort((a, b) => {
      let cmp = 0
      if (sortKey === 'title') cmp = a.title.localeCompare(b.title)
      if (sortKey === 'severity') cmp = a.severity - b.severity
      if (sortKey === 'logsource') cmp = (a.logsource ?? '').localeCompare(b.logsource ?? '')
      return sortDir === 'asc' ? cmp : -cmp
    })

  return (
    <div style={{
      flex: 1, display: 'flex', overflow: 'hidden',
      background: 'var(--bg-2)', padding: '16px'
    }}>
      <div style={{
        flex: 1, overflow: 'hidden', display: 'flex', flexDirection: 'column',
        background: 'var(--bg)', borderRadius: '12px', border: '1px solid var(--border)',
        boxShadow: 'var(--shadow)',
      }}>
        <div style={{
          padding: '14px 20px',
          borderBottom: '1px solid var(--border)',
          background: 'var(--bg)',
          display: 'flex', alignItems: 'center', gap: 12,
          flexShrink: 0,
        }}>
          <Settings size={15} color="var(--accent)" />
          <span style={{ fontSize: 14, fontWeight: 700, color: 'var(--text)' }}>Rules Engine</span>

          <span style={{
            background: 'var(--bg-3)', border: '1px solid var(--border)',
            borderRadius: 99, padding: '1px 8px', fontSize: 11, color: 'var(--text-3)',
          }}>
            {enabledCount} active
          </span>
          {disabledCount > 0 && (
            <span style={{
              background: 'var(--bg-3)', border: '1px solid var(--border)',
              borderRadius: 99, padding: '1px 8px', fontSize: 11, color: 'var(--text-3)',
            }}>
              {disabledCount} disabled
            </span>
          )}

          <div style={{ flex: 1 }} />

          <div style={{ position: 'relative' }}>
            <Search size={12} style={{
              position: 'absolute', left: 9, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-3)',
            }} />
            <input
              placeholder="Search rules..."
              value={search}
              onChange={e => setSearch(e.target.value)}
              style={{ paddingLeft: 28, paddingRight: 10, paddingTop: 6, paddingBottom: 6, fontSize: 12, width: 200 }}
            />
          </div>
        </div>

        <div className="scroll-y" style={{ flex: 1, background: 'var(--bg-2)' }}>
          {loading ? (
            <div style={{ display: 'flex', justifyContent: 'center', padding: 60 }}>
              <div className="spinner" />
            </div>
          ) : visibleRules.length === 0 ? (
            <div className="empty-state">
              <Shield size={40} />
              <h3>{search ? 'No rules match your search' : 'No rules loaded'}</h3>
              <p>Rules are loaded from the static Python detection engine.</p>
            </div>
          ) : (
            <div className="card" style={{ margin: 20, overflow: 'hidden' }}>
              <table style={{ tableLayout: 'fixed', width: '100%' }}>
                <thead>
                  <tr>
                    <th style={{ width: 66, paddingLeft: 20 }}>Status</th>
                    <th style={{ width: '30%' }}>
                      <Button 
                        variant="ghost" 
                        size="sm" 
                        onClick={() => handleSort('title')}
                        style={{ padding: '2px 6px', fontSize: 11, letterSpacing: '0.8px', textTransform: 'uppercase' }}
                      >
                        Rule Title <SortIcon k="title" />
                      </Button>
                    </th>
                    <th style={{ width: 100 }}>
                      <Button 
                        variant="ghost" 
                        size="sm" 
                        onClick={() => handleSort('severity')}
                        style={{ padding: '2px 6px', fontSize: 11, letterSpacing: '0.8px', textTransform: 'uppercase' }}
                      >
                        Severity <SortIcon k="severity" />
                      </Button>
                    </th>
                    <th style={{ width: 140 }}>MITRE Techniques</th>
                    <th style={{ width: 140 }}>
                      <Button 
                        variant="ghost" 
                        size="sm" 
                        onClick={() => handleSort('logsource')}
                        style={{ padding: '2px 6px', fontSize: 11, letterSpacing: '0.8px', textTransform: 'uppercase' }}
                      >
                        Log Source <SortIcon k="logsource" />
                      </Button>
                    </th>
                    <th>Tags</th>
                    <th style={{ width: 80, paddingRight: 20 }}>Type</th>
                  </tr>
                </thead>
                <tbody>
                  {visibleRules.map(rule => {
                    const isEnabled = rule.enabled !== false
                    return (
                      <tr key={rule.rule_id} style={{ opacity: isEnabled ? 1 : 0.45, transition: 'opacity 0.2s' }}>
                        <td style={{ paddingLeft: 20 }}>
                          <Toggle enabled={isEnabled} onChange={(val) => handleToggle(rule.rule_id, val)} />
                        </td>
                        <td>
                          <div style={{ fontWeight: 600, color: 'var(--text)', fontSize: 13, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', display: 'flex', alignItems: 'center', gap: 6 }} title={rule.title}>
                            {rule.title}
                            {rule.tags?.includes('custom.edr_enhanced') ? (
                              <span style={{ fontSize: 9, background: 'rgba(99, 102, 241, 0.1)', color: '#6366f1', padding: '2px 6px', borderRadius: 4, fontWeight: 700 }}>ENHANCED</span>
                            ) : (
                              <a href={`https://github.com/SigmaHQ/sigma/search?q=${rule.rule_id}`} target="_blank" rel="noreferrer" style={{ display: 'flex', alignItems: 'center', color: 'var(--text-3)' }} title="View Official Source on GitHub">
                                <ExternalLink size={12} />
                              </a>
                            )}
                          </div>
                          <div style={{ fontSize: 10, color: 'var(--text-3)', marginTop: 2, fontFamily: "'Courier New', monospace" }}>
                            {rule.rule_id}
                          </div>
                        </td>
                        <td>
                          <span className={`badge badge-${sevClass(rule.severity)}`}>
                            {sevLabel(rule.severity)}
                          </span>
                        </td>
                        <td>
                          <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                            {(rule.technique_ids ?? []).slice(0, 3).map(t => <span key={t} className="tag">{t}</span>)}
                            {(rule.technique_ids ?? []).length === 0 && (
                              <span style={{ fontSize: 11, color: 'var(--text-3)' }}>-</span>
                            )}
                          </div>
                        </td>
                        <td>
                          <span style={{ fontSize: 12, color: 'var(--text-2)', fontFamily: "'Courier New', monospace" }}>
                            {rule.logsource || '-'}
                          </span>
                        </td>
                        <td>
                          <div style={{ display: 'flex', gap: 3, flexWrap: 'wrap' }}>
                            {(rule.tags ?? []).filter(t => t !== 'custom.edr_enhanced').slice(0, 2).map(tag => (
                              <span key={tag} className="tag" style={{ fontSize: 10 }}>
                                {tag.replace('attack.', '')}
                              </span>
                            ))}
                          </div>
                        </td>
                        <td style={{ paddingRight: 20 }}>
                          <span style={{ fontSize: 10, color: 'var(--text-3)' }}>system</span>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
