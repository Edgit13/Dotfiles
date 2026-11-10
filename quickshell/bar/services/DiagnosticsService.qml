pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// DiagnosticsService — runs `edots doctor --json` and exposes the report.
// The CLI owns every check; this service only parses and presents it.
Singleton {
    id: root

    readonly property string cli: Quickshell.env("HOME") + "/edots/bin/edots"

    property var groups: []
    property int okCount: 0
    property int warnCount: 0
    property int failCount: 0
    property bool running: false
    property string error: ""
    property double lastRun: 0

    readonly property bool healthy: failCount === 0 && !running

    function refresh() {
        if (running) return
        running = true
        error = ""
        proc.running = true
    }

    function _parse(text) {
        try {
            const d = JSON.parse(text)
            groups = Array.isArray(d.groups) ? d.groups : []
            const s = d.summary || {}
            okCount = Number(s.ok) || 0
            warnCount = Number(s.warn) || 0
            failCount = Number(s.fail) || 0
            lastRun = Date.now()
        } catch (e) {
            groups = []
            okCount = warnCount = failCount = 0
            error = "Could not parse the doctor report"
        }
    }

    Process {
        id: proc
        command: [root.cli, "doctor", "--json"]
        stdout: StdioCollector { onStreamFinished: root._parse(text) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim()
        }
        onExited: root.running = false
    }
}
