pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// NightLightService — colour temperature through gammastep.
// The script owns the process; this service only exposes state and settings.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/nightlight.py"
    readonly property string statePath: Quickshell.env("HOME") + "/.cache/quickshell/nightlight.state"

    readonly property bool   enabled:   Settings.get("nightlight", "enabled") === true
    readonly property string mode:      String(Settings.get("nightlight", "mode") || "manual")
    readonly property int    temp:      Math.round(Number(Settings.get("nightlight", "temp") ?? 4000))
    readonly property int    dayTemp:   Math.round(Number(Settings.get("nightlight", "dayTemp") ?? 6500))
    readonly property int    nightTemp: Math.round(Number(Settings.get("nightlight", "nightTemp") ?? 4000))
    readonly property string sunset:    String(Settings.get("nightlight", "sunset") || "19:00")
    readonly property string sunrise:   String(Settings.get("nightlight", "sunrise") || "07:00")

    property int currentTemp: 6500
    property bool applying: false
    property bool pending: false
    property string error: ""

    function apply() {
        if (applying) { pending = true; return }
        applying = true
        pending = false
        proc.command = ["python3", script, "apply"]
        proc.running = true
    }

    function ensure() { if (Settings.loaded) apply() }

    function toggle()    { Settings.set("nightlight", "enabled", !enabled) }
    function setEnabled(v) { Settings.set("nightlight", "enabled", !!v) }
    function setTemp(v)  { Settings.set("nightlight", "temp", v); Settings.set("nightlight", "mode", "manual") }

    Process {
        id: proc
        onExited: {
            root.applying = false
            stateFile.reload()
            if (root.pending) root.apply()
        }
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._parse(text())
        onLoadFailed: { root.currentTemp = 6500; root.error = "" }
    }

    function _parse(t) {
        try {
            const s = JSON.parse(t)
            root.currentTemp = Math.round(Number(s.temp) || 6500)
            root.error = String(s.error || "")
        } catch (e) {
            root.currentTemp = 6500
            root.error = ""
        }
    }

    Connections {
        target: Settings
        function onChanged(cat, key, value) { if (cat === "nightlight") debounce.restart() }
        function onLoadedChanged() { if (Settings.loaded) root.apply() }
    }

    // Settings writes the JSON asynchronously; wait a moment before the script
    // reads it, and collapse several rapid changes into one apply.
    Timer {
        id: debounce
        interval: 200
        onTriggered: root.apply()
    }

    // Re-evaluate the schedule every minute while it is enabled.
    Timer {
        interval: 60000
        repeat: true
        running: root.enabled && root.mode === "schedule"
        onTriggered: root.apply()
    }
}
