pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// PrivacyService — міст до scripts/privacy.py: які застосунки зараз
// тримають камеру або мікрофон. Демон слухає PipeWire та inotify на
// /dev/video* і віддає по одному JSON-рядку на зміну стану.
Singleton {
    id: root

    readonly property string launcher:
        'for d in "$HOME/.config/quickshell/bar/scripts" "$HOME/.config/quickshell/scripts"; do ' +
        '[ -f "$d/privacy.py" ] && exec python3 "$d/privacy.py"; done; ' +
        'echo "privacy.py not found in ~/.config/quickshell/{bar/,}scripts" >&2; exit 127'

    readonly property bool enabled: Settings.get("modules", "privacy") !== false

    property bool ready: false
    property var camera: []        // [{ pid, app, device }]
    property var mic: []           // [{ pid, app }]
    readonly property bool active: camera.length > 0 || mic.length > 0

    property bool _alive: true

    function ensure() { /* торкнутися singleton — запускає демон */ }

    function _line(line) {
        const text = String(line || "").trim()
        if (text.length === 0) return
        try {
            const data = JSON.parse(text)
            camera = Array.isArray(data.camera) ? data.camera : []
            mic = Array.isArray(data.mic) ? data.mic : []
            ready = true
        } catch (e) {
            console.warn("[Privacy] bad line: " + text)
        }
    }

    function _names(list) {
        const out = []
        for (const item of (list || [])) {
            const name = String((item && item.app) || "").trim()
            if (name.length > 0 && out.indexOf(name) < 0) out.push(name)
        }
        return out
    }

    readonly property string cameraNames: _names(camera).join(", ")
    readonly property string micNames: _names(mic).join(", ")

    onEnabledChanged: {
        if (enabled) {
            _alive = true
        } else {
            _alive = false
            ready = false
            camera = []
            mic = []
        }
    }

    Process {
        id: proc
        running: root.enabled && root._alive
        command: ["sh", "-c", root.launcher]
        stdinEnabled: false
        stdout: SplitParser { onRead: data => root._line(data) }
        stderr: SplitParser { onRead: data => console.warn("[Privacy] " + data) }
        onExited: (code, status) => {
            root.ready = false
            root.camera = []
            root.mic = []
            if (root.enabled) {
                console.warn("[Privacy] daemon exited with code " + code + "; restarting")
                root._alive = false
                restart.start()
            }
        }
    }

    Timer {
        id: restart
        interval: 2000
        onTriggered: if (root.enabled) root._alive = true
    }
}
