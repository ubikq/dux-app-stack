# App Stack — Feature Inventory

This document tracks every user-facing feature of the plugin so that
functionality is not silently lost during debugging or refactoring.

**Last verified:** 2026-11-16
**Files:** `AppGroupWidget.qml` (bar widget), `AppGroupSettings.qml` (settings panel)

---

## Architecture: groups are DMS variants

Each app group is a **DMS variant** (`plugin.json` declares
`"capabilities": ["multiple-usecases", "variants"]`).

- The settings panel creates/edits/removes variants via the `PluginSettings`
  API (`createVariant` / `updateVariant` / `removeVariant`).
- When the user adds the widget to the bar, DMS lists each variant as
  `"App Stack - <group name>"` (via `PluginService.getAllPluginVariants()`),
  so the user picks which group to attach.
- `SurfaceWidgetHost` injects `variantId` and `variantData` into the widget.
- The widget reads `variantData` as its group and persists edits with
  `pluginService.updatePluginVariant(pluginId, variantId, { apps })`.

Variant (group) config shape:
```json
{
  "id": "variant_...",
  "name": "Dev",
  "icon": "code",
  "showLabel": true,
  "apps": [
    { "name": "...", "icon": "...", "iconPath": "...", "exec": "...", "source": "..." }
  ]
}
```

---

## Settings panel (`AppGroupSettings.qml`)

### Group management

| # | Feature | Implementation | Status |
|---|---|---|---|
| G1 | List all groups | `ScrollView` + `Repeater` over `root.groupsArray` (= `root.variants`) | ✅ |
| G2 | Select a group | `MouseArea` → `root.selectedGroupIndex = index` | ✅ |
| G3 | Add a group | `+ Add Group` button → `root.addGroup()` → `createVariant()` | ✅ |
| G4 | Remove a group | trash `DankIcon` + `MouseArea` → `root.removeGroup(index)` → `removeVariant()` | ✅ |
| G5 | Edit group name | `TextInput` `groupNameInput` → `updateGroupField("name", …)` | ✅ |
| G6 | Edit group icon (text) | `TextField` `groupIconInput` → `updateGroupField("icon", …)` | ✅ |
| G7 | Group icon picker (grid) | `Flow` + `Repeater` over `filteredIconList` | ✅ |
| G8 | Group icon picker search | `TextInput` `iconPickerSearchInput` → `iconPickerFilter` | ✅ |
| G9 | Group icon picker labels | `StyledText` showing icon name under each cell | ✅ |
| G10 | Show-label toggle | custom toggle → `updateGroupField("showLabel", …)` | ✅ |
| G11 | "Editing: <group>" header | `StyledText` above the group config | ✅ |
| G12 | Remember last-edited group | `saveState`/`loadState("selectedGroupIndex")` | ✅ |
| G13 | Legacy migration | `migrateLegacyGroups()` converts old `groups` JSON → variants | ✅ |
| G14 | Delete group (with confirmation) | trash `DankIcon` → `pendingDeleteIndex` → confirm row → `removeGroup()` | ✅ |
| G15 | Block delete if group is in use | `isVariantInUse()` scans `SettingsData.barConfigs` | ✅ |
| G16 | Save / Cancel editor | draft model (`draftGroup` / `draftDirty` / `editingOpen`) | ✅ |
| G17 | Bordered edit panel | `StyledRect` with `outlineVariant` border | ✅ |
| G18 | Group list scrollbar | `Flickable` + custom always-visible thumb | ✅ |
| G19 | Auto-scroll to selected group | `scrollToSelected()` on selection change | ✅ |

> **Deleting a group:** `PluginService.removePluginVariant()` also calls
> `removeWidgetFromDankBar(fullId)`, so any bar widget bound to that group is
> removed from the bar automatically. The settings panel shows a confirmation
> row warning about this before deleting.

### App management

| # | Feature | Implementation | Status |
|---|---|---|---|
| A1 | List apps in selected group | `ScrollView` + `Repeater` over `selectedGroup.apps` | ✅ |
| A2 | Real app icons | `Image` from `modelData.iconPath` (fallback `DankIcon`) | ✅ |
| A3 | Add app manually | `+ Add Custom App` / `× Close Manual Add` button → `showManualForm` | ✅ |
| A4 | Manual form: name | `TextField` `manualNameInput` | ✅ |
| A5 | Manual form: command | `TextField` `manualExecInput` | ✅ |
| A6 | Manual form: icon | `TextField` `manualIconInput` | ✅ |
| A7 | App icon picker (grid) | `Flow` + `Repeater` over `filteredAppIconList` | ✅ |
| A8 | App icon picker search | `TextInput` `appIconPickerSearch` → `appIconPickerFilter` | ✅ |
| A9 | App icon picker labels | `StyledText` showing icon name under each cell | ✅ |
| A10 | Commit manual app | `Add App` button → `root.commitEditManualAdd()` | ✅ |
| A11 | Edit existing app | pencil `DankIcon` + `MouseArea` `editMouse` → loads into manual form | ✅ |
| A12 | Remove app | close `DankIcon` + `MouseArea` `removeMouseArea` → `root.removeApp(index)` | ✅ |
| A13 | Hide exec text for picker apps | `visible: modelData.source !== "picker"` | ✅ |
| A14 | Hide edit button for picker apps | `visible: modelData.source !== "picker"` | ✅ |
| A15 | Capacity warning at 10 apps | `StyledRect` + `warningText` | ✅ |
| A16 | Visible form fields | `TextField` with `surfaceContainerHigh` background | ✅ |

### App picker (installed apps)

| # | Feature | Implementation | Status |
|---|---|---|---|
| P1 | Open/close picker | `+ Installed Apps` / `× Close Picker` button → `root.openPicker()` | ✅ |
| P2 | Scan installed apps | `Process` `appScanner` runs `scripts/list-apps.py` | ✅ |
| P3 | Loading indicator | `StyledText` "Scanning installed applications…" | ✅ |
| P4 | Python-missing error | `StyledRect` + `pickerErrText` with install instructions | ✅ |
| P5 | Search apps | `TextField` `pickerSearch` → `pickerFilter` | ✅ |
| P6 | App list | `ListView` over `filteredApps` | ✅ |
| P7 | Real icons in picker | `Image` from `iconPath` (fallback `DankIcon`) | ✅ |
| P8 | Add from picker | `MouseArea` → `root.addApp({… source: "picker"})` | ✅ |
| P9 | No-match message | `StyledText` "No apps match …" | ✅ |

### Persistence

| # | Feature | Implementation | Status |
|---|---|---|---|
| S1 | Groups stored as variants | `PluginSettings.variants` (`SettingsData` key `variants`) | ✅ |
| S2 | Save on change | `createVariant` / `updateVariant` / `removeVariant` | ✅ |
| S3 | Load on open | `groupsArray` aliases `root.variants` | ✅ |
| S4 | Legacy `groups` key | Read once by `migrateLegacyGroups()`, then unused | ✅ |

---

## Bar widget (`AppGroupWidget.qml`)

| # | Feature | Implementation | Status |
|---|---|---|---|
| W1 | Horizontal bar pill | `horizontalBarPill: Component { Row { … } }` | ✅ |
| W2 | Vertical bar pill | `verticalBarPill: Component { DankIcon { … } }` | ✅ |
| W3 | Bind to a group | `variantId` / `variantData` injected by `SurfaceWidgetHost` | ✅ |
| W4 | Group icon in bar | `DankIcon` `name: root._groupIcon` | ✅ |
| W5 | Optional label in bar | `StyledText` `visible: root._showLabel` | ✅ |
| W6 | Popout with app grid | `popoutContent: Component { PopoutComponent { … } }` | ✅ |
| W7 | Launch app on click | popout app click → `exec` | ✅ |
| W8 | Add/remove apps in popout | `saveApps()` → `updatePluginVariant(pluginId, variantId, { apps })` | ✅ |
| W9 | Live refresh on settings edit | `Connections` on `pluginDataChanged` → re-read `variantData` | ✅ |

---

## Known constraints

- **Max 10 apps per group** (enforced in `addApp()`).
- **Python 3 optional** — only required for the installed-apps picker.
- **`PluginSettings` context** does not expose `surfaceContext`; do not use it.
- **Undefined types** in this shell: `Spacer`, `ModalAction`. Use `Item { Layout.fillWidth: true }` inside a `RowLayout` instead of `Spacer`.
- **`TextField` / `ScrollView` / `Dialog`** require `import QtQuick.Controls`.
- **Two-way bindings** (`text: model.x` + `onTextChanged: model.x = text`) cause
  binding loops. Always guard with an equality check before writing back.
- **Variant-scoped settings page is not supported by DMS.** `WidgetsTab.configureWidget()`
  navigates to `SettingsTabs.pluginPrefix + item.pluginId`, discarding the variant,
  and `PluginSettingsPage` only receives `pluginId`. Clicking a bar widget entry
  therefore opens the shared plugin settings page (all groups). The plugin
  mitigates this by remembering the last-edited group and showing an
  "Editing: <group>" header.
