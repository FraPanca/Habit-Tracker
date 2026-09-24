#!/usr/bin/env bash
# Genera traffico realistico verso l'app per popolare la dashboard Grafana.
# Mix di richieste: letture, creazioni, entry, 404 e 400 (errori client).
#
# Uso: ./monitoring/scripts/load-test.sh [durata_secondi] [worker_paralleli] [base_url]
#   ./monitoring/scripts/load-test.sh              # 120s, 2 worker, http://localhost
#   ./monitoring/scripts/load-test.sh 300 5        # 5 minuti, 5 worker in parallelo
set -euo pipefail

DURATION="${1:-120}"
WORKERS="${2:-2}"
BASE_URL="${3:-http://localhost}"
API="$BASE_URL/api/habits"
END=$((SECONDS + DURATION))

command -v curl >/dev/null || { echo "curl non trovato"; exit 1; }
curl -sf "$API" >/dev/null || { echo "App non raggiungibile su $BASE_URL: hai avviato lo stack?"; exit 1; }

req() { curl -s -o /dev/null --max-time 15 -w '%{http_code}' "$@" || echo "000"; }

worker() {
  while (( SECONDS < END )); do
    # Crea un'abitudine e registra una entry per oggi
    id=$(curl -s --max-time 15 -X POST "$API" -H 'Content-Type: application/json' \
          -d "{\"name\":\"load-test-$RANDOM\",\"type\":\"boolean\"}" | sed -n 's/.*"_id":"\([^"]*\)".*/\1/p')
    if [[ -n "$id" ]]; then
      req -X POST "$API/$id/entries" -H 'Content-Type: application/json' \
          -d "{\"date\":\"$(date +%F)\",\"value\":true}" >/dev/null
      req "$API/$id/entries" >/dev/null
      req -X DELETE "$API/$id" >/dev/null   # pulizia: non lascia dati di test nel DB
    fi

    # Letture (la parte più frequente del traffico reale)
    for _ in 1 2 3; do req "$API" >/dev/null; done

    # Errori client: ID inesistente (404), ID malformato (400), route inesistente (unmatched)
    req "$API/000000000000000000000000/entries" >/dev/null
    req "$API/id-non-valido/entries" >/dev/null
    req "$BASE_URL/api/non-esiste" >/dev/null

    sleep 0.2
  done
}

echo "Genero traffico verso $BASE_URL per ${DURATION}s con $WORKERS worker (Ctrl+C per interrompere)..."
trap 'kill $(jobs -p) 2>/dev/null' EXIT
for _ in $(seq "$WORKERS"); do worker & done
while (( SECONDS < END )); do
  printf '\r%ds rimanenti   ' "$((END - SECONDS))"
  sleep 1
done
wait
echo -e "\nFatto. Apri Grafana su http://localhost:3000"