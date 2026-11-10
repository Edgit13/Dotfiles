pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// UpdateService — non-locking package update check (repo + AUR + Flatpak).
// Updating itself always happens in a terminal; nothing is installed silently.
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/updatecheck.py"

    property var repo: []
    property var aur: []
    property var flatpak: []
    property bool checking: false
    property string error: ""
    property int lastCheck: 0

    readonly property int total: repo.length + aur.length + flatpak.length
    readonly property bool hasUpdates: total > 0
    readonly property var rows: {
        const out = []
        const push = (list, source) => {
            for (let i = 0; i < list.length; i++) {
                const p = list[i]
                out.push({ name: p.name || "", old: p.old || "", new: p.new || "", source: source })
            }
        }
        push(repo, "repo")
        push(aur, "aur")
        push(flatpak, "flatpak")
        return out
    }

    readonly property bool autoCheck: Settings.get("updates", "autoCheck") === true
    readonly property int intervalHours: Math.round(Number(Settings.get("updates", "intervalHours") ?? 6))

    function refresh() {
        if (checking) return
        checking = true
        error = ""
        proc.running = true
    }

    function ensure() {
        if (!autoCheck) return
        if (lastCheck > 0 && (Date.now() / 1000 - lastCheck) < intervalHours * 3600) return
        refresh()
    }

    function updateAll() {
        if (!hasUpdates) return
        const configured = String(Settings.get("updates", "terminal") || "")
        const term = configured.length > 0
            ? configured
            : String(Settings.get("general", "terminalCommand") || "ghostty")
        Quickshell.execDetached(term.trim().split(/\s+/).concat(["-e", "sh", "-lc",
            "upkg update; printf '\\nPress Enter to close…'; read _"]))
    }

    function _parse(text) {
        try {
            const d = JSON.parse(text)
            repo = Array.isArray(d.repo) ? d.repo : []
            aur = Array.isArray(d.aur) ? d.aur : []
            flatpak = Array.isArray(d.flatpak) ? d.flatpak : []
            error = String(d.error || "")
            lastCheck = Number(d.checked) || Math.floor(Date.now() / 1000)
        } catch (e) {
            repo = []; aur = []; flatpak = []
            error = "Could not parse the update check output"
        }
    }

    Process {
        id: proc
        command: ["python3", root.script]
        stdout: StdioCollector { onStreamFinished: root._parse(text) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim()
        }
        onExited: root.checking = false
    }

    Connections {
        target: Settings
        function onChanged(cat, key, value) { if (cat === "updates" && key === "autoCheck") root.ensure() }
    }

    Timer {
        interval: Math.max(1, root.intervalHours) * 3600000
        repeat: true
        running: root.autoCheck
        onTriggered: root.refresh()
    }
}
