#!/usr/bin/env python3
"""
migrate-groups.py — Migrate legacy appStack_* plugin directories into the new
single-plugin multi-group format (groups array in pluginData).

Usage:
    python3 migrate-groups.py [--dry-run]

Dry-run (default): prints what would be done without making changes.
Without --dry-run: performs the migration.

The script:
1. Scans ~/.config/DankMaterialShell/plugins/ for appStack_* directories.
2. Reads each directory's plugin.json to discover the group name/icon.
3. Reads each group's apps from the old storage format (appsData key).
4. Writes the merged groups array into ~/.config/DuxShell/plugins/appStack_default/data.json
   (or creates it if it doesn't exist).
5. Prints instructions for cleaning up old plugin directories.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path
from typing import Any


# ── Paths ────────────────────────────────────────────────────────────────────

HOME = Path.home()
DUX_PLUGINS = HOME / ".config" / "DuxShell" / "plugins"
DANK_PLUGINS = HOME / ".config" / "DankMaterialShell" / "plugins"
DEFAULT_PLUGIN_DIR = DUX_PLUGINS / "appStack_default"
DATA_JSON = DUX_PLUGINS / "appStack_default" / "data.json"


# ── Helpers ──────────────────────────────────────────────────────────────────

def find_legacy_groups() -> list[Path]:
    """Find all appStack_* directories in legacy plugin paths."""
    candidates: list[Path] = []
    for base in (DANK_PLUGINS, DUX_PLUGINS):
        if not base.is_dir():
            continue
        for d in sorted(base.iterdir()):
            if d.is_dir() and d.name.startswith("appStack_"):
                candidates.append(d)
    # Deduplicate while preserving order
    seen: set[str] = set()
    unique: list[Path] = []
    for p in candidates:
        key = str(p.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(p)
    return unique


def read_plugin_json(path: Path) -> dict[str, Any] | None:
    """Read plugin.json from a directory, return None on failure."""
    pj = path / "plugin.json"
    if not pj.is_file():
        return None
    try:
        with open(pj, "r", encoding="utf-8") as f:
            return json.load(f)
    except (json.JSONDecodeError, OSError):
        return None


def read_apps_data(path: Path) -> list[dict[str, str]]:
    """
    Try to read apps from the old storage format.

    Old format options:
    1. pluginData.appsData (JSON string in data.json)
    2. A separate apps.json file (fallback)
    """
    # Try data.json for appsData key
    data_json = path / "data.json"
    if data_json.is_file():
        try:
            with open(data_json, "r", encoding="utf-8") as f:
                data = json.load(f)
            if "appsData" in data:
                apps = json.loads(data["appsData"])
                if isinstance(apps, list):
                    return apps
        except (json.JSONDecodeError, OSError, KeyError):
            pass

    # Try apps.json (some versions used this)
    apps_json = path / "apps.json"
    if apps_json.is_file():
        try:
            with open(apps_json, "r", encoding="utf-8") as f:
                apps = json.load(f)
            if isinstance(apps, list):
                return apps
        except (json.JSONDecodeError, OSError):
            pass

    return []


def ensure_default_plugin_dir() -> None:
    """Create the default plugin directory if it doesn't exist."""
    DEFAULT_PLUGIN_DIR.mkdir(parents=True, exist_ok=True)


def load_existing_groups() -> list[dict[str, Any]]:
    """Load existing groups from data.json if present."""
    if DATA_JSON.is_file():
        try:
            with open(DATA_JSON, "r", encoding="utf-8") as f:
                data = json.load(f)
            groups = data.get("groups", [])
            if isinstance(groups, list):
                return groups
        except (json.JSONDecodeError, OSError):
            pass
    return []


def save_groups(groups: list[dict[str, Any]]) -> None:
    """Save groups array to data.json."""
    ensure_default_plugin_dir()
    data: dict[str, Any] = {
        "groups": groups,
        "version": 2,
    }
    with open(DATA_JSON, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def migrate_group(legacy_dir: Path, index: int) -> dict[str, Any] | None:
    """
    Migrate a single legacy group directory into a group object.

    Returns the group dict or None if migration failed.
    """
    pj = read_plugin_json(legacy_dir)
    if not pj:
        print(f"  ⚠ No plugin.json found in {legacy_dir.name}, skipping.")
        return None

    group_id = pj.get("id", legacy_dir.name)
    group_name = pj.get("name", legacy_dir.name.replace("appStack_", "App Stack - "))

    # Extract icon from plugin.json or use default
    group_icon = pj.get("icon", "apps")

    # Read apps
    apps = read_apps_data(legacy_dir)

    # Read showLabel if present
    show_label = False
    data_json = legacy_dir / "data.json"
    if data_json.is_file():
        try:
            with open(data_json, "r", encoding="utf-8") as f:
                data = json.load(f)
            show_label = data.get("showLabel", False)
        except (json.JSONDecodeError, OSError):
            pass

    return {
        "id": group_id,
        "name": group_name,
        "icon": group_icon,
        "showLabel": show_label,
        "apps": apps,
        "_source_dir": legacy_dir.name,  # For cleanup tracking
    }


def print_separator(char: str = "─", length: int = 60) -> None:
    """Print a separator line."""
    print(char * length)


def main() -> None:
    """Main migration logic."""
    parser = argparse.ArgumentParser(
        description="Migrate legacy appStack_* plugin directories to multi-group format."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        default=True,
        help="Show what would be done without making changes (default: True)",
    )
    parser.add_argument(
        "--migrate",
        action="store_true",
        help="Actually perform the migration (opposite of --dry-run)",
    )
    args = parser.parse_args()
    dry_run = not args.migrate

    print_separator()
    print("  App Stack Multi-Group Migration Tool")
    print_separator()
    print()

    # Find legacy groups
    legacy_dirs = find_legacy_groups()

    if not legacy_dirs:
        print("No legacy appStack_* plugin directories found.")
        print()
        print("If you've already set up groups manually, you can add them")
        print("via the plugin settings UI (open App Stack settings → + Add Group).")
        print()
        return

    print(f"Found {len(legacy_dirs)} legacy group(s):")
    for d in legacy_dirs:
        pj = read_plugin_json(d)
        name = pj.get("name", d.name) if pj else d.name
        apps = read_apps_data(d)
        print(f"  • {d.name} ({name}, {len(apps)} apps)")
    print()

    if dry_run:
        print("── DRY RUN — No changes will be made ──")
        print()

    # Build new groups array
    existing_groups = load_existing_groups() if not dry_run else []
    new_groups = existing_groups.copy()

    for i, legacy_dir in enumerate(legacy_dirs):
        group = migrate_group(legacy_dir, len(new_groups))
        if group:
            new_groups.append(group)

    print(f"Result: {len(new_groups)} group(s) will be stored in:")
    print(f"  {DATA_JSON}")
    print()

    for i, g in enumerate(new_groups):
        apps = g.get("apps", [])
        print(f"  Group {i+1}: {g['name']} ({g['icon']}, {len(apps)} apps)")
        for j, app in enumerate(apps[:5]):  # Show first 5 apps
            print(f"    - {app.get('name', '?')} → {app.get('exec', '?')}")
        if len(apps) > 5:
            print(f"    ... and {len(apps) - 5} more")
    print()

    if dry_run:
        print("── Cleanup instructions (after verifying migration) ──")
        print()
        print("Once you've verified the groups work correctly in Dux Shell:")
        print()
        for d in legacy_dirs:
            print(f"  rm -rf {d}")
        print()
        print("Or run with --migrate to perform the migration automatically.")
    else:
        # Save the groups
        save_groups(new_groups)
        print("Migration complete! ✅")
        print()
        print("Next steps:")
        print("  1. Restart Dux Shell (or reload plugins)")
        print("  2. Open App Stack settings to verify groups")
        print("  3. Add widget instances to your bars")
        print()
        print("To clean up old directories after verifying:")
        for d in legacy_dirs:
            print(f"  rm -rf {d}")
    print()
    print_separator()


if __name__ == "__main__":
    main()
