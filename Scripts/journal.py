#!/usr/bin/env python3
"""Build a per-day journal from a claude.ai data export.

The journal is weighted to your voice: your messages are shown in full, Claude's are trimmed to a
short context snippet (use --full to keep them whole). Messages are bucketed into logical days using
the same 4am cutoff as the rest of the project — a late-night session stays with the evening.

Usage:
  ./Scripts/journal.py <export-dir-or-conversations.json> --list
  ./Scripts/journal.py <export-dir> --date 2026-06-12
  ./Scripts/journal.py <export-dir>                 # today
  ./Scripts/journal.py <export-dir> --date 2026-06-12 --full > day.md
"""
import argparse
import json
import os
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

CUTOFF_HOUR = 4


def load_conversations(path):
    if os.path.isdir(path):
        path = os.path.join(path, "conversations.json")
    with open(path) as f:
        return json.load(f)


def message_text(m):
    """Prefer the flat 'text'; fall back to joining text content blocks."""
    t = (m.get("text") or "").strip()
    if t:
        return t
    parts = [b.get("text", "") for b in m.get("content", []) if b.get("type") == "text"]
    return "\n".join(p for p in parts if p).strip()


def local_dt(iso, tz):
    return datetime.fromisoformat(iso.replace("Z", "+00:00")).astimezone(tz)


def logical_date(dt):
    return (dt - timedelta(hours=CUTOFF_HOUR)).strftime("%Y-%m-%d")


def trim(text, n):
    """First paragraph up to n chars, with code blocks collapsed — enough to recall the context."""
    t = re.sub(r"```.*?```", "[code]", text, flags=re.S)
    t = t.strip().split("\n\n")[0].strip()
    t = re.sub(r"\s+", " ", t)
    if len(t) > n:
        t = t[:n].rsplit(" ", 1)[0] + "…"
    return t


def attachment_note(m):
    names = [a.get("file_name") for a in m.get("attachments", []) if a.get("file_name")]
    names += [f.get("file_name") for f in m.get("files", []) if f.get("file_name")]
    return f"[attached: {', '.join(names)}]" if names else ""


def build_days(convs, tz):
    days = defaultdict(list)
    for c in convs:
        for m in c.get("chat_messages", []):
            ca = m.get("created_at")
            if not ca:
                continue
            dt = local_dt(ca, tz)
            days[logical_date(dt)].append((dt, c, m))
    return days


def cmd_list(days):
    for d in sorted(days):
        items = days[d]
        yours = sum(1 for _, _, m in items if m.get("sender") == "human")
        convos = len({c["uuid"] for _, c, _ in items})
        print(f"{d}   {len(items):4d} msgs   {yours:3d} yours   {convos:2d} conversations")


def cmd_render(date, items, args):
    items.sort(key=lambda x: x[0])
    order, by_conv = [], defaultdict(list)
    for dt, c, m in items:
        if c["uuid"] not in by_conv:
            order.append(c)
        by_conv[c["uuid"]].append((dt, m))

    yours = sum(1 for _, _, m in items if m.get("sender") == "human")
    print(f"# Journal — {date}")
    print(f"{len(items)} messages · {yours} yours · {len(order)} conversations\n")

    for c in order:
        msgs = by_conv[c["uuid"]]
        span = f"{msgs[0][0]:%H:%M}–{msgs[-1][0]:%H:%M}"
        print(f"## {c.get('name') or '(untitled)'}  [{span}]")
        if c.get("summary") and args.summary != "none":
            s = c["summary"] if args.summary == "full" else trim(c["summary"], 200)
            print(f"_{s}_")
        print()
        for dt, m in msgs:
            text = message_text(m)
            note = attachment_note(m)
            if not text and not note:
                continue
            body = (text + (f"\n{note}" if note else "")).strip()
            if m.get("sender") == "human":
                print(f"**You · {dt:%H:%M}**")
                print(body + "\n")
            else:
                snippet = body if args.full else trim(body, args.claude_chars)
                print(f"> Claude: {snippet}\n")
        print()


def main():
    ap = argparse.ArgumentParser(description="Build a per-day journal from a claude.ai export.")
    ap.add_argument("export", help="export directory or conversations.json")
    ap.add_argument("--date", help="logical date YYYY-MM-DD (default: today)")
    ap.add_argument("--list", action="store_true", help="list days with activity and exit")
    ap.add_argument("--full", action="store_true", help="keep Claude's messages in full")
    ap.add_argument("--claude-chars", type=int, default=350, help="trim length for Claude context")
    ap.add_argument("--summary", choices=["full", "short", "none"], default="short",
                    help="per-conversation summary line (default: short)")
    args = ap.parse_args()

    tz = datetime.now().astimezone().tzinfo
    days = build_days(load_conversations(args.export), tz)

    if args.list:
        cmd_list(days)
        return

    date = args.date or logical_date(datetime.now(timezone.utc).astimezone(tz))
    items = days.get(date)
    if not items:
        print(f"No conversations on {date}. Try --list to see days with activity.", file=sys.stderr)
        sys.exit(1)
    cmd_render(date, items, args)


if __name__ == "__main__":
    main()
