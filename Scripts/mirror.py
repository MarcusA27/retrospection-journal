#!/usr/bin/env python3
"""Generate an over-time "mirror" from a claude.ai export using the Claude API.

The mirror reflects how the user's thinking moved across a window of days — what they kept circling,
how their mind changed, what stayed constant — anchored in their own dated quotes. This is the
automated version of the hand-built sample; run it on a window and compare.

Usage:
  ./Scripts/mirror.py <export-dir> --from 2026-05-19 --to 2026-05-25
  ./Scripts/mirror.py <export-dir>                      # last 7 logical days
  ./Scripts/mirror.py <export-dir> --from .. --to .. --effort medium --model claude-sonnet-4-6
"""
import argparse
import json
import os
import pathlib
import re
import sys
from collections import defaultdict
from datetime import datetime, timedelta

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402

CUTOFF_HOUR = 4


def load_env():
    p = pathlib.Path(__file__).resolve().parent.parent / ".env"
    if p.exists():
        for line in p.read_text().splitlines():
            s = line.strip()
            if s and not s.startswith("#") and "=" in s:
                k, v = s.split("=", 1)
                os.environ.setdefault(k.strip(), "".join(v.split()))


def logical_date(dt):
    return (dt - timedelta(hours=CUTOFF_HOUR)).strftime("%Y-%m-%d")


def render_messages(by_day):
    out, count = [], 0
    for d in sorted(by_day):
        out.append(f"===== {d} =====")
        for dt, name, t in sorted(by_day[d], key=lambda x: x[0]):
            out.append(f"[{dt:%H:%M}] ({name}) {t}")
            count += 1
    return "\n".join(out), count


SYSTEM = """You are writing one section of a personal retrospection journal for the person whose \
words follow. You are given a window of messages THEY wrote to an AI assistant over several days — \
their own voice, each line stamped with a date/time and the conversation it came from. You do NOT \
have the assistant's replies; work only from their words.

Write a short "mirror": a reflection of how their thinking MOVED across this window — what they kept \
circling back to, where and how their mind changed, what stayed constant underneath. This is the \
part of the journal that shows them something they can't see from inside the days.

Rules, in order of importance:
1. Receipts or it doesn't ship, and bigger claims need more receipts. Every claim must be anchored \
in their actual words — quote short fragments verbatim and cite the date, e.g. (May 21). The bolder \
the read, the more direct quotes it must rest on; if you can't get there, scale the claim down or \
cut it.
2. Observe patterns; do not diagnose the person. You may name what kept happening across the window \
and point to it. You may NOT pronounce a verdict on who they are, what they "really want," what they \
"don't actually want," how they felt, or what they "realized" — unless they say it themselves. \
Prefer "X kept happening" over "you are X." Describe what the words show and let them draw the \
conclusion.
3. End on ONE specific, non-obvious observation — a pattern across the window they might not see \
from inside it. Stay close to the evidence. If the observation requires reading past their words \
into motive or character, either hedge it honestly ("the pattern suggests...", "it reads like...") \
or leave it out. Specific and grounded beats bold and sweeping. If the only thing you can honestly \
say is obvious ("you care about design"), say less.
4. Keep their voice. They write terse and direct. Don't translate them into smooth journal prose. \
Lean on their real sentences.
5. Be tight: a few short paragraphs. Second person ("you"). Past-looking. No preamble, no section \
headers, no sign-off. Output only the mirror text."""


def main():
    load_env()
    ap = argparse.ArgumentParser(description="Generate an over-time mirror from a claude.ai export.")
    ap.add_argument("export", nargs="?", help="claude.ai export dir/conversations.json (optional)")
    ap.add_argument("--from", dest="lo", help="start logical date YYYY-MM-DD")
    ap.add_argument("--to", dest="hi", help="end logical date YYYY-MM-DD")
    ap.add_argument("--no-claude-code", action="store_true", help="exclude ~/.claude/projects transcripts")
    ap.add_argument("--projects-dir", help="override Claude Code projects dir")
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--effort", default="high", choices=["low", "medium", "high", "max"])
    args = ap.parse_args()

    tz = datetime.now().astimezone().tzinfo
    hi = args.hi or logical_date(datetime.now().astimezone(tz))
    lo = args.lo or logical_date(datetime.now().astimezone(tz) - timedelta(days=6))

    by_day = sources.collect(lo, hi, tz, export_path=args.export,
                             include_claude_code=not args.no_claude_code,
                             projects_dir=args.projects_dir)
    body, count = render_messages(by_day)
    if not count:
        print(f"No messages in {lo}..{hi}.", file=sys.stderr)
        sys.exit(1)

    user = (f"Window: {lo} to {hi}. {count} of your messages, "
            f"across {len(by_day)} days.\n\n{body}")

    print(f"[mirror] {count} messages, {lo}..{hi}, model={args.model}, effort={args.effort}\n",
          file=sys.stderr)

    resp = anthropic.Anthropic().messages.create(
        model=args.model,
        max_tokens=4000,
        thinking={"type": "adaptive"},
        output_config={"effort": args.effort},
        system=SYSTEM,
        messages=[{"role": "user", "content": user}],
    )
    text = "".join(b.text for b in resp.content if b.type == "text").strip()
    print(text)

    u = resp.usage
    rate = {"claude-opus-4-8": (5, 25), "claude-sonnet-4-6": (3, 15), "claude-haiku-4-5": (1, 5)}
    ci, co = rate.get(args.model, (5, 25))
    cost = u.input_tokens / 1e6 * ci + u.output_tokens / 1e6 * co
    print(f"\n[usage] {u.input_tokens} in / {u.output_tokens} out  ~${cost:.3f}", file=sys.stderr)


if __name__ == "__main__":
    main()
