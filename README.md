# Retrospection

A local-only, private macOS menu-bar app that captures what you type, reconstructs it into
readable text, and stores it under an addressable **day** model. This is the v0 foundation:
capture → reconstruct → store → export. No dashboard or look-back UI yet — but the storage layer is
the real, durable one. Distillation and a look-back UI attach on top **with no schema migration**.

Everything stays on this Mac. There is no networking code anywhere in the app.

## Build & run

```bash
swift build              # compile
swift test               # 22 tests (day model, text reconstruction, encrypted storage, export)
./Scripts/make_app.sh    # build + assemble build/Retrospection.app (ad-hoc signed)
open build/Retrospection.app
```

The app lives in the menu bar (no Dock icon). On first launch it asks for two permissions in
**System Settings → Privacy & Security**:

- **Input Monitoring** — required for the keyboard event tap. Without it, nothing is captured.
- **Accessibility** — used to read the focused **window title** so entries are labelled. Without it,
  capture still works; entries just have no window title.

Capture starts automatically once Input Monitoring is granted. Because the app is packaged as a
signed `.app` bundle with a stable bundle id, the permission grants persist across launches.

## Controls (menu bar)

- **Pause / Resume** — stops the event tap entirely; the open entry is finalized. State persists.
- **Export Day** — pick a captured date → save a clean, app-grouped, timestamped `.txt`.
- **Ignore List** — check apps to never capture. Seeded with password managers and terminals.
- **Wipe All Data** — irreversibly deletes every day and entry (with confirmation).

## Distill a day with a local model

`Scripts/distill.sh` runs a day's export through a local [Ollama](https://ollama.com) model and asks
it to pull out what mattered (work, decisions, tasks, ideas, conversations). Fully local.

```bash
# 1. Menu bar → Export Day → pick a date → save, e.g. to ~/Downloads/Retrospection-2026-06-11.txt
# 2. Distill it:
./Scripts/distill.sh ~/Downloads/Retrospection-2026-06-11.txt

# Override the model (default: gemma4:e2b). A 7–8B model extracts noticeably better:
DISTILL_MODEL=qwen2.5:7b ./Scripts/distill.sh ~/Downloads/Retrospection-2026-06-11.txt

# Save the summary to a file (ANSI is stripped automatically when redirected):
./Scripts/distill.sh export.txt > summary.txt
```

This is the v0 experiment loop: capture all day → export → distill → see if the signal is there.

## Data model

The **day** is the primary, addressable unit. Fetching a full day is a direct keyed lookup, never a
timestamp scan.

```
days          logical_date PK ('YYYY-MM-DD'), timezone_identifier, timezone_offset_seconds,
              day_start_utc, day_end_utc, cutoff_hour, created_at, updated_at
entries       id PK, logical_date FK→days, app_name, window_title, start_utc, end_utc, text, created_at
distillations logical_date PK FK→days, summary, model, metadata_json, created_at, updated_at
```

`distillations` ships **empty in v0**. It exists now so the nightly distillation and look-back
attach per day later without touching `days` or `entries`. That is the whole point of fixing the
schema now.

### How a logical day is decided (the expensive-to-change part)

`logical_date` is a `YYYY-MM-DD` string and the primary key — exactly one row per date.

- The boundary is **not** strict midnight. A day runs from an early **cutoff (4am)** to the next
  day's cutoff. Concretely: subtract 4h from local wall time, take the calendar date. So 2am maps
  back to the previous evening's day; 5am rolls to the new day. A late-night session stays in one day.
- The **4-hour idle gap** closes the open entry and re-anchors the day on resume. It is deliberately
  *not* allowed to mint a second day for the same calendar date — that would collide with the primary
  key and break "a day is a direct keyed lookup." In practice 4am is the hard boundary; the idle gap
  guarantees clean re-anchoring after sleep.
- Each day stores its timezone identifier and offset, so a day is never ambiguous across DST or
  travel.

Entries are segmented by `(app name, window title)`: an entry stays open and accumulates text while
that context is frontmost, is checkpointed to disk every 30s (crash-durable), and is finalized on
context change, the idle gap, pause, or quit.

## Storage & privacy

- **SQLite encrypted at rest** via [`skiptools/swift-sqlcipher`](https://github.com/skiptools/swift-sqlcipher)
  (SQLCipher 4.12, self-contained, no OpenSSL/system-SQLite dependency).
- The 32-byte key is generated once and stored in the **Keychain**
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`); it never leaves the device.
- Database at `~/Library/Application Support/Retrospection/journal.sqlite`.
- **No network calls of any kind.** No `URLSession`, no sockets — verified by test and by grep.

## Known limitations (by design)

- **Secure Event Input**: macOS blocks the event tap during password entry in browsers, password
  managers, and terminals. This is respected, not worked around — those keystrokes are never seen.
- **Reconstruction is faithful for linear typing-and-correcting** (backspace, delete, return, tab,
  word/line edits, horizontal navigation). Mouse-based cursor repositioning and vertical (up/down)
  navigation are invisible to a keystroke tap, so the stream continues at the current cursor.
- The app is **not sandboxed** — an event tap and the Accessibility API are incompatible with the
  App Sandbox. That is expected for this class of utility.

## Layout

```
Sources/Retrospection/
  App/           main.swift, AppDelegate.swift          — menu bar, lifecycle, actions
  Capture/       EventTapController, TextReconstructor,  — tap → reconstruct → segment
                 FrontmostContext, Permissions, CaptureCoordinator
  Model/         Models (Day, Entry), DayBoundary        — the day logic
  Storage/       Database (SQLCipher wrapper), Store,     — encrypted persistence
                 KeychainKey
  Controls/      IgnoreList, Settings
  Export/        Exporter                                — per-day text document
Tests/RetrospectionTests/                                — day model, reconstruction, storage, export
```
