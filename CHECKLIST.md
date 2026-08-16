# 📋 KindleBreak Store - Project Checklist & Roadmap

This checklist tracks the implementation, testing, and rollout milestones for the KindleBreak Store.

---

## 🎯 Phase 1: Repository Architecture & KPM Schema
- [x] **Repository Directory Structure**: Created `registry/`, `tools/`, and `client/` layout.
- [x] **Source Definitions (`registry/sources.json`)**: Configured upstream repositories (KOReader, kTerm, ScreenSavers, FBInk, KindleBreak Plugin) with architecture asset filters (`kindlehf`, `kindlepw2`, `kindle`).
- [x] **KPM Manifest Schema (`registry/manifest.v2.json`)**: Adhered to standard KPM Manifest v2 while adding enriched GUI metadata (`category`, `homepage`, `package_type`).
- [x] **Manifest Validator & Packager (`tools/packager.py`)**:
  - [x] Schema & version tuple validation (`[major, minor, patch]`).
  - [x] `.kpkg` archive builder with `manifest.json` checks.
  - [x] Safe archive extraction with path-traversal guards.
- [x] **Milestone 1 Test**: Verified with `python tools/packager.py validate registry/manifest.v2.json`.

---

## 🤖 Phase 2: Automated Scraper & GitHub Actions
- [x] **Release Scraper (`tools/scraper.py`)**:
  - [x] Queries GitHub Releases API with optional `GITHUB_TOKEN` support.
  - [x] Matches target architecture assets via glob patterns.
  - [x] Parses tag versions and updates `manifest.v2.json` cleanly.
  - [x] Supports `--dry-run` and live sync modes.
- [x] **GitHub Actions Workflow (`.github/workflows/update-registry.yml`)**:
  - [x] Scheduled cron trigger (every 12 hours).
  - [x] Manual trigger (`workflow_dispatch`).
  - [x] Auto-commit and push updated manifest.
- [x] **Milestone 2 Test**: Successfully scraped live KOReader release assets (`kindlehf`, `kindlepw2`, `kindle`).

---

## 🔧 Phase 3: Installer Engine & KPM Bridge
- [x] **POSIX Installer Script (`tools/kinstall.sh`)**:
  - [x] Kindle hardware architecture detection (`kindlehf` vs `kindlepw2`).
  - [x] Native `kpm` CLI delegation for system packages.
  - [x] Standalone `.kpkg` extractor with `install.sh` / `uninstall.sh` hook support.
  - [x] Direct extraction for KOReader plugins to `/mnt/us/koreader/plugins/`.
- [x] **Milestone 3 Test**: Verified packaging and extraction routines.

---

## 📱 Phase 4: KOReader GUI Store Plugin (`kbreakstore.koplugin`)
- [x] **Plugin Metadata (`_meta.lua`)**: Registered under tools category with localization support.
- [x] **Main Menu Integration (`main.lua`)**: Hooks into KOReader's Top Menu -> Tools.
- [x] **Repository Network Manager (`kbreakstore_repo.lua`)**:
  - [x] Remote manifest fetching via `socket.http` / `curl`.
  - [x] Local offline cache in `/mnt/us/kbreakstore/manifest_cache.json`.
  - [x] Package state detection (*Not Installed*, *Installed*, *Update Available*).
- [x] **Package Installer Bridge (`kbreakstore_installer.lua`)**:
  - [x] Asynchronous download pipeline.
  - [x] Extraction and cleanup without restarting Kindle services.
- [x] **E-Ink Touch UI (`kbreakstore_ui.lua`)**:
  - [x] Category picker (All, KOReader Plugins, Readers, Utilities, Tweaks, Installed).
  - [x] Real-time on-screen keyboard search dialog.
  - [x] Package detail modal with Install / Update / Reinstall / Uninstall actions.
- [x] **Milestone 4 Test**: File integrity & syntax validation passed.

---

## 🚀 Phase 5: Next Steps & Device Deployment (To Do)
- [ ] **Copy Plugin to Kindle**: Copy `client/kbreakstore.koplugin/` to `/mnt/us/koreader/plugins/`.
- [ ] **On-Device UI Test**: Launch KOReader, connect to Wi-Fi, open the store menu, and browse packages.
- [ ] **Install Test**: Perform a test install of a package directly on-screen.
- [ ] **Push to GitHub**: Initialize git repository and push to GitHub so GitHub Pages can host the live manifest.
- [ ] **Seed Additional Packages**: Add more community homebrew and KOReader plugins to `registry/sources.json`.
