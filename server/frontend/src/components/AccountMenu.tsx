import { useState, useRef, useEffect } from 'react'
import { Download, Trash2, LogOut, ChevronDown, User, Shield } from 'lucide-react'
import { api } from '../api/client'

interface AccountMenuProps {
  email: string
  role: 'admin' | 'user'
  onSignOut?: () => void
}

export default function AccountMenu({ email, role, onSignOut }: AccountMenuProps) {
  const [open, setOpen] = useState(false)
  const [downloading, setDownloading] = useState(false)
  const [deleting, setDeleting] = useState(false)
  const [confirmDelete, setConfirmDelete] = useState(false)
  const ref = useRef<HTMLDivElement>(null)

  // Close dropdown when clicking outside
  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
        setConfirmDelete(false)
      }
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const handleDownloadDb = async () => {
    setDownloading(true)
    try {
      api.downloadDb()
    } finally {
      setTimeout(() => setDownloading(false), 2000)
    }
    setOpen(false)
  }

  const handleDeleteAccount = async () => {
    if (!confirmDelete) {
      setConfirmDelete(true)
      return
    }
    setDeleting(true)
    try {
      await api.deleteMyData()
      alert('Your account and all data have been permanently deleted.')
      if (onSignOut) onSignOut()
    } catch (e) {
      alert('Failed to delete account. Please try again.')
    } finally {
      setDeleting(false)
      setConfirmDelete(false)
      setOpen(false)
    }
  }

  const handleSignOut = () => {
    // Clear any local state/storage and reload
    localStorage.clear()
    sessionStorage.clear()
    if (onSignOut) {
      onSignOut()
    } else {
      // Redirect to Cloudflare Zero Trust logout (prod) or reload (dev)
      window.location.href = '/cdn-cgi/access/logout'
    }
  }

  const rawPrefix = email.split('@')[0].replace(/[._-]/g, ' ')
  const displayName = rawPrefix.split(' ').map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(' ')
  const isAdmin = role === 'admin'

  return (
    <div ref={ref} style={{ position: 'relative', userSelect: 'none' }}>
      {/* Trigger button */}
      <button
        onClick={() => { setOpen(o => !o); setConfirmDelete(false) }}
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          padding: '4px 8px',
          background: 'transparent',
          border: 'none',
          cursor: 'pointer',
          color: 'var(--text-1)',
        }}
      >
        {/* Avatar circle */}
        <div style={{
          width: 32, height: 32, borderRadius: '50%',
          background: isAdmin ? 'var(--accent)' : 'rgba(255,255,255,0.1)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          {isAdmin ? <Shield size={16} color="#fff" /> : <User size={16} color="#ccc" />}
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start' }}>
          <span style={{ fontSize: 13, fontWeight: 600, color: '#fff' }}>
            {displayName}
          </span>
          <span style={{ fontSize: 10, color: isAdmin ? '#ef4444' : 'var(--text-3)', fontWeight: 600, letterSpacing: '0.5px' }}>
            {isAdmin ? 'ADMIN' : 'USER'}
          </span>
        </div>
        <ChevronDown size={14} color="var(--text-3)" style={{ transition: 'transform 0.15s', transform: open ? 'rotate(180deg)' : 'rotate(0deg)', marginLeft: 4 }} />
      </button>

      {/* Dropdown */}
      {open && (
        <div style={{
          position: 'absolute',
          top: 'calc(100% + 6px)',
          right: 0,
          minWidth: 220,
          background: 'var(--bg-2)',
          border: '1px solid var(--border)',
          borderRadius: 10,
          boxShadow: '0 8px 32px rgba(0,0,0,0.4)',
          zIndex: 1000,
          overflow: 'hidden',
        }}>
          {/* User info header */}
          <div style={{ padding: '16px', borderBottom: '1px solid var(--border)', background: 'var(--bg-2)', borderTopLeftRadius: 12, borderTopRightRadius: 12 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 4 }}>
              <div style={{ width: 32, height: 32, borderRadius: '50%', background: isAdmin ? 'rgba(239, 68, 68, 0.15)' : 'var(--bg-4)', border: isAdmin ? '1px solid rgba(239, 68, 68, 0.4)' : '1px solid var(--border)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <Shield size={16} color={isAdmin ? '#ef4444' : 'var(--text-3)'} />
              </div>
              <div>
                <div style={{ fontSize: 14, fontWeight: 700, color: '#fff' }}>{displayName}</div>
                <div style={{ fontSize: 11, color: 'var(--text-3)' }}>{email}</div>
              </div>
            </div>
            <div style={{ marginTop: 8 }}>
              <div style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                fontSize: 10, fontWeight: 800, letterSpacing: '0.5px',
                color: isAdmin ? '#ef4444' : 'var(--text-3)',
                background: isAdmin ? 'rgba(239, 68, 68, 0.1)' : 'var(--bg-4)',
                border: isAdmin ? '1px solid rgba(239, 68, 68, 0.3)' : '1px solid var(--border)',
                padding: '3px 8px', borderRadius: 6,
              }}>
                {isAdmin ? <><Shield size={10} /> ADMIN</> : <><User size={10} /> USER</>}
              </div>
            </div>
          </div>

          {/* Actions */}
          <div style={{ padding: 6 }}>
            {/* Download DB */}
            <MenuRow
              icon={<Download size={14} />}
              label={downloading ? 'Preparing download...' : 'Download My DB'}
              sublabel="Export raw SQLite database"
              color="var(--text-2)"
              onClick={handleDownloadDb}
              disabled={downloading}
            />

            <div style={{ height: 1, background: 'var(--border)', margin: '4px 0' }} />

            {/* Sign Out */}
            <MenuRow
              icon={<LogOut size={14} />}
              label="Sign Out"
              color="var(--text-2)"
              onClick={handleSignOut}
            />

            <div style={{ height: 1, background: 'var(--border)', margin: '4px 0' }} />

            {/* Delete Account — danger zone */}
            <MenuRow
              icon={<Trash2 size={14} />}
              label={confirmDelete ? '⚠ Click again to confirm — IRREVERSIBLE' : 'Delete My Account & Data'}
              sublabel={confirmDelete ? 'All alerts, events, and your DB will be wiped' : 'Permanently wipes all your data'}
              color={confirmDelete ? 'var(--crit)' : '#e57373'}
              onClick={handleDeleteAccount}
              disabled={deleting}
              danger
            />
          </div>
        </div>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Internal helper: menu row
// ---------------------------------------------------------------------------
function MenuRow({
  icon, label, sublabel, color, onClick, disabled, danger
}: {
  icon: React.ReactNode
  label: string
  sublabel?: string
  color: string
  onClick: () => void
  disabled?: boolean
  danger?: boolean
}) {
  const [hover, setHover] = useState(false)
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        display: 'flex',
        alignItems: 'flex-start',
        gap: 10,
        width: '100%',
        padding: '8px 10px',
        background: hover ? (danger ? 'rgba(239,68,68,0.08)' : 'var(--bg-3)') : 'transparent',
        border: 'none',
        borderRadius: 7,
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.6 : 1,
        textAlign: 'left',
        transition: 'background 0.1s',
      }}
    >
      <span style={{ color, marginTop: 1, flexShrink: 0 }}>{icon}</span>
      <div>
        <div style={{ fontSize: 13, fontWeight: 600, color, lineHeight: 1.2 }}>{label}</div>
        {sublabel && <div style={{ fontSize: 11, color: 'var(--text-3)', marginTop: 2 }}>{sublabel}</div>}
      </div>
    </button>
  )
}
