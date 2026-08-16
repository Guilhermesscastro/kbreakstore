#!/usr/bin/env python3
"""
KindleBreak Package & Manifest Tool (packager.py)
Validates KPM-compatible repository manifests and packages homebrew into .kpkg archives.
"""

import argparse
import json
import logging
import os
import re
import sys
import tarfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logging.basicConfig(format="[%(levelname)s] %(message)s", level=logging.INFO)
logger = logging.getLogger("packager")

SUPPORTED_PLATFORMS = {"kindle", "kindle5", "kindlepw2", "kindlehf"}
VALID_MANIFEST_VERSIONS = {2, 3}


class ValidationError(Exception):
    """Raised when manifest validation fails."""
    pass


class Version:
    def __init__(self, major: int, minor: int, patch: int):
        self.major = int(major)
        self.minor = int(minor)
        self.patch = int(patch)

    def to_list(self) -> List[int]:
        return [self.major, self.minor, self.patch]

    @classmethod
    def from_list(cls, val: Any) -> "Version":
        if not isinstance(val, list) or len(val) != 3:
            raise ValidationError(f"Version must be a 3-element array [major, minor, patch], got {val}")
        for item in val:
            if not isinstance(item, int) or item < 0:
                raise ValidationError(f"Version components must be non-negative integers, got {val}")
        return cls(val[0], val[1], val[2])

    @classmethod
    def from_string(cls, s: str) -> "Version":
        # Extract numeric components from string like 'v2024.04.1' or '0.7k'
        cleaned = re.sub(r"^[^\d]*", "", s.strip())
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
        return cls(nums[0], nums[1], nums[2])

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    def __eq__(self, other: Any) -> bool:
        if not isinstance(other, Version):
            return False
        return (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch)

    def __lt__(self, other: "Version") -> bool:
        return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)


def validate_repo_manifest(data: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """Validates a repository manifest (e.g. manifest.v2.json)."""
    errors: List[str] = []

    if "manifest_version" not in data:
        errors.append("Missing 'manifest_version' field.")
    elif data["manifest_version"] not in VALID_MANIFEST_VERSIONS:
        errors.append(
            f"Unsupported 'manifest_version': {data.get('manifest_version')}. Expected one of {VALID_MANIFEST_VERSIONS}."
        )

    for req in ["id", "name", "description", "packages"]:
        if req not in data:
            errors.append(f"Missing required top-level field: '{req}'")

    if "packages" in data:
        if not isinstance(data["packages"], dict):
            errors.append("'packages' must be a dictionary/object of package entries.")
        else:
            for pkg_id, pkg in data["packages"].items():
                if not re.match(r"^[a-zA-Z0-9_\-]+$", pkg_id):
                    errors.append(f"Package ID '{pkg_id}' contains invalid characters. Use alphanumeric, -, _.")

                for req_pkg in ["name", "author", "description", "artifacts"]:
                    if req_pkg not in pkg:
                        errors.append(f"Package '{pkg_id}' is missing required field: '{req_pkg}'")

                if "artifacts" in pkg:
                    if not isinstance(pkg["artifacts"], list) or len(pkg["artifacts"]) == 0:
                        errors.append(f"Package '{pkg_id}' 'artifacts' must be a non-empty list.")
                    else:
                        for idx, art in enumerate(pkg["artifacts"]):
                            art_loc = f"Package '{pkg_id}' artifact #{idx + 1}"
                            if "url" not in art:
                                errors.append(f"{art_loc} is missing 'url'.")
                            if "version" not in art:
                                errors.append(f"{art_loc} is missing 'version'.")
                            else:
                                try:
                                    Version.from_list(art["version"])
                                except Exception as ex:
                                    errors.append(f"{art_loc} invalid 'version': {ex}")

                            if "supported_platforms" not in art:
                                errors.append(f"{art_loc} is missing 'supported_platforms'.")
                            elif not isinstance(art["supported_platforms"], list):
                                errors.append(f"{art_loc} 'supported_platforms' must be a list.")
                            else:
                                for plat in art["supported_platforms"]:
                                    if plat not in SUPPORTED_PLATFORMS:
                                        errors.append(
                                            f"{art_loc} unknown platform '{plat}'. Supported: {SUPPORTED_PLATFORMS}"
                                        )

    return (len(errors) == 0, errors)


def validate_package_manifest(data: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """Validates an individual package manifest.json (used inside a .kpkg)."""
    errors: List[str] = []

    for req in ["id", "name", "author", "description", "version", "supported_platforms"]:
        if req not in data:
            errors.append(f"Missing required field in package manifest: '{req}'")

    if "version" in data:
        try:
            Version.from_list(data["version"])
        except Exception as ex:
            errors.append(f"Invalid 'version': {ex}")

    if "supported_platforms" in data:
        if not isinstance(data["supported_platforms"], list):
            errors.append("'supported_platforms' must be a list.")
        else:
            for plat in data["supported_platforms"]:
                if plat not in SUPPORTED_PLATFORMS:
                    errors.append(f"Unknown platform '{plat}'. Supported: {SUPPORTED_PLATFORMS}")

    return (len(errors) == 0, errors)


def pack_directory(source_dir: Path, output_file: Path) -> bool:
    """Packs a directory into a .kpkg archive."""
    source_dir = source_dir.resolve()
    manifest_path = source_dir / "manifest.json"

    if not manifest_path.exists():
        logger.error(f"Cannot pack: {manifest_path} does not exist.")
        return False

    with open(manifest_path, "r", encoding="utf-8") as f:
        try:
            manifest_data = json.load(f)
        except Exception as ex:
            logger.error(f"Failed to parse manifest.json: {ex}")
            return False

    valid, errors = validate_package_manifest(manifest_data)
    if not valid:
        logger.error("Package manifest validation failed:")
        for err in errors:
            logger.error(f"  - {err}")
        return False

    output_file = output_file.resolve()
    output_file.parent.mkdir(parents=True, exist_ok=True)

    logger.info(f"Creating .kpkg archive: {output_file}")
    with tarfile.open(output_file, "w:gz") as tar:
        for item in source_dir.iterdir():
            # Skip git / temporary files
            if item.name.startswith((".", "__pycache__")):
                continue
            tar.add(item, arcname=item.name)

    logger.info(f"Successfully packed {manifest_data.get('id')} -> {output_file}")
    return True


def unpack_archive(kpkg_file: Path, target_dir: Path) -> bool:
    """Safely extracts a .kpkg archive to target directory."""
    kpkg_file = kpkg_file.resolve()
    target_dir = target_dir.resolve()

    if not kpkg_file.exists():
        logger.error(f"File not found: {kpkg_file}")
        return False

    target_dir.mkdir(parents=True, exist_ok=True)

    logger.info(f"Extracting {kpkg_file} -> {target_dir}")
    with tarfile.open(kpkg_file, "r:*") as tar:
        for member in tar.getmembers():
            # Guard against path traversal / Zip Slip
            target_path = (target_dir / member.name).resolve()
            if not str(target_path).startswith(str(target_dir)):
                logger.error(f"Security error: Archive member '{member.name}' escapes target directory.")
                return False
        tar.extractall(path=target_dir)

    manifest_path = target_dir / "manifest.json"
    if manifest_path.exists():
        with open(manifest_path, "r", encoding="utf-8") as f:
            try:
                manifest_data = json.load(f)
                valid, errors = validate_package_manifest(manifest_data)
                if valid:
                    logger.info(f"Extracted valid package: {manifest_data.get('name')} v{manifest_data.get('version')}")
                else:
                    logger.warning(f"Extracted package manifest has warnings: {errors}")
            except Exception as ex:
                logger.warning(f"Extracted package manifest unreadable: {ex}")

    return True


def main():
    parser = argparse.ArgumentParser(description="KindleBreak Package & Manifest Tool")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # Validate command
    val_parser = subparsers.add_parser("validate", help="Validate a repository manifest or package manifest")
    val_parser.add_argument("file", type=Path, help="Path to manifest JSON file")

    # Pack command
    pack_parser = subparsers.add_parser("pack", help="Pack a package folder into a .kpkg archive")
    pack_parser.add_argument("source_dir", type=Path, help="Directory containing manifest.json and payload")
    pack_parser.add_argument("output_kpkg", type=Path, help="Target .kpkg output path")

    # Unpack command
    unpack_parser = subparsers.add_parser("unpack", help="Extract a .kpkg archive")
    unpack_parser.add_argument("kpkg_file", type=Path, help="Path to .kpkg file")
    unpack_parser.add_argument("target_dir", type=Path, help="Target directory for extraction")

    args = parser.parse_args()

    if args.command == "validate":
        if not args.file.exists():
            logger.error(f"File not found: {args.file}")
            sys.exit(1)

        with open(args.file, "r", encoding="utf-8") as f:
            data = json.load(f)

        if "packages" in data:
            valid, errors = validate_repo_manifest(data)
            m_type = "Repository Manifest"
        else:
            valid, errors = validate_package_manifest(data)
            m_type = "Package Manifest"

        if valid:
            logger.info(f"SUCCESS: {m_type} is valid! ({args.file})")
            sys.exit(0)
        else:
            logger.error(f"FAILED: {m_type} validation errors:")
            for err in errors:
                logger.error(f"  - {err}")
            sys.exit(1)

    elif args.command == "pack":
        ok = pack_directory(args.source_dir, args.output_kpkg)
        sys.exit(0 if ok else 1)

    elif args.command == "unpack":
        ok = unpack_archive(args.kpkg_file, args.target_dir)
        sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
