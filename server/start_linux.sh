#!/bin/bash
# =============================================================
# ISHA-X EDR — Linux / GitHub Codespace Startup Script
# =============================================================
# Run this ONCE after Codespace finishes setup.
# Usage:  bash server/start_linux.sh
# =============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "  ISHA-X EDR — Starting Full Stack"
echo "=========================================="

# ---- Load .env ----
ENV_FILE="$SCRIPT_DIR/backend/.env"
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$SCRIPT_DIR/backend/.env.example" ]; then
    echo "[!] .env not found. Copying from .env.example..."
    cp "$SCRIPT_DIR/backend/.env.example" "$ENV_FILE"
    echo "    → Fill in your secrets in: $ENV_FILE"
    echo "    Then re-run this script."
    exit 1
  else
    echo "[!] No .env or .env.example found. Cannot start."
    exit 1
  fi
fi

export $(grep -v '^#' "$ENV_FILE" | xargs 2>/dev/null) || true

# ---- Step 1: Tailscale ----
echo ""
echo "[1/4] Starting Tailscale VPN..."
if command -v tailscale &>/dev/null; then
  if [ -n "$TAILSCALE_AUTH_KEY" ]; then
    sudo tailscale up --authkey="$TAILSCALE_AUTH_KEY" --accept-routes 2>/dev/null && \
      echo "      ✓ Tailscale connected (auth key used)" || \
      echo "      ! Tailscale already up or key invalid — check: tailscale status"
  else
    echo "      ! No TAILSCALE_AUTH_KEY in .env — run manually: sudo tailscale up"
    sudo tailscale up --accept-routes 2>/dev/null || true
  fi
else
  echo "      ! tailscale not installed — skipping VPN step"
fi

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "unknown")
echo "      Tailscale IP: $TAILSCALE_IP"

# ---- Step 2: Wazuh ----
echo ""
echo "[2/4] Starting Wazuh Manager (Docker)..."
if command -v docker &>/dev/null && [ -f "$SCRIPT_DIR/wazuh/docker-compose.yml" ]; then
  cd "$SCRIPT_DIR/wazuh"
  docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || echo "      ! Docker compose failed — is Docker running?"
  echo "      ✓ Wazuh containers starting (takes ~30s to become ready)"
else
  echo "      ! Docker or wazuh/docker-compose.yml not found — skipping Wazuh"
fi

# ---- Step 3: Ingestor pipeline ----
echo ""
echo "[3/4] Starting Ingestor Pipeline..."
cd "$SCRIPT_DIR/pipeline"
pkill -f "python3 ingestor.py" 2>/dev/null || true
sleep 1
MULTI_TENANT=1 nohup python3 ingestor.py > ingestor.log 2>&1 &
INGESTOR_PID=$!
echo "      ✓ Ingestor started (PID=$INGESTOR_PID) → pipeline/ingestor.log"

# ---- Step 4: FastAPI backend ----
echo ""
echo "[4/4] Starting FastAPI Backend + React Frontend..."
cd "$SCRIPT_DIR/backend"
pkill -f "uvicorn main:app" 2>/dev/null || true
sleep 1
nohup python3 -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload > backend.log 2>&1 &
BACKEND_PID=$!
echo "      ✓ Backend started  (PID=$BACKEND_PID) → backend/backend.log"

cd "$SCRIPT_DIR/frontend"
pkill -f "npm run dev" 2>/dev/null || true
sleep 1
nohup npm run dev -- --host 0.0.0.0 --port 5173 > frontend.log 2>&1 &
FRONTEND_PID=$!
echo "      ✓ Frontend started (PID=$FRONTEND_PID) → frontend/frontend.log"

echo ""
echo "=========================================="
echo "  Stack booting — check Ports tab in"
echo "  Codespace to open the dashboard."
echo ""
echo "  Dashboard : http://localhost:5173"
echo "  API Docs  : http://localhost:8000/docs"
echo "  Login     : http://localhost:8000/auth/login"
echo ""
echo "  Logs:"
echo "    tail -f server/pipeline/ingestor.log"
echo "    tail -f server/backend/backend.log"
echo "    tail -f server/frontend/frontend.log"
echo "=========================================="
