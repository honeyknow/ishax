#!/usr/bin/env bash
# ISHA-X EDR — start backend (serves pre-built dashboard on port 8000)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND="$SCRIPT_DIR/server/backend"

cd "$BACKEND"
exec uvicorn main:app --host 0.0.0.0 --port 8000
