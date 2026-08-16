# 📦 KindleBreak Store (KPM Index & KOReader GUI)

A modern, unified package repository and on-screen store for jailbroken Amazon Kindle devices (supporting all modern firmware versions: 5.14.x through 5.17.x+).

---

## 🌟 Features

- **Dual-Interface Compatibility**:
  - **KOReader GUI**: In-app graphical store (`kbreakstore.koplugin`) with categorized browsing, live search, and 1-click install/update.
  - **KPM CLI Compatible**: Serves standard `manifest.v2.json` index so users can also install packages using search-bar commands (`;kpm install <id>`).
- **Automated Upstream Scraper**:
  - GitHub Actions runs automatically to scrape upstream releases (KOReader, kTerm, ScreenSavers hack, FBInk) and update the manifest without manual intervention.
- **Support for All Architectures**:
  - Automatically resolves packages for `kindlehf` (modern Kindle Paperwhite 3/4/5, Oasis, Scribe, Basic 10/11) and `kindlepw2` / `kindle5`.

---

## 📂 Project Structure

```
kbreakstore/
├── .github/
│   └── workflows/
│       └── update-registry.yml       # Scheduled GitHub Action scraper
├── registry/
│   ├── sources.json                  # Upstream tracked repositories
│   └── manifest.v2.json              # Published KPM & GUI manifest
├── tools/
│   ├── scraper.py                    # GitHub releases scraper
│   ├── packager.py                   # KPM manifest validator & .kpkg builder
│   └── kinstall.sh                   # On-device shell installer & KPM bridge
└── client/
    └── kbreakstore.koplugin/         # KOReader GUI Store Plugin
        ├── _meta.lua                 # Plugin metadata
        ├── main.lua                  # Menu hook & lifecycle
        ├── kbreakstore_repo.lua      # Network fetcher, cache & state manager
        ├── kbreakstore_installer.lua # Download & extraction pipeline
        └── kbreakstore_ui.lua        # Touch interface (Tabs, Search, Details)
```

---

## 🚀 Installation

### Option 1: Install the KOReader Plugin (Recommended)

1. Connect your Kindle to your computer via USB.
2. Copy the `client/kbreakstore.koplugin/` folder into your Kindle's `/mnt/us/koreader/plugins/` directory:
   ```text
   /mnt/us/koreader/plugins/kbreakstore.koplugin/
   ```
3. Restart KOReader on your Kindle.
4. Open the top menu -> **Tools** (gear/wrench icon) -> **📦 KindleBreak Store**.

### Option 2: Use via KPM Search Bar

Add this repository URL to your KPM repositories or install directly:
```bash
;kpm add-repo https://raw.githubusercontent.com/kbreakstore/kbreakstore/main/registry/manifest.v2.json
;kpm update
;kpm install koreader
```

---

## 🛠 Developer Commands

### 1. Validate the Manifest
```bash
python tools/packager.py validate registry/manifest.v2.json
```

### 2. Test Upstream Scraper (Dry Run)
```bash
python tools/scraper.py --config registry/sources.json --dry-run
```

### 3. Sync and Update Manifest Locally
```bash
python tools/scraper.py --config registry/sources.json --output registry/manifest.v2.json
```

### 4. Pack a Homebrew Directory into a `.kpkg`
```bash
python tools/packager.py pack path/to/package_dir dist/mypackage.kpkg
```
