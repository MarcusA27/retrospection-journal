#!/usr/bin/env python3
"""Generate one day's journal entry from all local sources, via the Claude API.

The daily entry is the tight, readable counterpart to the over-time mirror: three short paragraphs
that recall what the day was actually about, in the user's own words. Writes to exports/daily/.

Usage:
  ./Scripts/daily.py <export-dir> --date 2026-06-11      # a specific day, all sources
  ./Scripts/daily.py                                      # yesterday's logical day, Claude Code only
"""
import argparse
import pathlib
import sys
from datetime import datetime, timedelta

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402
import mirror   # noqa: E402  (reuse load_env + render_messages)

SYSTEM = """You are writing one day's entry in a personal retrospection journal for the person whose \
messages follow. You are given everything they typed to AI assistants on this single day — their own \
voice, each line stamped with a time and where it came from: a plain conversation name is a desktop \
chat; "Code: project" is a Claude Code building session. You do NOT have the assistants' replies; \
work only from their words.

Output exactly this shape:
- First line, a SUBJECT: one specific line that sums up the day in their voice — a sharp phrase or a \
short real fragment from the day. Never generic ("A Day of Decisions", "Reflections"). No quotes, no \
label, no markdown, no trailing period.
- Then a blank line.
- Then a tight entry — three short paragraphs:
  1. What the day was actually about — the real throughline, not a list of topics.
  2. What they worked through, decided, or got stuck on — anchored in their actual words.
  3. What's unresolved or carried into tomorrow — the open loops.

Rules:
- Receipts. Quote short fragments verbatim and cite the time, e.g. (14:32). If you can't support a \
sentence with a real quote, cut it.
- No invented inner life. Describe what the words show; don't assert feelings, realizations, or \
motives they didn't state. Note patterns; don't pronounce verdicts on who they are.
- Keep their voice — terse and direct. Don't smooth them into generic journal prose.
- Second person ("you"). Past tense. No section headers, no sign-off. Output only the subject line, \
a blank line, then the entry."""

RATE = {"claude-opus-4-8": (5, 25), "claude-sonnet-4-6": (3, 15), "claude-haiku-4-5": (1, 5)}


def write_entry(date, out_dir, args, tz):
    """Generate and write one logical day's entry. Returns the path, or None if the day was empty."""
    by_day = sources.collect(date, date, tz, export_path=args.export,
                             include_claude_code=not args.no_claude_code,
                             include_capture=not args.no_capture,
                             projects_dir=args.projects_dir, capture_dir=args.capture_dir)
    body, n = mirror.render_messages(by_day)
    if not n:
        print(f"No messages on {date} — nothing to write.", file=sys.stderr)
        return None

    user = f"Day: {date}. {n} of your messages.\n\n{body}"
    print(f"[daily] {date}: {n} messages, model={args.model}, effort={args.effort}", file=sys.stderr)

    resp = anthropic.Anthropic().messages.create(
        model=args.model, max_tokens=1500,
        thinking={"type": "adaptive"}, output_config={"effort": args.effort},
        system=SYSTEM, messages=[{"role": "user", "content": user}])
    text = "".join(b.text for b in resp.content if b.type == "text").strip()
    parts = text.split("\n\n", 1)
    subject = parts[0].strip().strip('"').lstrip("# ").rstrip(".").strip()
    body = parts[1].strip() if len(parts) > 1 else text

    fn = out_dir / f"{date}.md"
    fn.write_text(f"# {subject}\n\n{body}\n")
    u = resp.usage
    ci, co = RATE.get(args.model, (5, 25))
    cost = u.input_tokens / 1e6 * ci + u.output_tokens / 1e6 * co
    print(f"[usage] {u.input_tokens} in / {u.output_tokens} out  ~${cost:.3f}  -> {fn}", file=sys.stderr)
    return fn


def main():
    mirror.load_env()
    ap = argparse.ArgumentParser(description="Generate one day's journal entry.")
    ap.add_argument("export", nargs="?", help="claude.ai export dir/conversations.json (optional)")
    ap.add_argument("--date", help="logical date YYYY-MM-DD (default: last completed logical day)")
    ap.add_argument("--catch-up", type=int, metavar="N",
                    help="fill any MISSING entry among the last N completed logical days (idempotent)")
    ap.add_argument("--no-claude-code", action="store_true")
    ap.add_argument("--no-capture", action="store_true", help="skip the desktop-app capture source")
    ap.add_argument("--projects-dir")
    ap.add_argument("--capture-dir", help="capture JSONL dir (default: journal/capture)")
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--effort", default="medium", choices=["low", "medium", "high", "max"])
    ap.add_argument("--out", default=str(pathlib.Path(sources.journal_dir()) / "daily"))
    args = ap.parse_args()

    tz = datetime.now().astimezone().tzinfo
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    # The last completed logical day: today's logical day has not closed yet (4am cutoff), so it's
    # the day before it. Computing from the logical date — not wall-clock minus 24h — keeps a run that
    # fires before 4am from silently targeting the wrong day.
    today_logical = datetime.strptime(sources.logical_date(datetime.now().astimezone(tz)), "%Y-%m-%d")

    if args.catch_up:
        wrote = 0
        for i in range(1, args.catch_up + 1):
            date = (today_logical - timedelta(days=i)).strftime("%Y-%m-%d")
            if (out_dir / f"{date}.md").exists():
                continue
            if write_entry(date, out_dir, args, tz):
                wrote += 1
        print(f"[catch-up] {wrote} entr{'y' if wrote == 1 else 'ies'} written.", file=sys.stderr)
        return

    date = args.date or (today_logical - timedelta(days=1)).strftime("%Y-%m-%d")
    write_entry(date, out_dir, args, tz)


if __name__ == "__main__":
    main()
