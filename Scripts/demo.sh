#!/bin/bash
# Launch the app in DEMO mode — reads the fake journal in demo/journal/ instead of your real entries,
# so you can screenshot/record the GUI safely. Quit any running instance first so the env var takes.
set -euo pipefail
cd "$(dirname "$0")/.."
pkill -f Retrospection.app 2>/dev/null || true
sleep 1
export RETROSPECTION_JOURNAL_DIR="$(pwd)/demo/journal"
exec build/Retrospection.app/Contents/MacOS/Retrospection
