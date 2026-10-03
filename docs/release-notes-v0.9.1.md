## What's new in v0.9.1

First public beta of **TagBankHighlightSync** — tag highlights, sync annotations across devices, and export a Markdown quote library for Obsidian.

### Core
- **Tag bank** — folders, tags, parent tags on export (`#buddhism #aversion`)
- **JSON sync** — merge `*.sdr.json` via Cloud storage+ (WebDAV, Dropbox, …)
- **Tag highlight menu** — tap to apply; hold to rename/move/delete; **Add folder…** / **Add tag…**
- **Add tag UX** — inside a folder, **Add** saves directly; at root, **Add to bank** opens tap-to-select folder picker

### Quote library
- Markdown export to `library/quotes/`, `tags/`, `books/`, `master-quotes.md`
- Screenshot capture, verse layout, scholarly headings for Obsidian
- Optional filters when [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) is installed

### Sync
- Open / close / wake sync; close-book push-only upload
- **Sync all books** — batch sync for reading history (also in AnkiKoFlash **View All Highlights**)

## Install

Download `tagbankhighlightsync-v0.9.1.zip`, unzip, and copy the `tagbankhighlightsync.koplugin` folder into your KOReader `plugins/` directory.

Enable **TagBankHighlightSync** and **Cloud storage** under **Tools → Plugin management**.

See [Getting started](https://github.com/3gnome/tagbankhighlightsync.koplugin/blob/main/docs/getting-started.md) for setup.

**Optional companion:** [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) — Anki cards from highlights (MIT). **License:** AGPL-3.0.
