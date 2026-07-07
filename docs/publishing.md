# Publishing TagBankHighlightSync

## GitHub About (one line)

```
KOReader plugin: tag highlights, sync annotations via WebDAV/cloud, export Obsidian quote library. Optional AnkiKOAi companion for Anki cards.
```

## Topics

`koreader-plugin` `koreader` `highlights` `webdav` `obsidian` `markdown` `sync`

## Before you publish

- [ ] `LOCAL_DEV.md` is **not** tracked (gitignored)
- [ ] No `*.sdr/`, `alice.epub`, or `*.log` in commits
- [ ] [LICENSE](../LICENSE) (AGPL-3.0) present
- [ ] [README.md](../README.md) links to [AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin) where relevant

## Release

```bash
# First time: gh auth login
bash release.sh --notes-file docs/release-notes-v0.9.1.md
```

Produces `../tagbankhighlightsync-vX.Y.Z.zip` and a GitHub Release.

## First-time GitHub repo

```bash
git init
git add .
git commit -m "Initial release: TagBankHighlightSync"
gh repo create 3gnome/tagbankhighlightsync.koplugin --public \
  --description "KOReader: tag highlights, cloud sync, Obsidian quote library" \
  --source=. --remote=origin --push
bash release.sh --notes-file docs/release-notes-v0.9.1.md
```

## Cross-links

When docs mention AnkiKOAi, link:  
`https://github.com/3gnome/AnkiKOAi.koplugin`

AnkiKOAi docs link back to this repo for Tag Bank / WebDAV / quote library.
