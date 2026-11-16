# App Stack — Multi-Group Bar Widget Plugin for Dux Shell

A [Dux Shell](https://duxlabs.dev) bar widget that manages multiple independent app groups. Each group is a **plugin variant** — add the widget to the bar and pick which group it shows. Each group gets its own bar icon and app list, placeable at the beginning, middle, or end of any bar.

<img src="docs/screenshot.webp" width="50%" alt="App Stack popout">

---

## Contents

- [Overview](#overview)
- [What's new](#whats-new)
- [Requirements](#requirements)
- [Getting the plugin](#getting-the-plugin)
- [Installation](#installation)
  - [Activating the plugin](#activating-the-plugin)
  - [Adding to your bar](#adding-to-your-bar)
- [Configuration](#configuration)
  - [Managing groups](#managing-groups)
  - [Managing apps](#managing-apps)
  - [Finding material icon names](#finding-material-icon-names)
  - [Bar placement](#bar-placement)
- [Using the bar widget](#using-the-bar-widget)
- [Migration from legacy groups](#migration-from-legacy-groups)
- [Development](#development)
- [Data model](#data-model)
- [Disclaimer](#disclaimer)
- [License](#license)

---

## Overview

The built-in Apps Dock widget in Dux Shell shows a single shared list of pinned apps across all instances. App Stack solves this by letting you create multiple app groups, each exposed as a **variant**. When you add the widget to the bar, Dux Shell asks which group to attach — so each bar slot gets its own icon, label, and curated set of app shortcuts.

> **Compatibility:** Tested on [niri](https://github.com/YaLTeR/niri) with Dux Shell / Dank Material Shell. Behaviour on other compositors has not been confirmed.

---

## What's new

Version 2.0 is a major rework of the plugin:

- **Multi-group architecture** — rebuilt from a set of separate `appStack_*` plugins into a single plugin that manages many groups. Each group is a DMS **variant**, so one plugin powers every group on your bar.
- **Per-slot group binding** — each bar widget instance is linked to a specific group via DMS variants, giving every bar slot its own icon, label, and app list.
- **Richer group management** — add, rename, re-icon, and delete groups with a confirmation step; deletion is blocked while a group is still in use on the bar.
- **Save / Cancel editing** — group edits are staged in a draft and only applied when you click **Save**.
- **Installed-apps picker** — browse and search your system's `.desktop` entries (including Flatpak) and add apps with their real icons (requires Python 3).
- **Inline icon picker** — a searchable Material icon grid for both groups and apps.
- **Popout app management** — add and remove apps directly from the bar widget's popout.
- **Collapsible "How to use" panel** — in-app guidance on the settings page.
- **Legacy migration** — a script converts old `appStack_*` plugin directories into the new multi-group format.

---

## Requirements

| Requirement | Purpose |
|---|---|
| Dux Shell (or Dank Material Shell) | Plugin host |
| **Python 3** *(optional)* | **"+ Installed Apps"** picker only |

Python 3 is **not required** for the core plugin. The manual "Add Custom App" form (Name / Command / Icon) works without it. If Python is missing, clicking "+ Installed Apps" will show an error message with install instructions.

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
git clone https://github.com/ubikq/dux-app-stack.git
```

---

## Installation

The plugin requires only the plugin files — not the entire repository. From the project root:

```bash
# Create the plugin directory
mkdir -p ~/.config/DankMaterialShell/plugins/appStack_default

# Copy only the plugin files
cp plugin.json          ~/.config/DankMaterialShell/plugins/appStack_default/
cp AppGroupWidget.qml   ~/.config/DankMaterialShell/plugins/appStack_default/
cp AppGroupSettings.qml ~/.config/DankMaterialShell/plugins/appStack_default/
cp -r scripts/          ~/.config/DankMaterialShell/plugins/appStack_default/
```

> **Note:** If you are using **Dux Shell** (the upstream variant), the config directory would be `~/.config/DuxShell/` instead of `~/.config/DankMaterialShell/`. Adjust the path accordingly.

### Activating the plugin

```bash
# In Dank Material Shell:
# Settings → Plugins → Scan for Plugins → toggle "App Stack" on → restart Dank Material Shell

# In Dux Shell:
# Settings → Plugins → Scan for Plugins → toggle "App Stack" on → restart Dux Shell
```

### Adding to your bar

```
Settings → Bar → Bar widgets → add "App Stack - <group name>" widget to a section
```

Each group appears as its own entry in the widget list (e.g. `App Stack - Development`). Pick the group you want for that bar slot. To change it later, remove the widget and add the desired group instead.

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

To remove a group, click **Delete** next to its name in the group list, then confirm. A group that is still linked to a bar widget cannot be deleted — remove that widget from the bar first (see [Using the bar widget](#using-the-bar-widget)).

### Managing apps

Select a group to see its **Apps** section. Each group supports up to **10 apps**; a warning appears when the limit is reached.

**+ Add Custom App** — opens a manual form. Fill in the fields, then click **Add App**:

| Field | Description |
|---|---|
| **Name** | Display label shown below the icon in the popout |
| **Command** | Shell command to launch the app (e.g. `firefox` or `/usr/bin/app --flag`) |
| **Icon** | [Material icon](https://fonts.google.com/icons) name (e.g. `code`, `movie`) |

**+ Installed Apps** — opens a searchable list of all applications found in your system's `.desktop` files (including Flatpak). Selecting an app adds it to the group immediately with its real icon.

Remove any app with the × button. Edit custom apps by clicking the pencil icon.

### Finding material icon names

Click **Pick** next to the Icon field to open an inline, searchable grid of common Material icons. You can also browse the full set at [fonts.google.com/icons](https://fonts.google.com/icons) and use the snake_case name shown under each icon (e.g. `open_in_new`, `folder_open`, `music_note`).

### Bar placement

Each group is a plugin **variant**, so you can place the widget on **multiple bars** or in **different sections** of the same bar — one entry per group. Each bar slot is bound to the group you picked when adding it, and edits made in the popout are saved to that group's variant.

---

## Using the bar widget

Clicking a group's bar icon opens a popout showing that group's apps as a grid. Click any app to launch it.

The popout also lets you manage the group's apps directly:

- Click the **edit** (pencil) icon to enter edit mode.
- In edit mode, click the **×** badge on an app to remove it, or the **+ Add App** tile to open the installed-apps picker and add another app.
- Click **Done** to leave edit mode.

Changes made in the popout are saved to the group's variant immediately. Group name, icon, and label are edited from the settings panel instead.

---

## Migration from legacy groups

If you have existing `appStack_*` plugin directories from previous versions, you can migrate them to the new multi-group format:

```bash
# Preview what would be migrated (dry run)
python3 ~/.config/DankMaterialShell/plugins/appStack_default/scripts/migrate-groups.py

# Perform the actual migration
python3 ~/.config/DankMaterialShell/plugins/appStack_default/scripts/migrate-groups.py --migrate
```

The migration script:
1. Scans for legacy `appStack_*` directories
2. Extracts group names, icons, and app lists
3. Writes a unified `groups` array to `data.json`
4. Prints cleanup instructions for removing old directories

> **Note:** The script writes a legacy `groups` array. On first open, the settings panel converts each entry into a DMS **variant** automatically (see [Data model](#data-model)).

> **Backup your configuration before migrating:**
> ```bash
> cp -r ~/.config/DankMaterialShell ~/.config/DankMaterialShell.bak
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
python3 ~/.config/DankMaterialShell/plugins/appStack_default/scripts/list-apps.py | python3 -m json.tool | head -40
```

---

## Data model

Each group is stored as a DMS **variant** under the `variants` key in `pluginData`:

```jsonc
{
  "variants": [
    {
      "id": "variant_1700000000000",
      "name": "Development",
      "icon": "code",
      "showLabel": true,
      "apps": [
        { "name": "VS Code", "icon": "visual-studio-code", "iconPath": "", "exec": "code", "source": "manual" },
        { "name": "Terminal", "icon": "terminal", "iconPath": "/usr/share/icons/.../terminal.svg", "exec": "kitty", "source": "picker" }
      ]
    },
    {
      "id": "variant_1700000000001",
      "name": "Media",
      "icon": "movie",
      "showLabel": false,
      "apps": [
        { "name": "Firefox", "icon": "language", "iconPath": "", "exec": "firefox", "source": "manual" }
      ]
    }
  ]
}
```

Each bar slot is bound to one variant. Dux Shell injects `variantId` and
`variantData` into the widget, and the widget persists edits with
`pluginService.updatePluginVariant(pluginId, variantId, { apps })`.

> **Legacy:** older versions stored a `groups` array. On first open, the
> settings panel migrates each entry to a variant automatically.

---

## Disclaimer

This plugin is provided as-is, with no warranty of any kind. Use it at your own risk.

Before installing or migrating, **back up your DMS configuration**:

```bash
cp -r ~/.config/DankMaterialShell ~/.config/DankMaterialShell.bak
```

The migration script copies and modifies files inside your DankMaterialShell plugins directory. Always verify the results before restarting Dank Material Shell. The author accepts no responsibility for lost configuration, broken setups, or any other damage arising from the use of this software.

---

## License

This project is licensed under the [GNU General Public License v2.0](LICENSE).
