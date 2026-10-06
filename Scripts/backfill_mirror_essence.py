#!/usr/bin/env python3
"""Title each weekly mirror with a one-line essence, written as the mirror's `# ` heading.

Cheap — reads the mirror you already have and names its throughline, without rewriting the mirror.
Rewrites journal/mirrors/<range>.md from "# <date → date>" (or any heading) to "# <essence>".
"""
import pathlib
import sys

import anthropic

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sources  # noqa: E402
import mirror   # noqa: E402

SYSTEM = """You are titling one week's "mirror" — a reflection of how someone's thinking moved across \
a span of days. Given the mirror below, write its ESSENCE: one specific line, in the writer's terse \
voice, naming what the span was really about — the throughline, not a summary. A sharp phrase or a \
short real fragment from it. Never generic ("A Week of Reflection", "Growth", "Change"). No quotes, \
no label, no markdown, no trailing period. Output only that one line."""


def body_of(raw):
    lines = raw.split("\n")
    if lines and lines[0].startswith("# "):
        lines = lines[1:]
        while lines and not lines[0].strip():
            lines = lines[1:]
    return "\n".join(lines).strip()


def main():
    mirror.load_env()
    mdir = pathlib.Path(sources.journal_dir()) / "mirrors"
    files = sorted(mdir.glob("*.md"))
    client = anthropic.Anthropic()
    print(f"{len(files)} mirrors to title\n", flush=True)
    total, n = 0.0, 0
    for f in files:
        body = body_of(f.read_text())
        if not body:
            continue
        resp = client.messages.create(
            model="claude-opus-4-8", max_tokens=80,
            thinking={"type": "adaptive"}, output_config={"effort": "low"},
            system=SYSTEM, messages=[{"role": "user", "content": body}])
        essence = "".join(b.text for b in resp.content if b.type == "text").strip()
        essence = essence.split("\n")[0].strip().strip('"').lstrip("# ").rstrip(".").strip()
        f.write_text(f"# {essence}\n\n{body}\n")
        u = resp.usage
        total += u.input_tokens / 1e6 * 5 + u.output_tokens / 1e6 * 25
        n += 1
        print(f"✓ {f.stem}  —  {essence}", flush=True)
    print(f"\n{n} titled · ~${total:.2f}", flush=True)


if __name__ == "__main__":
    main()
