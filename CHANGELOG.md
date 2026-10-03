# Changelog

## Unreleased

### Fixed (P0 — data loss / regressions)
- AnkiKoFlash peer detection — correct `ankikoflash` plugin id (was retired `ankikooai`)
- Bounded 412-conflict retry (no more unbounded retry loop)
- Corrupt/empty remote JSON no longer treated as "no highlights" (guard against silent data loss)
- Tag merge now propagates tag deletions (was a pure union)
- Socket timeouts restored on cloud sync paths (regression vs stock cloudstorage)

### Fixed (P1 — correctness)
- `write_json_file` fallback made atomic (tmp + rename, safe remove on Windows hosts)
- Sync-all no longer skips books with zero syncable annotations (deletions propagate)
- Concurrent-sync guard gaps closed; `_sync_now_target_ann` no longer leaks on early-return
- `markLibrarySynced` flush, single-highlight sync, and batch-sync confirmation paths fixed

### Added (P2 — UX / robustness)
- Progress + cancel for "Sync all books"
- Tag-bank integrity check (orphan tag ids)
- Batch-sync confirmation before overwrite

### Docs / hygiene
- `docs/companion-ankikooai.md` renamed to `docs/companion-ankikoflash.md`; all `AnkiKOAi` references swept
- Added `pre-commit-privacy-check.sh` and a pre-commit/privacy guard step (see `CONTRIBUTING.md`)
- `.shift/` added to `.gitignore`

## v0.9.1 (2026-07-07) — first public beta

### Highlights
- Hierarchical **tag bank** with folders, parent tags, and hold-to-edit (rename, move, delete)
- **JSON device sync** — merge `*.sdr.json` across KOReader devices via Cloud storage+ (WebDAV, Dropbox, etc.)
- **Quote library (Markdown)** — `library/quotes/`, `tags/`, `books/`, `master-quotes.md` for Obsidian and other Markdown tools
- **Tag highlight menu** — tap to apply tags; **Add folder…** / **Add tag…**; inside a folder, **Add tag** saves directly to that folder; at root, **Add to bank** opens a tap-to-select folder picker
- **Sync all books** — batch cloud sync for every book in reading history (also exposed from [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) **View All Highlights** when both plugins are installed)
- Screenshot capture, verse layout export, close-book push sync, Kindle `cloudstorage` compat patches

### Companion
- Optional [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) — Anki cards from highlights; Tag Bank handles tags, JSON sync, and Obsidian quote library
