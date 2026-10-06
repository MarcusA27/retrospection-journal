#!/bin/bash
# Distill a day's capture into "what mattered" using a local Ollama model.
#
# Usage:
#   ./Scripts/distill.sh path/to/Retrospection-2026-06-11.txt     # from an exported day
#   ./Scripts/distill.sh < some-export.txt                        # or via stdin
#   DISTILL_MODEL=qwen2.5:7b ./Scripts/distill.sh export.txt      # override the model
#
# Export a day first from the menu bar: Retrospection → Export Day → pick a date → Save.
# Everything runs locally through Ollama; nothing leaves your Mac.
set -euo pipefail

MODEL="${DISTILL_MODEL:-gemma4:e2b}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

if ! command -v ollama >/dev/null 2>&1; then
    echo "error: ollama not found on PATH" >&2
    exit 1
fi

# Read the day's text from the file argument, or stdin if none given.
if [[ -n "${1:-}" && "${1:-}" != "-" ]]; then
    [[ -f "$1" ]] || { echo "error: no such file: $1" >&2; exit 1; }
    DAY="$(cat "$1")"
else
    DAY="$(cat)"
fi

if [[ -z "${DAY// /}" ]]; then
    echo "error: no input text (empty export?)" >&2
    exit 1
fi

read -r -d '' INSTRUCTIONS <<'EOF' || true
You are reviewing a raw log of everything I typed on my computer today. It was reconstructed from
keystrokes and grouped by the app and window I was in, so it is messy: fragments, typos,
half-sentences, search queries, messages, notes, and code all mixed together.

Pull out what actually mattered. Use these sections, and omit any that would be empty:

- What I worked on — the main threads, projects, or topics of the day
- Decisions & conclusions — anything I appeared to decide, resolve, or commit to
- Tasks & follow-ups — things I said I'd do, or that are clearly still open
- Ideas worth keeping — notable thoughts, even half-formed ones
- People & conversations — who I was talking to or about, and the gist

Be concrete; quote short fragments when it helps. Ignore noise and meaningless keystrokes. Do not
invent anything that is not supported by the text. If the day is thin, say so briefly instead of
padding it out.
EOF

PROMPT="$(printf '%s\n\n--- BEGIN CAPTURE ---\n%s\n--- END CAPTURE ---\n' "$INSTRUCTIONS" "$DAY")"

if [[ -t 1 ]]; then
    # Interactive terminal: let Ollama stream with its live spinner.
    printf '%s' "$PROMPT" | ollama run "$MODEL"
else
    # Redirected to a file/pipe: strip Ollama's ANSI control codes so the output is clean text.
    printf '%s' "$PROMPT" | ollama run "$MODEL" | perl -pe 's/\x1b\[[0-9;?]*[A-Za-z]//g'
fi
