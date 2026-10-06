#!/usr/bin/env python3
"""Title each existing daily entry: generate a one-line subject and write it as the entry's heading.

Cheap — it reads the entry you already have and just titles it, without rewriting the entry itself.
Rewrites journal/daily/<date>.md from "# <date>" (or any heading) to "# <subject>".
"""
import pathlib
import sys

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402
import mirror   # noqa: E402

SYSTEM = """You are titling one day's journal entry. Given the entry below, write a SUBJECT: one \
specific line, in the writer's terse voice, that sums up what the day was really about — a sharp \
phrase or a short real fragment from the entry. Never generic ("A Day of Decisions", "Reflections"). \
No quotes, no label, no markdown, no trailing period. Output only that one line."""


def body_of(raw):
    lines = raw.split("\n")
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
        while lines and not lines[0].strip():
            lines = lines[1:]
    return "\n".join(lines).strip()


def main():
    mirror.load_env()
    daily_dir = pathlib.Path(sources.journal_dir()) / "daily"
    files = sorted(daily_dir.glob("*.md"))
    client = anthropic.Anthropic()
    print(f"{len(files)} entries to title\n", flush=True)
    total, n = 0.0, 0
    for f in files:
        body = body_of(f.read_text())
        if not body:
            continue
        resp = client.messages.create(
            model="claude-opus-4-8", max_tokens=80,
            thinking={"type": "adaptive"}, output_config={"effort": "low"},
            system=SYSTEM, messages=[{"role": "user", "content": body}])
        subject = "".join(b.text for b in resp.content if b.type == "text").strip()
        subject = subject.split("\n")[0].strip().strip('"').lstrip("# ").rstrip(".").strip()
        f.write_text(f"# {subject}\n\n{body}\n")
        u = resp.usage
        total += u.input_tokens / 1e6 * 5 + u.output_tokens / 1e6 * 25
        n += 1
        print(f"✓ {f.stem}  —  {subject}", flush=True)
    print(f"\n{n} titled · ~${total:.2f}", flush=True)


if __name__ == "__main__":
    main()
