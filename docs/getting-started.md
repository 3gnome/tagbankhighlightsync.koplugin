# Getting started

End-to-end setup: install TagBankHighlightSync, connect cloud storage, tag your first highlight, and sync.

## What you need

- A device running [KOReader](https://koreader.rocks/) (Kobo, Kindle with KOReader, or the desktop emulator)
- **Cloud storage** plugin enabled in KOReader (menu may show **Cloud Storage** on device)
- A cloud account or local [WebDAV server](webdav-setup-windows.md) on the same Wi‑Fi as your e-reader
- (Optional) [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) for Anki flashcards from highlights

Tag Bank works **standalone** for tagging, JSON sync, and Obsidian quote libraries. AnkiKoFlash is optional.

## Step 1 — Install the plugin

1. Download the latest release zip from [GitHub Releases](https://github.com/3gnome/tagbankhighlightsync.koplugin/releases).
2. Unzip and copy **`tagbankhighlightsync.koplugin`** into `koreader/plugins/`.
3. Restart KOReader.
4. **Tools → More tools → Plugin management** — enable **TagBankHighlightSync** and **Cloud storage**.

## Step 2 — Cloud storage account

1. **Tools → Cloud Storage** — add your account (WebDAV, Dropbox, etc.).
2. For a PC WebDAV server on Windows, see [WebDAV setup (Windows)](webdav-setup-windows.md).

Use plain HTTP WebDAV only on a trusted home LAN; use HTTPS on networks you do not control.

## Step 3 — Cloud folder (sync destination)

1. **Tools → Tag Bank Highlight Sync → Cloud folder**
2. Tap your server → open `/` (or your sync root)
3. Long-press → **Long-press here to choose current folder** → **Choose**

This folder holds per-book `*.sdr.json` files and (when enabled) the `library/` quote export.

## Step 4 — Turn on sync

1. **Tag Bank Highlight Sync → Settings → When to sync → Turn on Tag Bank Highlight Sync**
2. Choose **Sync on open**, **Sync on close**, and/or **Sync on wake** as you prefer.
3. **Cloud file name → Recommended: KOReader sidecar name** (same filename on all devices).

## Step 5 — Tag your first highlight

1. Long-press a highlight → **Tag & sync…** → **Tag highlight**
2. Tap existing tags or **Add tag…** / **Add folder…**
3. **Add tag…** inside a folder saves the tag there on **Add**; at the bank root, **Add to bank** opens a folder picker (**tap** folder to save, **hold** to browse).
4. Tags remain alphabetized inside each folder. After tagging a few passages, choose **Suggest tags from this book** to compare the current paragraph with your earlier tagged highlights.
5. Review the preselected suggestions and Recent tags, then tap **Apply selected**. This is local, uses no AI, and Back changes nothing.
6. **Sync now** (from Tag & sync hub) uploads JSON and refreshes the quote library when enabled.

## Step 6 — Quote library (optional, for Obsidian)

1. **Settings → Quote library → Turn on quote library (Markdown)**
2. Tag highlights, then **Sync now**
3. Open `library/` on your PC (WebDAV root or copy locally) in [Obsidian](https://obsidian.md)

## With AnkiKoFlash (optional)

Install [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) alongside Tag Bank:

- AnkiKoFlash sends Vocabulary / Memorization cards to desktop Anki
- Tag Bank tags highlights and syncs JSON + Markdown quote library
- **View All Highlights** in AnkiKoFlash can **Sync All Highlights** across all books when Tag Bank is loaded

See [AnkiKoFlash companion](companion-ankikoflash.md) and [AnkiKoFlash getting started](https://github.com/3gnome/AnkiKoFlash.koplugin/blob/main/docs/getting-started.md).

## Troubleshooting

| Problem | Check |
|---------|--------|
| **Cloud folder** tap does nothing | Kindle v2026.03 may need `buttonselector.lua` patch — see README § Kindle |
| Sync 404 for new book | Expected until first successful upload; re-sync after highlighting |
| **Sync pending** appears | The last upload was deferred or failed; reconnect and run **Sync Highlights**, or reopen the book with sync-on-open enabled |
| Tags not in Obsidian | Enable quote library; run **Sync now**; open `library/` not raw `*.sdr.json` |
| No contextual suggestions | Tag more highlights in this book first; only existing, previously used bank tags are suggested |
| Orange/green filter labels mention Anki | Only when [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin) is installed |
