import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// AppGroupSettings — Unified multi-group settings for App Stack plugin.
//
// Each app group is a DMS *variant*. The variant config shape is:
//   { "id": "variant_...", "name": "Dev", "icon": "code", "showLabel": true,
//     "apps": [{ "name": "...", "icon": "...", "iconPath": "...", "exec": "...", "source": "..." }] }
//
// The UI below is written against `groupsArray` / `selectedGroup`; those are
// thin aliases over the PluginSettings variant API (createVariant /
// updateVariant / removeVariant), so each bar widget can bind to one variant.
//
// pluginId is required by PluginSettings and must be declared explicitly.

PluginSettings {
    id: root
    pluginId: "appStack_default"

    // ── State ─────────────────────────────────────────────────────────────
    // Groups are stored as DMS variants (one variant per group).
    property var groupsArray: {
        variantsRevision  // re-evaluate whenever variants change
        return (root.variants || []).slice()
    }

    // One-time migration: legacy `groups` JSON array → variants.
    // Also restore the last-edited group so reopening the page is less confusing.
    Component.onCompleted: {
        Qt.callLater(root.migrateLegacyGroups)
        var saved = root.loadState("selectedGroupIndex", -1)
        if (saved >= 0 && saved < root.groupsArray.length)
            root.selectedGroupIndex = saved
        Qt.callLater(root.beginEdit)
    }

    onSelectedGroupIndexChanged: {
        if (selectedGroupIndex >= 0)
            root.saveState("selectedGroupIndex", selectedGroupIndex)
        root.beginEdit()
        root.editingOpen = true
        // Reset the text inputs (user typing breaks their text binding).
        groupNameInput.text = root.selectedGroup ? (root.selectedGroup.name || "") : ""
        groupIconInput.text = root.selectedGroup ? (root.selectedGroup.icon || "apps") : "apps"
        Qt.callLater(root.scrollToSelected)
    }

    onVariantsChanged: variantsRevision++

    // `variants` may be mutated in place, so onVariantsChanged can be missed.
    // Bump the revision on any plugin-data change to force the list to rebuild.
    Connections {
        target: pluginService
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === pluginId)
                root.variantsRevision++
        }
    }

    function migrateLegacyGroups() {
        if (root.variants.length > 0) return
        var legacy = root.loadValue("groups", "")
        if (!legacy) return
        var arr = []
        try { arr = JSON.parse(legacy) } catch (e) { return }
        if (!Array.isArray(arr) || arr.length === 0) return
        for (var i = 0; i < arr.length; i++) {
            var g = arr[i] || {}
            root.createVariant(g.name || ("Group " + (i + 1)), {
                icon: g.icon || "apps",
                showLabel: g.showLabel || false,
                apps: g.apps || []
            })
        }
        ToastService.showInfo("Migrated", arr.length + " group(s) converted to variants")
    }

    property int selectedGroupIndex: -1
    property int pendingDeleteIndex: -1
    readonly property bool pendingDeleteInUse: {
        if (pendingDeleteIndex < 0 || pendingDeleteIndex >= groupsArray.length) return false
        return isVariantInUse(groupsArray[pendingDeleteIndex].id)
    }
    property bool pickerVisible: false
    property bool pickerLoading: false
    property bool pickerFailed: false
    property string pickerFilter: ""
    property bool showManualForm: false
    property bool appIconPickerVisible: false
    property string appIconPickerFilter: ""
    property bool iconPickerVisible: false
    property string iconPickerFilter: ""
    property string editingAppName: ""
    property string editingAppExec: ""
    property string editingAppIcon: ""
    property string editingAppIconPath: ""
    property bool _iconSetByCode: false
    property string _manualIconPath: ""

    ListModel { id: systemAppsModel }
    ListModel { id: filteredApps }
    ListModel { id: appIconMatches }

    // ── Icon lists ────────────────────────────────────────────────────────
    readonly property var iconList: [
        "apps", "widgets", "dashboard", "grid_view", "work", "business_center",
        "folder", "folder_open", "description", "code", "terminal", "developer_mode",
        "build", "bug_report", "movie", "music_note", "headphones", "volume_up",
        "radio", "tv", "camera", "photo", "videocam", "mic", "language", "web",
        "public", "wifi", "email", "chat", "phone", "settings", "storage", "memory",
        "dns", "router", "devices", "computer", "laptop", "smartphone", "tablet",
        "monitor", "print", "keyboard", "download", "upload", "sync", "cloud",
        "attach_file", "person", "people", "group", "contacts",
        "sports_esports", "gamepad", "fitness_center", "medical_services",
        "favorite", "map", "place", "flight", "directions_car", "shopping_cart",
        "store", "attach_money", "credit_card", "school", "book", "science",
        "restaurant", "local_cafe", "home", "star", "bookmark", "search",
        "lock", "security", "notifications", "alarm", "calendar_today", "info"
    ]
    property var filteredIconList: {
        var f = root.iconPickerFilter
        if (!f) return root.iconList
        return root.iconList.filter(function(n) { return n.includes(f) })
    }
    property var filteredAppIconList: {
        var f = root.appIconPickerFilter
        if (!f) return root.iconList
        return root.iconList.filter(function(n) { return n.includes(f) })
    }

    // ── Resolved paths ────────────────────────────────────────────────────
    readonly property string listAppsScript:
        Qt.resolvedUrl("./scripts/list-apps.py").toString().replace(/^file:\/\//, "")

    // ── Computed ──────────────────────────────────────────────────────────
    // The persisted variant for the selected index.
    readonly property var savedGroup:
        (selectedGroupIndex >= 0 && selectedGroupIndex < groupsArray.length)
            ? groupsArray[selectedGroupIndex] : null

    // Working copy of the selected group. The UI edits this; changes are only
    // written back to the variant when the user clicks Save.
    property var draftGroup: null
    property bool draftDirty: false
    property bool editingOpen: false
    property bool helpExpanded: false
    property int variantsRevision: 0

    // The UI reads/writes the draft.
    readonly property var selectedGroup: draftGroup

        // ── Functions ─────────────────────────────────────────────────────────
    
        // No-op: variants persist themselves via the PluginSettings API.
        function saveGroups() {}
    
    // Load the selected variant into the draft.
    // Read groupsArray[selectedGroupIndex] directly: the `savedGroup` binding
    // may not have re-evaluated yet when this runs from onSelectedGroupIndexChanged.
    function beginEdit() {
        var g = (selectedGroupIndex >= 0 && selectedGroupIndex < groupsArray.length)
                ? groupsArray[selectedGroupIndex] : null
        if (!g) {
            draftGroup = null
            draftDirty = false
            return
        }
        draftGroup = JSON.parse(JSON.stringify(g))
        draftDirty = false
    }

    // Keep the selected group visible in the list.
    function scrollToSelected() {
        if (selectedGroupIndex < 0 || !groupListFlick) return
        var y = selectedGroupIndex * 42
        var maxY = Math.max(0, groupListFlick.contentHeight - groupListFlick.height)
        groupListFlick.contentY = Math.min(y, maxY)
    }

    // Commit the draft to the variant.
    function saveDraft() {
        // Use the draft's own id: for a freshly-added group the variants list
        // may not have refreshed yet, so savedGroup can still be null.
        if (!draftGroup || !draftGroup.id) return
        root.updateVariant(draftGroup.id, draftGroup)
        draftDirty = false
        root.editingOpen = false
        ToastService.showInfo("Saved", "Group \"" + (draftGroup.name || "Unnamed") + "\" saved")
    }

    // Discard unsaved edits and close the editor.
    function cancelDraft() {
        beginEdit()
        root.editingOpen = false
    }

    function addGroup() {
        var idx = groupsArray.length
        var name = "Group " + (idx + 1)
        var variantId = root.createVariant(name, {
            icon: "apps",
            showLabel: false,
            apps: []
        })
        selectedGroupIndex = idx
        // Set the draft immediately (variants may not have refreshed yet).
        draftGroup = {
            id: variantId,
            name: name,
            icon: "apps",
            showLabel: false,
            apps: []
        }
        draftDirty = false
        root.editingOpen = true
        return variantId
    }
    
        function removeGroup(idx) {
            if (idx < 0 || idx >= groupsArray.length) return
            root.removeVariant(groupsArray[idx].id)
            if (selectedGroupIndex >= groupsArray.length)
                selectedGroupIndex = groupsArray.length > 0 ? groupsArray.length - 1 : -1
        }
    
        // True if a bar widget is currently bound to this variant.
        // DMS's removePluginVariant() only strips the widget from the primary bar,
        // so we block deletion and ask the user to remove the widget manually.
        function isVariantInUse(variantId) {
            if (!variantId) return false
            var fullId = root.pluginId + ":" + variantId
            var bars = []
            try { bars = SettingsData.barConfigs || [] } catch (e) { return false }
            for (var i = 0; i < bars.length; i++) {
                var b = bars[i] || {}
                var lists = [b.leftWidgets || [], b.centerWidgets || [], b.rightWidgets || []]
                for (var j = 0; j < lists.length; j++) {
                    var ws = lists[j]
                    for (var k = 0; k < ws.length; k++) {
                        var w = ws[k]
                        var id = (typeof w === "string") ? w : (w && w.id)
                        if (id === fullId) return true
                    }
                }
            }
            return false
        }
    
    // Edit the draft (not the persisted variant).
    function updateGroupField(field, value) {
        if (!draftGroup) return
        var d = JSON.parse(JSON.stringify(draftGroup))
        d[field] = value
        draftGroup = d
        draftDirty = true
    }
    
    function saveGroupApps(apps) {
        if (!draftGroup) return
        var d = JSON.parse(JSON.stringify(draftGroup))
        d.apps = apps
        draftGroup = d
        draftDirty = true
    }

    function addApp(appData) {
        if (!draftGroup) return
        var apps = draftGroup.apps || []
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].exec === appData.exec) {
                ToastService.showInfo("Already added", appData.name + " is already in this group")
                return
            }
        }
        if (apps.length >= 10) {
            ToastService.showInfo("Limit reached", "Maximum 10 apps per group")
            return
        }
        apps = apps.slice()
        apps.push({
            name: appData.name,
            icon: appData.icon || "apps",
            iconPath: appData.iconPath || "",
            exec: appData.exec,
            source: appData.source || "manual"
        })
        saveGroupApps(apps)
    }

    function removeApp(idx) {
        if (!draftGroup) return
        var apps = draftGroup.apps.filter(function(_, i) { return i !== idx })
        saveGroupApps(apps)
    }

    function updateApp(idx, updates) {
        if (!draftGroup) return
        var apps = draftGroup.apps.slice()
        apps[idx] = Object.assign({}, apps[idx], updates)
        saveGroupApps(apps)
    }

    function filterSystemApps() {
        filteredApps.clear()
        var f = pickerFilter.toLowerCase().trim()
        for (var i = 0; i < systemAppsModel.count && filteredApps.count < 100; i++) {
            var a = systemAppsModel.get(i)
            if (f === "" || a.name.toLowerCase().includes(f) ||
                (a.comment && a.comment.toLowerCase().includes(f))) {
                filteredApps.append(a)
            }
        }
    }

    function tryAutoDetectIcon() {
        if (editingAppIcon !== "") return
        var n = editingAppName.toLowerCase()
        var e = editingAppExec.toLowerCase()
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
            _iconSetByCode = true
            editingAppIcon = bestApp.icon || "apps"
            _manualIconPath = bestApp.iconPath || ""
            _iconSetByCode = false
        }
    }

    function filterAppIconMatches() {
        appIconMatches.clear()
        var f = root.appIconPickerFilter.toLowerCase()
        var n = editingAppName.toLowerCase()
        var e = editingAppExec.toLowerCase()
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

    onPickerFilterChanged: filterSystemApps()
    onAppIconPickerFilterChanged: filterAppIconMatches()

    function openPicker() {
        root.pickerVisible = !root.pickerVisible
        if (root.pickerVisible) {
            root.pickerFailed = false
            if (systemAppsModel.count === 0) {
                // First open: scan the system for installed apps.
                root.pickerLoading = true
                appScanner.running = true
            } else {
                // Already scanned: reuse the cached list (no "Scanning…" hang).
                root.pickerLoading = false
                root.filterSystemApps()
            }
        }
    }

    // ── System app scanner ────────────────────────────────────────────────
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
                    if (root.showManualForm && editingAppIcon === "")
                        Qt.callLater(root.tryAutoDetectIcon)
                    if (root.appIconPickerVisible)
                        Qt.callLater(root.filterAppIconMatches)
                } catch (e) {}
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

    // ── UI ────────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: Theme.spacingM

        // ══════════════════════════════════════════════════════════════════
        // ── How to use (collapsible) ──────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════
        StyledRect {
            width: parent.width
            height: helpColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerLow || Theme.surfaceContainerHigh
            border.color: Theme.outlineVariant
            border.width: 1

            Column {
                id: helpColumn
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM; topMargin: Theme.spacingM
                }
                spacing: Theme.spacingS

                // Header (click to expand/collapse)
                Item {
                    width: parent.width
                    height: helpHeader.implicitHeight

                    RowLayout {
                        id: helpHeader
                        anchors.fill: parent
                        spacing: Theme.spacingS

                        DankIcon {
                            Layout.preferredWidth: Theme.iconSize
                            Layout.preferredHeight: Theme.iconSize
                            name: "help"
                            size: Theme.iconSize
                            color: Theme.primary
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: "How to use App Stack"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Bold
                            color: Theme.surfaceText
                        }

                        DankIcon {
                            Layout.preferredWidth: Theme.iconSize
                            Layout.preferredHeight: Theme.iconSize
                            name: root.helpExpanded ? "expand_less" : "expand_more"
                            size: Theme.iconSize
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.helpExpanded = !root.helpExpanded
                    }
                }

                // Body
                Column {
                    width: parent.width
                    spacing: Theme.spacingS
                    visible: root.helpExpanded

                    StyledText {
                        width: parent.width
                        text: "1. Create and edit groups"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    StyledText {
                        width: parent.width
                        text: "Each group is a set of app shortcuts that appears as its own widget on the bar. Click \"+ Add Group\" to create one, then select it in the list to edit it. Set its name, icon (type a Material icon name, or click \"Pick\" to browse), and whether to show the label next to the icon. Click \"Save\" to apply your changes, or \"Cancel\" to discard them."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: "2. Add apps to a group"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    StyledText {
                        width: parent.width
                        text: "Each group holds up to 10 apps. Use \"+ Installed Apps\" to browse and search the applications installed on your system (selecting one adds it with its real icon), or \"+ Add Custom App\" to enter a name, command, and icon manually. Remove an app with the × button; edit a custom app with the pencil icon. A warning appears when a group reaches 10 apps."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: "3. Add the widget to your bar"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    StyledText {
                        width: parent.width
                        text: "Widgets are added from the Bar widgets page, not from this settings page. Each app group is added to the bar individually: open Settings → Bar → Bar widgets, find the entry named \"App Stack – <group name>\", and add it to a bar section. Repeat for every group you want on the bar. The widget shows the group you picked when adding it; to change which group a bar slot shows, remove that widget and add the desired group instead."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: "4. Remove a group"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    StyledText {
                        width: parent.width
                        text: "A group can only be deleted once its widget has been removed from the bar. Open Settings → Bar → Bar widgets and remove the \"App Stack – <group name>\" entry, then return here and click \"Delete\" next to the group. If the group is still linked to a bar widget, deletion is blocked and a warning is shown. This is because the plugin cannot reliably remove a widget from every bar, so it asks you to remove it manually first."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        width: parent.width
                        text: "Notes"
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    StyledText {
                        width: parent.width
                        text: "• Python 3 is optional — it is only needed for the \"+ Installed Apps\" picker. Without it, use \"+ Add Custom App\".\n• Group name, icon, and label changes take effect when you click \"Save\".\n• Apps added or removed from the widget's popout are saved immediately."
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceVariantText
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // ── Group Management Header ───────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════
        RowLayout {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                text: "Groups"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Item { Layout.fillWidth: true }

            StyledRect {
                Layout.preferredHeight: addGroupBtnLabel.implicitHeight + Theme.spacingS * 2
                Layout.preferredWidth: addGroupBtnLabel.implicitWidth + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: addGroupMouse.containsMouse
                       ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                       : Theme.surfaceContainerHigh

                StyledText {
                    id: addGroupBtnLabel
                    anchors.centerIn: parent
                    text: "+ Add Group"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.primary
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

        // ── Group list ────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: Math.min(groupsArray.length * 44 + 10, 300)

            Flickable {
                id: groupListFlick
                anchors {
                    left: parent.left; right: groupScrollTrack.left; top: parent.top; bottom: parent.bottom
                }
                contentWidth: width
                contentHeight: groupListColumn.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: groupListColumn
                    width: groupListFlick.width
                    spacing: 2

                Repeater {
                    model: root.groupsArray

                    delegate: Item {
                        width: parent.width
                        height: 40

                        Rectangle {
                            anchors.fill: parent
                            color: index === root.selectedGroupIndex
                                   ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                                   : Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius
                        }

                        // Subtle divider between rows (not after the last one)
                        Rectangle {
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: Theme.outlineVariant
                            visible: index < root.groupsArray.length - 1
                        }

                        // Select area declared BEFORE the row so the delete
                        // button (inside the row) stays on top and clickable.
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.selectedGroupIndex = index
                                // Re-open the editor even when the index is unchanged.
                                root.beginEdit()
                                root.editingOpen = true
                            }
                        }

                        RowLayout {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingS; rightMargin: Theme.spacingS
                            }
                            spacing: Theme.spacingS

                            DankIcon {
                                Layout.preferredWidth: Theme.iconSize
                                Layout.preferredHeight: Theme.iconSize
                                name: modelData.icon || "apps"
                                size: Theme.iconSize
                                color: Theme.primary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.name || "Unnamed"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }

                            StyledRect {
                                Layout.preferredHeight: deleteGroupLabel.implicitHeight + Theme.spacingXS * 2
                                Layout.preferredWidth: deleteGroupLabel.implicitWidth + Theme.spacingM * 2
                                radius: Theme.cornerRadius
                                color: deleteGroupMouse.containsMouse ? Theme.error : Theme.surfaceContainerHighest

                                StyledText {
                                    id: deleteGroupLabel
                                    anchors.centerIn: parent
                                    text: "Delete"
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: deleteGroupMouse.containsMouse ? Theme.surface : Theme.error
                                }
                                MouseArea {
                                    id: deleteGroupMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.pendingDeleteIndex = index
                                }
                            }
                        }
                    }
                }

                // Empty state
                StyledText {
                    visible: root.groupsArray.length === 0
                    text: "No groups yet. Click '+ Add Group' to create one."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    horizontalAlignment: Text.AlignHCenter
                    width: parent.width
                }
                }
            }

            // Custom always-visible scrollbar (the default one fades out).
            Item {
                id: groupScrollTrack
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                width: 10
                visible: groupListFlick.contentHeight > groupListFlick.height

                Rectangle {
                    width: 6
                    radius: 3
                    color: Theme.primary
                    x: 2
                    height: Math.max(30, groupScrollTrack.height * (groupListFlick.height / Math.max(1, groupListFlick.contentHeight)))
                    y: (groupScrollTrack.height - height) * (groupListFlick.contentY / Math.max(1, groupListFlick.contentHeight - groupListFlick.height))
                }
            }
        }

        // ── Delete confirmation ───────────────────────────────────────────
        StyledRect {
            width: parent.width
            height: deleteConfirmColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha ? Theme.withAlpha(Theme.error || Theme.primary, 0.12) : Theme.surfaceContainerHigh
            visible: root.pendingDeleteIndex >= 0 && root.pendingDeleteIndex < root.groupsArray.length

            Column {
                id: deleteConfirmColumn
                anchors {
                    left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                }
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: {
                        var nm = (root.pendingDeleteIndex >= 0 && root.pendingDeleteIndex < root.groupsArray.length)
                                 ? (root.groupsArray[root.pendingDeleteIndex].name || "Unnamed") : ""
                        return root.pendingDeleteInUse
                               ? "Can't delete: \"" + nm + "\" is currently linked to a bar widget."
                               : "Delete group \"" + nm + "\"?"
                    }
                    font.pixelSize: Theme.fontSizeMedium
                    color: root.pendingDeleteInUse ? (Theme.error || Theme.surfaceText) : Theme.surfaceText
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    width: parent.width
                    text: root.pendingDeleteInUse
                          ? "Remove that widget from the bar first, then delete the group."
                          : "Any bar widget using this group will also be removed from the bar."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.WordWrap
                }

                Row {
                    spacing: Theme.spacingS

                    StyledRect {
                        height: cancelDeleteLabel.implicitHeight + Theme.spacingXS * 2
                        width: cancelDeleteLabel.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: cancelDeleteMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                        StyledText {
                            id: cancelDeleteLabel
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                        MouseArea {
                            id: cancelDeleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pendingDeleteIndex = -1
                        }
                    }

                    StyledRect {
                        visible: !root.pendingDeleteInUse
                        height: confirmDeleteLabel.implicitHeight + Theme.spacingXS * 2
                        width: confirmDeleteLabel.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: confirmDeleteMouse.containsMouse
                               ? Theme.error
                               : (Theme.withAlpha ? Theme.withAlpha(Theme.error || Theme.primary, 0.2) : Theme.surfaceContainerHigh)

                        StyledText {
                            id: confirmDeleteLabel
                            anchors.centerIn: parent
                            text: "Delete"
                            font.pixelSize: Theme.fontSizeSmall
                            color: confirmDeleteMouse.containsMouse ? Theme.surface : (Theme.error || Theme.surfaceText)
                        }
                        MouseArea {
                            id: confirmDeleteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.removeGroup(root.pendingDeleteIndex)
                                root.pendingDeleteIndex = -1
                            }
                        }
                    }
                }
            }
        }

        // ── Separator: groups list vs. selected group settings ────────────
        Rectangle {
            width: parent.width
            height: 1
            color: Theme.outlineVariant
        }

        // ══════════════════════════════════════════════════════════════════
        // ── Selected Group Settings ───────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════
        StyledRect {
            width: parent.width
            height: groupConfigColumn.implicitHeight + appsColumn.implicitHeight + Theme.spacingS + Theme.spacingL * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerLow || Theme.surfaceContainerHigh
            border.color: Theme.outlineVariant
            border.width: 1
            visible: root.selectedGroup !== null && root.editingOpen

            Column {
                id: groupConfigColumn
                anchors {
                    left: parent.left; right: parent.right; top: parent.top
                    leftMargin: Theme.spacingL; rightMargin: Theme.spacingL; topMargin: Theme.spacingL
                }
                spacing: Theme.spacingS

            // ── Editing header ────────────────────────────────────────────
            StyledText {
                text: "Editing: " + (root.selectedGroup ? (root.selectedGroup.name || "Unnamed") : "")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.primary
                elide: Text.ElideRight
                width: parent.width
            }

            // ── Save / Cancel ─────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: Theme.spacingS

                StyledRect {
                    height: saveGroupLabel.implicitHeight + Theme.spacingS * 2
                    width: saveGroupLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: root.draftDirty
                           ? (saveGroupMouse.containsMouse ? Theme.primary : (Theme.primaryContainer || Theme.surfaceContainerHigh))
                           : Theme.surfaceContainerHigh

                    StyledText {
                        id: saveGroupLabel
                        anchors.centerIn: parent
                        text: "Save"
                        font.pixelSize: Theme.fontSizeMedium
                        color: !root.draftDirty
                               ? Theme.surfaceVariantText
                               : (saveGroupMouse.containsMouse ? Theme.primaryText : Theme.primary)
                    }
                    MouseArea {
                        id: saveGroupMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root.draftDirty
                        cursorShape: root.draftDirty ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: root.saveDraft()
                    }
                }

                StyledRect {
                    height: cancelGroupLabel.implicitHeight + Theme.spacingS * 2
                    width: cancelGroupLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: cancelGroupMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: cancelGroupLabel
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: cancelGroupMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelDraft()
                    }
                }

                StyledText {
                    visible: root.draftDirty
                    text: "Unsaved changes"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.tertiary || Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Group name ────────────────────────────────────────────────
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
                    height: groupNameInput.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: groupNameInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        text: root.selectedGroup ? (root.selectedGroup.name || "") : ""
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onTextChanged: {
                            var cur = root.selectedGroup ? (root.selectedGroup.name || "") : ""
                            if (cur !== text)
                                root.updateGroupField("name", text)
                        }
                    }
                }
            }

            // ── Group icon ────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 4

                StyledText {
                    text: "Group Icon"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledRect {
                        height: Theme.iconSize + Theme.spacingM * 2
                        width: Theme.iconSize + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        DankIcon {
                            name: root.selectedGroup ? (root.selectedGroup.icon || "apps") : "apps"
                            size: Theme.iconSize
                            anchors.centerIn: parent
                        }
                    }

                    TextField {
                        id: groupIconInput
                        width: parent.width - Theme.iconSize - Theme.spacingM * 4 - 60
                        text: root.selectedGroup ? (root.selectedGroup.icon || "apps") : "apps"
                        color: Theme.surfaceText
                        placeholderText: "Icon name (e.g. apps, folder, code)"
                        placeholderTextColor: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        leftPadding: Theme.spacingM
                        rightPadding: Theme.spacingM
                        background: Rectangle {
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius
                        }
                        onTextChanged: {
                            var cur = root.selectedGroup ? (root.selectedGroup.icon || "apps") : "apps"
                            if (cur !== text)
                                root.updateGroupField("icon", text)
                        }
                    }

                    StyledRect {
                        height: Theme.iconSize + Theme.spacingS
                        width: iconPickerBtnLabel.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: iconPickerBtnMouse.containsMouse
                               ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                               : Theme.surfaceContainerHigh

                        StyledText {
                            id: iconPickerBtnLabel
                            anchors.centerIn: parent
                            text: "Pick"
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.primary
                        }
                        MouseArea {
                            id: iconPickerBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.iconPickerVisible = !root.iconPickerVisible
                        }
                    }
                }

                // Inline icon picker
                Column {
                    width: parent.width
                    spacing: Theme.spacingXS
                    visible: root.iconPickerVisible

                    StyledRect {
                        width: parent.width
                        height: iconPickerSearchInput.implicitHeight + Theme.spacingM * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius

                        TextInput {
                            id: iconPickerSearchInput
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            clip: true
                            onTextChanged: root.iconPickerFilter = text.toLowerCase()
                            Text {
                                visible: iconPickerSearchInput.text === ""
                                text: "Search icons…"
                                color: Theme.surfaceVariantText
                                font: iconPickerSearchInput.font
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
                                           ? (Theme.primaryContainer || Theme.surfaceContainerHighest) : Theme.surfaceContainerHigh

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        DankIcon {
                                            name: modelData
                                            size: Theme.iconSize
                                            color: (root.selectedGroup && root.selectedGroup.icon === modelData)
                                                   ? Theme.primary : Theme.surfaceText
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }

                                        StyledText {
                                            text: modelData
                                            font.pixelSize: 9
                                            color: Theme.surfaceVariantText
                                            width: 62
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            anchors.horizontalCenter: parent.horizontalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: iconCellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.updateGroupField("icon", modelData)
                                            groupIconInput.text = modelData
                                            root.iconPickerVisible = false
                                            iconPickerSearchInput.text = ""
                                            root.iconPickerFilter = ""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Show label toggle ─────────────────────────────────────────
            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: "Show Label in Bar"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }

                Item { Layout.fillWidth: true }

                StyledRect {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 24
                    radius: 12
                    color: (root.selectedGroup && root.selectedGroup.showLabel)
                           ? Theme.primary : Theme.surfaceContainerHigh

                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                        x: (root.selectedGroup && root.selectedGroup.showLabel)
                           ? parent.width - width - 3 : 3
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.updateGroupField("showLabel",
                            !(root.selectedGroup && root.selectedGroup.showLabel))
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════
        // ── Apps Management ───────────────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════
        Column {
            id: appsColumn
            anchors {
                left: parent.left; right: parent.right; top: groupConfigColumn.bottom
                leftMargin: Theme.spacingL; rightMargin: Theme.spacingL; topMargin: Theme.spacingS
            }
            spacing: Theme.spacingS
            visible: root.selectedGroup !== null

            RowLayout {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: "Apps (" + (root.selectedGroup ? (root.selectedGroup.apps || []).length : 0) + "/10)"
                    font.pixelSize: Theme.fontSizeLarge
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                Item { Layout.fillWidth: true }

                StyledRect {
                    Layout.preferredHeight: browseBtnLabel.implicitHeight + Theme.spacingS * 2
                    Layout.preferredWidth: browseBtnLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    // Filled while the picker is open so the "hide" action stands out.
                    color: root.pickerVisible
                           ? (browseBtnMouse.containsMouse ? Theme.primary : (Theme.primaryContainer || Theme.surfaceContainerHighest))
                           : (browseBtnMouse.containsMouse ? (Theme.primaryContainer || Theme.surfaceContainerHighest) : Theme.surfaceContainerHigh)

                    StyledText {
                        id: browseBtnLabel
                        anchors.centerIn: parent
                        text: root.pickerVisible ? "× Close Picker" : "+ Installed Apps"
                        font.pixelSize: Theme.fontSizeMedium
                        color: root.pickerVisible && browseBtnMouse.containsMouse ? Theme.primaryText : Theme.primary
                    }
                    MouseArea {
                        id: browseBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openPicker()
                    }
                }

                StyledRect {
                    Layout.preferredHeight: addAppBtnLabel.implicitHeight + Theme.spacingS * 2
                    Layout.preferredWidth: addAppBtnLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    // Filled while the manual form is open so the "hide" action stands out.
                    color: root.showManualForm
                           ? (addAppBtnMouse.containsMouse ? Theme.primary : (Theme.primaryContainer || Theme.surfaceContainerHighest))
                           : (addAppBtnMouse.containsMouse ? (Theme.primaryContainer || Theme.surfaceContainerHighest) : Theme.surfaceContainerHigh)

                    StyledText {
                        id: addAppBtnLabel
                        anchors.centerIn: parent
                        text: root.showManualForm ? "× Close Manual Add" : "+ Add Custom App"
                        font.pixelSize: Theme.fontSizeMedium
                        color: root.showManualForm && addAppBtnMouse.containsMouse ? Theme.primaryText : Theme.primary
                    }
                    MouseArea {
                        id: addAppBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.showManualForm = !root.showManualForm
                            if (root.showManualForm) {
                                root.editingAppName = ""
                                root.editingAppIcon = ""
                                root.editingAppExec = ""
                                root._manualIconPath = ""
                            }
                        }
                    }
                }
            }

            // ── Manual app form ───────────────────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.showManualForm

                StyledText {
                    text: "Add App Manually"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Bold
                    color: Theme.surfaceText
                }

                // App name
                Column {
                    width: parent.width
                    spacing: 4

                    StyledText {
                        text: "App Name"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    TextField {
                        id: manualNameInput
                        width: parent.width
                        placeholderText: "e.g. Firefox"
                        color: Theme.surfaceText
                        placeholderTextColor: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        leftPadding: Theme.spacingM
                        rightPadding: Theme.spacingM
                        background: Rectangle {
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius
                        }
                    }
                }

                // App exec/command
                Column {
                    width: parent.width
                    spacing: 4

                    StyledText {
                        text: "Command"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    TextField {
                        id: manualExecInput
                        width: parent.width
                        placeholderText: "e.g. firefox or /usr/bin/app --flag"
                        color: Theme.surfaceText
                        placeholderTextColor: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        leftPadding: Theme.spacingM
                        rightPadding: Theme.spacingM
                        background: Rectangle {
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius
                        }
                    }
                }

                // App icon
                Column {
                    width: parent.width
                    spacing: 4

                    StyledText {
                        text: "Icon"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                    Row {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledRect {
                            height: Theme.iconSize + Theme.spacingM * 2
                            width: Theme.iconSize + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            DankIcon {
                                name: root.editingAppIcon || "apps"
                                size: Theme.iconSize
                                anchors.centerIn: parent
                            }
                        }

                        TextField {
                            id: manualIconInput
                            width: parent.width - Theme.iconSize - Theme.spacingM * 4 - 60
                            placeholderText: "Icon name"
                            color: Theme.surfaceText
                            placeholderTextColor: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeMedium
                            leftPadding: Theme.spacingM
                            rightPadding: Theme.spacingM
                            text: root.editingAppIcon
                            background: Rectangle {
                                color: Theme.surfaceContainerHigh
                                radius: Theme.cornerRadius
                            }
                            onTextChanged: {
                                if (root.editingAppIcon !== text)
                                    root.editingAppIcon = text
                            }
                        }

                        StyledRect {
                            height: Theme.iconSize + Theme.spacingS
                            width: appIconPickerBtnLabel.implicitWidth + Theme.spacingM * 2
                            radius: Theme.cornerRadius
                            color: appIconPickerBtnMouse.containsMouse
                                   ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                                   : Theme.surfaceContainerHigh

                            StyledText {
                                id: appIconPickerBtnLabel
                                anchors.centerIn: parent
                                text: "Pick"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.primary
                            }
                            MouseArea {
                                id: appIconPickerBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appIconPickerVisible = !root.appIconPickerVisible
                            }
                        }
                    }

                    // Inline app icon picker
                    Column {
                        width: parent.width
                        spacing: Theme.spacingXS
                        visible: root.appIconPickerVisible

                        StyledRect {
                            width: parent.width
                            height: appIconPickerSearch.implicitHeight + Theme.spacingM * 2
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius

                            TextInput {
                                id: appIconPickerSearch
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                }
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                onTextChanged: root.appIconPickerFilter = text.toLowerCase()
                                Text {
                                    visible: appIconPickerSearch.text === ""
                                    text: "Search icons…"
                                    color: Theme.surfaceVariantText
                                    font: appIconPickerSearch.font
                                }
                            }
                        }

                        Flow {
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.filteredAppIconList
                                delegate: Item {
                                    width: 68; height: 68

                                    StyledRect {
                                        anchors.fill: parent; anchors.margins: 2
                                        radius: Theme.cornerRadius
                                        color: appIconCellMouse.containsMouse
                                               ? (Theme.primaryContainer || Theme.surfaceContainerHighest) : Theme.surfaceContainerHigh

                                        Column {
                                            anchors.centerIn: parent
                                            spacing: 2

                                            DankIcon {
                                                name: modelData
                                                size: Theme.iconSize
                                                color: root.editingAppIcon === modelData ? Theme.primary : Theme.surfaceText
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }

                                            StyledText {
                                                text: modelData
                                                font.pixelSize: 9
                                                color: Theme.surfaceVariantText
                                                width: 62
                                                elide: Text.ElideRight
                                                horizontalAlignment: Text.AlignHCenter
                                                anchors.horizontalCenter: parent.horizontalCenter
                                            }
                                        }

                                        MouseArea {
                                            id: appIconCellMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.editingAppIcon = modelData
                                                root.appIconPickerVisible = false
                                                appIconPickerSearch.text = ""
                                                root.appIconPickerFilter = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Commit button
                StyledRect {
                    width: parent.width
                    height: commitBtnLabel.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: commitBtnMouse.containsMouse
                           ? Theme.primary
                           : (Theme.primaryContainer || Theme.surfaceContainerHigh)

                    StyledText {
                        id: commitBtnLabel
                        anchors.centerIn: parent
                        text: "Add App"
                        font.pixelSize: Theme.fontSizeMedium
                        color: commitBtnMouse.containsMouse ? Theme.primaryText : Theme.primary
                    }
                    MouseArea {
                        id: commitBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.commitEditManualAdd()
                    }
                }
            }

            // ── App list ──────────────────────────────────────────────────
            ScrollView {
                id: appListScroll
                width: parent.width
                height: Math.min((root.selectedGroup ? (root.selectedGroup.apps || []).length : 0) * 60 + 10, 300)
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                visible: root.selectedGroup && (root.selectedGroup.apps || []).length > 0

                Column {
                    width: appListScroll.availableWidth
                    spacing: 2

                    Repeater {
                        model: root.selectedGroup ? (root.selectedGroup.apps || []) : []

                        delegate: Item {
                            width: parent.width
                            height: 56

                            Rectangle {
                                anchors.fill: parent
                                color: Theme.surfaceContainerHigh
                                radius: Theme.cornerRadius
                            }

                            Row {
                                anchors {
                                    left: parent.left; right: appBtns.left
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingS
                                }
                                spacing: Theme.spacingS

                                Item {
                                    width: Theme.iconSize
                                    height: Theme.iconSize
                                    anchors.verticalCenter: parent.verticalCenter

                                    Image {
                                        visible: (modelData.iconPath || "") !== ""
                                        source: (modelData.iconPath || "") !== "" ? ("file://" + modelData.iconPath) : ""
                                        width: Theme.iconSize; height: Theme.iconSize
                                        fillMode: Image.PreserveAspectFit; smooth: true
                                        anchors.fill: parent
                                    }
                                    DankIcon {
                                        visible: (modelData.iconPath || "") === ""
                                        name: modelData.icon || "apps"
                                        size: Theme.iconSize
                                        color: Theme.primary
                                        anchors.centerIn: parent
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    width: parent.width - Theme.iconSize - Theme.spacingS * 2

                                    StyledText {
                                        text: modelData.name || "Unnamed"
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
                            }

                            Row {
                                id: appBtns
                                anchors {
                                    right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    rightMargin: Theme.spacingS
                                }
                                spacing: 0

                                Item {
                                    width: Theme.iconSize + Theme.spacingS
                                    height: Theme.iconSize
                                    visible: modelData.source !== "picker"

                                    DankIcon {
                                        name: "edit"
                                        size: Theme.iconSize
                                        color: editMouse.containsMouse ? Theme.primary : Theme.surfaceVariantText
                                        anchors.centerIn: parent
                                    }
                                    MouseArea {
                                        id: editMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.editingAppName = modelData.name || ""
                                            root.editingAppExec = modelData.exec || ""
                                            root.editingAppIcon = modelData.icon || "apps"
                                            root.editingAppIconPath = modelData.iconPath || ""
                                            root._manualIconPath = modelData.iconPath || ""
                                            root.showManualForm = true
                                        }
                                    }
                                }

                                Item {
                                    width: Theme.iconSize + Theme.spacingS
                                    height: Theme.iconSize

                                    DankIcon {
                                        name: "close"
                                        size: Theme.iconSize
                                        color: removeMouseArea.containsMouse ? Theme.error : Theme.surfaceVariantText
                                        anchors.centerIn: parent
                                    }
                                    MouseArea {
                                        id: removeMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.removeApp(index)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Capacity warning ──────────────────────────────────────────
            StyledRect {
                width: parent.width
                height: warningText.implicitHeight + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: Theme.withAlpha ? Theme.withAlpha(Theme.tertiary || Theme.primary, 0.12) : Theme.surfaceContainerHigh
                visible: root.selectedGroup && (root.selectedGroup.apps || []).length >= 10

                StyledText {
                    id: warningText
                    anchors {
                        left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                    }
                    text: "You have 10 apps in this group. Consider creating another group for additional apps."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.tertiary || Theme.primary
                    wrapMode: Text.WordWrap
                }
            }

            // ── App picker (inline) ───────────────────────────────────────
            Column {
                width: parent.width
                spacing: Theme.spacingS
                visible: root.pickerVisible

                StyledText {
                    visible: root.pickerLoading
                    text: "Scanning installed applications…"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledRect {
                    visible: root.pickerFailed && !root.pickerLoading
                    width: parent.width
                    height: pickerErrText.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha ? Theme.withAlpha(Theme.error || Theme.primary, 0.12) : Theme.surfaceContainerHigh

                    StyledText {
                        id: pickerErrText
                        anchors {
                            left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        text: "Could not scan installed apps. Python 3 is required for this feature.\n" +
                              "Install:  sudo pacman -S python  (Arch)  |  sudo dnf install python3  (Fedora)  |  sudo apt install python3  (Debian/Ubuntu)\n\n" +
                              "You can still add apps manually using the Name / Icon / Command fields above."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.error || Theme.surfaceText
                        wrapMode: Text.WordWrap
                    }
                }

                TextField {
                    id: pickerSearch
                    width: parent.width
                    placeholderText: "Search apps..."
                    color: Theme.surfaceText
                    placeholderTextColor: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    visible: !root.pickerLoading && systemAppsModel.count > 0
                    onTextChanged: root.pickerFilter = text
                }

                ListView {
                    width: parent.width
                    height: 300
                    model: filteredApps
                    clip: true
                    visible: !root.pickerLoading && systemAppsModel.count > 0

                    delegate: StyledRect {
                        width: parent.width
                        height: 50
                        radius: Theme.cornerRadius
                        color: pickerItemMouse.containsMouse
                               ? (Theme.surfaceContainerHighest || Theme.surfaceContainerHigh)
                               : Theme.surfaceContainerHigh

                        MouseArea {
                            id: pickerItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.addApp({
                                    name: name, icon: icon,
                                    iconPath: iconPath, exec: exec,
                                    source: "picker"
                                })
                                root.pickerVisible = false
                                pickerSearch.text = ""
                            }
                        }

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingS
                            }
                            spacing: Theme.spacingS

                            Item {
                                width: Theme.iconSize
                                height: Theme.iconSize
                                anchors.verticalCenter: parent.verticalCenter

                                Image {
                                    visible: (iconPath || "") !== ""
                                    source: (iconPath || "") !== "" ? ("file://" + iconPath) : ""
                                    width: Theme.iconSize; height: Theme.iconSize
                                    fillMode: Image.PreserveAspectFit; smooth: true
                                    anchors.fill: parent
                                }
                                DankIcon {
                                    visible: (iconPath || "") === ""
                                    name: icon || "apps"
                                    size: Theme.iconSize
                                    color: Theme.primary
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
        }
    }

    // ── Helper: commit manual add ─────────────────────────────────────────
    function commitEditManualAdd() {
        var n = manualNameInput.text.trim()
        var e = manualExecInput.text.trim()
        if (!n || !e) {
            ToastService.showInfo("Incomplete", "Name and Command are required")
            return
        }
        root.addApp({
            name: n,
            icon: root.editingAppIcon.trim() || "apps",
            iconPath: root._manualIconPath,
            exec: e,
            source: "manual"
        })
        root.editingAppName = ""
        root.editingAppIcon = ""
        root.editingAppExec = ""
        root._manualIconPath = ""
        root.appIconPickerVisible = false
        manualNameInput.text = ""
        manualIconInput.text = ""
        manualExecInput.text = ""
        manualNameInput.forceActiveFocus()
    }
}
