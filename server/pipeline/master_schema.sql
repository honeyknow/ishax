-- =============================================================================
-- ISHAX SaaS v2 — Master Database Schema
-- =============================================================================
-- Purpose: Acts as the central directory/router for multi-tenant operations.
--          Does NOT store EDR logs or alerts. Those live in per-tenant .db files.
--
-- Tables:
--   tenants   : Registered SaaS users (linked to Google email via JWT/OAuth)
--   agents    : Wazuh-registered agent IDs mapped to owning tenant
-- =============================================================================

PRAGMA journal_mode = WAL;
PRAGMA synchronous  = NORMAL;
PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- tenants
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tenants (
    id           TEXT PRIMARY KEY,             -- UUID slug: e.g. "tenant_8f3a2b"
    email        TEXT UNIQUE NOT NULL,         -- Google email: "user@gmail.com"
    display_name TEXT,                         -- Optional display name
    db_filename  TEXT UNIQUE NOT NULL,         -- e.g. "tenant_8f3a2b.db"
    created_at   INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    last_login   INTEGER,
    is_active    INTEGER NOT NULL DEFAULT 1    -- 0 = banned/disabled
);

CREATE INDEX IF NOT EXISTS idx_tenants_email ON tenants(email);

-- ---------------------------------------------------------------------------
-- agents
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agents (
    agent_id      TEXT PRIMARY KEY,            -- Wazuh-issued agent ID: "015"
    tenant_id     TEXT NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    agent_name    TEXT,                        -- Human label: "Rahul-PC"
    registered_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
    last_seen_at  INTEGER,
    is_revoked    INTEGER NOT NULL DEFAULT 0   -- 1 = agent removed by user
);

CREATE INDEX IF NOT EXISTS idx_agents_tenant   ON agents(tenant_id);
CREATE INDEX IF NOT EXISTS idx_agents_revoked  ON agents(is_revoked);
