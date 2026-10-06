#!/usr/bin/env python3
"""Backfill: generate a weekly mirror for every active week in a claude.ai export.

Reuses Scripts/mirror.py (same prompt, model, settings). Writes one file per week to
exports/mirrors/ plus a combined ALL.md you can read as a sequence.

Usage:
  ./Scripts/backfill.py <export-dir> [--min-msgs 8] [--model claude-opus-4-8] [--effort high]
"""
import argparse
import json
import os
import pathlib
import sys
from collections import defaultdict
from datetime import datetime

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import mirror   # noqa: E402
import sources  # noqa: E402

RATE = {"claude-opus-4-8": (5, 25), "claude-sonnet-4-6": (3, 15), "claude-haiku-4-5": (1, 5)}


def main():
    mirror.load_env()
    ap = argparse.ArgumentParser()
    ap.add_argument("export")
    ap.add_argument("--min-msgs", type=int, default=8)
    ap.add_argument("--model", default="claude-opus-4-8")
    ap.add_argument("--effort", default="high")
    args = ap.parse_args()

    path = args.export if os.path.isfile(args.export) else os.path.join(args.export, "conversations.json")
    data = json.load(open(path))
    tz = datetime.now().astimezone().tzinfo

    # Bucket human messages into ISO weeks → logical date → [(dt, conversation, text)]
    weeks = defaultdict(lambda: defaultdict(list))
    for c in data:
        for m in c.get("chat_messages", []):
            if m.get("sender") != "human":
                continue
            ca = m.get("created_at")
            if not ca:
                continue
            dt = datetime.fromisoformat(ca.replace("Z", "+00:00")).astimezone(tz)
            ld = mirror.logical_date(dt)
            iso = datetime.strptime(ld, "%Y-%m-%d").isocalendar()[:2]
            t = " ".join((m.get("text") or "").split())[:600]
            if t:
                weeks[iso][ld].append((dt, c.get("name", "")[:40], t))

    out_dir = pathlib.Path(sources.journal_dir()) / "mirrors"
    out_dir.mkdir(parents=True, exist_ok=True)
    client = anthropic.Anthropic()
    ci, co = RATE.get(args.model, (5, 25))

    ordered = sorted(weeks)
    print(f"{len(ordered)} weeks with data | model={args.model} effort={args.effort}\n", flush=True)
    total_cost, made, combined = 0.0, 0, []
    for iso in ordered:
        by_day = weeks[iso]
        dates = sorted(by_day)
        lo, hi = dates[0], dates[-1]
        n = sum(len(v) for v in by_day.values())
        if n < args.min_msgs:
            print(f"skip {lo}..{hi}  ({n} msgs < {args.min_msgs})", flush=True)
            continue
        body, _ = mirror.render_messages(by_day)
        user = f"Window: {lo} to {hi}. {n} of your messages, across {len(by_day)} days.\n\n{body}"
        try:
            resp = client.messages.create(
                model=args.model, max_tokens=4000,
                thinking={"type": "adaptive"}, output_config={"effort": args.effort},
                system=mirror.SYSTEM, messages=[{"role": "user", "content": user}])
        except Exception as e:
            print(f"✗ {lo}..{hi}  ERROR: {e}", flush=True)
            continue
        text = "".join(b.text for b in resp.content if b.type == "text").strip()
        u = resp.usage
        cost = u.input_tokens / 1e6 * ci + u.output_tokens / 1e6 * co
        total_cost += cost
        made += 1
        section = f"# {lo} → {hi}   ({n} messages)\n\n{text}\n"
        (out_dir / f"mirror-{lo}_{hi}.md").write_text(section + "\n")
        combined.append(section)
        print(f"✓ {lo}..{hi}  {n:4d} msgs  ${cost:.3f}", flush=True)

    (out_dir / "ALL.md").write_text("\n\n---\n\n".join(combined) + "\n")
    print(f"\n{made} mirrors → {out_dir}/  (combined: {out_dir}/ALL.md)  | total ~${total_cost:.2f}",
          flush=True)


if __name__ == "__main__":
    main()
