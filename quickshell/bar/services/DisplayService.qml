pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// ==========================================================================
// DisplayService.qml — runtime output configuration for wlroots/MangoWC.
//
// The heavy lifting lives in scripts/displayctl.py (wlr-randr --json):
//   • list     — outputs, modes, scale, transform, arrangement
//   • apply    — write a new layout, saving the old one as a snapshot
//   • keep     — confirm the new layout (drop the snapshot)
//   • revert   — restore the snapshot
//
// The UI edits a `pending` map; applyAll() sends the merged draft. A successful
// apply starts an 18-second countdown. If it is not confirmed, the previous
// layout is restored automatically — no more guessing if a mode change will
// leave you with a black screen.
// ==========================================================================
Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/displayctl.py"

    property var outputs: []
    property var pending: ({})
    property bool loading: false
    property bool applying: false
    property bool confirming: false
    property int confirmSeconds: 0
    property bool canRevert: false
    property string error: ""
    property string message: ""

    readonly property int confirmTimeout: 18

    // Merged view: current output configuration + local pending edits.
    readonly property var draft: {
        const source = outputs || []
        const changes = pending || {}
        return source.map(function (out) {
            const p = changes[out.name] || {}
            const copy = Object.assign({}, out)
            if (p.enabled !== undefined) copy.enabled = p.enabled
            if (p.mode !== undefined) copy.currentMode = p.mode
            if (p.scale !== undefined) copy.scale = p.scale
            if (p.transform !== undefined) copy.transform = p.transform
            if (p.adaptiveSync !== undefined) copy.adaptiveSync = p.adaptiveSync
            copy.relative = p.relative !== undefined ? p.relative : null
            return copy
        })
    }

    readonly property bool hasPending: {
        const changes = pending || {}
        for (const name in changes) {
            if (Object.keys(changes[name] || {}).length > 0)
                return true
        }
        return false
    }

    readonly property bool locked: applying || confirming

    function original(name) {
        return (outputs || []).find(function (out) { return out.name === name }) || null
    }

    function isChanged(name) {
        const entry = (pending || {})[name]
        return !!entry && Object.keys(entry).length > 0
    }

    function _setValue(name, key, value) {
        const out = original(name)
        if (!out || locked)
            return

        const changes = Object.assign({}, pending)
        const entry = Object.assign({}, changes[name] || {})
        const originalValue = key === "mode" ? out.currentMode : out[key]

        let same
        if (key === "relative") {
            same = value === null || value === undefined
        } else if (typeof originalValue === "number" || typeof value === "number") {
            same = Number(originalValue) === Number(value)
        } else {
            same = String(originalValue) === String(value)
        }

        if (same) delete entry[key]
        else entry[key] = value

        if (Object.keys(entry).length === 0) delete changes[name]
        else changes[name] = entry

        pending = changes
        error = ""
        message = ""
    }

    function setEnabled(name, value) {
        const out = original(name)
        if (!out || locked) return
        _setValue(name, "enabled", !!value)
        if (value && !out.enabled) {
            // A monitor that was off has no sensible position: park it to the
            // right of the first active monitor until the user arranges it.
            const other = (outputs || []).find(function (item) {
                return item.name !== name && item.enabled
            })
            if (other && !((pending[name] || {}).relative))
                _setValue(name, "relative", { to: other.name, where: "right" })
        }
    }

    function setMode(name, modeId)        { _setValue(name, "mode", modeId) }
    function setScale(name, value)        { _setValue(name, "scale", Number(value)) }
    function setTransform(name, value)    { _setValue(name, "transform", value) }
    function setAdaptiveSync(name, value) { _setValue(name, "adaptiveSync", !!value) }

    function setRelative(name, relative) {
        _setValue(name, "relative", relative && relative.to ? {
            to: relative.to,
            where: relative.where
        } : null)
    }

    function resetPending() {
        if (locked) return
        pending = ({})
        error = ""
        message = ""
    }

    // ── data ────────────────────────────────────────────────────────────

    function refresh() {
        if (listProc.running || applying) return
        loading = true
        error = ""
        _listOut = ""
        listProc.running = true
    }

    function _finishList(code) {
        loading = false
        const raw = String(_listOut || "").trim()
        if (raw.length === 0) {
            if (code !== 0)
                error = "Display query failed (" + code + ")"
            return
        }

        let data
        try { data = JSON.parse(raw) }
        catch (e) {
            error = "Could not parse wlr-randr output"
            outputs = []
            return
        }

        if (!data || data.ok === false) {
            error = (data && data.error) ? data.error : "Display query failed"
            outputs = []
            return
        }

        outputs = data.outputs || []
        canRevert = data.canRevert === true

        if (outputs.length === 0)
            message = Lang.t("display.none")

        // Drop pending edits for outputs that disappeared.
        const changes = Object.assign({}, pending)
        let pruned = false
        for (const name in changes) {
            if (!outputs.some(function (out) { return out.name === name })) {
                delete changes[name]
                pruned = true
            }
        }
        if (pruned) pending = changes
    }

    // ── apply / keep / revert ───────────────────────────────────────────

    function buildSpec() {
        return {
            outputs: draft.map(function (out) {
                const entry = {
                    name: out.name,
                    enabled: !!out.enabled,
                    scale: Number(out.scale || 1),
                    transform: out.transform || "normal",
                    adaptiveSync: !!out.adaptiveSync
                }
                if (out.enabled) {
                    const mode = (out.modes || []).find(function (item) {
                        return item.id === out.currentMode
                    })
                    if (mode)
                        entry.mode = {
                            width: mode.width,
                            height: mode.height,
                            refresh: mode.refresh
                        }
                }
                if (out.relative && out.relative.to) {
                    entry.relative = {
                        to: out.relative.to,
                        where: out.relative.where
                    }
                } else if (out.position) {
                    entry.position = {
                        x: Number(out.position.x || 0),
                        y: Number(out.position.y || 0)
                    }
                }
                return entry
            })
        }
    }

    function applyAll() {
        if (applying || !hasPending) return
        error = ""
        message = ""
        applying = true
        _applyOut = ""
        _applyErr = ""
        applyProc.command = ["python3", helper, "apply", JSON.stringify(buildSpec())]
        applyProc.running = true
    }

    function _finishApply(code) {
        applying = false
        let data = null
        try { data = JSON.parse(String(_applyOut || "")) }
        catch (e) { data = null }

        if (code === 0 && data && data.ok === true) {
            pending = ({})
            canRevert = true
            message = Lang.t("display.applied")
            confirming = true
            confirmSeconds = confirmTimeout
            countdown.restart()
            refreshTimer.restart()
            return
        }

        error = (data && data.error) ? data.error
            : (String(_applyErr || "").trim() || ("Could not apply display settings (" + code + ")"))
    }

    function keepChanges() {
        if (applying) return
        countdown.stop()
        confirming = false
        confirmSeconds = 0
        pending = ({})
        canRevert = false
        message = Lang.t("display.kept")
        Quickshell.execDetached(["python3", helper, "keep"])
    }

    function revertNow() {
        if (applying) return
        countdown.stop()
        confirming = false
        confirmSeconds = 0
        error = ""
        message = ""
        applying = true
        _revertOut = ""
        _revertErr = ""
        revertProc.running = true
    }

    function _finishRevert(code) {
        applying = false
        let data = null
        try { data = JSON.parse(String(_revertOut || "")) }
        catch (e) { data = null }

        if (code === 0 && data && data.ok === true) {
            pending = ({})
            canRevert = false
            message = Lang.t("display.reverted")
            refreshTimer.restart()
            return
        }

        error = (data && data.error) ? data.error
            : (String(_revertErr || "").trim() || ("Could not restore the previous display setup (" + code + ")"))
    }

    // ── processes / timers ─────────────────────────────────────────────

    property string _listOut: ""
    property string _applyOut: ""
    property string _applyErr: ""
    property string _revertOut: ""
    property string _revertErr: ""

    Process {
        id: listProc
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector { onStreamFinished: root._listOut = text }
        stderr: StdioCollector { onStreamFinished: if (text.trim().length) root.error = text.trim() }
        onExited: (code, status) => root._finishList(code)
    }

    Process {
        id: applyProc
        command: []
        stdout: StdioCollector { onStreamFinished: root._applyOut = text }
        stderr: StdioCollector { onStreamFinished: root._applyErr = text }
        onExited: (code, status) => root._finishApply(code)
    }

    Process {
        id: revertProc
        command: ["python3", root.helper, "revert"]
        stdout: StdioCollector { onStreamFinished: root._revertOut = text }
        stderr: StdioCollector { onStreamFinished: root._revertErr = text }
        onExited: (code, status) => root._finishRevert(code)
    }

    Timer {
        id: refreshTimer
        interval: 650
        repeat: false
        onTriggered: root.refresh()
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.confirmSeconds = Math.max(0, root.confirmSeconds - 1)
            if (root.confirmSeconds <= 0) {
                countdown.stop()
                root.revertNow()
            }
        }
    }
}
