#!/bin/sh
# dsh may only bind loopback; start the edge relay, then run dsh in the foreground.
set -e
node /app/orbstack-relay.cjs &
RELAY_PID=$!
trap 'kill "$RELAY_PID" 2>/dev/null || true' TERM INT
exec pnpm dsh web --patch "${DSH_HOME:-/root/.dsh}/profiles/web/mcp.patch.yml" \
  --host 127.0.0.1 --port "${DSH_INTERNAL_PORT:-3080}" --no-open \
  --trusted-host dsh.orb.local "$@"
