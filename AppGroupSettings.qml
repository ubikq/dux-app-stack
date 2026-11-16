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
    property var groupsArray: root.variants

    // One-time migration: legacy `groups` JSON array → variants.
    // Also restore the last-edited group so reopening the page is less confusing.
    Component.onCompleted: {
        Qt.callLater(root.migrateLegacyGroups)
        var saved = root.loadState("selectedGroupIndex", -1)
        if (saved >= 0 && saved < root.groupsArray.length)
            root.selectedGroupIndex = saved
    }

    onSelectedGroupIndexChanged: {
        if (selectedGroupIndex >= 0)
            root.saveState("selectedGroupIndex", selectedGroupIndex)
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
    readonly property var selectedGroup:
        (selectedGroupIndex >= 0 && selectedGroupIndex < groupsArray.length)
            ? groupsArray[selectedGroupIndex] : null

        // ── Functions ─────────────────────────────────────────────────────────
    
        // No-op: variants persist themselves via the PluginSettings API.
        function saveGroups() {}
    
        function addGroup() {
            var idx = groupsArray.length
            var variantId = root.createVariant("Group " + (idx + 1), {
                icon: "apps",
                showLabel: false,
                apps: []
            })
            selectedGroupIndex = idx
            return variantId
        }
    
        function removeGroup(idx) {
            if (idx < 0 || idx >= groupsArray.length) return
            root.removeVariant(groupsArray[idx].id)
            if (selectedGroupIndex >= groupsArray.length)
                selectedGroupIndex = groupsArray.length > 0 ? groupsArray.length - 1 : -1
        }
    
        function updateGroupField(field, value) {
            if (selectedGroupIndex < 0 || !selectedGroup) return
            var patch = {}
            patch[field] = value
            root.updateVariant(selectedGroup.id, patch)
        }
    
        function saveGroupApps(apps) {
            if (selectedGroupIndex < 0 || !selectedGroup) return
            root.updateVariant(selectedGroup.id, { apps: apps })
        }

    function addApp(appData) {
        if (!selectedGroup) return
        var apps = selectedGroup.apps || []
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
        if (!selectedGroup) return
        var apps = selectedGroup.apps.filter(function(_, i) { return i !== idx })
        saveGroupApps(apps)
    }

    function updateApp(idx, updates) {
        if (!selectedGroup) return
        var apps = selectedGroup.apps.slice()
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
            root.pickerLoading = true
            root.pickerFailed = false
            if (systemAppsModel.count === 0)
                appScanner.running = true
            else
                root.filterSystemApps()
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
        ScrollView {
            width: parent.width
            height: Math.min(groupsArray.length * 44 + 10, 200)
            clip: true

            Column {
                width: parent.width
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

                        Row {
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingS; rightMargin: Theme.spacingS
                            }
                            spacing: Theme.spacingS

                            DankIcon {
                                name: modelData.icon || "apps"
                                size: Theme.iconSize
                                color: Theme.primary
                            }

                            StyledText {
                                text: modelData.name || "Unnamed"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width - Theme.iconSize * 2 - Theme.spacingS
                            }

                            Item {
                                width: Theme.iconSize
                                height: Theme.iconSize

                                MouseArea {
                                    id: groupDeleteMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeGroup(index)
                                    DankIcon {
                                        name: "delete"
                                        size: Theme.iconSize
                                        color: groupDeleteMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                                        anchors.centerIn: parent
                                    }
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.selectedGroupIndex = index
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

        // ══════════════════════════════════════════════════════════════════
        // ── Selected Group Settings ───────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════
        Column {
            width: parent.width
            spacing: Theme.spacingS
            visible: root.selectedGroup !== null

            // ── Editing header ────────────────────────────────────────────
            StyledText {
                text: "Editing: " + (root.selectedGroup ? (root.selectedGroup.name || "Unnamed") : "")
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.primary
                elide: Text.ElideRight
                width: parent.width
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
                        font.pixelSize: Theme.fontSizeMedium
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
            width: parent.width
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
                    color: browseBtnMouse.containsMouse
                           ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                           : Theme.surfaceContainerHigh

                    StyledText {
                        id: browseBtnLabel
                        anchors.centerIn: parent
                        text: root.pickerVisible ? "Hide App Picker" : "Choose from Installed Apps"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.primary
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
                    color: addAppBtnMouse.containsMouse
                           ? (Theme.primaryContainer || Theme.surfaceContainerHighest)
                           : Theme.surfaceContainerHigh

                    StyledText {
                        id: addAppBtnLabel
                        anchors.centerIn: parent
                        text: "+ Add App"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.primary
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
                        font.pixelSize: Theme.fontSizeMedium
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
                        font.pixelSize: Theme.fontSizeMedium
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
                            font.pixelSize: Theme.fontSizeMedium
                            text: root.editingAppIcon
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
                        color: Theme.primaryText
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
                width: parent.width
                height: Math.min((root.selectedGroup ? (root.selectedGroup.apps || []).length : 0) * 60 + 10, 300)
                clip: true
                visible: root.selectedGroup && (root.selectedGroup.apps || []).length > 0

                Column {
                    width: parent.width
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

                                    StyledText {
                                        text: modelData.name || "Unnamed"
                                        font.pixelSize: Theme.fontSizeMedium
                                        color: Theme.surfaceText
                                        elide: Text.ElideRight
                                        width: parent.width - Theme.spacingS
                                    }

                                    StyledText {
                                        visible: modelData.source !== "picker"
                                        text: modelData.exec || ""
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                        elide: Text.ElideRight
                                        width: parent.width - Theme.spacingS
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
