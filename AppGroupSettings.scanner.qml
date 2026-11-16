import QtQuick
import Quickshell
import Quickshell.Io

// AppGroupSettings.scanner.qml — System app scanner for App Stack plugin.
// Loaded asynchronously by AppGroupSettings.qml to avoid Quickshell type
// resolution issues in PluginSettings context.

QtObject {
    id: root

    property var pluginService: null
    property string pluginId: "appStack_default"
    property string listAppsScript: ""
    property bool running: false
    property var onAppsLoaded: null

    Process {
        id: scanner
        running: root.running
        command: ["python3", root.listAppsScript]

        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                try {
                    var apps = JSON.parse(line)
                    if (root.onAppsLoaded) {
                        root.onAppsLoaded(apps)
                    }
                } catch(e) {}
            }
        }

        onExited: function(exitCode) {
            root.running = false
        }
    }

    function start() {
        root.running = true
    }

    function stop() {
        root.running = false
    }
}
