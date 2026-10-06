#!/usr/bin/env python3
"""Backfill: generate a daily entry for every active day across all sources.

The weekly mirror backfill (backfill.py) fills the "Weeks" view; this fills "Days". Skips days that
already have an entry, and days below a message threshold. Writes to the journal's daily/ directory.

Usage:
  ./Scripts/backfill_daily.py <export-dir> [--min-msgs 5] [--effort medium] [--overwrite]
"""
import argparse
import pathlib
import sys
from datetime import datetime

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402
import mirror   # noqa: E402
import daily    # noqa: E402  (reuse the daily entry prompt)

RATE = {"claude-opus-4-8": (5, 25), "claude-sonnet-4-6": (3, 15), "claude-haiku-4-5": (1, 5)}


def main():
    mirror.load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("export", nargs="?")
    ap.add_argument("--min-msgs", type=int, default=5)
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--effort", default="medium")
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()

    tz = datetime.now().astimezone().tzinfo
    by_day = sources.collect("0000-00-00", "9999-99-99", tz,
                             export_path=args.export, include_claude_code=True)

    out_dir = pathlib.Path(sources.journal_dir()) / "daily"
    out_dir.mkdir(parents=True, exist_ok=True)
    client = anthropic.Anthropic()
    ci, co = RATE.get(args.model, (5, 25))

    days = sorted(by_day)
    print(f"{len(days)} active days | model={args.model} effort={args.effort}\n", flush=True)
    total, made = 0.0, 0
    for date in days:
        items = by_day[date]
        if len(items) < args.min_msgs:
            print(f"skip {date} ({len(items)} msgs < {args.min_msgs})", flush=True)
            continue
        fn = out_dir / f"{date}.md"
        if fn.exists() and not args.overwrite:
            print(f"skip {date} (exists)", flush=True)
            continue
        body, n = mirror.render_messages({date: items})
        user = f"Day: {date}. {n} of your messages.\n\n{body}"
        try:
            resp = client.messages.create(
                model=args.model, max_tokens=1500,
                thinking={"type": "adaptive"}, output_config={"effort": args.effort},
                system=daily.SYSTEM, messages=[{"role": "user", "content": user}])
        except Exception as e:
            print(f"✗ {date}  ERROR: {e}", flush=True)
            continue
        text = "".join(b.text for b in resp.content if b.type == "text").strip()
        fn.write_text(f"# {date}\n\n{text}\n")
        u = resp.usage
        cost = u.input_tokens / 1e6 * ci + u.output_tokens / 1e6 * co
        total += cost
        made += 1
        print(f"✓ {date}  {n:4d} msgs  ${cost:.3f}", flush=True)

    print(f"\n{made} daily entries written → {out_dir}  | total ~${total:.2f}", flush=True)


if __name__ == "__main__":
    main()
