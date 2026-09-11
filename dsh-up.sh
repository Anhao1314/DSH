#!/usr/bin/env bash
# Start the lightweight local DeepSeek-Harness stack (single container, on-demand).
set -euo pipefail
cd "$(dirname "$0")/orbstack"

if ! docker info >/dev/null 2>&1; then
  echo "OrbStack/Docker is not running. Start OrbStack first." >&2
  exit 1
fi

docker compose up -d
echo "waiting for dsh to become healthy..."
for i in $(seq 1 30); do
  status=$(docker inspect -f '{{.State.Health.Status}}' dsh 2>/dev/null || echo starting)
  [ "$status" = "healthy" ] && break
  sleep 2
done

TOKEN=$(docker logs dsh 2>&1 | grep -oE 'token=[A-Za-z0-9_-]+' | tail -1 | cut -d= -f2 || true)
echo
docker ps --filter name=dsh --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
if [ -n "${TOKEN:-}" ]; then
  URL="http://127.0.0.1:3081/console?token=${TOKEN}"
  echo "Open: $URL"
  open "$URL" 2>/dev/null || true
fi
