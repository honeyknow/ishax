import './App.css'
import Topbar from './components/Topbar'
import Overview from './pages/Overview'
import ThreatHunt from './pages/ThreatHunt'
import Firehose from './pages/Firehose'
import RulesEngine from './pages/RulesEngine'
import AdminPanel from './pages/AdminPanel'
import AIPanel from './components/AIPanel'
import { useState, useEffect } from 'react'
import { api } from './api/client'

// View can now include 'admin' for the admin panel
export type View = 'overview' | 'hunt' | 'firehose' | 'rules' | 'admin'

interface UserIdentity {
  email: string
  role: 'admin' | 'user'
  tenant: Record<string, unknown> | null
}

export default function App() {
  const [view, setView] = useState<View>('overview')
  const [huntHost, setHuntHost] = useState<string | null>(null)
  const [aiPanelOpen, setAiPanelOpen] = useState(false)
  const [aiContext, setAiContext] = useState<{ alert_id?: number; host_id?: string; hours?: number } | undefined>(undefined)

  // SaaS: current user identity (role, email, tenant)
  const [user, setUser] = useState<UserIdentity | null>(null)

  // Admin impersonation: when admin views a specific tenant's dashboard
  const [impersonateTenantId, setImpersonateTenantId] = useState<string | null>(null)
  const [impersonateEmail, setImpersonateEmail] = useState<string | null>(null)

  // Load user identity on mount — redirect to login if not authenticated
  useEffect(() => {
    api.getMe()
      .then(me => {
        if (!me.authenticated) {
          window.location.href = '/auth/login'
          return
        }
        setUser({ email: me.email, role: me.role, tenant: me.tenant ?? null })
        if (me.role === 'admin') setView('admin')
      })
      .catch(() => {
        // If /auth/me fails entirely (network error in dev), stay on page
        // The 401 interceptor will redirect if it's an auth failure
      })
  }, [])

  // Global event: open AI panel
  useEffect(() => {
    const handler = (e: Event) => {
      const customEvent = e as CustomEvent
      setAiContext(customEvent.detail)
      setAiPanelOpen(true)
    }
    window.addEventListener('open-ai', handler)
    return () => window.removeEventListener('open-ai', handler)
  }, [])

  const handleNavigateToHunt = (hostId: string) => {
    setHuntHost(hostId)
    setView('hunt')
  }

  // Admin: impersonate a tenant's dashboard
  const handleImpersonate = (tenantId: string, email: string) => {
    setImpersonateTenantId(tenantId)
    setImpersonateEmail(email)
    setView('overview')
  }

  // Admin: stop impersonating — go back to admin panel
  const handleStopImpersonating = () => {
    setImpersonateTenantId(null)
    setImpersonateEmail(null)
    setView('admin')
  }

  const handleSignOut = () => {
    window.location.href = '/auth/logout'
  }

  return (
    <div className="app-shell" style={{ display: 'flex', flexDirection: 'column', height: '100vh', position: 'relative' }}>
      <Topbar
        view={view}
        onViewChange={setView}
        onToggleAI={() => {
          setAiContext(undefined)
          setAiPanelOpen(o => !o)
        }}
        user={user}
        onSignOut={handleSignOut}
        isAdmin={user?.role === 'admin'}
        impersonating={impersonateEmail}
        onStopImpersonating={handleStopImpersonating}
      />

      {/* Impersonation banner */}
      {impersonateEmail && (
        <div style={{
          background: 'rgba(99,102,241,0.15)',
          borderBottom: '1px solid rgba(99,102,241,0.3)',
          padding: '6px 20px',
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          fontSize: 12,
          color: 'var(--accent)',
          fontWeight: 600,
        }}>
          <span>👁 Viewing dashboard as: <strong>{impersonateEmail}</strong></span>
          <button
            onClick={handleStopImpersonating}
            style={{
              marginLeft: 'auto', padding: '3px 10px', borderRadius: 6,
              background: 'rgba(99,102,241,0.2)', border: '1px solid rgba(99,102,241,0.4)',
              color: 'var(--accent)', cursor: 'pointer', fontSize: 12, fontWeight: 700,
            }}
          >
            ← Back to Admin Panel
          </button>
        </div>
      )}

      <div className="main-layout" style={{ display: 'flex', flex: 1, overflow: 'hidden' }}>
        <div className="page-content" style={{ display: 'flex', flexDirection: 'column', flex: 1, overflow: 'hidden' }}>
          {view === 'admin'    && user?.role === 'admin' && !impersonateTenantId &&
            <AdminPanel onImpersonate={handleImpersonate} />
          }
          {view === 'overview' && <Overview
            onHostClick={handleNavigateToHunt}
            impersonateTenantId={impersonateTenantId ?? undefined}
          />}
          {view === 'hunt'     && <ThreatHunt initialHost={huntHost} />}
          {view === 'firehose' && <Firehose />}
          {view === 'rules'    && <RulesEngine />}
        </div>
      </div>

      <AIPanel
        isOpen={aiPanelOpen}
        onClose={() => setAiPanelOpen(false)}
        context={aiContext}
      />
    </div>
  )
}
