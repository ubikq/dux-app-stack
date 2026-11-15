import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// AppGroupWidget — Multi-group bar widget for App Stack plugin.
//
// Data shape: pluginData.groups is a JSON array of group objects:
// [
//   { "id": "group_0", "name": "Dev", "icon": "code", "showLabel": true,
//     "apps": [{ "name": "...", "icon": "...", "iconPath": "...", "exec": "...", "source": "..." }] },
//   ...
// ]
//
// widgetInstanceId (auto-injected by Dux Shell) maps each bar slot to a
// groups array index. Instance 0 → groups[0], instance 1 → groups[1], etc.

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

    // Derived properties for convenience (null-safe)
    property string _groupName: currentGroup ? (currentGroup.name || "Group") : "Empty"
    property string _groupIcon: currentGroup ? (currentGroup.icon || "apps") : "apps"
    property bool _showLabel: currentGroup ? (currentGroup.showLabel || false) : false
    property var _groupApps: currentGroup ? (currentGroup.apps || []) : []

    // Default apps shown when group has none configured
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
            // Save apps array back to the groups array in pluginData.
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
                        text: "Tap \u2715 to remove"
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

                    // "+" add tile (shown when below limit and in edit mode)
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
                        text: "Scanning installed apps\u2026"
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
                                text: "Search apps\u2026"
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
