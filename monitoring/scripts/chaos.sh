#!/usr/bin/env bash
# Simula guasti per verificare end-to-end il flusso di alerting:
#   Prometheus (regola) -> Alertmanager (routing/inhibit) -> alert-receiver (log)
#
# Uso:
#   ./monitoring/scripts/chaos.sh backend-down   # ferma il backend  -> BackendDown (critical) dopo ~1-2 min
#   ./monitoring/scripts/chaos.sh mongo-down     # ferma MongoDB     -> MongoDBDown (critical); le eventuali
#                                     #   HighErrorRate vengono soppresse dall'inhibit rule
#   ./monitoring/scripts/chaos.sh restore        # riavvia tutto     -> notifiche RESOLVED
#   ./monitoring/scripts/chaos.sh status         # alert attivi secondo Prometheus
set -euo pipefail

COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.monitoring.yml)
cd "$(dirname "$0")/../.."

show_status() {
  echo "Alert attivi in Prometheus:"
  curl -s 'http://localhost:9090/api/v1/alerts' \
    | grep -o '"alertname":"[^"]*"\|"state":"[^"]*"' | paste - - | sed 's/"//g' || echo "  (nessuno)"
}

case "${1:-}" in
  backend-down)
    "${COMPOSE[@]}" stop backend
    echo "Backend fermato. Tra ~1-2 minuti BackendDown passa da pending a firing."
    echo "Segui le notifiche con: ${COMPOSE[*]} logs -f alert-receiver"
    ;;
  mongo-down)
    "${COMPOSE[@]}" stop mongodb
    echo "MongoDB fermato. Le richieste al backend ora vanno in timeout (500)."
    echo "Lancia ./monitoring/scripts/load-test.sh in un altro terminale per generare errori."
    ;;
  restore)
    "${COMPOSE[@]}" up -d
    echo "Servizi riavviati. Entro qualche minuto arrivano le notifiche RESOLVED."
    ;;
  status)
    show_status
    ;;
  *)
    sed -n '2,9p' "$0"
    exit 1
    ;;
esac