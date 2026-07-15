#!/bin/bash
set -e
echo "=========================================="
echo "  ISHA-X EDR — Codespace Setup"
echo "=========================================="

WORKSPACE=$(pwd)

# ---- Python: backend deps ----
echo "[1/4] Installing Python backend dependencies..."
pip3 install -q -r "$WORKSPACE/server/backend/requirements.txt"

# ---- Python: pipeline deps ----
echo "[2/4] Installing Python pipeline dependencies..."
pip3 install -q -r "$WORKSPACE/server/pipeline/requirements.txt" 2>/dev/null || true

# ---- Node: frontend ----
echo "[3/4] Installing Node.js frontend dependencies..."
cd "$WORKSPACE/server/frontend" && npm install --silent && cd "$WORKSPACE"

# ---- Wine & Inno Setup ----
echo "[4/5] Installing Wine and Inno Setup compiler for dynamic MSI generation..."
sudo dpkg --add-architecture i386
sudo apt-get update -qq
# Using DEBIAN_FRONTEND=noninteractive to avoid prompt hangs
sudo DEBIAN_FRONTEND=noninteractive apt-get install -yqq wine wine32 wine64 xvfb wget
echo "  → Downloading Inno Setup 6..."
wget -q -O /tmp/innosetup.exe "https://jrsoftware.org/download.php/is.exe"
echo "  → Installing Inno Setup 6 via Wine..."
# Run installer headless using xvfb-run
xvfb-run -a wine /tmp/innosetup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR="C:\inno" >/dev/null 2>&1 || true
rm -f /tmp/innosetup.exe

# Verify InnoSetup was installed correctly
ISCC="$HOME/.wine/drive_c/inno/ISCC.exe"
if [ ! -f "$ISCC" ]; then
  echo "  ⚠ InnoSetup ISCC.exe not found at $ISCC"
  echo "  → The 'Download Agent' feature will not work."
  echo "  → Re-run: xvfb-run -a wine /tmp/innosetup.exe /VERYSILENT /DIR='C:\\inno'"
else
  echo "  ✓ InnoSetup verified at $ISCC"
fi

# ---- Auto-build .env from Codespace Secrets ----
echo "[5/5] Building .env from Codespace secrets..."
ENV_FILE="$WORKSPACE/server/backend/.env"

# Generate SESSION_SECRET if not set
if [ -z "$SESSION_SECRET" ]; then
  SESSION_SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
fi

cat << EOF > "$ENV_FILE"
# -----------------------------------------------------------------------------
# ISHA-X SYSTEM ENVIRONMENT VARIABLES
# -----------------------------------------------------------------------------
# Tailscale Authentication Key
TAILSCALE_AUTH_KEY=${TAILSCALE_AUTH_KEY:-tskey-auth-k5AY78pP5121CNTRL-6vcXc624RLVBfrtKbh9tLV2YXpy6NY9YC}
# Wazuh API — must match API_USERNAME/API_PASSWORD in docker-compose.yml
WAZUH_API_BASE=https://localhost:55000
WAZUH_API_USER=wazuh-wui
WAZUH_API_PASS=MyS3cr37P450r.*-
FRONTEND_ORIGIN=https://weknows.me
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID:-}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET:-}
SESSION_SECRET=${SESSION_SECRET}
SERVER_HOST=agents.weknows.me
MULTI_TENANT=1
EDR_RETENTION_DAYS=30
# Admin login password
ADMIN_PASSWORD=${ADMIN_PASSWORD:-isha}
EOF

echo "  → .env written at $ENV_FILE"

# Check what's missing
MISSING=()
[ -z "$GOOGLE_CLIENT_ID" ]     && MISSING+=("GOOGLE_CLIENT_ID")
[ -z "$GOOGLE_CLIENT_SECRET" ] && MISSING+=("GOOGLE_CLIENT_SECRET")
[ -z "$TAILSCALE_AUTH_KEY" ]   && MISSING+=("TAILSCALE_AUTH_KEY")

if [ ${#MISSING[@]} -gt 0 ]; then
  echo ""
  echo "  ⚠ Missing Codespace Secrets:"
  for m in "${MISSING[@]}"; do
    echo "    - $m"
  done
  echo ""
  echo "  → Go to: github.com/settings/codespaces → Secrets"
  echo "  → Add missing secrets, then: Codespaces → Rebuild Container"
fi

# ---- Clean leftover build dirs ----
find /tmp -maxdepth 1 -name "ishax_build_*" -type d -exec rm -rf {} + 2>/dev/null || true

echo ""
echo "✓ Setup complete!"
echo ""
echo "  Run: bash server/start_linux.sh"
echo ""
