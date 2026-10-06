#!/usr/bin/env python3
"""Score the daily sentiment of the user's own words, for the Look Back sparkline.

Reads the same local sources as the journal (their messages, not Claude's replies), runs each
message through VADER, and averages the per-message compound score per logical day. Writes a flat
journal/sentiment.json the macOS app draws as a quiet curve.

VADER is a lexicon — cheap and instant, but literal about chat/technical text. If the curve reads as
noise, swap the scorer here for a Claude pass; the output shape and the app don't change.

Usage:
  ./Scripts/sentiment.py <export-dir>     # full recompute: export history + Claude Code, all days
  ./Scripts/sentiment.py                  # Claude Code only (what the nightly job has)
"""
import argparse
import json
import pathlib
import sys
from datetime import datetime

from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description="Score daily sentiment of the user's words.")
    ap.add_argument("export", nargs="?", help="claude.ai export dir/conversations.json (optional)")
    ap.add_argument("--no-claude-code", action="store_true")
    ap.add_argument("--projects-dir")
    ap.add_argument("--merge", action="store_true",
                    help="keep existing days the recompute doesn't cover (nightly, no export)")
    ap.add_argument("--out", default=str(pathlib.Path(sources.journal_dir()) / "sentiment.json"))
    args = ap.parse_args()

    tz = datetime.now().astimezone().tzinfo
    lo, hi = "2020-01-01", sources.logical_date(datetime.now().astimezone(tz))
    by_day = sources.collect(lo, hi, tz, export_path=args.export,
                             include_claude_code=not args.no_claude_code, projects_dir=args.projects_dir)

    vader = SentimentIntensityAnalyzer()
    out = pathlib.Path(args.out)
    # Merge mode preserves history the recompute can't see (e.g. export-only days when run CC-only).
    by_date = {}
    if args.merge and out.exists():
        for r in json.loads(out.read_text()):
            by_date[r["date"]] = r
    for date in sorted(by_day):
        scores = [vader.polarity_scores(text)["compound"] for _, _, text in by_day[date]]
        if not scores:
            continue
        by_date[date] = {"date": date, "score": round(sum(scores) / len(scores), 4), "n": len(scores)}
    rows = [by_date[d] for d in sorted(by_date)]

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(rows, indent=0))
    if rows:
        avg = sum(r["score"] for r in rows) / len(rows)
        print(f"{len(rows)} days scored · mean {avg:+.3f} · "
              f"{rows[0]['date']} → {rows[-1]['date']}  -> {out}", file=sys.stderr)
    else:
        print("No messages found — nothing scored.", file=sys.stderr)


if __name__ == "__main__":
    main()
