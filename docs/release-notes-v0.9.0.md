## What's new in v0.9.0

First public beta of **TagBankHighlightSync** — tag highlights, sync annotations across devices, and export a Markdown quote library for Obsidian.

### Core
- **Tag bank** — folders, tags, parent tags on export (`#buddhism #aversion`)
- **JSON sync** — merge `*.sdr.json` via Cloud storage+ (WebDAV, Dropbox, …)
- **Tag highlight menu** — tap to apply; hold to rename/move/delete; **Add folder…** / **Add tag…**
- **Add tag UX** — inside a folder, **Add** saves directly; at root, **Add to bank** opens tap-to-select folder picker

### Quote library
- Markdown export to `library/quotes/`, `tags/`, `books/`, `master-quotes.md`
- Screenshot capture, verse layout, scholarly headings for Obsidian
- Optional filters when [AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin) is installed

### Sync
- Open / close / wake sync; close-book push-only upload
- **Sync all books** — batch sync for reading history (also in AnkiKOAi **View All Highlights**)

### Install
Download `tagbankhighlightsync-v0.9.0.zip`, unzip, copy `tagbankhighlightsync.koplugin` into `koreader/plugins/`. Enable **TagBankHighlightSync** and **Cloud storage**.

See [Getting started](https://github.com/3gnome/tagbankhighlightsync.koplugin/blob/main/docs/getting-started.md).

**License:** AGPL-3.0. Optional companion: [AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin) (MIT).
