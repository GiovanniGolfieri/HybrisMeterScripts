#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/BE/api/.env"
ENV_EXAMPLE="$SCRIPT_DIR/BE/api/.env.example"
VENV="$SCRIPT_DIR/BE/api/venv"

if [ ! -f "$ENV_FILE" ]; then
    echo "ERRORE: BE/api/.env non trovato. Esegui prima: ./BE/api/setup.sh"
    exit 1
fi

if diff -q "$ENV_FILE" "$ENV_EXAMPLE" > /dev/null 2>&1; then
    echo "ATTENZIONE: BE/api/.env è identico a .env.example."
    echo "            Compila le variabili richieste (DB_HOST, DB_USER, DB_PASSWORD, SECRET_KEY)"
    echo "            prima di avviare il server."
    exit 1
fi

if [ ! -d "$VENV" ]; then
    echo "ERRORE: BE/api/venv non trovato. Esegui prima: ./BE/api/setup.sh"
    exit 1
fi

source "$VENV/bin/activate"

echo "Avvio HybrisMeter FastAPI backend..."
echo "  API:  http://localhost:8000"
echo "  Docs: http://localhost:8000/docs"
echo ""

uvicorn app.main:app --reload --host 0.0.0.0 --port 8000 --app-dir "$SCRIPT_DIR/BE/api"
