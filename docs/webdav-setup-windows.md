# WebDAV setup (Windows)

Run a small local WebDAV server on your PC so KOReader can sync highlight sidecars and read exported library files over home Wi‑Fi.

**Full step-by-step guide (shared with AnkiKOAi ecosystem):**  
[AnkiKOAi — WebDAV setup (Windows)](https://github.com/3gnome/AnkiKOAi.koplugin/blob/main/docs/webdav-setup-windows.md)

That guide covers:

- Installing [hacdias/webdav](https://github.com/hacdias/webdav)
- `webdav.yaml`, firewall, scheduled task (no terminal window)
- KOReader **Cloud storage+** and **Tag Bank → Cloud folder** configuration
- iPhone **Files** app access

## Quick summary

| Item | Typical value |
|------|----------------|
| WebDAV root | A dedicated folder (e.g. `Desktop/KOReader Highlights`) |
| URL from e-reader | `http://<LAN-IP>:8181/` |
| Auth | Blank user/password (home network only) |
| Tag Bank | **Tools → Tag Bank Highlight Sync → Cloud folder** → choose `/` |

After setup: tag highlights → **Sync now** → `*.sdr.json` and `library/` appear in the WebDAV root.

## Related

- [Getting started](getting-started.md) — plugin install and first sync
- [AnkiKOAi](https://github.com/3gnome/AnkiKOAi.koplugin) — optional Anki cards from highlights
