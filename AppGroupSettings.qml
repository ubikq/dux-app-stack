import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modules.Plugins
import qs.Services
import qs.Widgets

// pluginId must match the "id" field in plugin.json.
// When copying this plugin for a second group, update BOTH files.
PluginSettings {
    id: root
    pluginId: "appStack_default"

    // ── Persistent storage ────────────────────────────────────────────────
    // ── Standard group settings ───────────────────────────────────────────
    StringSetting {
        settingKey: "groupName"
        label: "Group Label"
        description: "Name shown in the popout header"
        placeholder: "App Stack"
        defaultValue: "App Stack"
    }

    // Registers the appsData key with DMS so pluginData.appsData is populated
    // when the settings panel opens. No defaultValue — omitting it prevents
    // DMS from batch-writing a fixed default on panel creation, which would
    // overwrite the list saved by saveValue.
    StringSetting {
        id: appsDataStore
        settingKey: "appsData"
        label: "appsData"
        visible: false
    }

    Column {
        width: parent.width
        spacing: Theme.spacingXS

        StyledText {
            text: "Bar Icon"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
        }
        StyledText {
            text: "Material icon shown in the bar — type a name or click Browse"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
            width: parent.width
        }

        Row {
            width: parent.width
            spacing: Theme.spacingS

            DankIcon {
                name: iconNameInput.text || "apps"
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledRect {
                height: iconNameInput.implicitHeight + Theme.spacingM * 2
                width: parent.width - Theme.iconSize - Theme.spacingS
                       - iconBrowseBtn.width - Theme.spacingS
                color: Theme.surfaceContainerHigh
                radius: Theme.cornerRadius

                TextInput {
                    id: iconNameInput
                    property bool _initialized: false
                    anchors {
                        left: parent.left; right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                    }
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    onTextChanged: if (_initialized) root.saveValue("groupIcon", text)
                    Text {
                        visible: iconNameInput.text === ""
                        text: "apps"
                        color: Theme.surfaceVariantText
                        font: iconNameInput.font
                    }
                }
            }

            StyledRect {
                id: iconBrowseBtn
                height: iconNameInput.implicitHeight + Theme.spacingM * 2
                width: iconBrowseLabel.implicitWidth + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: (iconBrowseMouse.containsMouse || root.iconPickerVisible)
                       ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                StyledText {
                    id: iconBrowseLabel
                    anchors.centerIn: parent
                    text: "Browse"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.primary
                }
                MouseArea {
                    id: iconBrowseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.iconPickerVisible = !root.iconPickerVisible
                        root.iconPickerFilter = ""
                        iconPickerSearchInput.text = ""
                    }
                }
            }
        }

        // ── Inline icon grid ──────────────────────────────────────────
        Column {
            visible: root.iconPickerVisible
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
                        width: 68
                        height: 68

                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Theme.cornerRadius
                            color: iconCellMouse.containsMouse
                                   ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                            Column {
                                anchors.centerIn: parent
                                spacing: 2

                                DankIcon {
                                    name: modelData
                                    size: Theme.iconSize
                                    color: iconNameInput.text === modelData
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
                                    iconNameInput.text = modelData
                                    root.saveValue("groupIcon", modelData)
                                    root.iconPickerVisible = false
                                    root.iconPickerFilter = ""
                                    iconPickerSearchInput.text = ""
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    ToggleSetting {
        settingKey: "showLabel"
        label: "Show label in bar"
        description: "Display the group name next to the icon in DankBar"
        defaultValue: false
    }

    // ── In-memory state ───────────────────────────────────────────────────

    property var appsArray: {
        try {
            var arr = JSON.parse(appsDataStore.value || "[]")
            if (Array.isArray(arr)) return arr
        } catch(e) {}
        return []
    }

    ListModel { id: systemAppsModel }
    ListModel { id: filteredApps }
    ListModel { id: appIconMatches }

    property bool pickerVisible: false
    property bool pickerLoading: false
    property bool pickerFailed: false
    property string pickerFilter: ""
    property bool confirmCreateVisible: false
    property bool createFormVisible: false
    property int editingIndex: -1
    property string _manualIconPath: ""
    property bool _iconSetByCode: false
    property bool appIconPickerVisible: false
    property string appIconPickerFilter: ""

    readonly property string _newGroupId:
        "appStack_" + groupSuffixInput.text.trim().replace(/\s+/g, "_")
    readonly property string _newGroupName:
        "App Stack - " + groupSuffixInput.text.trim()
    property bool iconPickerVisible: false
    property string iconPickerFilter: ""
    property bool showManualForm: false

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

    // Resolved paths (strips file:// prefix from Qt URL)
    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
    readonly property string listAppsScript: Qt.resolvedUrl("./scripts/list-apps.py").toString().replace(/^file:\/\//, "")
    readonly property string createGroupScript: Qt.resolvedUrl("./scripts/create-group.sh").toString().replace(/^file:\/\//, "")

    // ── Functions ─────────────────────────────────────────────────────────

    function addApp(appData) {
        for (var i = 0; i < root.appsArray.length; i++) {
            if (root.appsArray[i].exec === appData.exec) {
                ToastService.showInfo("Already added", appData.name + " is already in this group")
                return
            }
        }
        var newList = root.appsArray.slice()
        newList.push({ name: appData.name, icon: appData.icon || "apps",
                       iconPath: appData.iconPath || "", exec: appData.exec,
                       source: appData.source || "manual" })
        root.persistApps(newList)
    }

    function persistApps(list) {
        var json = JSON.stringify(list)
        appsDataStore.value = json
        root.saveValue("appsData", json)
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
            // Penalise PWA wrappers and multi-flag entries
            if (appExec.includes("--app-id=")) score -= 8
            if (appExec.includes("--profile-directory=")) score -= 3
            // Prefer shorter exec (real apps are simpler)
            score -= appExec.length / 200
            // Bonus if name contains the exec base
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
                // Exclude PWA wrappers from the default "matched apps" view
                hit = (execMatch || nameMatch) && !appExec.includes("--app-id=")
            } else {
                hit = app.name.toLowerCase().includes(f) || appExecBase.includes(f)
            }
            if (hit) appIconMatches.append(app)
        }
    }

    // ── Initialise from saved settings ────────────────────────────────────
    function reloadIconInput() {
        iconNameInput._initialized = false
        iconNameInput.text = root.loadValue("groupIcon", "apps")
        iconNameInput._initialized = true
    }

    Component.onCompleted: {
        Qt.callLater(reloadIconInput)
    }

    onPluginServiceChanged: {
        if (pluginService) Qt.callLater(reloadIconInput)
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

    // ═══════════════════════════════════════════════════════════════════════
    // ── Apps section ──────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════════════════

    Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.3 }

    StyledText {
        width: parent.width
        text: "Apps"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingS
    }

    // ── Existing app list ─────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 2
        visible: root.appsArray.length > 0

        Repeater {
            model: root.appsArray

            delegate: Item {
                id: delegateRoot
                width: parent.width
                property bool isEditing: root.editingIndex === index
                height: isEditing ? editForm.implicitHeight + Theme.spacingS * 2
                                  : Theme.iconSize + Theme.spacingS * 2

                // ── Display row ───────────────────────────────────────────
                Item {
                    id: displayRow
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top; topMargin: Theme.spacingS
                    }
                    height: Theme.iconSize
                    visible: !delegateRoot.isEditing

                    // App icon (file or material)
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

                    // Name + exec (exec hidden for picker apps)
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

                    // Pencil + remove buttons
                    Row {
                        id: displayBtns
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        spacing: 0

                        // Pencil (edit) — manual/legacy apps only
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
                                onClicked: root.editingIndex = index
                            }
                        }

                        // Remove
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
                                onClicked: {
                                    var idx = index
                                    var newList = root.appsArray.filter(function(_, i) { return i !== idx })
                                    root.persistApps(newList)
                                }
                            }
                        }
                    }
                }

                // ── Edit form (manual apps only) ──────────────────────────
                Column {
                    id: editForm
                    anchors {
                        left: parent.left; right: parent.right
                        top: parent.top; topMargin: Theme.spacingS
                    }
                    spacing: Theme.spacingXS
                    visible: delegateRoot.isEditing

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
                                text: modelData.name || ""
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                Text {
                                    visible: editNameInput.text === ""
                                    text: "App name"
                                    color: Theme.surfaceVariantText
                                    font: editNameInput.font
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 4

                        StyledText {
                            text: "Icon (material icon name)"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledRect {
                            width: parent.width
                            height: editIconInput.implicitHeight + Theme.spacingM * 2
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius

                            TextInput {
                                id: editIconInput
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                }
                                text: modelData.icon || ""
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                Text {
                                    visible: editIconInput.text === ""
                                    text: "e.g. apps"
                                    color: Theme.surfaceVariantText
                                    font: editIconInput.font
                                }
                            }
                        }
                    }

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
                            height: editExecInput.implicitHeight + Theme.spacingM * 2
                            color: Theme.surfaceContainerHigh
                            radius: Theme.cornerRadius

                            TextInput {
                                id: editExecInput
                                anchors {
                                    left: parent.left; right: parent.right
                                    verticalCenter: parent.verticalCenter
                                    leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                                }
                                text: modelData.exec || ""
                                color: Theme.surfaceText
                                font.pixelSize: Theme.fontSizeMedium
                                clip: true
                                Text {
                                    visible: editExecInput.text === ""
                                    text: "Shell command"
                                    color: Theme.surfaceVariantText
                                    font: editExecInput.font
                                }
                            }
                        }
                    }

                    Row {
                        spacing: Theme.spacingS

                        StyledRect {
                            height: saveEditLabel.implicitHeight + Theme.spacingS * 2
                            width: saveEditLabel.implicitWidth + Theme.spacingL * 2
                            radius: Theme.cornerRadius
                            color: saveEditMouse.containsMouse ? Theme.primary
                                   : Theme.surfaceContainerHighest || Theme.surfaceContainerHigh

                            StyledText {
                                id: saveEditLabel
                                anchors.centerIn: parent
                                text: "Save"
                                font.pixelSize: Theme.fontSizeMedium
                                color: saveEditMouse.containsMouse
                                       ? Theme.onPrimary || Theme.surface : Theme.primary
                            }
                            MouseArea {
                                id: saveEditMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var n = editNameInput.text.trim()
                                    var e = editExecInput.text.trim()
                                    if (!n || !e) {
                                        ToastService.showInfo("Incomplete",
                                            "Name and Command are required")
                                        return
                                    }
                                    var newList = root.appsArray.slice()
                                    newList[index] = {
                                        name: n,
                                        icon: editIconInput.text.trim() || "apps",
                                        iconPath: modelData.iconPath,
                                        exec: e,
                                        source: "manual"
                                    }
                                    root.persistApps(newList)
                                    root.editingIndex = -1
                                }
                            }
                        }

                        StyledRect {
                            height: cancelEditLabel.implicitHeight + Theme.spacingS * 2
                            width: cancelEditLabel.implicitWidth + Theme.spacingL * 2
                            radius: Theme.cornerRadius
                            color: Theme.surfaceContainerHigh

                            StyledText {
                                id: cancelEditLabel
                                anchors.centerIn: parent
                                text: "Cancel"
                                font.pixelSize: Theme.fontSizeMedium
                                color: Theme.surfaceVariantText
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.editingIndex = -1
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Capacity warning ──────────────────────────────────────────────────
    StyledRect {
        visible: root.appsArray.length >= 10
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

    // ── Add section (shown when below limit) ─────────────────────────────
    Column {
        id: addForm
        visible: root.appsArray.length < 10
        width: parent.width
        spacing: Theme.spacingXS
        topPadding: appsModel.count > 0 ? Theme.spacingXS : 0

        // Action buttons — picker first, manual add second
        Row {
            spacing: Theme.spacingS

            // Choose from installed apps
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

            // Add manually (toggles the form below)
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
                            nameInput.text = ""
                            iconInput.text = ""
                            execInput.text = ""
                            root._manualIconPath = ""
                            root.appIconPickerVisible = false
                            root.appIconPickerFilter = ""
                        }
                    }
                }
            }
        }

        // Manual entry fields (hidden until "Add Manually" is clicked)
        Column {
            visible: root.showManualForm
            width: parent.width
            spacing: Theme.spacingXS
            topPadding: Theme.spacingXS

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
                    height: nameInput.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: nameInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onAccepted: if (execInput.text.trim()) root.commitManualAdd()
                        onTextChanged: if (iconInput.text === "") Qt.callLater(root.tryAutoDetectIcon)
                        Text {
                            visible: nameInput.text === ""
                            text: "App name (e.g. Firefox)"
                            color: Theme.surfaceVariantText
                            font: nameInput.font
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

                // Preview + text input + Choose button
                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    // Live icon preview
                    Item {
                        width: Theme.iconSize
                        height: Theme.iconSize
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
                            name: iconInput.text || "apps"
                            size: Theme.iconSize
                            color: Theme.primary
                            anchors.centerIn: parent
                        }
                    }

                    StyledRect {
                        height: iconInput.implicitHeight + Theme.spacingM * 2
                        width: parent.width - Theme.iconSize - chooseIconBtn.width
                               - Theme.spacingS * 2
                        color: Theme.surfaceContainerHigh
                        radius: Theme.cornerRadius

                        TextInput {
                            id: iconInput
                            anchors {
                                left: parent.left; right: parent.right
                                verticalCenter: parent.verticalCenter
                                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                            }
                            color: Theme.surfaceText
                            font.pixelSize: Theme.fontSizeMedium
                            clip: true
                            onTextChanged: if (!root._iconSetByCode) root._manualIconPath = ""
                            Text {
                                visible: iconInput.text === ""
                                text: "auto-detect from name/command"
                                color: Theme.surfaceVariantText
                                font: iconInput.font
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

                    StyledText {
                        visible: root.pickerLoading
                        text: "Scanning installed applications…"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    // Matched app icons from .desktop files
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

                                        // Icon — explicit height fixes Row's implicit height
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

                                        // Name — wrapped in Item so text can vertically centre
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
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    radius: Theme.cornerRadius
                                    color: appIconCellMouse.containsMouse
                                           ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2

                                        DankIcon {
                                            name: modelData
                                            size: Theme.iconSize
                                            color: (iconInput.text === modelData && root._manualIconPath === "")
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
                    height: execInput.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    radius: Theme.cornerRadius

                    TextInput {
                        id: execInput
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                        }
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        clip: true
                        onAccepted: if (nameInput.text.trim()) root.commitManualAdd()
                        onTextChanged: if (iconInput.text === "") Qt.callLater(root.tryAutoDetectIcon)
                        Text {
                            visible: execInput.text === ""
                            text: "Shell command (e.g. firefox)"
                            color: Theme.surfaceVariantText
                            font: execInput.font
                        }
                    }
                }
            }

            // Add App confirm button
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
                    onClicked: root.commitManualAdd()
                }
            }
        }
    }

    // ── App picker ────────────────────────────────────────────────────────
    Column {
        visible: root.pickerVisible
        width: parent.width
        spacing: Theme.spacingXS
        topPadding: Theme.spacingXS

        // Loading state
        StyledText {
            visible: root.pickerLoading
            text: "Scanning installed applications…"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        // Error state (python3 not found or script failed)
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

        // Search field
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

        // Scrollable app list
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

                        // App icon
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

                        // Name + comment
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

    // ═══════════════════════════════════════════════════════════════════════
    // ── Create Another Group ──────────────────────────────────════════════
    // ═══════════════════════════════════════════════════════════════════════

    Rectangle { width: parent.width; height: 1; color: Theme.outline; opacity: 0.3 }

    StyledText {
        width: parent.width
        text: "Create Another Group"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingS
    }

    StyledText {
        width: parent.width
        text: "Creates a new independent copy of this plugin with its own bar icon, " +
              "settings, and app list."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ── Entry button (default state) ──────────────────────────────────────
    StyledRect {
        visible: !root.createFormVisible && !root.confirmCreateVisible
        height: newGroupBtnLabel.implicitHeight + Theme.spacingS * 2
        width: newGroupBtnLabel.implicitWidth + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: newGroupBtnMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

        StyledText {
            id: newGroupBtnLabel
            anchors.centerIn: parent
            text: "New Group…"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.primary
        }
        MouseArea {
            id: newGroupBtnMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.createFormVisible = true
        }
    }

    // ── Form (shown after clicking New Group…) ────────────────────────────
    Column {
        visible: root.createFormVisible && !root.confirmCreateVisible
        width: parent.width
        spacing: Theme.spacingS

        // Group suffix field
        Column {
            width: parent.width
            spacing: 4

            StyledText {
                text: "Group name"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
            StyledRect {
                width: parent.width
                height: groupSuffixInput.implicitHeight + Theme.spacingM * 2
                color: Theme.surfaceContainerHigh
                radius: Theme.cornerRadius

                TextInput {
                    id: groupSuffixInput
                    anchors {
                        left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                        leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
                    }
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    clip: true
                    Text {
                        visible: groupSuffixInput.text === ""
                        text: "e.g. media"
                        color: Theme.surfaceVariantText
                        font: groupSuffixInput.font
                    }
                }
            }
        }

        // Live preview of generated name + directory
        StyledText {
            visible: groupSuffixInput.text.trim() !== ""
            width: parent.width
            text: "Will create: " + root._newGroupName + "  →  " + root._newGroupId
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.primary
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        }

        // Action buttons
        Row {
            spacing: Theme.spacingS
            topPadding: Theme.spacingXS

            StyledRect {
                height: createBtnLabel.implicitHeight + Theme.spacingS * 2
                width: createBtnLabel.implicitWidth + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: createMouse.containsMouse ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                StyledText {
                    id: createBtnLabel
                    anchors.centerIn: parent
                    text: "Create Group"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.primary
                }
                MouseArea {
                    id: createMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (groupSuffixInput.text.trim() === "") {
                            ToastService.showInfo("Missing name", "Please enter a group name")
                            return
                        }
                        root.confirmCreateVisible = true
                    }
                }
            }

            StyledRect {
                height: formCancelLabel.implicitHeight + Theme.spacingS * 2
                width: formCancelLabel.implicitWidth + Theme.spacingL * 2
                radius: Theme.cornerRadius
                color: formCancelMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                StyledText {
                    id: formCancelLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
                MouseArea {
                    id: formCancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.createFormVisible = false
                        groupSuffixInput.text = ""
                    }
                }
            }
        }
    }

    // ── Confirmation card ─────────────────────────────────────────────────
    StyledRect {
        visible: root.confirmCreateVisible
        width: parent.width
        height: confirmColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: confirmColumn
            anchors {
                left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                leftMargin: Theme.spacingM; rightMargin: Theme.spacingM
            }
            spacing: Theme.spacingM

            StyledText {
                width: parent.width
                text: "⚠  Confirm: Create \"" + root._newGroupName + "\""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
            }

            StyledText {
                width: parent.width
                text: "This will create a new independent plugin:\n" +
                      "  Name:      " + root._newGroupName + "\n" +
                      "  Directory: ~/.config/DankMaterialShell/plugins/" + root._newGroupId + "\n\n" +
                      "After creation:\n" +
                      "1. Settings → Plugins → Scan for Plugins\n" +
                      "2. Enable \"" + root._newGroupName + "\"\n" +
                      "3. Settings → DankBar → add it to your bar\n\n" +
                      "The new group starts empty — configure its bar icon, label, and apps " +
                      "through Settings → Plugins → " + root._newGroupName + ". " +
                      "Its settings and app list are completely separate from this group."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.WordWrap
            }

            Row {
                spacing: Theme.spacingS

                StyledRect {
                    height: confirmLabel.implicitHeight + Theme.spacingS * 2
                    width: confirmLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: confirmYesMouse.containsMouse ? Theme.primaryContainer || Theme.surfaceContainerHighest : Theme.primary

                    StyledText {
                        id: confirmLabel
                        anchors.centerIn: parent
                        text: "Confirm — Create"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.onPrimary || Theme.surface
                    }
                    MouseArea {
                        id: confirmYesMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.execDetached([
                                "bash", root.createGroupScript,
                                root.pluginDir,
                                root._newGroupId,
                                root._newGroupName
                            ])
                            root.confirmCreateVisible = false
                            root.createFormVisible = false
                            groupSuffixInput.text = ""
                            ToastService.showInfo(
                                "Group created",
                                "Go to Settings → Plugins → Scan for Plugins to activate it"
                            )
                        }
                    }
                }

                StyledRect {
                    height: cancelLabel.implicitHeight + Theme.spacingS * 2
                    width: cancelLabel.implicitWidth + Theme.spacingL * 2
                    radius: Theme.cornerRadius
                    color: cancelMouse.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh

                    StyledText {
                        id: cancelLabel
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Theme.fontSizeMedium
                        color: Theme.surfaceText
                    }
                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmCreateVisible = false
                    }
                }
            }
        }
    }

    // ── Helper: commit manual add ─────────────────────────────────────────
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
        nameInput.forceActiveFocus()
        // Form stays open so the user can add another app immediately
    }
}
