#!/bin/bash
set -e
echo "=========================================="
echo "  ISHA-X EDR — Codespace Setup"
echo "=========================================="

# ---- Python: backend deps ----
echo "[1/4] Installing Python backend dependencies..."
cd /workspaces/*/server/backend
pip3 install -q -r requirements.txt

# ---- Python: pipeline deps ----
echo "[2/4] Installing Python pipeline dependencies..."
cd /workspaces/*/server/pipeline
pip3 install -q -r requirements.txt 2>/dev/null || true

# ---- Node: frontend ----
echo "[3/4] Installing Node.js frontend dependencies..."
cd /workspaces/*/server/frontend
npm install --silent

# ---- Create .env from example if not exists ----
echo "[4/4] Setting up environment..."
ENV_TARGET="/workspaces/*/server/backend/.env"
ENV_EXAMPLE="/workspaces/*/server/backend/.env.example"
# expand glob
ENV_TARGET_REAL=$(ls $ENV_TARGET 2>/dev/null || echo "")
ENV_EXAMPLE_REAL=$(ls $ENV_EXAMPLE 2>/dev/null || echo "")
if [ -z "$ENV_TARGET_REAL" ] && [ -n "$ENV_EXAMPLE_REAL" ]; then
  cp "$ENV_EXAMPLE_REAL" "${ENV_EXAMPLE_REAL%.example}"
  echo "  → Copied .env.example to .env — fill in your secrets!"
fi

# ---- Clean up any leftover installer build dirs ----
find /tmp -maxdepth 1 -name "ishax_build_*" -type d -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "✓ Setup complete!"
echo ""
echo "NEXT STEPS:"
echo "  1. Edit server/backend/.env — add GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,"
echo "     SESSION_SECRET, ALLOWED_EMAILS, WAZUH_API_PASS, TAILSCALE_AUTH_KEY"
echo "  2. Run:  bash server/start_linux.sh"
echo "  3. Open port 5173 in the Ports tab"
echo ""
