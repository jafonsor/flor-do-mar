#!/usr/bin/env bash
# Restart the client under test: replace whatever listens on 3911 with a freshly
# launched binary, and wait until it answers.
set -euo pipefail
cd /Users/joaorodrigues/devs/flor-do-mar
pid=$(lsof -nP -iTCP:3911 -sTCP:LISTEN -t | head -1)
if [ -n "${pid:-}" ]; then kill "$pid" 2>/dev/null || true; fi
for _ in $(seq 1 40); do
  lsof -nP -iTCP:3911 -sTCP:LISTEN -t >/dev/null 2>&1 || break
  sleep 0.25
done
CABAL_DIR="$PWD/.cabal-local" nohup cabal run -v0 flor-do-mar-client >.scratch/diagnosis/client-3911.log 2>&1 &
for _ in $(seq 1 120); do
  if curl -s --max-time 2 -o /dev/null http://127.0.0.1:3911/; then echo "client back up"; exit 0; fi
  sleep 0.5
done
echo "client did not come back" >&2
exit 1
