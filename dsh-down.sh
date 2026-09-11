#!/usr/bin/env bash
# Stop the local DeepSeek-Harness stack. After this, its CPU/RAM footprint is 0.
set -euo pipefail
cd "$(dirname "$0")/orbstack"
docker compose stop
echo "dsh stopped (data and config kept in ../dsh-home)."
docker ps --filter name=dsh --format '{{.Names}}: {{.Status}}' || true
