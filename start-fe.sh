#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/FE/.env"
ENV_EXAMPLE="$SCRIPT_DIR/FE/.env.example"
FE_DIR="$SCRIPT_DIR/FE"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERRORE: FE/.env non trovato. Esegui prima: ./FE/setup.sh"
    exit 1
fi

if [ -f "$ENV_EXAMPLE" ] && diff -q "$ENV_FILE" "$ENV_EXAMPLE" > /dev/null 2>&1; then
    echo "ATTENZIONE: FE/.env è identico a .env.example."
    echo "            Compilare NEXT_PUBLIC_API_URL prima di avviare."
    echo "  Es: NEXT_PUBLIC_API_URL=http://localhost:8000/api/v1"
    exit 1
fi

if [ ! -d "$FE_DIR/node_modules" ]; then
    echo "ERRORE: FE/node_modules non trovato. Esegui prima: ./FE/setup.sh"
    exit 1
fi

echo "Avvio HybrisMeter Next.js frontend..."
echo "  App:  http://localhost:3000"
echo ""

cd "$FE_DIR"
exec npm run dev
