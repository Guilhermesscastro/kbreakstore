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

- [x] **Release Scraper (`tools/scraper.py`)**:
  - [x] Implemented dynamic GitHub topic crawler (`koreader-plugin`, `koreader-user-patch`, `kindle-homebrew`).
  - [x] Auto-discovered 146+ packages (including AI Assistants like omer-faruq/assistant, koassistant, ProjectTitle, Z-Library, Frotz, Wallabag, Readwise, Games, Tweaks).
  - [x] Automatic category classification & branch archive fallback generation.
- [x] **GitHub Actions Workflow (`.github/workflows/update-registry.yml`)**:
  - [x] Scheduled cron trigger (every 12 hours) to keep all 146+ packages continuously updated from GitHub.
- [x] **Milestone 2 Test**: Successfully built and validated 146-package catalog in `manifest.v2.json`.

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
- [x] **Push to GitHub**: Pushed project to `https://github.com/Guilhermesscastro/kbreakstore`.
- [ ] **Ensure Public Visibility**: Check repo visibility in Settings.
- [ ] **On-Device UI Test**: Launch KOReader, connect to Wi-Fi, open the store menu, and browse packages.
- [ ] **Install Test**: Perform a test install of a package directly on-screen.
- [ ] **Seed Additional Packages**: Add more community homebrew and KOReader plugins to `registry/sources.json`.
