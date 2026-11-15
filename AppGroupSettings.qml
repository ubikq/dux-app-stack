import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// AppGroupSettings — Unified multi-group settings for App Stack plugin.
//
// Data shape: pluginData.groups is a JSON array of group objects:
// [
//   { "id": "group_0", "name": "Dev", "icon": "code", "showLabel": true,
//     "apps": [{ "name": "...", "icon": "...", "iconPath": "...", "exec": "...", "source": "..." }] },
//   ...
// ]
//
// Each group is managed independently via the group list on the left and
// app list on the right. No hardcoded pluginId — uses auto-injected value.

PluginSettings {
    id: root
    // pluginId is auto-injected by Dux Shell — do NOT hardcode

    // ── Persistent storage ────────────────────────────────────────────────
    // Groups array stored as JSON string in pluginData
    StringSetting {
        id: groupsDataStore
        settingKey: "groups"
        label: "groups"
        visible: false
    }

    // ── State ─────────────────────────────────────────────────────────────
    property var groupsArray: {
        try {
            var arr = JSON.parse(groupsDataStore.value || "[]")
            if (Array.isArray(arr)) return arr
        } catch(e) {}
        return []
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
        "attach_file", "person", "account_circle", "group", "contacts",
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
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
    readonly property string listAppsScript: Qt.resolvedUrl("./scripts/list-apps.py").toString().replace(/^file:\/\//, "")

    // ── Computed ──────────────────────────────────────────────────────────
    readonly property var selectedGroup:
        (selectedGroupIndex >= 0 && selectedGroupIndex < groupsArray.length)
            ? groupsArray[selectedGroupIndex] : null

    // ── Functions ─────────────────────────────────────────────────────────

    function saveGroups() {
        var json = JSON.stringify(groupsArray)
        groupsDataStore.value = json
        root.saveValue("groups", json)
    }

    function addGroup() {
        var idx = groupsArray.length
        var newGroup = {
            id: "group_" + idx,
            name: "Group " + (idx + 1),
            icon: "apps",
            showLabel: false,
            apps: []
        }
        var newGroups = groupsArray.slice()
        newGroups.push(newGroup)
        groupsArray = newGroups
        saveGroups()
        selectedGroupIndex = idx
    }

    function removeGroup(idx) {
        var newGroups = groupsArray.filter(function(_, i) { return i !== idx })
        groupsArray = newGroups
        saveGroups()
        if (selectedGroupIndex >= groupsArray.length)
            selectedGroupIndex = groupsArray.length > 0 ? groupsArray.length - 1 : -1
    }

    function updateGroupField(field, value) {
        if (selectedGroupIndex < 0) return
        var newGroups = groupsArray.slice()
        newGroups[selectedGroupIndex] = Object.assign({}, newGroups[selectedGroupIndex])
        newGroups[selectedGroupIndex][field] = value
        groupsArray = newGroups
        saveGroups()
    }

    function saveGroupApps(apps) {
        if (selectedGroupIndex < 0) return
        var newGroups = groupsArray.slice()
        newGroups[selectedGroupIndex] = Object.assign({}, newGroups[selectedGroupIndex], { apps: apps })
        groupsArray = newGroups
        saveGroups()
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

    // ── Layout ────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: Theme.spacingM

        // ══════════════════════════════════════════════════════════════════
        // ── Group Management Header ───────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                text: "Groups"
                font.pixelSize: Theme.fontSizeLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
            }

            Spacer { layout: Row.Spacer }

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
            radius: Theme.cornerRadius

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
                                   ? Theme.primaryContainer || Theme.surfaceContainerHighest
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
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeGroup(index)
                                    DankIcon {
                                        name: "delete"
                                        size: Theme.iconSize
                                        color: mouse.containsMouse ? Theme.error : Theme.surfaceVariantText
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

        visible: root.selectedGroup !== null
        width: parent.width
        spacing: Theme.spacingS

        // ── Group name ────────────────────────────────────────────────────
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
                    text: root.selectedGroup.name || ""
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    onTextChanged: root.updateGroupField("name", text)
                    Text {
                        visible: groupNameInput.text === ""
                        text: "Group name"
                        color: Theme.surfaceVariantText
                        font: groupNameInput.font
                    }
                }
            }
        }

        // ── Group icon ────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4

            StyledText {
                text: "Group Icon (Material icon name)"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankIcon {
                    name: groupIconInput.text || (root.selectedGroup.icon || "apps")
                    size: Theme.iconSize
                    color: Theme.primary
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledRect {
                    height: groupIconInput.implicitHeight + Theme.spacingM * 2
                    width: parent.width - Theme.iconSize - groupIconBrowseBtn.width
                           - Theme.spacingS * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: groupIconInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        text: root.selectedGroup.icon || "apps"
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onTextChanged: root.updateGroupField("icon", text)
                        Text {
                            visible: groupIconInput.text === ""
                            text: "apps"
                            color: Theme.surfaceVariantText
                            font: groupIconInput.font
                        }
                    }
                }

                StyledRect {
                    id: groupIconBrowseBtn
                    height: groupIconInput.implicitHeight + Theme.spacingM * 2
                    width: groupIconBrowseLabel.implicitWidth + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: (groupIconBrowseMouse.containsMouse || root.iconPickerVisible)
                           ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: groupIconBrowseLabel
                        anchors.centerIn: parent
                        text: "Browse"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.primary
                    }
                    MouseArea {
                        id: groupIconBrowseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.iconPickerVisible = !root.iconPickerVisible
                            iconPickerSearchInput.text = ""
                            root.iconPickerFilter = ""
                        }
                    }
                }
            }

            // ── Inline icon grid ────────────────────────────────────────
            visible: root.iconPickerVisible
            Column {
                width: parent.width
                spacing: Theme.spacingXS

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
                                       ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2

                                    DankIcon {
                                        name: modelData
                                        size: Theme.iconSize
                                        color: groupIconInput.text === modelData
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
                                        groupIconInput.text = modelData
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

        // ── Show label toggle ─────────────────────────────────────────────
        ToggleSetting {
            settingKey: "group_showLabel_" + (selectedGroupIndex + 1)
            label: "Show label in bar"
            description: "Display the group name next to the icon in DankBar"
            defaultValue: root.selectedGroup.showLabel || false
            onValueChanged: root.updateGroupField("showLabel", value)
        }

        // ══════════════════════════════════════════════════════════════════
        // ── App Management ────────────────────────────────────────────────
        // ══════════════════════════════════════════════════════════════════

        Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.3 }

        StyledText {
            width: parent.width
            text: "Apps (" + (root.selectedGroup ? (root.selectedGroup.apps || []).length : 0) + "/10)"
            font.pixelSize: Theme.fontSizeLarge
            font.weight: Font.Bold
            color: Theme.surfaceText
        }

        // ── Action buttons ────────────────────────────────────────────────
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
                    color: (pickerMouse.containsMouse || root.pickerVisible)
                           ? Theme.onSecondaryContainer || Theme.surfaceText : Theme.surfaceText
                }
                MouseArea {
                    id: pickerMouse
                    anchors.fill: parent
                    hoverEnabled: true
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
                    color: (addManuallyMouse.containsMouse || root.showManualForm)
                           ? Theme.onPrimary || Theme.surface : Theme.primary
                }
                MouseArea {
                    id: addManuallyMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.showManualForm = !root.showManualForm
                        if (!root.showManualForm) {
                            root.editingAppName = ""
                            root.editingAppIcon = ""
                            root.editingAppExec = ""
                            root._manualIconPath = ""
                            root.appIconPickerVisible = false
                            root.appIconPickerFilter = ""
                        }
                    }
                }
            }
        }

        // ── Manual entry form ─────────────────────────────────────────────
        visible: root.showManualForm
        Column {
            width: parent.width
            spacing: Theme.spacingXS

            // Name field
            Column {
                width: parent.width
                spacing: 4

                StyledText {
                    text: "Name"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                StyledRect {
                    width: parent.width
                    height: manualNameInput.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: manualNameInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        text: root.editingAppName
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onAccepted: if (manualExecInput.text.trim()) root.commitEditManualAdd()
                        onTextChanged: {
                            root.editingAppName = text
                            if (root.editingAppIcon === "") Qt.callLater(root.tryAutoDetectIcon)
                        }
                        Text {
                            visible: manualNameInput.text === ""
                            text: "App name (e.g. Firefox)"
                            color: Theme.surfaceVariantText
                            font: manualNameInput.font
                        }
                    }
                }
            }

            // Icon field
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

                    Item {
                        width: Theme.iconSize; height: Theme.iconSize
                        anchors.verticalCenter: parent.verticalCenter

                        Image {
                            visible: root._manualIconPath !== ""
                            source: root._manualIconPath !== "" ? ("file://" + root._manualIconPath) : ""
                            width: Theme.iconSize; height: Theme.iconSize
                            fillMode: Image.PreserveAspectFit; smooth: true
                            anchors.fill: parent
                        }
                        DankIcon {
                            visible: root._manualIconPath === ""
                            name: root.editingAppIcon || "apps"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    StyledRect {
                        height: manualIconInput.implicitHeight + Theme.spacingM * 2
                        width: parent.width - Theme.iconSize - chooseIconBtn.width
                               - Theme.spacingS * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius

                        TextInput {
                            id: manualIconInput
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                            }
                            text: root.editingAppIcon
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            clip: true
                            onTextChanged: {
                                root.editingAppIcon = text
                                if (!root._iconSetByCode) root._manualIconPath = ""
                            }
                            Text {
                                visible: manualIconInput.text === ""
                                text: "auto-detect from name/command"
                                color: Theme.surfaceVariantText
                                font: manualIconInput.font
                            }
                        }
                    }

                    StyledRect {
                        id: chooseIconBtn
                        height: chooseIconBtnLabel.implicitHeight + Theme.spacingS * 2
                        width: chooseIconBtnLabel.implicitWidth + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: (chooseIconMouse.containsMouse || root.appIconPickerVisible)
                               ? Theme.primaryContainer || Theme.surfaceContainerHighest
                               : Theme.surfaceContainerHigh
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            id: chooseIconBtnLabel
                            anchors.centerIn: parent
                            text: "Choose"
                            font.pixelSize: Theme.fontSizeMedium
                            color: (chooseIconMouse.containsMouse || root.appIconPickerVisible)
                                   ? Theme.onPrimary || Theme.surface : Theme.primary
                        }
                        MouseArea {
                            id: chooseIconMouse
                            anchors.fill: parent
                            hoverEnabled: true
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

                // ── App icon picker ───────────────────────────────────────
                Column {
                    visible: root.appIconPickerVisible
                    width: parent.width
                    spacing: Theme.spacingXS

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
                            onTextChanged: root.appIconPickerFilter = text
                            Text {
                                visible: appIconPickerSearch.text === ""
                                text: "Search apps or icons…"
                                color: Theme.surfaceVariantText
                                font: appIconPickerSearch.font
                            }
                        }
                    }

                    // Matched app icons
                    Column {
                        visible: appIconMatches.count > 0
                        width: parent.width
                        spacing: 2

                        StyledText {
                            text: root.appIconPickerFilter === "" ? "Matched apps" : "App results"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: appIconMatches
                            delegate: Item {
                                width: parent.width
                                height: Theme.iconSize + Theme.spacingXS * 2

                                StyledRect {
                                    anchors { left: parent.left; right: parent.right
                                              top: parent.top; bottom: parent.bottom; margins: 1 }
                                    radius: Theme.cornerRadius
                                    color: appMatchMouse.containsMouse
                                           ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    Row {
                                        anchors {
                                            left: parent.left; right: parent.right
                                            verticalCenter: parent.verticalCenter
                                            leftMargin: Theme.spacingS; rightMargin: Theme.spacingS
                                        }
                                        spacing: Theme.spacingS

                                        Item {
                                            width: Theme.iconSize; height: Theme.iconSize

                                            Image {
                                                visible: iconPath !== ""
                                                source: iconPath !== "" ? ("file://" + iconPath) : ""
                                                width: Theme.iconSize; height: Theme.iconSize
                                                fillMode: Image.PreserveAspectFit; smooth: true
                                                anchors.fill: parent
                                            }
                                            DankIcon {
                                                visible: iconPath === ""
                                                name: icon || "apps"
                                                size: Theme.iconSize
                                                color: Theme.primary
                                                anchors.centerIn: parent
                                            }
                                        }

                                        Item {
                                            width: parent.width - Theme.iconSize - Theme.spacingS
                                            height: Theme.iconSize

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
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root._iconSetByCode = true
                                            root.editingAppIcon = icon || "apps"
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
                    StyledText {
                        text: "Material icons"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
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
                                           ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        DankIcon {
                                            name: modelData
                                            size: Theme.iconSize
                                            color: (root.editingAppIcon === modelData && root._manualIconPath === "")
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
                                        id: appIconCellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root._iconSetByCode = true
                                            root.editingAppIcon = modelData
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

            // Command field
            Column {
                width: parent.width
                spacing: 4

                StyledText {
                    text: "Command"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
                StyledRect {
                    width: parent.width
                    height: manualExecInput.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: manualExecInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        text: root.editingAppExec
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onAccepted: if (manualNameInput.text.trim()) root.commitEditManualAdd()
                        onTextChanged: {
                            root.editingAppExec = text
                            if (root.editingAppIcon === "") Qt.callLater(root.tryAutoDetectIcon)
                        }
                        Text {
                            visible: manualExecInput.text === ""
                            text: "Shell command (e.g. firefox)"
                            color: Theme.surfaceVariantText
                            font: manualExecInput.font
                        }
                    }
                }
            }

            // Add button
            StyledRect {
                height: addAppLabel.implicitHeight + Theme.spacingS * 2
                width: addAppLabel.implicitWidth + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: addAppMouse.containsMouse
                       ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                StyledText {
                    id: addAppLabel
                    anchors.centerIn: parent
                    text: "Add App"
                    font.pixelSize: Theme.fontSizeMedium
                    color: addAppMouse.containsMouse ? Theme.onPrimary || Theme.surface : Theme.primary
                }
                MouseArea {
                    id: addAppMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.commitEditManualAdd()
                }
            }
        }

        // ── App list ──────────────────────────────────────────────────────
        visible: root.selectedGroup && (root.selectedGroup.apps || []).length > 0
        Column {
            width: parent.width
            spacing: 2

            Repeater {
                model: root.selectedGroup ? (root.selectedGroup.apps || []) : []

                delegate: Item {
                    width: parent.width
                    height: Theme.iconSize + Theme.spacingS * 2
                    property bool isEditing: root.editingAppName !== "" && root.editingAppExec !== ""

                    // Display row
                    Item {
                        id: displayRow
                        anchors {
                            left: parent.left; right: parent.right
                            top: parent.top; topMargin: Theme.spacingS
                        }
                        height: Theme.iconSize
                        visible: !isEditing

                        // App icon
                        Item {
                            id: iconItem
                            width: Theme.iconSize
                            height: Theme.iconSize
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

                        // Name + exec
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

                        // Edit + remove buttons
                        Row {
                            id: displayBtns
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
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
                                    color: removeMouse.containsMouse ? Theme.error : Theme.surfaceVariantText
                                    anchors.centerIn: parent
                                }
                                MouseArea {
                                    id: removeMouse
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

        // ── Capacity warning ──────────────────────────────────────────────
        visible: root.selectedGroup && (root.selectedGroup.apps || []).length >= 10
        StyledRect {
            width: parent.width
            height: warningText.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha ? Theme.withAlpha(Theme.tertiary || Theme.primary, 0.12) : Theme.surfaceContainerHigh

            StyledText {
                id: warningText
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                          leftMargin: Theme.spacingM; rightMargin: Theme.spacingM }
                text: "You have 10 apps in this group. Consider creating another group for additional apps."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.tertiary || Theme.primary
                wrapMode: Text.WordWrap
            }
        }

        // ── App picker ────────────────────────────────────────────────────
        visible: root.pickerVisible
        Column {
            width: parent.width
            spacing: Theme.spacingXS
            topPadding: Theme.spacingXS

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
                        left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                    }
                    text: "Could not scan installed apps. Python 3 is required for this feature.\n" +
                          "Install:  sudo pacman -S python  (Arch)  |  sudo dnf install python3  (Fedora)  |  sudo apt install python3  (Debian/Ubuntu)\n\n" +
                          "You can still add apps manually using the Name / Icon / Command fields above."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.error || Theme.surfaceText
                    wrapMode: Text.WordWrap
                }
            }

            StyledRect {
                visible: !root.pickerLoading && systemAppsModel.count > 0
                width: parent.width
                height: pickerSearch.implicitHeight + Theme.spacingM * 2
                color: Theme.surfaceContainerHigh
                radius: Theme.cornerRadius

                TextInput {
                    id: pickerSearch
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                    }
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    onTextChanged: root.pickerFilter = text
                    Text {
                        visible: pickerSearch.text === ""
                        text: "Search apps…"
                        color: Theme.surfaceVariantText
                        font: pickerSearch.font
                    }
                }
            }

            StyledRect {
                visible: !root.pickerLoading && filteredApps.count > 0
                width: parent.width
                height: Math.min(pickerListView.contentHeight, 280)
                clip: true
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerLow || Theme.surfaceContainerHigh

                ListView {
                    id: pickerListView
                    anchors.fill: parent
                    model: filteredApps
                    clip: true
                    spacing: 1

                    delegate: Item {
                        width: pickerListView.width
                        height: pickerItemRow.implicitHeight + Theme.spacingXS * 2

                        StyledRect {
                            anchors.fill: parent
                            color: pickerItemMouse.containsMouse
                                   ? Theme.surfaceContainerHighest : "transparent"
                            radius: 0
                        }

                        Row {
                            id: pickerItemRow
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingS; rightMargin: Theme.spacingS
                            }
                            spacing: Theme.spacingS

                            Item {
                                width: Theme.iconSize
                                height: Theme.iconSize
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
                                    name: "apps"
                                    size: Theme.iconSize
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
                                root.addApp({
                                    name: name, icon: icon,
                                    iconPath: iconPath, exec: exec,
                                    source: "picker"
                                })
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
