pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ==========================================================================
// AudioStudioService.qml — стан і команди Аудіостудії.
// Бекенд — scripts/audio-studio.py: генерує пресети EasyEffects (10-смуговий
// еквалайзер + RNNoise для мікрофона), завантажує їх у запущений сервіс і
// повертає JSON. Тут — лише стан для UI, оптимістичні зміни та debounce,
// щоб перетягування смуг не спавнило python на кожен піксель.
// ==========================================================================
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/audio-studio.py"

    property bool installed: false
    property bool running: false
    property bool bypassed: false
    property var gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property real preamp: 0
    property string preset: "Flat"
    property string loadedOutput: ""
    property string loadedInput: ""
    property bool mic: false
    property var presets: [
        { name: "Flat", builtin: true },
        { name: "Bass boost", builtin: true },
        { name: "Vocal", builtin: true },
        { name: "Treble", builtin: true },
        { name: "Warm", builtin: true }
    ]
    property var builtins: ({})
    property var freqs: [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    property var freqLabels: ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]

    property bool busy: false
    property bool dragging: false
    property bool watching: false
    property string error: ""

    property real _localUntil: 0
    property var _pending: null
    property string _action: ""
    property bool _gotReply: false

    // ── публічні дії ────────────────────────────────────────────────────

    function refresh() {
        if (statusProc.running || busy) return
        statusProc.running = true
    }

    function setGain(index, db) {
        if (index < 0 || index >= gains.length) return
        const next = gains.slice()
        next[index] = Math.max(-12, Math.min(12, Math.round(Number(db) * 2) / 2))
        gains = next
        preset = "Custom"
        scheduleApply()
    }

    function setPreamp(db) {
        let v = Math.max(-12, Math.min(12, Number(db)))
        v = Math.round(v * 2) / 2
        preamp = Math.abs(v) < 0.05 ? 0 : v
        preset = "Custom"
        scheduleApply()
    }

    function loadPreset(name) {
        if (!name || name.length === 0) return
        const curve = builtins[name]
        if (curve && curve.length === gains.length) gains = curve.slice()
        preset = name
        _exec("preset", [name])
    }

    function setBypass(on) {
        bypassed = !!on
        _exec("bypass", [on ? "on" : "off"])
    }

    function toggleBypass() { setBypass(!bypassed) }

    function setMic(on) {
        mic = !!on
        _exec("mic", [on ? "on" : "off"])
    }

    function toggleMic() { setMic(!mic) }

    function resetEq() {
        gains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        preamp = 0
        preset = "Flat"
        _exec("reset", [])
    }

    function startEngine() { _exec("start", []) }
    function openEasyEffects() { _exec("open", []) }

    function beginDrag() {
        dragging = true
        _localUntil = Date.now() + 1500
    }

    function endDrag() {
        dragging = false
        flush()
    }

    function flush() {
        if (applyTimer.running) applyTimer.stop()
        applyEq()
    }

    // ── внутрішнє ───────────────────────────────────────────────────────

    function applyEq() {
        const values = []
        for (let i = 0; i < gains.length; i++) values.push(Number(gains[i]).toFixed(1))
        _exec("eq", ["--gains", values.join(","),
                     "--preamp", Number(preamp).toFixed(1),
                     "--preset", preset])
    }

    function scheduleApply() {
        _localUntil = Date.now() + 1200
        applyTimer.restart()
    }

    function _exec(action, args) {
        if (busy) {
            _pending = { action: action, args: args }
            return
        }
        busy = true
        _action = action
        // Ignore any status query that started before this action: its JSON is
        // already stale and must not overwrite optimistic/local values.
        _localUntil = Date.now() + 1800
        error = ""
        actionProc.command = ["python3", script, action].concat(args || [])
        actionProc.running = true
    }

    function _consume(raw, fromAction) {
        if (!raw || raw.trim().length === 0) return
        let d
        try { d = JSON.parse(raw) }
        catch (e) { error = "Unexpected response from the audio helper"; return }
        if (!d || d.ok === false) {
            error = (d && d.error) ? d.error : "Audio helper failed"
            return
        }
        _apply(d, fromAction)
    }

    function _apply(d, fromAction) {
        installed = d.installed === true
        running = d.running === true
        bypassed = d.bypassed === true
        mic = d.mic === true
        loadedOutput = d.loadedOutput || ""
        loadedInput = d.loadedInput || ""
        if (d.presets) presets = d.presets
        if (d.builtins) builtins = d.builtins
        if (d.freqs) freqs = d.freqs
        if (d.freqLabels) freqLabels = d.freqLabels

        // Під час перетягування не даємо старій відповіді смикнути ручку назад.
        const fresh = !dragging && (fromAction || Date.now() >= _localUntil)
        if (fresh && d.gains && d.gains.length === gains.length) {
            gains = d.gains
            preamp = Number(d.preamp || 0)
            if (d.preset) preset = d.preset
        }
        _gotReply = true
        error = ""
    }

    Timer {
        id: applyTimer
        interval: 260
        repeat: false
        onTriggered: root.applyEq()
    }

    Timer {
        interval: 3500
        repeat: true
        running: root.watching && !root.busy && !root.dragging
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Process {
        id: statusProc
        command: ["python3", root.script, "status"]
        stdout: StdioCollector { onStreamFinished: root._consume(text, false) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim()
        }
        onExited: (code, status) => {
            if (code !== 0 && root.error.length === 0)
                root.error = "Audio status query failed (" + code + ")"
        }
    }

    Process {
        id: actionProc
        command: []
        stdout: StdioCollector { onStreamFinished: root._consume(text, true) }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.error = text.trim()
        }
        onExited: (code, status) => {
            root.busy = false
            if (code !== 0 && root.error.length === 0)
                root.error = "Audio action failed (" + code + ")"
            if (root._pending) {
                const p = root._pending
                root._pending = null
                root._exec(p.action, p.args)
            }
        }
    }
}
