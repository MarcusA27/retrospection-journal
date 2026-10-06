#!/bin/bash
# Nightly job: fill in any missing recent journal entries + mirrors from the automatic local sources.
# Invoked by the LaunchAgent (5am / 11am / 5pm). Two layers of resilience so a day is never dropped:
#   1. It often fires on wake, BEFORE the network/DNS is up — so we wait for the API to be reachable.
#   2. The generators are idempotent catch-ups, retried a few times here, and re-run on the next fire.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
LOG=logs/nightly.log

echo "=== nightly run $(date +%Y-%m-%dT%H:%M:%S) ===" >> "$LOG"

# Wait until the Anthropic API resolves + accepts a connection (curl exits 0 on any HTTP reply; it
# only fails on DNS/connect errors — exactly the wake-before-network case). Up to ~5 min.
api_reachable() { curl -s --max-time 8 -o /dev/null https://api.anthropic.com/v1/messages; }
for i in $(seq 1 20); do
    api_reachable && break
    [ "$i" -eq 20 ] && { echo "network unreachable after wait — next run will retry" >> "$LOG"; exit 1; }
    sleep 15
done

# Refresh the desktop-app capture: the signed app binary (which holds the key + links SQLCipher)
# decrypts the recent days of the keylogger store to plaintext JSONL under journal/capture/, where
# daily.py folds them in. Best-effort — if the app isn't built or capture is off, daily.py falls back
# to Claude Code only. 6 days covers the catch-up window plus today.
APP_BIN="build/Retrospection.app/Contents/MacOS/Retrospection"
if [ -x "$APP_BIN" ]; then
    "$APP_BIN" --export-capture 6 >> "$LOG" 2>&1 || echo "capture export failed — continuing without it" >> "$LOG"
fi

# No export arg: going-forward sources are Claude Code transcripts + the desktop-app capture (above).
# Catch-up 4: fill any of the last 4 completed logical days missing an entry. Retried — idempotent, so
# already-written days are skipped and only a genuinely failed day is reattempted.
status=1
for attempt in 1 2 3; do
    if .venv/bin/python Scripts/daily.py --catch-up 4 >> "$LOG" 2>&1; then status=0; break; fi
    echo "daily attempt $attempt failed — retrying in 30s" >> "$LOG"
    sleep 30
done

# Ensure every COMPLETED recent week has its over-time mirror (idempotent — no API calls when nothing
# is missing, never deletes/thins an existing mirror). Self-heals so loose days fold into a week's
# mirror once that week closes.
.venv/bin/python Scripts/weekly.py --weeks 3 >> "$LOG" 2>&1 || echo "weekly failed — next run will retry" >> "$LOG"
# Rescore the sentiment curve from Claude Code transcripts (cheap, instant — recomputes the whole file).
.venv/bin/python Scripts/sentiment.py --merge >> "$LOG" 2>&1 || true

echo "exit $status" >> "$LOG"
exit "$status"
