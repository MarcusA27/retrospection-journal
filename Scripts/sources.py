"""Unified ingestion: pull the user's own messages from every local source into one per-day stream.

Sources:
  - from_export      : a claude.ai data export (conversations.json) — desktop chats, history backfill.
  - from_claude_code : ~/.claude/projects/*.jsonl — the user's typed prompts in Claude Code sessions.
  - from_capture     : journal/capture/*.jsonl — the user's typed prompts in the desktop Claude app,
                       captured live by the keylogger and decrypted to JSONL by the app binary
                       (the SQLCipher store has no Python driver, so the app does the decryption).

All readers return {logical_date: [(datetime, label, text)]} and keep ONLY the user's own words.
The Claude Code reader is deliberately strict: it drops tool results, bash I/O, system reminders,
skill injections, and anything in <...> tags — so secrets that land in a transcript (API keys in
bash output, etc.) never reach the journal.
"""
import glob
import json
import os
from collections import defaultdict
from datetime import datetime, timedelta

CUTOFF_HOUR = 4


def journal_dir():
    """Canonical journal location, shared with the macOS app's Look Back reader."""
    return os.path.expanduser("~/Library/Application Support/Retrospection/journal")


def logical_date(dt):
    return (dt - timedelta(hours=CUTOFF_HOUR)).strftime("%Y-%m-%d")


def _add(by_day, lo, hi, dt, label, text, cap=600):
    d = logical_date(dt)
    if lo <= d <= hi:
        t = " ".join((text or "").split())[:cap]
        if t:
            by_day[d].append((dt, label, t))


def from_export(export_path, lo, hi, tz):
    """Desktop chats from a claude.ai export."""
    path = export_path if os.path.isfile(export_path) else os.path.join(export_path, "conversations.json")
    data = json.load(open(path))
    by_day = defaultdict(list)
    for c in data:
        name = (c.get("name") or "untitled")[:40]
        for m in c.get("chat_messages", []):
            if m.get("sender") != "human":
                continue
            ca = m.get("created_at")
            if not ca:
                continue
            dt = datetime.fromisoformat(ca.replace("Z", "+00:00")).astimezone(tz)
            _add(by_day, lo, hi, dt, name, m.get("text", ""))
    return by_day


# Anything starting with one of these is machinery, not something the user typed.
_CC_NOISE = ("<", "Caveat:", "Base directory for this skill:", "[Request interrupted")


def _cc_user_text(msg):
    content = msg.get("content")
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        return " ".join(b.get("text", "") for b in content
                        if isinstance(b, dict) and b.get("type") == "text").strip()
    return ""


def from_claude_code(lo, hi, tz, projects_dir=None):
    """The user's typed prompts across all Claude Code sessions."""
    projects_dir = projects_dir or os.path.expanduser("~/.claude/projects")
    by_day = defaultdict(list)
    for f in glob.glob(os.path.join(projects_dir, "*", "*.jsonl")):
        for line in open(f, errors="ignore"):
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("type") != "user" or d.get("isSidechain"):
                continue          # skip subagent ("sidechain") prompts — not the human
            msg = d.get("message")
            if not isinstance(msg, dict) or msg.get("role") != "user":
                continue
            txt = _cc_user_text(msg)
            if not txt or txt.startswith(_CC_NOISE):
                continue          # drops tool results, bash I/O, reminders, skill dumps, secrets
            ts = d.get("timestamp")
            if not ts:
                continue
            try:
                dt = datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone(tz)
            except ValueError:
                continue
            project = os.path.basename(d.get("cwd", "") or "") or "code"
            _add(by_day, lo, hi, dt, f"Code: {project}", txt)
    return by_day


def from_capture(lo, hi, tz, capture_dir=None):
    """The user's typed prompts in the desktop Claude app, exported from the encrypted store to JSONL.

    Each line is one capture entry: a stretch of continuous typing in one conversation window. Sending
    a message inserts a newline, so we split each entry on newlines into message-sized items — keeping
    boundaries the other sources have, instead of one run-on blob per session.
    """
    capture_dir = capture_dir or os.path.join(journal_dir(), "capture")
    by_day = defaultdict(list)
    for f in glob.glob(os.path.join(capture_dir, "*.jsonl")):
        for line in open(f, errors="ignore"):
            try:
                e = json.loads(line)
            except json.JSONDecodeError:
                continue
            su = e.get("start_utc")
            if su is None:
                continue
            dt = datetime.fromtimestamp(su, tz)
            label = (e.get("title") or "Claude")[:40]   # window title = conversation name (a desktop chat)
            for piece in (e.get("text") or "").split("\n"):
                _add(by_day, lo, hi, dt, label, piece)
    return by_day


def collect(lo, hi, tz, export_path=None, include_claude_code=True, include_capture=True,
            projects_dir=None, capture_dir=None):
    """Merge every source into one {logical_date: [(dt, label, text)]}, chronologically sorted."""
    merged = defaultdict(list)
    if export_path:
        for d, items in from_export(export_path, lo, hi, tz).items():
            merged[d].extend(items)
    if include_claude_code:
        for d, items in from_claude_code(lo, hi, tz, projects_dir).items():
            merged[d].extend(items)
    if include_capture:
        for d, items in from_capture(lo, hi, tz, capture_dir).items():
            merged[d].extend(items)
    for d in merged:
        merged[d].sort(key=lambda x: x[0])
    return merged
