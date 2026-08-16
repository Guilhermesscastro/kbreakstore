#!/usr/bin/env python3
"""
KindleBreak Dynamic Scraper & Catalog Builder (scraper.py)
1. Crawls GitHub topics ('koreader-plugin', 'koreader-user-patch', 'kindle-homebrew')
2. Synchronizes curated standalone packages and tweaks from sources.json
3. Generates release/archive download links and builds an extensive manifest.v2.json
"""

import argparse
import fnmatch
import json
import logging
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

logging.basicConfig(format="[%(levelname)s] %(message)s", level=logging.INFO)
logger = logging.getLogger("scraper")

GITHUB_API_BASE = "https://api.github.com"

# Category classification heuristics based on keywords/topics
CATEGORY_RULES = {
    "ai": ["ai", "gpt", "claude", "gemini", "deepseek", "ollama", "llm", "assistant", "summariz"],
    "dict": ["dictionary", "translate", "translation", "anki", "vocab", "deepl", "stardict", "lookup"],
    "sync": ["sync", "readwise", "wallabag", "notion", "obsidian", "telegram", "cloud", "webdav", "dropbox", "storygraph", "hardcover", "omnivore"],
    "library": ["library", "zotero", "calibre", "opds", "cover", "projecttitle", "bookends", "manga", "zlibrary"],
    "games": ["game", "chess", "sudoku", "frotz", "2048", "doom", "mines", "tetris", "solitaire", "puzzle", "zork"],
    "tweaks": ["tweak", "screensaver", "font", "hotfix", "sanctuary", "adbreak", "patch", "kual", "lock"],
    "readers": ["reader", "koreader", "plato", "viewer", "epub", "pdf"],
    "utilities": ["terminal", "kterm", "fbink", "usbnet", "ssh", "python", "tailscale", "syncthing", "vnc", "calc", "clock", "browser"],
}


def parse_version_string(v_str: str) -> List[int]:
    """Converts version strings like 'v2026.07.1', '1.4.2', 'v0.7k' into [major, minor, patch]."""
    cleaned = re.sub(r"^[^\d]*", "", str(v_str).strip())
    parts = re.split(r"[.\-_]", cleaned)
    nums: List[int] = []
    for part in parts:
        m = re.match(r"^(\d+)", part)
        if m:
            nums.append(int(m.group(1)))
        if len(nums) == 3:
            break
    while len(nums) < 3:
        nums.append(0)
    return nums[:3]


def infer_category(name: str, desc: str, topics: List[str]) -> str:
    """Classifies a package into a standard category."""
    text = f"{name} {desc} {' '.join(topics)}".lower()
    for cat, kws in CATEGORY_RULES.items():
        for kw in kws:
            if kw in text:
                return cat
    return "plugins"


def github_request(endpoint: str, token: Optional[str] = None) -> Any:
    """Performs a GET request to the GitHub API."""
    url = f"{GITHUB_API_BASE}/{endpoint.lstrip('/')}"
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "KindleBreak-Scraper/2.0",
    }
    if token:
        headers["Authorization"] = f"token {token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except urllib.error.HTTPError as e:
        logger.warning(f"HTTP Error {e.code} for {url}: {e.reason}")
        return None
    except Exception as e:
        logger.warning(f"Error requesting {url}: {e}")
        return None


def search_github_topic(topic: str, token: Optional[str] = None, max_results: int = 100) -> List[Dict[str, Any]]:
    """Searches GitHub for repositories tagged with a specific topic."""
    logger.info(f"Searching GitHub topic '{topic}'...")
    query = urllib.parse.quote(f"topic:{topic}")
    data = github_request(f"search/repositories?q={query}&sort=stars&order=desc&per_page={max_results}", token)
    if data and "items" in data:
        return data["items"]
    return []


def fetch_latest_release(repo: str, token: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Fetches the latest release data for a repo."""
    data = github_request(f"repos/{repo}/releases/latest", token)
    if data and "tag_name" in data:
        return data
    releases = github_request(f"repos/{repo}/releases?per_page=1", token)
    if releases and isinstance(releases, list) and len(releases) > 0:
        return releases[0]
    return None


def match_asset(assets: List[Dict[str, Any]], pattern: str) -> Optional[Dict[str, Any]]:
    """Finds the first release asset matching a glob pattern."""
    for asset in assets:
        name = asset.get("name", "")
        if fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(name.lower(), pattern.lower()):
            return asset
    return None


def clean_title(full_name: str, name: str) -> str:
    """Generates a clean human-readable title."""
    title = name.replace(".koplugin", "").replace("koreader-", "").replace("-koplugin", "").replace("-", " ").replace("_", " ").title()
    if "Assistant" in title and "Omer Faruq" in full_name:
        return "Assistant (AI Multi-Provider)"
    if "Assistant" in title and "Zeeyado" in full_name:
        return "KOAssistant (AI Translation & Summary)"
    return title


def run_full_scrape(
    sources_file: Path,
    manifest_file: Path,
    token: Optional[str] = None,
    dry_run: bool = False,
    discover_topics: bool = True,
) -> bool:
    """Orchestrates topic discovery + curated sources sync."""
    sources_cfg: Dict[str, Any] = {"sources": [], "discover_topics": ["koreader-plugin", "kindle-homebrew"]}
    if sources_file.exists():
        with open(sources_file, "r", encoding="utf-8") as f:
            sources_cfg = json.load(f)

    manifest_data: Dict[str, Any] = {
        "manifest_version": 2,
        "id": "kbreakstore",
        "name": "KindleBreak Store",
        "description": "Unified homebrew, tweaks, games, and KOReader plugins repository for jailbroken Kindles",
        "url": "https://raw.githubusercontent.com/Guilhermesscastro/kbreakstore/main/registry/",
        "packages": {},
    }

    if manifest_file.exists():
        try:
            with open(manifest_file, "r", encoding="utf-8") as f:
                manifest_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load existing manifest: {e}")

    packages_dict = manifest_data.setdefault("packages", {})
    processed_repos: Set[str] = set()

    # 1. Process curated sources from sources.json first
    logger.info(f"--- Processing {len(sources_cfg.get('sources', []))} curated sources ---")
    for src in sources_cfg.get("sources", []):
        pkg_id = src["id"]
        github_repo = src.get("github_repo")
        asset_filters = src.get("asset_filters", {})

        if pkg_id not in packages_dict:
            packages_dict[pkg_id] = {}

        pkg_entry = packages_dict[pkg_id]
        pkg_entry["name"] = src.get("name", pkg_entry.get("name", pkg_id))
        pkg_entry["author"] = src.get("author", pkg_entry.get("author", "Community"))
        pkg_entry["description"] = src.get("description", pkg_entry.get("description", ""))
        pkg_entry["category"] = src.get("category", pkg_entry.get("category", "utilities"))
        pkg_entry["package_type"] = src.get("package_type", pkg_entry.get("package_type", "system"))
        if "homepage" in src:
            pkg_entry["homepage"] = src["homepage"]

        if github_repo:
            processed_repos.add(github_repo.lower())
            rel = fetch_latest_release(github_repo, token)
            if rel:
                tag = rel.get("tag_name", "1.0.0")
                ver = parse_version_string(tag)
                assets = rel.get("assets", [])
                new_arts = []

                if "all" in asset_filters:
                    m = match_asset(assets, asset_filters["all"])
                    if m:
                        new_arts.append({
                            "url": m["browser_download_url"],
                            "version": ver,
                            "dependencies": [],
                            "supported_platforms": ["kindlehf", "kindlepw2", "kindle"],
                        })
                else:
                    for plat, pattern in asset_filters.items():
                        m = match_asset(assets, pattern)
                        if m:
                            new_arts.append({
                                "url": m["browser_download_url"],
                                "version": ver,
                                "dependencies": [],
                                "supported_platforms": [plat],
                            })
                if new_arts:
                    pkg_entry["artifacts"] = new_arts
            
            # If no release assets matched, ensure archive zip exists
            if "artifacts" not in pkg_entry or not pkg_entry["artifacts"]:
                pkg_entry["artifacts"] = [{
                    "url": f"https://github.com/{github_repo}/archive/refs/heads/main.zip",
                    "version": [1, 0, 0],
                    "dependencies": [],
                    "supported_platforms": ["kindlehf", "kindlepw2", "kindle"],
                }]

    # 2. Automatically discover all plugins from GitHub topics
    if discover_topics:
        topics_to_crawl = sources_cfg.get("discover_topics", ["koreader-plugin", "kindle-homebrew"])
        logger.info(f"--- Crawling GitHub topics: {topics_to_crawl} ---")
        for topic in topics_to_crawl:
            discovered_items = search_github_topic(topic, token, max_results=100)
            logger.info(f"Found {len(discovered_items)} repositories tagged '{topic}'.")

            for repo_data in discovered_items:
                full_name = repo_data["full_name"]
                if full_name.lower() in processed_repos:
                    continue

                processed_repos.add(full_name.lower())
                repo_name = repo_data["name"]
                owner = repo_data.get("owner", {}).get("login", "Community")
                desc = repo_data.get("description") or f"{repo_name} for KOReader."
                stars = repo_data.get("stargazers_count", 0)
                topics = repo_data.get("topics", [])
                default_branch = repo_data.get("default_branch", "main")

                # Generate clean package id (alphanumeric with hyphens)
                clean_id = re.sub(r"[^a-zA-Z0-9_\-]", "", repo_name.lower().replace(".koplugin", ""))
                if not clean_id or len(clean_id) < 2:
                    clean_id = re.sub(r"[^a-zA-Z0-9_\-]", "", f"{owner.lower()}-{repo_name.lower()}")

                # If duplicate id, prepend owner
                if clean_id in packages_dict and packages_dict[clean_id].get("homepage") != repo_data.get("html_url"):
                    clean_id = f"{owner.lower()}-{clean_id}"

                is_koplugin = "koreader-plugin" in topics or repo_name.endswith(".koplugin") or "koplugin" in repo_name.lower()
                pkg_type = "koreader_plugin" if is_koplugin else "system"
                cat = infer_category(repo_name, desc, topics)

                # Check for releases or default branch zip
                rel = fetch_latest_release(full_name, token)
                artifacts = []
                if rel:
                    tag = rel.get("tag_name", "1.0.0")
                    ver = parse_version_string(tag)
                    assets = rel.get("assets", [])
                    # Match any zip / tarball asset
                    for asset in assets:
                        aname = asset.get("name", "").lower()
                        if aname.endswith((".zip", ".tar.gz", ".kpkg", ".tar.xz")):
                            artifacts.append({
                                "url": asset["browser_download_url"],
                                "version": ver,
                                "dependencies": [],
                                "supported_platforms": ["kindlehf", "kindlepw2", "kindle"],
                            })
                            break

                if not artifacts:
                    # Fallback to direct archive download
                    artifacts = [{
                        "url": f"https://github.com/{full_name}/archive/refs/heads/{default_branch}.zip",
                        "version": [1, 0, 0],
                        "dependencies": [],
                        "supported_platforms": ["kindlehf", "kindlepw2", "kindle"],
                    }]

                packages_dict[clean_id] = {
                    "name": clean_title(full_name, repo_name),
                    "author": owner,
                    "description": desc,
                    "category": cat,
                    "package_type": pkg_type,
                    "homepage": repo_data.get("html_url"),
                    "stars": stars,
                    "artifacts": artifacts,
                }

    total_count = len(packages_dict)
    logger.info(f"Scrape completed! Total packages in registry: {total_count}")

    if dry_run:
        logger.info("DRY RUN: skipping file write.")
        print(f"Total packages discovered: {total_count}")
        return True

    manifest_file.parent.mkdir(parents=True, exist_ok=True)
    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2, ensure_ascii=False)

    logger.info(f"Saved {total_count} packages to {manifest_file}")
    return True


def main():
    parser = argparse.ArgumentParser(description="KindleBreak Dynamic Scraper & Catalog Builder")
    parser.add_argument("--config", type=Path, default=Path("registry/sources.json"), help="Path to sources.json")
    parser.add_argument("--output", type=Path, default=Path("registry/manifest.v2.json"), help="Path to output manifest.v2.json")
    parser.add_argument("--token", type=str, default=os.getenv("GITHUB_TOKEN"), help="GitHub API Token")
    parser.add_argument("--dry-run", action="store_true", help="Dry run without writing")
    parser.add_argument("--no-discover", action="store_true", help="Disable dynamic GitHub topic discovery")

    args = parser.parse_args()
    success = run_full_scrape(
        sources_file=args.config,
        manifest_file=args.output,
        token=args.token,
        dry_run=args.dry_run,
        discover_topics=not args.no_discover,
    )
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
