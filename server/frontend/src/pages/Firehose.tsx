import { useEffect, useRef, useState, useCallback } from 'react'
import { Terminal, Pause, Play, Trash2, Download, Filter, AlignJustify, Code } from 'lucide-react'
import { api, type TimelineEvent, type RegisteredEndpoint } from '../api/client'
import Button from '../components/Button'

const EVENT_COLORS: Record<string, string> = {
  process:   '#F97316',      // Sharp Orange
  network:   '#3B82F6',      // Blue
  file:      '#EAB308',      // Bright Yellow
  registry:  '#14B8A6',      // Teal
  amsi:      '#EC4899',      // Pink
  alert:     '#EF4444',      // Red (Critical)
  auth:      '#06B6D4',      // Cyan
  system:    '#A855F7',      // Purple
  default:   'var(--text-3)',
}

const ALL_EVENT_TYPES = ['process', 'network', 'file', 'registry', 'amsi', 'alert', 'auth', 'system']
const HOURS_OPTIONS   = [1, 2, 6, 12, 24, 48]

function eventColor(type: string): string {
  return EVENT_COLORS[type] ?? EVENT_COLORS.default
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

function sevClass(score: number | undefined): string {
  if (score === undefined) return 'crit' // fallback for old alerts
  if (score >= 9) return 'crit'
  if (score >= 7) return 'high'
  if (score >= 5) return 'med'
  return 'low'
}

export default function Firehose() {
  const [events, setEvents]         = useState<TimelineEvent[]>([])
  const [hosts, setHosts]           = useState<RegisteredEndpoint[]>([])

  const [selectedHost, setHost]     = useState<string>('all')
  const [selectedTypes, setTypes]   = useState<Set<string>>(new Set(ALL_EVENT_TYPES))
  const [searchText, setSearch]     = useState('')
  const [hours, setHours]           = useState(2)
  const [paused, setPaused]         = useState(false)
  const [loading, setLoading]       = useState(true)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [viewMode, setViewMode]     = useState<'table' | 'raw'>('table')

  const formatRawJson = (jsonStr: string) => {
    try { return JSON.stringify(JSON.parse(jsonStr), null, 2) }
    catch { return jsonStr }
  }
  const bottomRef = useRef<HTMLDivElement>(null)
  const containerRef = useRef<HTMLDivElement>(null)

  // Load host list once
  useEffect(() => {
    api.getHosts().then(d => setHosts(d.hosts ?? [])).catch(() => null)
  }, [])

  const loadEvents = useCallback(async () => {
    if (paused) {
      setLoading(false)
      return
    }
    try {
      if (selectedHost === 'all') {
        const data = await api.getTimeline({ host_id: 'all', hours })
        const sorted = [...data.events].sort((a, b) =>
          new Date(a.event_timestamp).getTime() - new Date(b.event_timestamp).getTime()
        )
        setEvents(sorted)
      } else {
        const data = await api.getTimeline({ host_id: selectedHost, hours })
        const sorted = [...data.events].sort((a, b) =>
          new Date(a.event_timestamp).getTime() - new Date(b.event_timestamp).getTime()
        )
        setEvents(sorted)
      }
    } catch {
      // backend not ready
    } finally {
      setLoading(false)
    }
  }, [selectedHost, hours, paused])

  useEffect(() => {
    setLoading(true)
    loadEvents()
    const t = setInterval(loadEvents, 5000)
    return () => clearInterval(t)
  }, [loadEvents])

  // Auto-scroll to bottom
  useEffect(() => {
    if (!paused) {
      bottomRef.current?.scrollIntoView({ behavior: 'smooth' })
    }
  }, [events, paused])

  const toggleType = (t: string) => {
    setTypes(prev => {
      const next = new Set(prev)
      if (next.has(t)) next.delete(t)
      else next.add(t)
      return next
    })
  }

  const filtered = events.filter(e =>
    selectedTypes.has(e.event_type) &&
    (searchText === '' || e.label.toLowerCase().includes(searchText.toLowerCase()) || e.event_type.toLowerCase().includes(searchText.toLowerCase()))
  )

  const exportCSV = () => {
    const csv = ['timestamp,type,label,id',
      ...filtered.map(e => `"${e.event_timestamp}","${e.event_type}","${e.label.replace(/"/g, '""')}","${e.id}"`)
    ].join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a'); a.href = url; a.download = 'firehose_export.csv'; a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'var(--bg-2)', overflow: 'hidden' }}>
      {/* Unified Toolbar */}
      <div style={{
        display: 'flex', flexDirection: 'column', gap: 12,
        padding: '12px 20px',
        borderBottom: '1px solid var(--border)',
        background: 'var(--bg-2)',
        flexShrink: 0,
      }}>
        {/* Top Row */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16 }}>
          {/* Left: Basic Filters */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <Filter size={13} color="var(--text-3)" />
              <span style={{ fontSize: 12, fontWeight: 700, color: 'var(--text-2)' }}>Filters</span>
            </div>
            <select
              value={selectedHost}
              onChange={e => setHost(e.target.value)}
              style={{ padding: '5px 10px', fontSize: 12, minWidth: 140 }}
            >
              <option value="all">All Hosts</option>
              {hosts.map(h => <option key={h.host_id} value={h.host_id}>{h.pc_name || h.host_id}</option>)}
            </select>
            <select
              value={hours}
              onChange={e => setHours(Number(e.target.value))}
              style={{ padding: '5px 10px', fontSize: 12 }}
            >
              {HOURS_OPTIONS.map(h => <option key={h} value={h}>Last {h}h</option>)}
            </select>
          </div>

          {/* Center: Search */}
          <div style={{ flex: 1, maxWidth: 600, padding: '0 20px' }}>
            <input
              placeholder="Search events..."
              value={searchText}
              onChange={e => setSearch(e.target.value)}
              style={{ padding: '6px 12px', fontSize: 12, width: '100%', borderRadius: 6, border: '1px solid var(--border-2)', background: 'var(--bg)' }}
            />
          </div>

          {/* Right: Tools */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{ display: 'flex', background: 'var(--bg)', borderRadius: 6, overflow: 'hidden', border: '1px solid var(--border)' }}>
                <Button 
                  variant="ghost" onClick={() => setViewMode('table')} title="Table View" aria-label="Table View" active={viewMode === 'table'} icon={<AlignJustify size={14} />} style={{ padding: '6px 10px', borderRadius: 0, background: viewMode === 'table' ? 'var(--bg-3)' : 'transparent' }}
                />
                <Button 
                  variant="ghost" onClick={() => setViewMode('raw')} title="Raw JSON View" aria-label="Raw JSON View" active={viewMode === 'raw'} icon={<Code size={14} />} style={{ padding: '6px 10px', borderRadius: 0, background: viewMode === 'raw' ? 'var(--bg-3)' : 'transparent' }}
                />
              </div>
              <span style={{ fontSize: 11, color: 'var(--text-3)' }}>
                {filtered.length.toLocaleString()} events
              </span>
            </div>
            <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
              <Button variant="ghost" size="sm" onClick={() => setPaused(p => !p)} icon={paused ? <Play size={12} /> : <Pause size={12} />}>
                {paused ? 'Resume' : 'Pause'}
              </Button>
              <Button variant="ghost" size="sm" onClick={() => setEvents([])} icon={<Trash2 size={12} />}>
                Clear
              </Button>
              <Button variant="ghost" size="sm" onClick={exportCSV} icon={<Download size={12} />}>
                Export CSV
              </Button>
            </div>
          </div>
        </div>

        {/* Bottom Row: Event Type Toggles */}
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {ALL_EVENT_TYPES.map(t => (
            <Button
              key={t} variant="custom" size="sm" active={selectedTypes.has(t)} customColor={EVENT_COLORS[t]} onClick={() => toggleType(t)}
              style={{
                padding: '4px 12px', borderRadius: 99, fontSize: 11, textTransform: 'uppercase', fontWeight: 600,
                opacity: selectedTypes.has(t) ? 1 : 0.4, transition: 'all 0.15s ease'
              }}
            >
              {t}
            </Button>
          ))}
        </div>
      </div>

      {/* Terminal stream */}
      <div
        ref={containerRef}
        className="scroll-y mono"
        style={{
          flex: 1,
          padding: '12px 20px',
          background: 'var(--bg-3)',
          overflowY: 'auto',
        }}
      >
        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 48 }}>
            <div className="spinner" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <Terminal size={40} />
            <h3>No events in stream</h3>
            <p>Events will appear here as the pipeline processes telemetry from connected hosts.</p>
          </div>
        ) : (
          <>
            {filtered.map((e, i) => {
              const rowId = `${e.id}-${i}`
              const isExpanded = expandedId === rowId

              if (viewMode === 'raw') {
                return (
                  <div key={rowId} style={{ padding: '8px 20px', borderBottom: '1px solid var(--border)' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
                      <span style={{ color: 'var(--text-3)', fontSize: 11, letterSpacing: '0.3px' }}>
                        {formatTime(e.event_timestamp)}
                      </span>
                      <span style={{
                        padding: '1px 6px', borderRadius: 3,
                        background: `${eventColor(e.event_type)}18`,
                        color: eventColor(e.event_type),
                        fontSize: 10, fontWeight: 700,
                        letterSpacing: '0.5px', textTransform: 'uppercase',
                      }}>
                        {e.event_type}
                      </span>
                      <span style={{ color: 'var(--text-2)', fontSize: 10, marginLeft: 'auto' }}>
                        {e.id}
                      </span>
                    </div>
                    <pre style={{
                      margin: 0, padding: 12, borderRadius: 6,
                      background: 'rgba(0,0,0,0.2)', color: 'var(--text-3)',
                      fontSize: 11, overflowX: 'auto', whiteSpace: 'pre-wrap',
                      border: '1px solid var(--border)'
                    }}>
                      {e.raw_json ? formatRawJson(e.raw_json) : JSON.stringify(e, null, 2)}
                    </pre>
                  </div>
                )
              }

              return (
                <div key={rowId} className="fade-in" style={{
                  borderBottom: i < filtered.length - 1 ? '1px solid rgba(0,0,0,0.04)' : 'none',
                  padding: '4px 0',
                  background: e.event_type === 'alert' ? `var(--${sevClass(e.severity_score)}-bg)` : 'transparent',
                  borderLeft: e.event_type === 'alert' ? `3px solid var(--${sevClass(e.severity_score)})` : '3px solid transparent',
                }}>
                  <div
                    onClick={() => setExpandedId(isExpanded ? null : rowId)}
                    style={{
                      display: 'flex', alignItems: 'baseline', gap: 10,
                      cursor: 'pointer', padding: '2px 0'
                    }}
                  >
                    {/* Timestamp */}
                    <span style={{ color: 'var(--text-3)', fontSize: 11, flexShrink: 0, letterSpacing: '0.3px' }}>
                      {formatTime(e.event_timestamp)}
                    </span>
    
                    {/* Event type badge */}
                    <span style={{
                      padding: '1px 6px', borderRadius: 3,
                      background: `${eventColor(e.event_type)}18`,
                      color: eventColor(e.event_type),
                      fontSize: 10, fontWeight: 700,
                      letterSpacing: '0.5px', textTransform: 'uppercase',
                      flexShrink: 0, fontFamily: 'inherit',
                    }}>
                      {e.event_type}
                    </span>
    
                    {/* Label */}
                    <span style={{
                      color: e.event_type === 'alert' ? 'var(--crit)' : 'var(--text)',
                      fontWeight: e.event_type === 'alert' ? 700 : 400,
                      fontSize: 12,
                      wordBreak: 'break-all',
                    }}>
                      {e.label}
                    </span>
    
                    {/* GUID (truncated) */}
                    <span style={{ color: 'var(--text-2)', fontSize: 10, marginLeft: 'auto', flexShrink: 0 }}>
                      {e.id?.substring(0, 8)}
                    </span>
                  </div>
                  {isExpanded && e.raw_json && (
                    <div style={{ padding: '4px 0 8px 40px' }}>
                      <pre style={{
                        margin: 0, padding: 12, borderRadius: 6,
                        background: 'rgba(0,0,0,0.2)', color: 'var(--text-3)',
                        fontSize: 11, overflowX: 'auto', whiteSpace: 'pre-wrap',
                        border: '1px solid var(--border)'
                      }}>
                        {formatRawJson(e.raw_json)}
                      </pre>
                    </div>
                  )}
                </div>
              )
            })}
            <div ref={bottomRef} />
          </>
        )}
      </div>

      {/* Status bar */}
      <div style={{
        padding: '6px 20px',
        borderTop: '1px solid var(--border)',
        background: 'var(--bg)',
        display: 'flex', alignItems: 'center', gap: 12,
        fontSize: 11, color: 'var(--text-3)', flexShrink: 0,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
          <div style={{
            width: 6, height: 6, borderRadius: '50%',
            background: paused ? 'var(--high)' : 'var(--info)',
            animation: paused ? 'none' : 'pulse 2s infinite',
          }} />
          {paused ? 'Paused' : 'Live stream'}
        </div>
        <span>|</span>
        <span>Refreshing every 5s</span>
        <span>|</span>
        <span>{selectedHost === 'all' ? 'All hosts' : selectedHost}</span>
        <span>|</span>
        <span>Last {hours}h</span>
      </div>
    </div>
  )
}

