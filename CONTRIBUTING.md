# Contributing

1. Fork [tagbankhighlightsync.koplugin](https://github.com/3gnome/tagbankhighlightsync.koplugin)
2. Create a branch for your change
3. Run tests: `bash _check.sh` and `luajit spec/run_tests.lua` (KOReader luajit)
4. Run the privacy guard (below)
5. Open a pull request

Do not commit `LOCAL_DEV.md`, `.shift/`, `*.sdr/`, test epubs, or logs.

## Privacy guard (before commit, push, or deploy)

This plugin stores quotes and syncs over your local network, so it is easy to
accidentally commit personal data (LAN IP, `/mnt/c/Users/<you>` paths, WebDAV
URLs, sample highlights). Before any `git commit`, `git push`, or release, run:

```bash
bash pre-commit-privacy-check.sh
```

It scans staged, unstaged, and untracked changes for personal home paths, private
LAN IPs, email addresses, private keys, and hardcoded secrets, and exits non-zero
if anything is found. Replace findings with placeholders (`192.168.x.x`,
`YOUR_API_KEY`, `/mnt/c/Users/<you>`) and re-run. To make it automatic, symlink it
once as a git hook:

```bash
ln -s ../../pre-commit-privacy-check.sh .git/hooks/pre-commit
```

Optional companion plugin: [AnkiKoFlash](https://github.com/3gnome/AnkiKoFlash.koplugin).
