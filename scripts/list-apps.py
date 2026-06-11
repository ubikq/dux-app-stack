#!/usr/bin/env python3
"""
Scans system .desktop files and outputs a JSON array of launchable applications.
Used by AppGroupSettings.qml to populate the app picker.
Output: one JSON line to stdout: [{name, icon, iconPath, exec, comment}, ...]
"""
import json
import os
import glob
import configparser
import sys


def find_icon_path(icon_name):
    if not icon_name:
        return ""
    if os.path.isabs(icon_name) and os.path.exists(icon_name):
        return icon_name

    home = os.path.expanduser("~")
    icon_dirs = [
        os.path.join(home, ".local/share/icons"),
        os.path.join(home, ".local/share/flatpak/exports/share/icons"),
        "/var/lib/flatpak/exports/share/icons",
        "/usr/share/icons",
    ]
    sizes = ["scalable", "256x256", "128x128", "64x64", "48x48", "32x32", "22x22"]
    categories = ["apps", "applications", ""]
    extensions = [".svg", ".png", ".xpm"]

    for icon_dir in icon_dirs:
        for theme in ["hicolor", "Papirus", "breeze", "Adwaita", ""]:
            base = os.path.join(icon_dir, theme) if theme else icon_dir
            for size in sizes:
                for cat in categories:
                    for ext in extensions:
                        path = os.path.join(base, size, cat, icon_name + ext) if cat \
                               else os.path.join(base, size, icon_name + ext)
                        if os.path.exists(path):
                            return path

    for ext in [".png", ".svg", ".xpm"]:
        path = f"/usr/share/pixmaps/{icon_name}{ext}"
        if os.path.exists(path):
            return path

    return ""


def clean_exec(exec_str):
    """Strip desktop entry field codes (%u, %f, etc.) from Exec string."""
    tokens = exec_str.split()
    return " ".join(t for t in tokens if not (len(t) == 2 and t[0] == "%")).strip()


def scan():
    home = os.path.expanduser("~")
    search_dirs = [
        "/usr/share/applications",
        os.path.join(home, ".local/share/applications"),
        "/var/lib/flatpak/exports/share/applications",
        os.path.join(home, ".local/share/flatpak/exports/share/applications"),
    ]

    apps = {}  # keyed by name — later paths (user overrides) win

    for search_dir in search_dirs:
        if not os.path.isdir(search_dir):
            continue
        for desktop_file in glob.glob(os.path.join(search_dir, "*.desktop")):
            try:
                parser = configparser.ConfigParser(strict=False, interpolation=None)
                parser.read(desktop_file, encoding="utf-8")

                if not parser.has_section("Desktop Entry"):
                    continue

                entry = parser["Desktop Entry"]

                if entry.get("Type", "") != "Application":
                    continue
                if entry.get("NoDisplay", "false").lower() == "true":
                    continue
                if entry.get("Hidden", "false").lower() == "true":
                    continue

                name = entry.get("Name", "").strip()
                exec_raw = entry.get("Exec", "").strip()
                if not name or not exec_raw:
                    continue

                icon = entry.get("Icon", "").strip()
                apps[name] = {
                    "name": name,
                    "icon": icon,
                    "iconPath": find_icon_path(icon),
                    "exec": clean_exec(exec_raw),
                    "comment": entry.get("Comment", "").strip(),
                }
            except Exception:
                continue

    return sorted(apps.values(), key=lambda a: a["name"].lower())


if __name__ == "__main__":
    print(json.dumps(scan()))
    sys.stdout.flush()
