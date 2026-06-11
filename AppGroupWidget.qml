import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property string groupName: pluginData.groupName || "App Group"
    property string groupIcon: pluginData.groupIcon || "apps"
    property bool showLabel: pluginData.showLabel || false

    property var defaultApps: [
        { "name": "Firefox",  "icon": "language",  "exec": "firefox"  },
        { "name": "Terminal", "icon": "terminal",  "exec": "kitty"    },
        { "name": "Files",    "icon": "folder",    "exec": "nautilus" },
        { "name": "Settings", "icon": "settings",  "exec": "gnome-control-center" }
    ]

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            DankIcon {
                name: root.groupIcon
                size: Theme.iconSize
                color: Theme.primary
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: root.showLabel
                text: root.groupName
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: root.groupIcon
            size: Theme.iconSize
            color: Theme.primary
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            headerText: root.groupName
            showCloseButton: true

            property var liveApps: root.defaultApps

            Component.onCompleted: {
                var raw = pluginData.appsData
                if (raw === undefined || raw === null || raw === "") { liveApps = root.defaultApps; return }
                try {
                    var arr = JSON.parse(raw)
                    liveApps = Array.isArray(arr) ? arr : root.defaultApps
                } catch(e) {
                    liveApps = root.defaultApps
                }
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingS
                topPadding: Theme.spacingS

                Repeater {
                    model: popout.liveApps

                    delegate: Item {
                        width: 80
                        height: 84

                        StyledRect {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Theme.cornerRadius
                            color: appMouse.containsMouse
                                   ? Theme.surfaceContainerHighest
                                   : Theme.surfaceContainerHigh

                            Column {
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                // Use the resolved icon file when available (system apps),
                                // otherwise fall back to a material icon name.
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
                                            width: Theme.iconSize
                                            height: Theme.iconSize
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
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

                            MouseArea {
                                id: appMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.exec) {
                                        Quickshell.execDetached(["/bin/sh", "-c", modelData.exec])
                                    }
                                    popout.closePopout()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 300
    popoutHeight: 400
}
