#!/usr/bin/env python3
"""
KindleBreak Upstream Release Scraper (scraper.py)
Fetches latest releases from upstream GitHub repositories and updates manifest.v2.json.
"""

import argparse
import fnmatch
import json
import logging
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logging.basicConfig(format="[%(levelname)s] %(message)s", level=logging.INFO)
logger = logging.getLogger("scraper")

GITHUB_API_BASE = "https://api.github.com"


def parse_version_string(v_str: str) -> List[int]:
    """Converts version strings like 'v2024.04.1', '0.7k', 'v0.25.N' into [major, minor, patch]."""
    cleaned = re.sub(r"^[^\d]*", "", v_str.strip())
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


def github_request(endpoint: str, token: Optional[str] = None) -> Any:
    """Performs an authenticated or anonymous GET request to GitHub API."""
    url = f"{GITHUB_API_BASE}/{endpoint.lstrip('/')}"
    headers = {
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "KindleBreak-Scraper/1.0",
    }
    if token:
        headers["Authorization"] = f"token {token}"

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data)
    except urllib.error.HTTPError as e:
        logger.warning(f"HTTP Error {e.code} for {url}: {e.reason}")
        return None
    except Exception as e:
        logger.warning(f"Error requesting {url}: {e}")
        return None


def fetch_latest_release(repo: str, token: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Fetches the latest release data for a repo."""
    logger.info(f"Fetching latest release for {repo}...")
    data = github_request(f"repos/{repo}/releases/latest", token)
    if data and "tag_name" in data:
        return data
    
    # Fallback to list of releases if 'latest' is not tagged
    releases = github_request(f"repos/{repo}/releases?per_page=1", token)
    if releases and isinstance(releases, list) and len(releases) > 0:
        return releases[0]

    return None


def match_asset(assets: List[Dict[str, Any]], pattern: str) -> Optional[Dict[str, Any]]:
    """Finds first release asset whose name matches the given glob pattern."""
    for asset in assets:
        name = asset.get("name", "")
        if fnmatch.fnmatch(name, pattern) or fnmatch.fnmatch(name.lower(), pattern.lower()):
            return asset
    return None


def scrape_sources(
    sources_file: Path,
    manifest_file: Path,
    token: Optional[str] = None,
    dry_run: bool = False,
) -> bool:
    """Processes sources.json and updates manifest.v2.json."""
    if not sources_file.exists():
        logger.error(f"Sources file not found: {sources_file}")
        return False

    with open(sources_file, "r", encoding="utf-8") as f:
        sources_cfg = json.load(f)

    manifest_data: Dict[str, Any] = {
        "manifest_version": 2,
        "id": "kbreakstore",
        "name": "KindleBreak Store",
        "description": "Unified homebrew and KOReader plugin repository for jailbroken Kindles",
        "packages": {},
    }

    if manifest_file.exists():
        try:
            with open(manifest_file, "r", encoding="utf-8") as f:
                manifest_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load existing manifest: {e}, creating new.")

    packages_dict = manifest_data.setdefault("packages", {})
    updated_count = 0

    for src in sources_cfg.get("sources", []):
        pkg_id = src["id"]
        github_repo = src.get("github_repo")
        asset_filters = src.get("asset_filters", {})

        logger.info(f"Processing source '{pkg_id}' ({github_repo or 'local'})...")

        # Initialize or update base package metadata
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

        if not github_repo:
            continue

        release_data = fetch_latest_release(github_repo, token)
        if not release_data:
            logger.warning(f"Could not fetch release for {github_repo}, preserving existing artifacts.")
            continue

        tag_name = release_data.get("tag_name", "0.0.0")
        version_tuple = parse_version_string(tag_name)
        assets = release_data.get("assets", [])

        new_artifacts: List[Dict[str, Any]] = []

        # Check filter for all platforms
        if "all" in asset_filters:
            matched = match_asset(assets, asset_filters["all"])
            if matched:
                new_artifacts.append({
                    "url": matched["browser_download_url"],
                    "version": version_tuple,
                    "dependencies": [],
                    "supported_platforms": ["kindlehf", "kindlepw2", "kindle"],
                })
        else:
            for platform, pattern in asset_filters.items():
                matched = match_asset(assets, pattern)
                if matched:
                    new_artifacts.append({
                        "url": matched["browser_download_url"],
                        "version": version_tuple,
                        "dependencies": [],
                        "supported_platforms": [platform],
                    })

        if new_artifacts:
            pkg_entry["artifacts"] = new_artifacts
            updated_count += 1
            logger.info(f"  -> Updated {pkg_id} to tag {tag_name} (v{version_tuple}) with {len(new_artifacts)} artifact(s)")
        else:
            logger.warning(f"  -> No assets matched filters for {pkg_id} in release {tag_name}")

    logger.info(f"Scraper finished: updated {updated_count} package(s).")

    if dry_run:
        logger.info("DRY RUN: skipping file write. Resulting manifest preview:")
        print(json.dumps(manifest_data, indent=2))
        return True

    manifest_file.parent.mkdir(parents=True, exist_ok=True)
    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(manifest_data, f, indent=2)

    logger.info(f"Saved updated manifest to {manifest_file}")
    return True


def main():
    parser = argparse.ArgumentParser(description="KindleBreak Upstream Release Scraper")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("registry/sources.json"),
        help="Path to sources.json",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("registry/manifest.v2.json"),
        help="Path to output manifest.v2.json",
    )
    parser.add_argument(
        "--token",
        type=str,
        default=os.getenv("GITHUB_TOKEN"),
        help="GitHub API token (optional, avoids rate limits)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Test scraping without overwriting manifest",
    )

    args = parser.parse_args()
    success = scrape_sources(
        sources_file=args.config,
        manifest_file=args.output,
        token=args.token,
        dry_run=args.dry_run,
    )
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
