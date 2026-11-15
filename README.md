# App Stack — Multi-Group Bar Widget Plugin for Dux Shell

A [Dux Shell](https://duxlabs.dev) bar widget that manages multiple independent app groups from a **single plugin instance**. Each group gets its own bar icon and app list, placeable at the beginning, middle, or end of any bar.

<img src="docs/screenshot.webp" width="50%" alt="App Stack popout">

---

## Overview

The built-in Apps Dock widget in Dux Shell shows a single shared list of pinned apps across all instances. App Stack solves this by letting you create multiple app groups from one plugin — each group is a separate bar slot with its own icon, label, and curated set of app shortcuts.

> **Compatibility:** Tested on [niri](https://github.com/YaLTeR/niri) with Dux Shell / Dank Material Shell. Behaviour on other compositors has not been confirmed.

---

## Requirements

| Requirement | Purpose |
|---|---|
| Dux Shell (or Dank Material Shell) | Plugin host |
| **Python 3** *(optional)* | **"Choose from Installed Apps"** picker only |

Python 3 is **not required** for the core plugin. The manual "Add App" form (Name / Icon / Command) works without it. If Python is missing, clicking "Choose from Installed Apps" will show an error message with install instructions.

Install Python 3 if you want the app picker:

```bash
# Arch / CachyOS / Manjaro
sudo pacman -S python

# Fedora
sudo dnf install python3

# Debian / Ubuntu
sudo apt install python3
```

---

## Getting the plugin

```bash
git clone https://github.com/ubikq/dms-app-stack.git
```

---

## Installation

```bash
# Copy the plugin directory into the Dux Shell plugins folder
cp -r dms-app-stack ~/.config/DuxShell/plugins/appStack_default

# Activate
# Settings → Plugins → Scan for Plugins → toggle "App Stack" on → dux restart

# Add to your bar
# Settings → DankBar → add "App Stack" to a section
```

No further editing is required — the plugin ID is already set to `appStack_default`.

---

## Configuration

Open **Settings → Plugins → App Stack** to manage all groups and apps from a single settings panel.

### Managing groups

The **Groups** section at the top shows all configured groups. Click a group to select it, or use **+ Add Group** to create a new one. Each group has its own:

| Setting | Description | Default |
|---|---|---|
| **Group Name** | Display name shown in the bar and popout header | `Group 1` |
| **Group Icon** | [Material icon](https://fonts.google.com/icons) name shown in DankBar | `apps` |
| **Show label in bar** | Display the group name next to the icon | off |

To remove a group, click the trash icon next to its name in the group list.

### Managing apps

Select a group to see its **Apps** section. Each group supports up to **10 apps**.

**Add App (manual)** — fill in Name, Icon, and Command, then click **Add App**:

| Field | Description |
|---|---|
| **Name** | Display label shown below the icon in the popout |
| **Icon** | [Material icon](https://fonts.google.com/icons) name (e.g. `code`, `movie`) |
| **Command** | Shell command to launch the app (e.g. `firefox`) |

**Choose from Installed Apps** — opens a searchable list of all applications found in your system's `.desktop` files (including Flatpak). Selecting an app fills in all fields automatically and shows the app's real icon in the popout.

Remove any app with the × button. Edit manual apps by clicking the pencil icon.

### Finding material icon names

Browse at [fonts.google.com/icons](https://fonts.google.com/icons). Use the snake_case name shown under each icon (e.g. `open_in_new`, `folder_open`, `music_note`).

### Bar placement

Because each group is stored in a shared `groups` array and distinguished by `widgetInstanceId`, you can place the widget on **multiple bars** or in **different sections** of the same bar. Each bar slot gets its own group automatically — no file copying or plugin duplication required.

---

## Migration from legacy groups

If you have existing `appStack_*` plugin directories from previous versions, you can migrate them to the new multi-group format:

```bash
# Preview what would be migrated (dry run)
python3 ~/.config/DuxShell/plugins/appStack_default/scripts/migrate-groups.py

# Perform the actual migration
python3 ~/.config/DuxShell/plugins/appStack_default/scripts/migrate-groups.py --migrate
```

The migration script:
1. Scans for legacy `appStack_*` directories
2. Extracts group names, icons, and app lists
3. Creates a unified `groups` array in `data.json`
4. Prints cleanup instructions for removing old directories

> **Backup your configuration before migrating:**
> ```bash
> cp -r ~/.config/DuxShell ~/.config/DuxShell.bak
> ```

---

## Development

Hot-reload after editing QML:

```bash
dux ipc call plugins reload appStack_default
# or for Dank Material Shell:
dms ipc call plugins reload appStack_default
```

View QML errors:

```bash
journalctl --user -u dux-shell -f
# or for Dank Material Shell:
journalctl --user -u dank-material-shell -f
```

Test the app scanner script directly:

```bash
python3 ~/.config/DuxShell/plugins/appStack_default/scripts/list-apps.py | python3 -m json.tool | head -40
```

---

## Data model

The plugin stores all groups in a single `groups` array in `pluginData`:

```jsonc
{
  "groups": [
    {
      "id": "group_0",
      "name": "Development",
      "icon": "code",
      "showLabel": true,
      "apps": [
        { "name": "VS Code", "icon": "visual-studio-code", "exec": "code", "source": "manual" },
        { "name": "Terminal", "icon": "terminal", "exec": "kitty", "source": "picker" }
      ]
    },
    {
      "id": "group_1",
      "name": "Media",
      "icon": "movie",
      "showLabel": false,
      "apps": [
        { "name": "Firefox", "icon": "language", "exec": "firefox", "source": "manual" }
      ]
    }
  ],
  "version": 2
}
```

Each bar slot (distinguished by `widgetInstanceId`) maps to a `groups` array index. Instance 0 → `groups[0]`, instance 1 → `groups[1]`, etc.

---

## Disclaimer

This plugin is provided as-is, with no warranty of any kind. Use it at your own risk.

Before installing or migrating, **back up your Dux Shell configuration**:

```bash
cp -r ~/.config/DuxShell ~/.config/DuxShell.bak
```

The migration script copies and modifies files inside your Dux Shell plugins directory. Always verify the results before restarting Dux Shell. The author accepts no responsibility for lost configuration, broken setups, or any other damage arising from the use of this software.

---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE).
