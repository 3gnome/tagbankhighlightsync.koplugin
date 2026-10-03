# AnkiKoFlash companion (optional)

[AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) turns KOReader highlights into Anki flashcards (Vocabulary Card, Memorization Card). **TagBankHighlightSync** is a separate plugin — you can use either alone or both together.

## Division of labor

| Task | Plugin |
|------|--------|
| Tag highlights, folder hierarchy, parent tags | **Tag Bank** |
| Merge `*.sdr.json` across devices (WebDAV, etc.) | **Tag Bank** |
| Export Obsidian quote library (`library/quotes/`, `tags/`, `books/`) | **Tag Bank** |
| Send flashcards to desktop Anki via AnkiConnect | **AnkiKoFlash** |
| View / delete / batch-send highlights as Anki cards | **AnkiKoFlash** |

## Typical workflow (both installed)

1. Read on KOReader → highlight passages
2. **Tag highlight** (Tag Bank) — organize by theme or manuscript status
3. **AnkiKoFlash** — create and send cards for study
4. **Sync now** (Tag Bank) — JSON merge + quote library to WebDAV
5. Browse `library/` in Obsidian on your PC

## Cross-plugin features

When both plugins are loaded:

- **View All Highlights** ([AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin)) includes **Sync All Highlights** — runs Tag Bank cloud sync for every book in reading history
- **Settings → Quote library** orange/green filters use Anki-branded labels (“Exclude Anki pending/sent highlights”); with Tag Bank alone, labels stay neutral

Peer detection uses KOReader’s plugin loader — no hard dependency between repos.

## Install both

| Plugin | Releases |
|--------|----------|
| Tag Bank Highlight Sync | [tagbankhighlightsync.koplugin](https://github.com/3gnome/tagbankhighlightsync.koplugin/releases) |
| AnkiKoFlash | [AnkiKoFlash.koplugin](https://github.com/3gnome/AnkiKoFlash.koplugin/releases) |

Copy both folders into `koreader/plugins/` and enable under **Plugin management**.

## Shared dev setup

Developers often run both plugins from a multi-root workspace. See [AnkiKoFlash LOCAL_DEV.md.sample](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/LOCAL_DEV.md.sample) and Tag Bank `LOCAL_DEV.md.sample` for `dev-start.sh` sync + emulator launch.

## WebDAV

Both plugins share the same WebDAV root for sidecar JSON. Full Windows setup: [WebDAV setup (Windows)](webdav-setup-windows.md) (also in [AnkiKoFlash docs](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/docs/webdav-setup-windows.md)).
