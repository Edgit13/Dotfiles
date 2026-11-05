pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// SessionService — keeps ~/.config/mango/swayidle.conf in sync with
// Settings → System → Session. The actual config rendering, service reload
// and lock/suspend actions live in scripts/sessionidle.py.
Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/sessionidle.py"

    readonly property bool idleEnabled: Settings.get("session", "idleEnabled") !== false
    readonly property int lockMinutes: Number(Settings.get("session", "lockMinutes") ?? 5)
    readonly property int screenOffMinutes: Number(Settings.get("session", "screenOffMinutes") ?? 10)
    readonly property int suspendMinutes: Number(Settings.get("session", "suspendMinutes") ?? 0)
    readonly property bool lockOnSuspend: Settings.get("session", "lockOnSuspend") !== false

    // Debounced: sliders emit a lot of updates while dragging.
    Timer {
        id: debounce
        interval: 450
        repeat: false
        onTriggered: root.apply()
    }

    Process {
        id: applyProc
        command: ["python3", root.helper, "apply"]
        property bool pending: false
        onExited: {
            if (pending) {
                pending = false
                running = true
            }
        }
    }

    Connections {
        target: Settings
        function onChanged(cat, key, value) {
            if (cat === "session") debounce.restart()
        }
    }

    function apply() {
        // Never run two writers at once: remember the latest change and
        // re-apply once the current run finishes.
        if (applyProc.running) applyProc.pending = true
        else applyProc.running = true
    }

    // Called once from ShellNext. apply() is a no-op when the generated file
    // already matches the settings, so this does not reset idle timers on
    // every shell restart.
    function ensure() { apply() }
}
