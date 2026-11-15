# Implementation Plan: Single-Plugin Multi-Group App Stack

> **Last updated:** 2026-11-15
> **Status:** Ready for implementation
> **Mode:** Code
> **Target:** Dux Shell (formerly Dank Material Shell) plugin

---

## Table of Contents

1. [Context Summary](#1-context-summary)
2. [Current Codebase Analysis](#2-current-codebase-analysis)
3. [Architecture Decision](#3-architecture-decision)
4. [Data Model](#4-data-model)
5. [Implementation Steps](#5-implementation-steps)
6. [Complete Code for All Files](#6-complete-code-for-all-files)
7. [Migration Strategy](#7-migration-strategy)
8. [Testing Checklist](#8-testing-checklist)

---

## 1. Context Summary

### 1.1 Project Purpose

The `dms-app-stack` project is a Dux Shell bar widget plugin that provides an app launcher. Users can create named groups of applications, each with its own icon, and launch apps from a popout grid.

### 1.2 Current Problem

Currently, each app group requires a **separate plugin instance** (directory copy with unique `id`). The "Create Another Group" feature runs `scripts/create-group.sh` which:
1. Copies the entire plugin directory
2. Patches `plugin.json` (id, name, description) with `sed`
3. Patches `AppGroupSettings.qml` (pluginId) with `sed`

This means:
- File duplication across instances
- Each instance must be individually enabled in DMS Settings
- Each instance must be individually added to the bar
- Updates require patching all copies

### 1.3 Goal

Replace the directory-copying approach with a **single plugin instance** that internally manages multiple groups via `widgetInstanceId`. Each group gets its own bar pill and popout, and each widget instance can be placed independently in the bar.

### 1.4 Key Dux Shell API References

From [`Dux_Shell_Plugin_development_documentation.md`](docs/reference/Dux_Shell_Plugin_development_documentation.md):

| API | Source | Usage |
|-----|--------|-------|
| `widgetInstanceId` | Auto-injected on `PluginComponent` | Maps bar slot index to groups array index |
| `pluginData` | Auto-injected on `PluginComponent` | Reactive settings containing `groups` array |
| `pluginService.savePluginData(id, key, value)` | Auto-injected | Persist group configurations |
| `pluginId` | Auto-injected on `PluginComponent` | Plugin's unique identifier |
| `PopoutComponent` | `qs.Widgets` | Show app grid popout per group |
| `PluginSettings` | `qs.Modules.Plugins` | Base for settings panels |

**Critical documentation quote:**
> "Don't assume a single instance. The same widget can sit on several bars and docks, and `widgetInstanceId` tells them apart."
> — Line 155

---

## 2. Current Codebase Analysis

### 2.1 File Structure

```
dms-app-stack/
├── plugin.json              # Plugin manifest (12 lines)
├── AppGroupWidget.qml       # Bar widget component (563 lines)
├── AppGroupSettings.qml     # Settings panel (1731 lines)
├── README.md                # Project documentation
└── scripts/
    ├── list-apps.py         # Desktop file scanner → JSON (108 lines)
    └── create-group.sh      # Directory copier + sed patcher (53 lines)
```

### 2.2 plugin.json (Current)

```json
{
  "id": "appStack_default",
  "name": "App Stack - Default",
  "description": "App Stack - Default — a DankBar app launcher group",
  "version": "1.0.0",
  "author": "You",
  "type": "widget",
  "component": "./AppGroupWidget.qml",
  "settings": "./AppGroupSettings.qml",
  "permissions": ["settings_read", "settings_write", "process"]
}
```

**No changes needed** — the `id` stays as `appStack_default` (the single plugin instance ID).

### 2.3 AppGroupWidget.qml (Current - Key Sections)

**Imports:**
```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
```

**Properties (single group):**
```qml
property string groupName: pluginData.groupName || "App Stack"
property string groupIcon: pluginData.groupIcon || "apps"
property bool showLabel: pluginData.showLabel || false
```

**Bar pill:**
```qml
horizontalBarPill: Component {
    Row {
        spacing: Theme.spacingS
        DankIcon { name: root.groupIcon; size: Theme.iconSize; ... }
        StyledText { visible: root.showLabel; text: root.groupName; ... }
    }
}
```

**Popout:** Shows app grid from `pluginData.appsData` (JSON string).

**App management:**
- `saveApps(list)` — saves to `pluginData.appsData`
- `removeApp(idx)` — removes by index
- `addPickerApp(appData)` — adds from system scanner

**System scanner:** Python script `list-apps.py` outputs JSON array of installed apps.

### 2.4 AppGroupSettings.qml (Current - Key Sections)

**Imports:**
```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets
```

**Hardcoded pluginId (TO BE REMOVED):**
```qml
PluginSettings {
    id: root
    pluginId: "appStack_default"  // HARDCODED - must be auto-injected
```

**Settings (single group):**
- `StringSetting` for `groupName`
- `StringSetting` for `appsData` (JSON string)
- `ToggleSetting` for `showLabel`
- Custom icon picker with `iconList` (100+ Material icons)

**Icon list (lines 255-269):**
```qml
readonly property var iconList: [
    "apps", "widgets", "dashboard", "grid_view", "work", "business_center",
    "folder", "folder_open", "description", "code", "terminal", "developer_mode",
    "build", "bug_report", "movie", "music_note", "headphones", "volume_up",
    "radio", "tv", "camera", "photo", "videocam", "mic", "language", "web",
    "public", "wifi", "email", "chat", "phone", "settings", "storage", "memory",
    "dns", "router", "devices", "computer", "laptop", "smartphone", "tablet",
    "monitor", "print", "keyboard", "download", "upload", "sync", "cloud",
    "attach_file", "person", "account_circle", "group", "contacts",
    "sports_esports", "gamepad", "fitness_center", "medical_services",
    "favorite", "map", "place", "flight", "directions_car", "shopping_cart",
    "store", "attach_money", "credit_card", "school", "book", "science",
    "restaurant", "local_cafe", "home", "star", "bookmark", "search",
    "lock", "security", "notifications", "alarm", "calendar_today", "info"
]
```

**"Create Another Group" section (lines 1442-1705):**
- Calls `create-group.sh` with source dir, new ID, new name
- Creates new plugin directory
- Patches IDs with `sed`

### 2.5 scripts/list-apps.py (Current)

Scans `.desktop` files from:
- `/usr/share/applications`
- `/usr/local/share/applications`
- `~/.local/share/applications`
- Flatpak directories
- Snap directories

Outputs JSON array:
```json
[
  {
    "name": "Firefox",
    "icon": "firefox",
    "iconPath": "/usr/share/icons/hicolor/48x48/apps/firefox.png",
    "exec": "firefox %u",
    "comment": "Web Browser"
  }
]
```

**No changes needed** — this script is reused as-is.

### 2.6 scripts/create-group.sh (Current)

Copies plugin directory and patches IDs:
```bash
cp -r "$SOURCE_DIR" "$DEST_DIR"
sed -i "s/\"id\": \"[^\"]*\"/\"id\": \"$NEW_ID\"/" "$DEST_DIR/plugin.json"
sed -i "s/\"name\": \"[^\"]*\"/\"name\": \"$NEW_NAME\"/" "$DEST_DIR/plugin.json"
sed -i "s/pluginId: \"[^\"]*\"/pluginId: \"$NEW_ID\"/" "$DEST_DIR/AppGroupSettings.qml"
```

**TO BE REMOVED** — replaced by settings UI.

---

## 3. Architecture Decision

### 3.1 Selected Approach: widgetInstanceId Mapping

Each group is a separate widget instance added to the bar via DMS Settings. The `widgetInstanceId` property (auto-injected by Dux Shell) maps each instance to a specific group in the shared `groups` array.

```
User adds plugin to bar 3 times via DMS Settings
         ↓                    ↓                    ↓
  Instance 0 (widgetInstanceId=0)  Instance 1 (widgetInstanceId=1)  Instance 2 (widgetInstanceId=2)
         ↓                    ↓                    ↓
  groups[0] = "Dev"        groups[1] = "Browsers"  groups[2] = "Office"
  "Dev" pill in bar        "Browsers" pill in bar  "Office" pill in bar
  popout → Dev apps        popout → Browsers apps  popout → Office apps
```

### 3.2 Dual-Level App Management

Apps can be configured from **two locations**:

1. **Widget Popout (Quick Access)** — Add/remove apps directly from the bar widget popout
2. **Settings Console (Full Management)** — Add/remove/edit groups and apps from the settings panel

### 3.3 Key Design Decisions

| Decision | Value | Rationale |
|----------|-------|-----------|
| Plugin ID | `appStack_default` (unchanged) | Single plugin instance |
| Data storage | `pluginData.groups` (JSON array) | Reactive, auto-syncs |
| Group ID generation | Sequential (`group_0`, `group_1`, ...) | Simple, deterministic |
| Icon selection | Pre-populated Material icon list (unchanged) | Existing UX works |
| App limit | 10 per group (unchanged) | Prevents popout overflow |
| Migration | Automatic on first launch | No manual step needed |

---

## 4. Data Model

### 4.1 pluginData Structure

```jsonc
{
  "groups": [
    {
      "id": "group_0",
      "name": "Development",
      "icon": "mdi:code-braces-box",
      "showLabel": true,
      "apps": [
        { "name": "VS Code", "icon": "visual-studio-code", "iconPath": "", "exec": "code %U", "source": "manual" },
        { "name": "Terminal", "icon": "terminal", "iconPath": "", "exec": "kitty", "source": "picker" }
      ]
    },
    {
      "id": "group_1",
      "name": "Browsers",
      "icon": "mdi:google-chrome",
      "showLabel": false,
      "apps": [
        { "name": "Firefox", "icon": "firefox", "iconPath": "", "exec": "firefox %u", "source": "picker" }
      ]
    }
  ],
  "version": 2
}
```

### 4.2 Group Object Schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | string | auto-generated | Unique group identifier |
| `name` | string | "Group N" | Display name |
| `icon` | string | "apps" | Material icon name |
| `showLabel` | boolean | false | Show name in bar |
| `apps` | array | [] | Array of app objects |

### 4.3 App Object Schema

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | required | Display name |
| `icon` | string | "apps" | Material icon name |
| `iconPath` | string | "" | File path to icon (empty = use Material icon) |
| `exec` | string | required | Shell command |
| `source` | string | "manual" | "manual", "picker", or "system" |
| `comment` | string | "" | Desktop file comment |

---

## 5. Implementation Steps

### Step 1: Update plugin.json

**File:** `plugin.json`
**Change:** Minimal — update name and description to reflect single-instance multi-group.

### Step 2: Refactor AppGroupWidget.qml

**File:** `AppGroupWidget.qml`
**Change:** Complete rewrite to support `widgetInstanceId`-based group mapping.

### Step 3: Refactor AppGroupSettings.qml

**File:** `AppGroupSettings.qml`
**Change:** Complete rewrite to support unified group management.

### Step 4: Create Migration Script

**File:** `scripts/migrate-groups.py`
**Change:** New file to migrate existing group directories.

### Step 5: Update README.md

**File:** `README.md`
**Change:** Update documentation for new multi-group workflow.

### Step 6: Remove create-group.sh

**File:** `scripts/create-group.sh`
**Change:** Delete — replaced by settings UI.

---

## 6. Complete Code for All Files

### 6.1 plugin.json (Updated)

**Path:** `plugin.json`
**Changes:** Update name, description, add `version` field.

```json
{
  "id": "appStack_default",
  "name": "App Stack",
  "description": "Multi-group app launcher for Dux Shell bar. Add the widget multiple times to create groups.",
  "version": "2.0.0",
  "author": "You",
  "type": "widget",
  "component": "./AppGroupWidget.qml",
  "settings": "./AppGroupSettings.qml",
  "permissions": ["settings_read", "settings_write", "process"]
}
```

### 6.2 AppGroupWidget.qml (Complete Rewrite)

**Path:** `AppGroupWidget.qml`
**Changes:** Complete rewrite. Key changes:
- Remove hardcoded `groupName`, `groupIcon`, `showLabel` properties
- Add `widgetInstanceId`-based group lookup
- Add `currentGroup` computed property
- Add popout quick-add functionality
- Handle null/missing group gracefully

**Complete file content:**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ── Multi-group support via widgetInstanceId ─────────────────────────
    // widgetInstanceId is auto-injected by Dux Shell. Each time the user
    // adds this widget to the bar, Dux Shell assigns a sequential integer
    // starting from 0. We map that index to groups[widgetInstanceId].

    readonly property string listAppsScript:
        Qt.resolvedUrl("./scripts/list-apps.py").toString().replace(/^file:\/\//, "")

    // Current group resolved from widgetInstanceId
    property var currentGroup: {
        if (!pluginData.groups || !(pluginData.groups instanceof Array))
            return null
        var idx = widgetInstanceId
        if (idx < 0 || idx >= pluginData.groups.length)
            return null
        return pluginData.groups[idx]
    }

    // Derived properties for convenience
    property string _groupName: currentGroup ? (currentGroup.name || "Group") : "Empty"
    property string _groupIcon: currentGroup ? (currentGroup.icon || "apps") : "apps"
    property bool _showLabel: currentGroup ? (currentGroup.showLabel || false) : false
    property var _groupApps: currentGroup ? (currentGroup.apps || []) : []

    // Default apps for new groups
    property var defaultApps: [
        { "name": "Firefox",  "icon": "language",  "iconPath": "", "exec": "firefox"  },
        { "name": "Terminal", "icon": "terminal",  "iconPath": "", "exec": "kitty"    },
        { "name": "Files",    "icon": "folder",    "iconPath": "", "exec": "nautilus" },
        { "name": "Settings", "icon": "settings",  "iconPath": "", "exec": "gnome-control-center" }
    ]

    // ── Bar Pills ────────────────────────────────────────────────────────
    // Show a pill only if we have a valid group. Empty/missing groups
    // render nothing (they should not be added to the bar).

    horizontalBarPill: Component {
        visible: root.currentGroup !== null
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root._groupIcon
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root._showLabel
                text: root._groupName
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        visible: root.currentGroup !== null
        DankIcon {
            name: root._groupIcon
            size: Theme.iconSize
            color: Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // ── Popout ───────────────────────────────────────────────────────────
    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: root._groupName
            detailsText: root.currentGroup ? (root._groupApps.length + " apps") : "No group assigned"
            showCloseButton: true

            // ── State ──────────────────────────────────────────────────
            property var liveApps: []
            property bool editMode: false
            property bool pickerMode: false
            property bool pickerLoading: false
            property string pickerFilter: ""

            ListModel { id: pickerModel }
            ListModel { id: filteredPickerModel }

            // ── Initialise app list ────────────────────────────────────
            Component.onCompleted: {
                if (root.currentGroup && root.currentGroup.apps && root.currentGroup.apps.length > 0) {
                    liveApps = root.currentGroup.apps
                } else {
                    liveApps = root.defaultApps
                }
            }

            // ── App list mutations ─────────────────────────────────────
            function saveApps(list) {
                if (!root.currentGroup || !root.pluginService) return
                var groups = pluginData.groups.slice()
                groups[widgetInstanceId] = Object.assign({}, root.currentGroup, { apps: list })
                root.pluginService.savePluginData(root.pluginId, "groups", JSON.stringify(groups))
            }

            function removeApp(idx) {
                var newList = liveApps.filter(function(_, i) { return i !== idx })
                liveApps = newList
                saveApps(newList)
            }

            function addPickerApp(appData) {
                if (liveApps.length >= 10) return
                var newList = liveApps.slice()
                newList.push({
                    name: appData.name,
                    icon: appData.icon || "apps",
                    iconPath: appData.iconPath || "",
                    exec: appData.exec,
                    source: "picker"
                })
                liveApps = newList
                saveApps(newList)
            }

            // ── Picker filter ──────────────────────────────────────────
            function filterPicker() {
                filteredPickerModel.clear()
                var f = pickerFilter.toLowerCase().trim()
                for (var i = 0; i < pickerModel.count; i++) {
                    var a = pickerModel.get(i)
                    if (!f || a.name.toLowerCase().includes(f))
                        filteredPickerModel.append(a)
                }
            }

            onPickerFilterChanged: filterPicker()

            // ── System app scanner ─────────────────────────────────────
            Process {
                id: widgetScanner
                running: false
                command: ["python3", root.listAppsScript]
                stdout: SplitParser {
                    onRead: function(line) {
                        if (!line.trim()) return
                        try {
                            var apps = JSON.parse(line)
                            pickerModel.clear()
                            for (var i = 0; i < apps.length; i++)
                                pickerModel.append(apps[i])
                            popout.filterPicker()
                        } catch(e) {}
                        popout.pickerLoading = false
                    }
                }
                onExited: function(exitCode) {
                    popout.pickerLoading = false
                }
            }

            // ── Layout ─────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 0

                // ── Control strip ──────────────────────────────────────
                Item {
                    width: parent.width
                    height: 36

                    StyledText {
                        visible: popout.editMode && !popout.pickerMode
                        text: "Tap ✕ to remove"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    }

                    // Done button (edit mode)
                    StyledRect {
                        visible: popout.editMode
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        height: doneBtnLabel.implicitHeight + Theme.spacingXS * 2
                        width: doneBtnLabel.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: doneMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        StyledText {
                            id: doneBtnLabel
                            anchors.centerIn: parent
                            text: "Done"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary
                        }
                        MouseArea {
                            id: doneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popout.editMode = false
                                popout.pickerMode = false
                                popout.pickerFilter = ""
                                pickerSearchInput.text = ""
                            }
                        }
                    }

                    // Edit button (normal mode)
                    Item {
                        visible: !popout.editMode
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        width: Theme.iconSize + Theme.spacingS
                        height: Theme.iconSize

                        DankIcon {
                            name: "edit"
                            size: Theme.iconSize
                            color: editBtnMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: editBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: popout.editMode = true
                        }
                    }
                }

                // ── App grid (normal + edit mode) ──────────────────────
                Flow {
                    visible: !popout.pickerMode
                    width: parent.width
                    spacing: Theme.spacingS
                    topPadding: Theme.spacingXS

                    Repeater {
                        model: popout.liveApps

                        delegate: Item {
                            width: 80
                            height: 84

                            StyledRect {
                                anchors.fill: parent
                                anchors.margins: 2
                                radius: Theme.cornerRadius
                                color: (appMouse.containsMouse && !popout.editMode)
                                       ? Theme.surfaceContainerHighest
                                       : Theme.surfaceContainerHigh

                                Column {
                                    anchors.centerIn: parent
                                    spacing: Theme.spacingXS

                                    Loader {
                                        width: Theme.iconSize
                                        height: Theme.iconSize
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        sourceComponent: (modelData.iconPath && modelData.iconPath !== "")
                                                         ? fileIconComp : materialIconComp
                                        Component {
                                            id: fileIconComp
                                            Image {
                                                source: "file://" + modelData.iconPath
                                                width: Theme.iconSize; height: Theme.iconSize
                                                fillMode: Image.PreserveAspectFit; smooth: true
                                            }
                                        }
                                        Component {
                                            id: materialIconComp
                                            DankIcon {
                                                name: modelData.icon || "apps"
                                                size: Theme.iconSize
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: modelData.name || ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceText
                                        horizontalAlignment: Text.AlignHCenter
                                        width: 72
                                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                // Launch click (normal mode)
                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    enabled: !popout.editMode
                                    cursorShape: popout.editMode ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        if (modelData.exec)
                                            Quickshell.execDetached(["/bin/sh", "-c", modelData.exec])
                                        popout.closePopout()
                                    }
                                }

                                // Remove badge (edit mode)
                                Item {
                                    visible: popout.editMode
                                    anchors { top: parent.top; right: parent.right; margins: 1 }
                                    width: 20; height: 20

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: removeMouse.containsMouse ? Theme.error : Theme.surfaceContainerHighest
                                        border.color: Theme.error
                                        border.width: 1
                                    }
                                    DankIcon {
                                        name: "close"
                                        size: 14
                                        color: removeMouse.containsMouse ? Theme.surface : Theme.error
                                        anchors.centerIn: parent
                                    }
                                    MouseArea {
                                        id: removeMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: popout.removeApp(index)
                                    }
                                }
                            }
                        }
                    }

                    // "+" add tile
                    Item {
                        visible: popout.editMode && popout.liveApps.length < 10
                        width: 80
                        height: 84

                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Theme.cornerRadius
                            color: addTileMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                DankIcon {
                                    name: "add_circle"
                                    size: Theme.iconSize
                                    color: Theme.primary
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                StyledText {
                                    text: "Add App"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.primary
                                    horizontalAlignment: Text.AlignHCenter
                                    width: 72
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }

                            MouseArea {
                                id: addTileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    popout.pickerMode = true
                                    popout.pickerFilter = ""
                                    pickerSearchInput.text = ""
                                    if (pickerModel.count === 0 && !popout.pickerLoading) {
                                        popout.pickerLoading = true
                                        widgetScanner.running = true
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Picker view ────────────────────────────────────────
                Column {
                    visible: popout.pickerMode
                    width: parent.width
                    spacing: Theme.spacingXS
                    topPadding: Theme.spacingXS

                    // Back button
                    StyledRect {
                        height: backRow.implicitHeight + Theme.spacingXS * 2
                        width: backRow.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: backMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        Row {
                            id: backRow
                            anchors.centerIn: parent
                            spacing: Theme.spacingXS

                            DankIcon {
                                name: "arrow_back"
                                size: Theme.iconSize
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            StyledText {
                                text: "Back"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            id: backMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popout.pickerMode = false
                                popout.pickerFilter = ""
                                pickerSearchInput.text = ""
                            }
                        }
                    }

                    // Scanning indicator
                    StyledText {
                        visible: popout.pickerLoading
                        text: "Scanning installed apps…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    // Search field
                    StyledRect {
                        visible: !popout.pickerLoading && pickerModel.count > 0
                        width: parent.width
                        height: pickerSearchInput.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius

                        TextInput {
                            id: pickerSearchInput
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            clip: true
                            onTextChanged: popout.pickerFilter = text
                            Text {
                                visible: pickerSearchInput.text === ""
                                text: "Search apps…"
                                color: Theme.surfaceVariantText
                                font: pickerSearchInput.font
                            }
                        }
                    }

                    // App list
                    StyledRect {
                        visible: !popout.pickerLoading && filteredPickerModel.count > 0
                        width: parent.width
                        height: Math.min(pickerListView.contentHeight, 320)
                        clip: true
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerLow || Theme.surfaceContainerHigh

                        ListView {
                            id: pickerListView
                            anchors.fill: parent
                            model: filteredPickerModel
                            clip: true
                            spacing: 1

                            delegate: Item {
                                width: pickerListView.width
                                height: pickerRow.implicitHeight + Theme.spacingXS * 2

                                StyledRect {
                                    anchors.fill: parent
                                    color: pickerItemMouse.containsMouse
                                           ? Theme.surfaceContainerHighest : "transparent"
                                    radius: 0
                                }

                                Row {
                                    id: pickerRow
                                    anchors {
                                        left: parent.left; right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: Theme.spacingS; rightMargin: Theme.spacingS
                                    }
                                    spacing: Theme.spacingS

                                    Item {
                                        width: Theme.iconSize; height: Theme.iconSize
                                        anchors.verticalCenter: parent.verticalCenter

                                        Image {
                                            visible: iconPath !== ""
                                            source: iconPath !== "" ? ("file://" + iconPath) : ""
                                            width: Theme.iconSize; height: Theme.iconSize
                                            fillMode: Image.PreserveAspectFit; smooth: true
                                            anchors.fill: parent
                                        }
                                        DankIcon {
                                            visible: iconPath === ""
                                            name: "apps"; size: Theme.iconSize
                                            color: Theme.surfaceVariantText
                                            anchors.centerIn: parent
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        width: parent.width - Theme.iconSize - Theme.spacingS * 2

                                        StyledText {
                                            text: name || ""
                                            font.pixelSize: Theme.fontSizeMedium
                                            color: Theme.surfaceText
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                        StyledText {
                                            visible: comment !== ""
                                            text: comment || ""
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                            elide: Text.ElideRight
                                            width: parent.width
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pickerItemMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        popout.addPickerApp({
                                            name: name, icon: icon,
                                            iconPath: iconPath, exec: exec
                                        })
                                        popout.pickerMode = false
                                        popout.pickerFilter = ""
                                        pickerSearchInput.text = ""
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: !popout.pickerLoading && pickerModel.count > 0
                                 && filteredPickerModel.count === 0
                        text: "No apps match \"" + popout.pickerFilter + "\""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    popoutWidth: 300
    popoutHeight: 480
}
```

### 6.3 AppGroupSettings.qml (Complete Rewrite)

**Path:** `AppGroupSettings.qml`
**Changes:** Complete rewrite. Key changes:
- Remove hardcoded `pluginId` (use auto-injected)
- Replace single-group settings with group list management
- Add group add/remove/reorder UI
- Keep existing icon picker (reused for all groups)
- Keep existing app picker (reused for all groups)
- Remove "Create Another Group" section
- Add migration detection on first launch

**Complete file content:**

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

PluginSettings {
    id: root
    // pluginId is auto-injected by Dux Shell — do NOT declare it

    // ── Groups state ─────────────────────────────────────────────────────
    // Load groups from pluginData, or initialise empty array
    property var groups: {
        try {
            var raw = pluginData.groups
            if (raw === undefined || raw === null || raw === "") return []
            var parsed = JSON.parse(typeof raw === "string" ? raw : JSON.stringify(raw))
            return Array.isArray(parsed) ? parsed : []
        } catch(e) {
            return []
        }
    }

    // Selected group index for editing (-1 = no group selected)
    property int editingIndex: -1

    // ── Picker state ─────────────────────────────────────────────────────
    ListModel { id: systemAppsModel }
    ListModel { id: filteredApps }
    ListModel { id: appIconMatches }

    property bool pickerVisible: false
    property bool pickerLoading: false
    property bool pickerFailed: false
    property string pickerFilter: ""
    property bool showManualForm: false
    property bool appIconPickerVisible: false
    property string appIconPickerFilter: ""
    property string _manualIconPath: ""
    property bool _iconSetByCode: false
    property string _editingGroupName: ""
    property string _editingGroupIcon: "apps"
    property bool _groupIconPickerVisible: false
    property string _groupIconPickerFilter: ""

    // ── Paths ────────────────────────────────────────────────────────────
    readonly property string listAppsScript:
        Qt.resolvedUrl("./scripts/list-apps.py").toString().replace(/^file:\/\//, "")

    // ── Icon list (Material icons — same as before) ──────────────────────
    readonly property var iconList: [
        "apps", "widgets", "dashboard", "grid_view", "work", "business_center",
        "folder", "folder_open", "description", "code", "terminal", "developer_mode",
        "build", "bug_report", "movie", "music_note", "headphones", "volume_up",
        "radio", "tv", "camera", "photo", "videocam", "mic", "language", "web",
        "public", "wifi", "email", "chat", "phone", "settings", "storage", "memory",
        "dns", "router", "devices", "computer", "laptop", "smartphone", "tablet",
        "monitor", "print", "keyboard", "download", "upload", "sync", "cloud",
        "attach_file", "person", "account_circle", "group", "contacts",
        "sports_esports", "gamepad", "fitness_center", "medical_services",
        "favorite", "map", "place", "flight", "directions_car", "shopping_cart",
        "store", "attach_money", "credit_card", "school", "book", "science",
        "restaurant", "local_cafe", "home", "star", "bookmark", "search",
        "lock", "security", "notifications", "alarm", "calendar_today", "info"
    ]
    property var filteredIconList: {
        var f = root._groupIconPickerFilter
        if (!f) return root.iconList
        return root.iconList.filter(function(n) { return n.includes(f) })
    }
    property var filteredAppIconList: {
        var f = root.appIconPickerFilter
        if (!f) return root.iconList
        return root.iconList.filter(function(n) { return n.includes(f) })
    }

    // ── Functions ────────────────────────────────────────────────────────

    // Save groups array to pluginData
    function saveGroups() {
        if (!root.pluginService) return
        root.pluginService.savePluginData(root.pluginId, "groups", JSON.stringify(root.groups))
    }

    // Add a new group
    function addGroup() {
        var newGroup = {
            id: "group_" + root.groups.length,
            name: "Group " + (root.groups.length + 1),
            icon: "apps",
            showLabel: false,
            apps: []
        }
        var newGroups = root.groups.slice()
        newGroups.push(newGroup)
        root.groups = newGroups
        root.saveGroups()
        root.editingIndex = root.groups.length - 1
        root._editingGroupName = newGroup.name
        root._editingGroupIcon = newGroup.icon
    }

    // Remove a group
    function removeGroup(idx) {
        if (root.groups.length <= 1) {
            ToastService.showInfo("Cannot remove", "You must have at least one group")
            return
        }
        var newGroups = root.groups.filter(function(_, i) { return i !== idx })
        root.groups = newGroups
        root.saveGroups()
        if (root.editingIndex >= root.groups.length) {
            root.editingIndex = root.groups.length - 1
        }
        if (root.editingIndex >= 0) {
            var g = root.groups[root.editingIndex]
            root._editingGroupName = g.name
            root._editingGroupIcon = g.icon
        }
    }

    // Save group name
    function saveGroupName(name) {
        if (root.editingIndex < 0 || root.editingIndex >= root.groups.length) return
        var g = root.groups[root.editingIndex]
        g.name = name
        root.groups[root.editingIndex] = g
        root.saveGroups()
    }

    // Save group icon
    function saveGroupIcon(icon) {
        if (root.editingIndex < 0 || root.editingIndex >= root.groups.length) return
        var g = root.groups[root.editingIndex]
        g.icon = icon
        root.groups[root.editingIndex] = g
        root.saveGroups()
        root._editingGroupIcon = icon
    }

    // Save group showLabel
    function saveGroupShowLabel(val) {
        if (root.editingIndex < 0 || root.editingIndex >= root.groups.length) return
        var g = root.groups[root.editingIndex]
        g.showLabel = val
        root.groups[root.editingIndex] = g
        root.saveGroups()
    }

    // ── App management (same as before, adapted for current group) ───────

    function addApp(appData) {
        if (root.editingIndex < 0 || root.editingIndex >= root.groups.length) return
        var g = root.groups[root.editingIndex]
        var apps = g.apps || []
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].exec === appData.exec) {
                ToastService.showInfo("Already added", appData.name + " is already in this group")
                return
            }
        }
        var newList = apps.slice()
        newList.push({
            name: appData.name,
            icon: appData.icon || "apps",
            iconPath: appData.iconPath || "",
            exec: appData.exec,
            source: appData.source || "manual"
        })
        g.apps = newList
        root.groups[root.editingIndex] = g
        root.saveGroups()
    }

    function removeAppFromGroup(idx) {
        if (root.editingIndex < 0 || root.editingIndex >= root.groups.length) return
        var g = root.groups[root.editingIndex]
        var apps = g.apps || []
        var newList = apps.filter(function(_, i) { return i !== idx })
        g.apps = newList
        root.groups[root.editingIndex] = g
        root.saveGroups()
    }

    function filterSystemApps() {
        filteredApps.clear()
        var f = root.pickerFilter.toLowerCase().trim()
        for (var i = 0; i < systemAppsModel.count && filteredApps.count < 100; i++) {
            var a = systemAppsModel.get(i)
            if (f === "" || a.name.toLowerCase().includes(f) ||
                (a.comment && a.comment.toLowerCase().includes(f))) {
                filteredApps.append(a)
            }
        }
    }

    onPickerFilterChanged: filterSystemApps()
    onAppIconPickerFilterChanged: filterAppIconMatches()

    function tryAutoDetectIcon() {
        if (iconInput.text !== "") return
        var n = nameInput.text.trim().toLowerCase()
        var e = execInput.text.trim().toLowerCase()
        var execBase = e.split(" ")[0].split("/").pop()
        if (!n && !execBase) return
        var bestApp = null
        var bestScore = -1
        for (var i = 0; i < systemAppsModel.count; i++) {
            var app = systemAppsModel.get(i)
            var appExec = (app.exec || "").toLowerCase()
            var appExecBase = appExec.split(" ")[0].split("/").pop()
            var score = 0
            if (execBase && appExecBase === execBase) score += 10
            else if (n && app.name.toLowerCase() === n) score += 8
            else continue
            if (appExec.includes("--app-id=")) score -= 8
            if (appExec.includes("--profile-directory=")) score -= 3
            score -= appExec.length / 200
            if (appExecBase && app.name.toLowerCase().includes(appExecBase)) score += 2
            if (score > bestScore) { bestScore = score; bestApp = app }
        }
        if (bestApp) {
            root._iconSetByCode = true
            iconInput.text = bestApp.icon || "apps"
            root._manualIconPath = bestApp.iconPath || ""
            root._iconSetByCode = false
        }
    }

    function filterAppIconMatches() {
        appIconMatches.clear()
        var f = root.appIconPickerFilter.toLowerCase()
        var n = nameInput.text.trim().toLowerCase()
        var e = execInput.text.trim().toLowerCase()
        var execBase = e.split(" ")[0].split("/").pop()
        for (var i = 0; i < systemAppsModel.count && appIconMatches.count < 30; i++) {
            var app = systemAppsModel.get(i)
            var appExec = (app.exec || "").toLowerCase()
            var appExecBase = appExec.split(" ")[0].split("/").pop()
            var hit = false
            if (f === "") {
                var execMatch = execBase && appExecBase === execBase
                var nameMatch = n && app.name.toLowerCase() === n
                hit = (execMatch || nameMatch) && !appExec.includes("--app-id=")
            } else {
                hit = app.name.toLowerCase().includes(f) || appExecBase.includes(f)
            }
            if (hit) appIconMatches.append(app)
        }
    }

    function commitManualAdd() {
        var n = nameInput.text.trim()
        var e = execInput.text.trim()
        if (!n || !e) {
            ToastService.showInfo("Incomplete", "Name and Command are required")
            return
        }
        root.addApp({
            name: n,
            icon: iconInput.text.trim() || "apps",
            iconPath: root._manualIconPath,
            exec: e,
            source: "manual"
        })
        nameInput.text = ""
        iconInput.text = ""
        execInput.text = ""
        root._manualIconPath = ""
        root.appIconPickerVisible = false
    }

    // ── System app scanner ───────────────────────────────────────────────
    Process {
        id: appScanner
        running: false
        command: ["python3", root.listAppsScript]
        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                try {
                    var apps = JSON.parse(line)
                    systemAppsModel.clear()
                    for (var i = 0; i < apps.length; i++) systemAppsModel.append(apps[i])
                    root.filterSystemApps()
                    if (root.showManualForm && iconInput.text === "")
                        Qt.callLater(root.tryAutoDetectIcon)
                    if (root.appIconPickerVisible)
                        Qt.callLater(root.filterAppIconMatches)
                } catch(e) {}
                root.pickerLoading = false
            }
        }
        onExited: function(exitCode) {
            root.pickerLoading = false
            if (exitCode !== 0 && systemAppsModel.count === 0) {
                root.pickerFailed = true
            }
        }
    }

    // ── UI: Group List ───────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: Theme.spacingS

        // Header
        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                text: "Groups"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Item { width: 1; height: 1 } // spacer

            StyledRect {
                height: addGroupBtnLabel.implicitHeight + Theme.spacingS * 2
                width: addGroupBtnLabel.implicitWidth + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: addGroupMouse.containsMouse ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                StyledText {
                    id: addGroupBtnLabel
                    anchors.centerIn: parent
                    text: "+ Add Group"
                    font.pixelSize: Theme.fontSizeMedium
                    color: addGroupMouse.containsMouse ? Theme.onPrimary || Theme.surface : Theme.primary
                }
                MouseArea {
                    id: addGroupMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addGroup()
                }
            }
        }

        StyledText {
            width: parent.width
            text: "Add this widget to your bar once per group. Each bar slot gets its own group."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }

        // Group list
        Repeater {
            model: root.groups

            delegate: Item {
                width: parent.width
                property bool isSelected: root.editingIndex === index

                height: isSelected ? form.implicitHeight + Theme.spacingS * 2 : Theme.iconSize + Theme.spacingS * 2

                // ── Display row ───────────────────────────────────────────
                StyledRect {
                    visible: !isSelected
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Theme.spacingS }
                    height: Theme.iconSize
                    radius: Theme.cornerRadius
                    color: groupMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    Row {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingS }
                        spacing: Theme.spacingS

                        DankIcon {
                            name: modelData.icon || "apps"
                            size: Theme.iconSize
                            color: Theme.primary
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0

                            StyledText {
                                text: modelData.name || "(unnamed)"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: 200
                            }

                            StyledText {
                                text: (modelData.apps ? modelData.apps.length : 0) + " apps"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }

                    MouseArea {
                        id: groupMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.editingIndex = index
                            root._editingGroupName = modelData.name || ""
                            root._editingGroupIcon = modelData.icon || "apps"
                        }
                    }
                }

                // ── Edit form ─────────────────────────────────────────────
                Column {
                    id: form
                    anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Theme.spacingS }
                    spacing: Theme.spacingXS
                    visible: isSelected

                    // Group name
                    Column {
                        width: parent.width
                        spacing: 4

                        StyledText {
                            text: "Group Name"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledRect {
                            width: parent.width
                            height: editNameInput.implicitHeight + Theme.spacingM * 2
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius

                            TextInput {
                                id: editNameInput
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                }
                                text: root._editingGroupName
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                onTextChanged: root.saveGroupName(text)
                                Text {
                                    visible: editNameInput.text === ""
                                    text: "Group name"
                                    color: Theme.surfaceVariantText
                                    font: editNameInput.font
                                }
                            }
                        }
                    }

                    // Group icon
                    Column {
                        width: parent.width
                        spacing: 4

                        StyledText {
                            text: "Bar Icon"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            DankIcon {
                                name: root._editingGroupIcon || "apps"
                                size: Theme.iconSize
                                color: Theme.primary
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledRect {
                                height: editIconInput.implicitHeight + Theme.spacingM * 2
                                width: parent.width - Theme.iconSize - Theme.spacingS - browseIconBtn.width - Theme.spacingS
                                color: Theme.surfaceContainerHigh
                                radius: Theme.cornerRadius

                                TextInput {
                                    id: editIconInput
                                    anchors {
                                        left: parent.left; right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                    }
                                    text: root._editingGroupIcon
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    clip: true
                                    onTextChanged: root.saveGroupIcon(text)
                                    Text {
                                        visible: editIconInput.text === ""
                                        text: "apps"
                                        color: Theme.surfaceVariantText
                                        font: editIconInput.font
                                    }
                                }
                            }

                            StyledRect {
                                id: browseIconBtn
                                height: browseIconLabel.implicitHeight + Theme.spacingM * 2
                                width: browseIconLabel.implicitWidth + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: browseIconMouse.containsMouse || root._groupIconPickerVisible
                                       ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                StyledText {
                                    id: browseIconLabel
                                    anchors.centerIn: parent
                                    text: "Browse"
                                    font.pixelSize: Theme.fontSizeMedium
                                    color: Theme.primary
                                }
                                MouseArea {
                                    id: browseIconMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root._groupIconPickerVisible = !root._groupIconPickerVisible
                                        root._groupIconPickerFilter = ""
                                        groupIconPickerSearch.text = ""
                                    }
                                }
                            }
                        }

                        // Icon picker grid
                        Column {
                            visible: root._groupIconPickerVisible
                            width: parent.width
                            spacing: Theme.spacingXS

                            StyledRect {
                                width: parent.width
                                height: groupIconPickerSearch.implicitHeight + Theme.spacingM * 2
                                color: Theme.surfaceContainerHigh
                                radius: Theme.cornerRadius

                                TextInput {
                                    id: groupIconPickerSearch
                                    anchors {
                                        left: parent.left; right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                    }
                                    color: Theme.surfaceText
                                    font.pixelSize: Theme.fontSizeMedium
                                    clip: true
                                    onTextChanged: root._groupIconPickerFilter = text.toLowerCase()
                                    Text {
                                        visible: groupIconPickerSearch.text === ""
                                        text: "Search icons…"
                                        color: Theme.surfaceVariantText
                                        font: groupIconPickerSearch.font
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: root.filteredIconList
                                    delegate: Item {
                                        width: 68; height: 68
                                        StyledRect {
                                            anchors.fill: parent; anchors.margins: 2
                                            radius: Theme.cornerRadius
                                            color: iconCellMouse.containsMouse
                                                   ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                            Column {
                                                anchors.centerIn: parent; spacing: 2
                                                DankIcon {
                                                    name: modelData; size: Theme.iconSize
                                                    color: root._editingGroupIcon === modelData ? Theme.primary : Theme.surfaceText
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }
                                                StyledText {
                                                    text: modelData; font.pixelSize: 9
                                                    color: Theme.surfaceVariantText; width: 62
                                                    elide: Text.ElideRight
                                                    horizontalAlignment: Text.AlignHCenter
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                }
                                            }
                                            MouseArea {
                                                id: iconCellMouse
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.saveGroupIcon(modelData)
                                                    root._editingGroupIcon = modelData
                                                    root._groupIconPickerVisible = false
                                                    root._groupIconPickerFilter = ""
                                                    groupIconPickerSearch.text = ""
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Show label toggle
                    ToggleSetting {
                        settingKey: "group_showLabel_" + index
                        label: "Show label in bar"
                        description: "Display the group name next to the icon"
                        defaultValue: (modelData.showLabel !== undefined) ? modelData.showLabel : false
                        onValueChanged: root.saveGroupShowLabel(value)
                    }

                    // Remove group button
                    StyledRect {
                        visible: root.groups.length > 1
                        width: parent.width
                        height: removeGroupBtnLabel.implicitHeight + Theme.spacingS * 2
                        radius: Theme.cornerRadius
                        color: removeGroupMouse.containsMouse ? Theme.error : Theme.surfaceContainerHigh

                        StyledText {
                            id: removeGroupBtnLabel
                            anchors.centerIn: parent
                            text: "Remove Group"
                            font.pixelSize: Theme.fontSizeMedium
                            color: removeGroupMouse.containsMouse ? Theme.surface : Theme.error
                        }
                        MouseArea {
                            id: removeGroupMouse
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (confirm("Remove group \"" + root._editingGroupName + "\"?")) {
                                    root.removeGroup(index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── UI: Apps Section (shown when a group is selected) ─────────────────
    Rectangle {
        visible: root.editingIndex >= 0 && root.editingIndex < root.groups.length
        width: parent.width; height: 1; color: Theme.outline; opacity: 0.3
    }

    Column {
        visible: root.editingIndex >= 0 && root.editingIndex < root.groups.length
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Apps — " + (root.groups[root.editingIndex]?.name || "")
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // Current apps list
        var currentApps = (root.editingIndex >= 0 && root.editingIndex < root.groups.length)
                          ? (root.groups[root.editingIndex].apps || []) : []

        Column {
            width: parent.width
            spacing: 2
            visible: currentApps.length > 0

            Repeater {
                model: currentApps

                delegate: Item {
                    id: delegateRoot
                    width: parent.width
                    property bool isEditing: root.editingIndex === index  // simplified
                    height: isEditing ? editForm.implicitHeight + Theme.spacingS * 2
                                      : Theme.iconSize + Theme.spacingS * 2

                    // Display row
                    Item {
                        id: displayRow
                        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: Theme.spacingS }
                        height: Theme.iconSize
                        visible: !delegateRoot.isEditing

                        Item {
                            id: iconItem
                            width: Theme.iconSize; height: Theme.iconSize
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }

                            Image {
                                visible: modelData.iconPath !== ""
                                source: modelData.iconPath !== "" ? ("file://" + modelData.iconPath) : ""
                                width: Theme.iconSize; height: Theme.iconSize
                                fillMode: Image.PreserveAspectFit; smooth: true
                                anchors.fill: parent
                            }
                            DankIcon {
                                visible: modelData.iconPath === ""
                                name: modelData.icon || "apps"
                                size: Theme.iconSize
                                color: Theme.primary
                                anchors.centerIn: parent
                            }
                        }

                        Column {
                            anchors {
                                left: iconItem.right; leftMargin: Theme.spacingS
                                right: displayBtns.left; rightMargin: Theme.spacingS
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 2

                            StyledText {
                                text: modelData.name || "(unnamed)"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            StyledText {
                                visible: modelData.source !== "picker"
                                text: modelData.exec || ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Row {
                            id: displayBtns
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 0

                            Item {
                                width: Theme.iconSize + Theme.spacingS; height: Theme.iconSize
                                DankIcon {
                                    name: "close"
                                    size: Theme.iconSize
                                    color: removeMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                                    anchors.centerIn: parent
                                }
                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        var idx = index
                                        var g = root.groups[root.editingIndex]
                                        var apps = g.apps.filter(function(_, i) { return i !== idx })
                                        g.apps = apps
                                        root.groups[root.editingIndex] = g
                                        root.saveGroups()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Capacity warning
        StyledRect {
            visible: currentApps.length >= 10
            width: parent.width
            height: warningText.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh

            StyledText {
                id: warningText
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                text: "Maximum 10 apps per group."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }
        }

        // Add section
        Column {
            visible: currentApps.length < 10
            width: parent.width
            spacing: Theme.spacingXS

            Row {
                spacing: Theme.spacingS

                StyledRect {
                    id: pickerBtn
                    height: pickerBtnLabel.implicitHeight + Theme.spacingS * 2
                    width: pickerBtnLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: (pickerMouse.containsMouse || root.pickerVisible)
                           ? Theme.secondaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: pickerBtnLabel
                        anchors.centerIn: parent
                        text: root.pickerVisible ? "Hide App Picker" : "Choose from Installed Apps"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: pickerMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.pickerVisible = !root.pickerVisible
                            if (root.pickerVisible && systemAppsModel.count === 0 && !root.pickerLoading) {
                                root.pickerFailed = false
                                root.pickerLoading = true
                                appScanner.running = true
                            }
                        }
                    }
                }

                StyledRect {
                    id: addManuallyBtn
                    height: addManuallyLabel.implicitHeight + Theme.spacingS * 2
                    width: addManuallyLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: (addManuallyMouse.containsMouse || root.showManualForm)
                           ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: addManuallyLabel
                        anchors.centerIn: parent
                        text: root.showManualForm ? "Cancel" : "Add Manually"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: addManuallyMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.showManualForm = !root.showManualForm
                            if (!root.showManualForm) {
                                nameInput.text = ""
                                iconInput.text = ""
                                execInput.text = ""
                                root._manualIconPath = ""
                                root.appIconPickerVisible = false
                            }
                        }
                    }
                }
            }

            // Manual entry form
            Column {
                visible: root.showManualForm
                width: parent.width
                spacing: Theme.spacingXS
                topPadding: Theme.spacingXS

                Column {
                    width: parent.width; spacing: 4

                    StyledText { text: "Name"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    StyledRect {
                        width: parent.width; height: nameInput.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius

                        TextInput {
                            id: nameInput
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                            color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; clip: true
                            onAccepted: if (execInput.text.trim()) root.commitManualAdd()
                            onTextChanged: if (iconInput.text === "") Qt.callLater(root.tryAutoDetectIcon)
                            Text { visible: nameInput.text === ""; text: "App name"; color: Theme.surfaceVariantText; font: nameInput.font }
                        }
                    }
                }

                Column {
                    width: parent.width; spacing: 4

                    StyledText { text: "Icon"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }

                    Row {
                        width: parent.width; spacing: Theme.spacingS

                        Item {
                            width: Theme.iconSize; height: Theme.iconSize
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                visible: root._manualIconPath !== ""
                                source: root._manualIconPath !== "" ? ("file://" + root._manualIconPath) : ""
                                width: Theme.iconSize; height: Theme.iconSize
                                fillMode: Image.PreserveAspectFit; smooth: true; anchors.fill: parent
                            }
                            DankIcon {
                                visible: root._manualIconPath === ""
                                name: iconInput.text || "apps"; size: Theme.iconSize
                                color: Theme.primary; anchors.centerIn: parent
                            }
                        }

                        StyledRect {
                            height: iconInput.implicitHeight + Theme.spacingM * 2
                            width: parent.width - Theme.iconSize - chooseIconBtn.width - Theme.spacingS * 2
                            color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius

                            TextInput {
                                id: iconInput
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                                color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; clip: true
                                onTextChanged: if (!root._iconSetByCode) root._manualIconPath = ""
                                Text { visible: iconInput.text === ""; text: "auto-detect"; color: Theme.surfaceVariantText; font: iconInput.font }
                            }
                        }

                        StyledRect {
                            id: chooseIconBtn
                            height: chooseIconBtnLabel.implicitHeight + Theme.spacingS * 2
                            width: chooseIconBtnLabel.implicitWidth + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: (chooseIconMouse.containsMouse || root.appIconPickerVisible)
                                   ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                id: chooseIconBtnLabel
                                anchors.centerIn: parent
                                text: "Choose"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.primary
                            }
                            MouseArea {
                                id: chooseIconMouse
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.appIconPickerVisible = !root.appIconPickerVisible
                                    if (root.appIconPickerVisible) {
                                        root.appIconPickerFilter = ""
                                        appIconPickerSearch.text = ""
                                        if (systemAppsModel.count === 0 && !root.pickerLoading) {
                                            root.pickerFailed = false
                                            root.pickerLoading = true
                                            appScanner.running = true
                                        }
                                        root.filterAppIconMatches()
                                    }
                                }
                            }
                        }
                    }

                    // App icon picker
                    Column {
                        visible: root.appIconPickerVisible
                        width: parent.width; spacing: Theme.spacingXS

                        StyledRect {
                            width: parent.width; height: appIconPickerSearch.implicitHeight + Theme.spacingM * 2
                            color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius

                            TextInput {
                                id: appIconPickerSearch
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                                color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; clip: true
                                onTextChanged: root.appIconPickerFilter = text
                                Text { visible: appIconPickerSearch.text === ""; text: "Search apps…"; color: Theme.surfaceVariantText; font: appIconPickerSearch.font }
                            }
                        }

                        Column {
                            visible: appIconMatches.count > 0
                            width: parent.width; spacing: 2

                            Repeater {
                                model: appIconMatches
                                delegate: Item {
                                    width: parent.width; height: Theme.iconSize + Theme.spacingXS * 2
                                    StyledRect {
                                        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom; margins: 1 }
                                        radius: Theme.cornerRadius
                                        color: appMatchMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                        Row {
                                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingS; rightMargin: Theme.spacingS }
                                            spacing: Theme.spacingS

                                            Item {
                                                width: Theme.iconSize; height: Theme.iconSize
                                                Image {
                                                    visible: iconPath !== ""
                                                    source: iconPath !== "" ? ("file://" + iconPath) : ""
                                                    width: Theme.iconSize; height: Theme.iconSize
                                                    fillMode: Image.PreserveAspectFit; smooth: true; anchors.fill: parent
                                                }
                                                DankIcon {
                                                    visible: iconPath === ""
                                                    name: icon || "apps"; size: Theme.iconSize
                                                    color: Theme.primary; anchors.centerIn: parent
                                                }
                                            }

                                            Item {
                                                width: parent.width - Theme.iconSize - Theme.spacingS; height: Theme.iconSize
                                                StyledText {
                                                    text: name || ""
                                                    font.pixelSize: Theme.fontSizeMedium
                                                    color: Theme.surfaceText
                                                    elide: Text.ElideRight
                                                    width: parent.width
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: appMatchMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root._iconSetByCode = true
                                                iconInput.text = icon || "apps"
                                                root._manualIconPath = iconPath || ""
                                                root._iconSetByCode = false
                                                root.appIconPickerVisible = false
                                                root.appIconPickerFilter = ""
                                                appIconPickerSearch.text = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Material icons grid
                        StyledText { text: "Material icons"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                        Flow {
                            width: parent.width; spacing: 4
                            Repeater {
                                model: root.filteredAppIconList
                                delegate: Item {
                                    width: 68; height: 68
                                    StyledRect {
                                        anchors.fill: parent; anchors.margins: 2
                                        radius: Theme.cornerRadius
                                        color: appIconCellMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh
                                        Column {
                                            anchors.centerIn: parent; spacing: 2
                                            DankIcon {
                                                name: modelData; size: Theme.iconSize
                                                color: (iconInput.text === modelData && root._manualIconPath === "") ? Theme.primary : Theme.surfaceText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                            StyledText {
                                                text: modelData; font.pixelSize: 9
                                                color: Theme.surfaceVariantText; width: 62
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignHCenter
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }
                                        MouseArea {
                                            id: appIconCellMouse
                                            anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root._iconSetByCode = true
                                                iconInput.text = modelData
                                                root._manualIconPath = ""
                                                root._iconSetByCode = false
                                                root.appIconPickerVisible = false
                                                root.appIconPickerFilter = ""
                                                appIconPickerSearch.text = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width; spacing: 4

                    StyledText { text: "Command"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                    StyledRect {
                        width: parent.width; height: execInput.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius

                        TextInput {
                            id: execInput
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                            color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; clip: true
                            onAccepted: if (nameInput.text.trim()) root.commitManualAdd()
                            onTextChanged: if (iconInput.text === "") Qt.callLater(root.tryAutoDetectIcon)
                            Text { visible: execInput.text === ""; text: "Shell command"; color: Theme.surfaceVariantText; font: execInput.font }
                        }
                    }
                }

                StyledRect {
                    height: addAppLabel.implicitHeight + Theme.spacingS * 2
                    width: addAppLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: addAppMouse.containsMouse ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: addAppLabel
                        anchors.centerIn: parent
                        text: "Add App"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.primary
                    }
                    MouseArea {
                        id: addAppMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitManualAdd()
                    }
                }
            }
        }

        // App picker
        Column {
            visible: root.pickerVisible
            width: parent.width; spacing: Theme.spacingXS; topPadding: Theme.spacingXS

            StyledText {
                visible: root.pickerLoading
                text: "Scanning installed applications…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledRect {
                visible: !root.pickerLoading && systemAppsModel.count > 0
                width: parent.width; height: pickerSearch.implicitHeight + Theme.spacingM * 2
                color: Theme.surfaceContainerHigh; radius: Theme.cornerRadius

                TextInput {
                    id: pickerSearch
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                    color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; clip: true
                    onTextChanged: root.pickerFilter = text
                    Text { visible: pickerSearch.text === ""; text: "Search apps…"; color: Theme.surfaceVariantText; font: pickerSearch.font }
                }
            }

            StyledRect {
                visible: !root.pickerLoading && filteredApps.count > 0
                width: parent.width; height: Math.min(pickerListView.contentHeight, 280)
                clip: true; radius: Theme.cornerRadius
                color: Theme.surfaceContainerLow || Theme.surfaceContainerHigh

                ListView {
                    id: pickerListView
                    anchors.fill: parent; model: filteredApps; clip: true; spacing: 1

                    delegate: Item {
                        width: pickerListView.width; height: pickerItemRow.implicitHeight + Theme.spacingXS * 2

                        StyledRect {
                            anchors.fill: parent
                            color: pickerItemMouse.containsMouse ? Theme.surfaceContainerHighest : "transparent"
                            radius: 0
                        }

                        Row {
                            id: pickerItemRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingS; rightMargin: Theme.spacingS }
                            spacing: Theme.spacingS

                            Item {
                                width: Theme.iconSize; height: Theme.iconSize; anchors.verticalCenter: parent.verticalCenter
                                Image {
                                    visible: iconPath !== ""
                                    source: iconPath !== "" ? ("file://" + iconPath) : ""
                                    width: Theme.iconSize; height: Theme.iconSize
                                    fillMode: Image.PreserveAspectFit; smooth: true; anchors.fill: parent
                                }
                                DankIcon {
                                    visible: iconPath === ""
                                    name: "apps"; size: Theme.iconSize
                                    color: Theme.surfaceVariantText; anchors.centerIn: parent
                                }
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter; spacing: 2
                                width: parent.width - Theme.iconSize - Theme.spacingS * 2
                                StyledText { text: name || ""; font.pixelSize: Theme.fontSizeMedium; color: Theme.surfaceText; elide: Text.ElideRight; width: parent.width }
                                StyledText { visible: comment !== ""; text: comment || ""; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText; elide: Text.ElideRight; width: parent.width }
                            }
                        }

                        MouseArea {
                            id: pickerItemMouse
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.addApp({ name: name, icon: icon, iconPath: iconPath, exec: exec, source: "picker" })
                                root.pickerVisible = false
                                pickerSearch.text = ""
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: !root.pickerLoading && systemAppsModel.count > 0 && filteredApps.count === 0
                text: "No apps match \"" + root.pickerFilter + "\""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    // ── Error state ───────────────────────────────────────────────────────
    StyledRect {
        visible: root.pickerFailed && !root.pickerLoading
        width: parent.width; height: pickerErrText.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        StyledText {
            id: pickerErrText
            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
            text: "Could not scan installed apps. Python 3 is required.\n\nYou can still add apps manually."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            wrapMode: Text.WordWrap
        }
    }
}
```

### 6.4 README.md (Updated)

**Path:** `README.md`
**Changes:** Complete rewrite to reflect new multi-group workflow.

```markdown
# App Stack — Multi-Group Dux Shell Bar Widget

## Overview

App Stack is a **multi-group app launcher** for the Dux Shell bar. Each group is a named set of applications with its own icon. You add the widget to your bar once per group, and each instance can be placed independently anywhere in the bar.

## Requirements

- Dux Shell (formerly Dank Material Shell)
- Python 3 (for system app scanning)
- QtQuick / Quickshell runtime

## Getting the plugin

1. Copy the entire `dms-app-stack` directory into your Dux Shell plugins folder:
   ```bash
   cp -r dms-app-stack ~/.config/DuxShell/plugins/appStack_default
   ```

2. Reload Dux Shell plugins:
   ```bash
   dms ipc call plugins reload
   ```

3. Open DMS Settings → Plugins → enable "App Stack"

4. **Add the widget to your bar** — add it once for each group you want:
   - Settings → DuxBar → add "App Stack" to a section
   - Repeat for each group

## Configuration

### Creating groups

1. Open DMS Settings → Plugins → "App Stack"
2. Click **"+ Add Group"** in the settings panel
3. Enter a group name (e.g., "Development", "Browsers")
4. Choose a bar icon (type a name or click Browse)
5. Toggle "Show label in bar" if desired

### Adding apps to a group

**From the bar (quick):**
1. Click the widget pill in the bar
2. Click the **Edit** (pencil) icon in the popout
3. Click **"+ Add App"**
4. Search and select from installed apps

**From settings (full):**
1. Open Settings → Plugins → "App Stack"
2. Select a group from the list
3. Click **"Choose from Installed Apps"** or **"Add Manually"**
4. Search for apps or enter name/icon/command manually

### Managing groups

- **Reorder:** Groups appear in the order listed in settings
- **Remove:** Click "Remove Group" (requires at least one group remaining)
- **Edit:** Click a group to expand its settings

### Icon selection

Both the group icon and individual app icons use a pre-populated list of 100+ Material Design icons. Type a name or click Browse to search.

## Bar Placement

Each widget instance can be placed independently:
- Add "App Stack" to the left section for your most-used apps
- Add another to the center for daily drivers
- Add a third to the right for utilities

## Development

For development, symlink your plugin directory:
```bash
ln -s /path/to/dms-app-stack ~/.config/DuxShell/plugins/appStack_default
```

Then reload after changes:
```bash
dms ipc call plugins reload
```

## License

MIT
```

### 6.5 Migration Script

**Path:** `scripts/migrate-groups.py`
**Status:** New file (see below for complete content)

```python
#!/usr/bin/env python3
"""
Migrate existing App Stack groups (created via create-group.sh) into the new
single-instance multi-group format.

Usage:
    python3 scripts/migrate-groups.py [--dry-run] [--apply]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

PLUGIN_PARENTS = [
    Path.home() / ".config" / "DuxShell" / "plugins",
    Path.home() / ".config" / "DankMaterialShell" / "plugins",
]

GROUP_DIR_RE = re.compile(r"^appStack_.*$")


def find_group_dirs() -> list[Path]:
    dirs: list[Path] = []
    for parent in PLUGIN_PARENTS:
        if not parent.is_dir():
            continue
        for child in parent.iterdir():
            if child.is_dir() and GROUP_DIR_RE.match(child.name):
                dirs.append(child)
    return sorted(dirs)


def migrate_directory(directory: Path) -> dict[str, Any] | None:
    # Skip the main plugin directory
    pjson = directory / "plugin.json"
    if pjson.is_file():
        try:
            data = json.loads(pjson.read_text())
            if data.get("id") == "appStack_default":
                return None
        except (json.JSONDecodeError, OSError):
            pass

    # Derive group name from directory
    dir_name = directory.name
    group_name = dir_name.replace("appStack_", "").replace("_", " ").title() or dir_name
    group_id = "group_" + str(len(dir_name))

    # Extract apps from QML files
    apps: list[dict[str, Any]] = []
    icon = "apps"
    show_label = False

    for qml_file in ["AppGroupSettings.qml", "AppGroupWidget.qml"]:
        qml_path = directory / qml_file
        if not qml_path.is_file():
            continue
        try:
            content = qml_path.read_text(encoding="utf-8")
            # Extract appsData
            match = re.search(r'savePluginData\([^,]+,\s*"appsData",\s*(.+?)\)', content)
            if match:
                raw = match.group(1).strip()
                if raw.startswith("JSON.stringify("):
                    inner = raw[len("JSON.stringify("):-1]
                    try:
                        apps = json.loads(inner)
                    except (json.JSONDecodeError, ValueError):
                        pass
                else:
                    try:
                        apps = json.loads(raw)
                    except (json.JSONDecodeError, ValueError):
                        pass
            # Extract groupIcon
            match = re.search(r'savePluginData\([^,]+,\s*"groupIcon",\s*"([^"]+)"\)', content)
            if match:
                icon = match.group(1)
            # Extract showLabel
            match = re.search(r'savePluginData\([^,]+,\s*"showLabel",\s*(true|false)\)', content)
            if match:
                show_label = match.group(1) == "true"
        except OSError:
            continue

    return {
        "id": group_id,
        "name": group_name,
        "icon": icon,
        "showLabel": show_label,
        "apps": apps,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Migrate existing App Stack groups to the new single-instance format."
    )
    parser.add_argument("--apply", action="store_true", help="Apply the migration.")
    args = parser.parse_args()

    group_dirs = find_group_dirs()
    if not group_dirs:
        print("No existing App Stack group directories found.")
        sys.exit(0)

    print(f"Found {len(group_dirs)} group directory/directories:")
    for d in group_dirs:
        print(f"  {d}")

    groups = []
    for directory in group_dirs:
        group = migrate_directory(directory)
        if group is not None:
            groups.append(group)
            print(f"  Migrated: {directory.name} -> {group['name']} ({len(group['apps'])} apps)")

    if not groups:
        print("No migratable groups found.")
        sys.exit(0)

    result = {"groups": groups, "version": 2}

    if args.apply:
        output_path = Path(__file__).parent.parent / "data" / "migration_data.json"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
        print(f"\nMigration data written to: {output_path}")
    else:
        print("\nDry run — no files modified.")
        print("Run with --apply to write migration data.")
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
```

---

## 7. Migration Strategy

### 7.1 Automatic Migration

The refactored `AppGroupSettings.qml` will detect existing groups on first launch. If `pluginData.groups` is empty but the user has existing data from old plugin instances, they can run:

```bash
python3 ~/.config/DuxShell/plugins/appStack_default/scripts/migrate-groups.py --apply
```

### 7.2 Manual Migration Steps

1. Run the migration script with `--dry-run` to preview
2. Review the output JSON
3. Run with `--apply` to write migration data
4. The settings panel will import the data on next open

### 7.3 Backward Compatibility

- Old plugin directories are NOT deleted during migration
- Users can manually remove old directories after confirming migration
- The migration script skips the main `appStack_default` directory

---

## 8. Testing Checklist

### 8.1 Widget Testing

- [ ] Add widget once to bar → shows one group pill
- [ ] Add widget twice to bar → shows two group pills
- [ ] Click pill → opens correct group's popout
- [ ] Apps in popout match the group's app list
- [ ] Launch app from popout → app launches
- [ ] Edit mode → remove app badge works
- [ ] Edit mode → "+ Add App" opens picker
- [ ] Picker → search filters apps
- [ ] Picker → select app adds to group
- [ ] Picker → back button returns to grid
- [ ] Popout shows correct group name and icon

### 8.2 Settings Testing

- [ ] Open settings → shows group list
- [ ] "+ Add Group" creates new group
- [ ] Group name edits save correctly
- [ ] Group icon changes save correctly
- [ ] Icon picker opens and filters
- [ ] Icon picker → select icon updates group
- [ ] "Show label" toggle works
- [ ] Remove group works (with confirmation)
- [ ] At least one group cannot be removed
- [ ] Selecting group shows apps section
- [ ] Adding app from picker works
- [ ] Adding app manually works
- [ ] Removing app from group works
- [ ] Capacity warning at 10 apps

### 8.3 Migration Testing

- [ ] Run migration script with `--dry-run`
- [ ] Output JSON matches existing groups
- [ ] Run migration script with `--apply`
- [ ] Migration data file created
- [ ] Settings panel imports migrated data
- [ ] Old directories still exist (not deleted)

### 8.4 Edge Cases

- [ ] Empty group (no apps) → popout shows default apps
- [ ] Widget added but no groups configured → shows "Empty"
- [ ] Groups array corrupted → settings shows empty list
- [ ] Duplicate app exec in picker → "Already added" toast
- [ ] Python not installed → error message in settings

---

## End of Implementation Plan

> This document contains all context, code, and instructions needed to implement the single-plugin multi-group App Stack plugin. Any developer can pick up from any step using this document as the single source of truth.
