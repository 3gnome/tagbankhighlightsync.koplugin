# TagBankHighlightSync

**TagBankHighlightSync** tags highlights on KOReader, synchronizes and merges annotations across devices via cloud storage (WebDAV, Dropbox, and other Cloud storage+ providers), and exports a tagged quote library for Obsidian and other Markdown tools.

**Releases:** [github.com/3gnome/tagbankhighlightsync.koplugin](https://github.com/3gnome/tagbankhighlightsync.koplugin/releases)  
**Optional companion:** [AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin) — Anki flashcards from highlights (works standalone without AnkiKOAi)

---

## Beta Warning

This plugin is in **beta**. Back up your annotations regularly.

---

## Installation

1. Download the [latest release](https://github.com/3gnome/tagbankhighlightsync.koplugin/releases) or copy the `tagbankhighlightsync.koplugin` folder.
2. Place it in `koreader/plugins/` on your device.
3. Enable **TagBankHighlightSync** and **Cloud storage** (plugin name; menu may show **Cloud Storage** on device) in **Tools → More tools → Plugin management**.

**Full walkthrough:** [docs/getting-started.md](docs/getting-started.md)

TagBank works on its own for Obsidian/WebDAV quote libraries and JSON sync. **[AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin)** is optional — a separate plugin. When both are installed, **Settings → Quote library** labels orange/green highlight filters with Anki workflow wording; with TagBank alone, the same filters use neutral “Exclude orange/green highlights” labels (behavior unchanged). See [docs/companion-ankikooai.md](docs/companion-ankikooai.md).

## Documentation

| Guide | Contents |
|-------|----------|
| [Documentation index](docs/README.md) | Overview of all guides |
| [Getting started](docs/getting-started.md) | Install, cloud folder, first tag, first sync |
| [WebDAV setup (Windows)](docs/webdav-setup-windows.md) | Local WebDAV for home Wi‑Fi (links full AnkiKOAi guide) |
| [AnkiKOAi companion](docs/companion-ankikooai.md) | Optional Anki cards + View All Highlights sync |
| [Publishing](docs/publishing.md) | GitHub releases, topics |

---

## Setup

### Cloud storage (required)

Two separate steps — configuring WebDAV in **Cloud Storage** does **not** auto-fill HighlightSync:

1. **Tools → Cloud Storage** — add your cloud account (WebDAV, Dropbox, etc.).
2. **Tools → Tag Bank Highlight Sync → Cloud folder** — tap your server, open `/`, long-press **Long-press here to choose current folder**, tap **Choose**.

If **Cloud folder** tap does nothing, check terminal for `ERROR cloudstorage:onShowCloudStorageList` (emulator) or an on-screen **Cloud storage failed to open** message. On Kindle, if **Choose** at WebDAV root (`/`) does nothing, update TagBank — it applies a runtime fix for stock `cloudstorage.koplugin` (emulator patches this on disk).

### Local WebDAV on Windows (optional)

If you run a WebDAV server on your PC (e.g. `webdav.exe` serving `KOReader Highlights` on port 8181):

| Setting | Value |
|---------|-------|
| Type | WebDAV |
| Address | `http://<your-PC-LAN-IP>:8181/` |
| Username / password | Leave **blank** if auth is disabled |
| Sync folder | `/` (flat root) |

**Dev emulator (WSL):** install Cloud storage for the v2026.03 emulator, then seed WebDAV settings:

```bash
bash setup-emulator-cloud.sh    # must print: Load OK: cloudstorage plugin + buttonselector
bash configure-emulator-webdav.sh
```

See `KOReader-WebDAV-Setup.md` in your Highlights folder for the full PC setup (scheduled task, firewall, troubleshooting).

---

## Menu

| Item | Description |
|------|-------------|
| **Cloud folder** | Configure cloud folder (Edit / Delete) |
| **Sync Highlights** | Manual sync for current book (reader only) |
| **Batch sync folder** | Upload existing sidecar JSON files (file manager only) |
| **Settings** | When/how to sync, what to sync, categories, quote library, advanced options |

JSON sync (`*.sdr.json`) remains the source of truth for device merge. Tags are stored as `highlight_sync_tags` (tag and category ids). Markdown export expands ancestors (e.g. opening **Buddhism** and choosing **aversion** → `#buddhism #aversion`). Inside a folder, the folder name row toggles the parent tag (e.g. `#buddhism`); **Add tag… → Make folder** creates a new category at the current location and applies that parent tag.

Long-press a highlight → **Tag & sync…** → **Tag highlight** / **Sync now** (tags save locally; cloud Markdown only on **Sync now**). Hold tags or folders in Tag highlight to rename, move, or delete. **Add tag…** inside a folder saves the tag there on **Add** (like **Add folder…**). At the bank root, **Add** offers Make folder / Add to bank / Apply only; **Add to bank** opens a folder picker (**tap** to save, **hold** to browse).

### Two layers on cloud storage

| Layer | Files | Purpose | Default |
|-------|-------|---------|---------|
| **Device sync** | `{sidecar}.json` | Merge highlights, notes, and tags across KOReader devices | On (Sync Highlights) |
| **Quote library** | `library/books/*.md`, `master-quotes.md`, `library/tags/*.md`, `library/quotes/*.md` | Browse and search on PC (Obsidian, Apple Notes) | Off — enable in Settings |

Enable **Settings → Quote library → Turn on quote library (Markdown)**, then **Tag & sync → Sync now** after tagging.

| File (in cloud `library/` folder) | Contents |
|-----------------------------------|----------|
| `books/{sidecar}.md` | Full literature note per book (**Apple Notes** import) |
| `quotes/{key}.md` | One atomic note per tagged highlight — link with `[[quotes/…]]` |
| `master-quotes.md` | Cross-book index linking to `quotes/` |
| `tags/{tag}.md` | Theme index linking to `quotes/` (e.g. `buddhism.md`) |

The quote library always uses this layout: canonical quote bodies live in `quotes/`; master and tags are link indexes; `books/` stays a full per-book file. **First sync after a plugin upgrade** re-uploads the library even when highlight text is unchanged.

### Obsidian (free, personal use)

[Obsidian](https://obsidian.md) is free for personal use. Open your WebDAV `library/` folder as a vault (or copy it locally). Link `[[quotes/…]]` from drafts; use Dataview on `quotes/` (see `templates/Writing Dashboard.md`). Paid Sync/Publish add-ons are optional if you already use WebDAV.

### Apple Notes (macOS Tahoe / iOS 26+)

**Always use `library/books/{book}.md`** — one Markdown file → one note (File → Import Markdown on Mac; Share → Notes on iPhone).

| Need | Best approach |
|------|----------------|
| **Live reading on phone** | Open `books/{book}.md` from Files (WebDAV) or Obsidian Mobile — updates after each Sync now |
| **Occasional Apple Notes snapshot** | Import one book file; delete the old note before re-importing (re-import creates a duplicate) |
| **Cross-book tag search on phone** | Obsidian Mobile or Files — not Apple Notes |

Do **not** import `quotes/`, `master-quotes.md`, or `tags/` into Notes (too fragmented). Notes does not live-link to WebDAV — use **per-book** files here and **quotes/** or **tags/** indexes in Obsidian for cross-book work.

Do not merge devices through Markdown; always use JSON sync for that.

---

## Quote library (tagged highlights)

Tap **gray rows** in Settings for help. Recommended path for most users:

1. **Cloud folder** (top-level menu) — set your cloud sync folder.
2. **When to sync → Turn on Tag Bank Highlight Sync**
3. **Cloud file name → Recommended: KOReader sidecar name** (same on all devices)
4. **Categories** — **Tag highlight** → **Add folder…** / **Add tag…** (Make folder from Add tag when needed)
5. **Quote library → Turn on quote library (Markdown)**
6. Tag highlights → **Sync now** (or **Sync Highlights** for JSON + library upload)

JSON syncs devices; Markdown is for PC browsing only. Markdown is regenerated on sync — safe to re-import into Apple Notes.

### Writing a book from your quotes (Obsidian)

TagBankHighlightSync exports a **research library** on WebDAV, not just raw sync files:

| Step | On device | In Obsidian |
|------|-----------|-------------|
| **Read** | Highlight passages | — |
| **Tag** | Tag by theme (Buddhism/aversion) or manuscript status (Manuscript/used) | — |
| **Collect** | **Sync now** | Open `library/` as vault |
| **Browse** | — | `tags/*.md`, `#tag` search, `quotes/` (Hybrid), or **Dataview** on `templates/Writing Dashboard.md` |
| **Synthesize** | Add highlight **notes** on device | Link `[[quotes/…]]` (Hybrid) or `[[books/{book}.md]]` |
| **Draft** | — | Tag `#used` in separate Obsidian notes (not overwritten on re-sync) |

**Export format (writer defaults):**

- Per-book `library/books/*.md` — YAML frontmatter (`type: literature`, title, author) + all highlights
- Tagged quotes — scholarly headings (`Author · *Title* · p. N · Sat 28 Jun 2026, 11:34 pm`), Obsidian callouts (`[!quote]`, `[!note]`), inline fields (`book::`, `author::`, `captured::`, `tags::`)
- No sync markers — blocks upsert by heading (re-sync replaces in place)
- `library/templates/` — Writing Dashboard, Manuscript MOC, optional `scholarly-quotes.css` snippet

**Tag bank folders for writers:** **Manuscript** (draft, used, cut) and **Themes** (add your book’s argument tags).

### Menu structure

| Submenu | What it controls |
|---------|------------------|
| **When to sync** | Master switch, auto-sync on open/close/wake, skip this book |
| **What to sync** | Highlights, notes, page bookmarks |
| **Cloud file name** | How each book's JSON file is named in the cloud |
| **Categories** | **Tag highlight** — tap to apply, hold to edit; **Add folder…** / **Add tag…** at current path |
| **Quote library** | Markdown export to `library/` on cloud sync (atomic `quotes/` + link indexes) |
| **Advanced…** | JSON size, extra exports, cloud subfolders, local copy, backup |

Advanced defaults match previous behavior (flat cloud folder, sidecar filename, no exports).

JSON remains the sync source of truth; Markdown/TXT/CSV exports (under Advanced) are optional.

---

## Important notes

### Hash-based metadata

All devices must use the same **document metadata folder** setting (sidecar vs hash). Mismatched settings produce different sync filenames.

### Changing cloud folder

Move existing JSON files manually in your cloud/WebDAV folder. The plugin warns when the folder changes but does not migrate files.

### Sync freeze & reload

Open-book sync waits a few seconds before starting so page turns work immediately; quote library Markdown regen and PNG uploads follow in the background (changed files only). Manual **Sync now** uploads capture PNGs first; use it after **Capture with screenshot** for fastest delivery to `library/quotes/images/`. Capture works without tagging; tags add master/tags index links.

After a merge that imports remote highlights, the document may reload so new highlights appear on screen.

---

## Known limitations

- Book sync filenames must match across devices (same metadata setting).
- Same position, different end: newest timestamp wins.
- Batch sync uploads JSON only (no merge) from file manager.
- Quote library Markdown is regenerated on sync; use Obsidian on PC for search UI.
- Apple Notes import is manual and may not map `#tags` to native note tags.

### Kindle (manual plugin copy)

Copy **`tagbankhighlightsync.koplugin`** (and **[AnkiKOAi.koplugin](https://github.com/3gnome/AnkiKOAi.koplugin)** if needed) into the device `koreader/plugins/` folder. KOReader v2026.03 on Kindle may also need:

| File | Why |
|------|-----|
| `frontend/ui/widget/buttonselector.lua` | Cloud storage+ folder picker |
| `frontend/datetime.lua` with `stringRFC1123ToSeconds` | WebDAV listing (stock v2026.03 crashes) |

Copy those from upstream KOReader or from your WSL emulator tree after `bash setup-emulator-cloud.sh`.

**On device:** PC WebDAV at `http://<LAN-IP>:8181/` (blank user/pass) → **Cloud storage+** → **Tag Bank → Cloud folder** → `/` → long-press → **Choose** → **Sync now**.

---

## Development

Requires the KOReader dev emulator. See [AnkiKOAi LOCAL_DEV.md.sample](https://github.com/3gnome/AnkiKOAi.koplugin/blob/main/LOCAL_DEV.md.sample) for the 3-folder workspace.

```bash
# One-time: Cloud storage plugin + WebDAV (from this repo)
bash setup-emulator-cloud.sh
bash configure-emulator-webdav.sh

# Sync both plugins + launch (from AnkiKOAi repo — clone sibling repos):
bash /path/to/AnkiKOAi.koplugin/dev-start.sh --emulator alice.epub

# Or from this repo (delegates to AnkiKOAi dev-start.sh):
bash dev-start.sh --sync-only
```

Copy `LOCAL_DEV.md.sample` → `LOCAL_DEV.md` (gitignored) for machine-specific paths.

---

## Contributing

Issues and pull requests welcome on [GitHub](https://github.com/3gnome/tagbankhighlightsync.koplugin). See [CONTRIBUTING.md](CONTRIBUTING.md).

## Testing

From the plugin directory:

```bash
bash _check.sh   # parse-check all .lua with emulator luajit
~/koreader-dev/emulator/usr/lib/koreader/luajit spec/run_tests.lua
```
