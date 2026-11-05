pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// ==========================================================================
// AudioService.qml — бекенд Audio Device Manager для Edots Quickshell.
// Повне керування пристроями відтворення (sinks), мікрофонами (sources),
// гучністю окремих програм (sink-inputs) та перемиканням за замовчуванням.
// Поєднує реактивні події Pipewire та команди pactl/wpctl.
// ==========================================================================

Singleton {
    id: root

    property string defaultSinkName: ""
    property string defaultSourceName: ""

    property var sinks: []   // [{ index, name, description, volume, muted, isDefault, activePort, ports }]
    property var sources: [] // [{ index, name, description, volume, muted, isDefault, activePort, ports }]
    property var streams: [] // [{ index, name, binary, media, volume, muted, sink, key, icon, pinned }]
    property var routes: ({}) // per-app output routes { appKey: sinkName }

    readonly property var defaultSink: sinks.find(s => s.isDefault) || (sinks.length > 0 ? sinks[0] : null)
    readonly property var defaultSource: sources.find(s => s.isDefault) || (sources.length > 0 ? sources[0] : null)

    readonly property bool micMuted: defaultSource ? defaultSource.muted : false
    readonly property int micVolume: defaultSource ? defaultSource.volume : 0

    property int subscribers: 0

    readonly property string helper: Quickshell.shellPath("scripts/audioinfo.py")
    // Stream indexes already checked against saved routes, so a manual move is
    // not undone by the next poll while the same stream keeps playing.
    property var _routedStreams: ({})
    readonly property bool active: subscribers > 0

    function subscribe() {
        subscribers += 1
        if (subscribers === 1) refresh()
    }
    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1)
    }

    // Реактивне оновлення з Quickshell Pipewire сервісу
    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.refresh() }
        function onDefaultAudioSourceChanged() { root.refresh() }
    }

    Timer {
        id: pollTimer
        interval: 2500
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    Process {
        id: infoProc
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || !text.trim()) return
                try {
                    const data = JSON.parse(text)
                    if (data.defaultSink) root.defaultSinkName = data.defaultSink
                    if (data.defaultSource) root.defaultSourceName = data.defaultSource
                    if (Array.isArray(data.sinks)) root.sinks = data.sinks
                    if (Array.isArray(data.sources)) root.sources = data.sources
                    if (data.routes && typeof data.routes === "object") root.routes = data.routes
                    if (Array.isArray(data.streams)) {
                        root.streams = data.streams
                        root._applyRoutes(data.streams)
                    }
                } catch (e) {
                    console.warn("AudioService parse error:", e)
                }
            }
        }
    }

    // Apply a saved route only the first time a stream index appears. This
    // pins new apps to their chosen output while still letting the user move
    // the same stream elsewhere for the rest of its lifetime.
    function _applyRoutes(streams) {
        const seen = {}
        const moves = []
        for (const stream of streams) {
            seen[stream.index] = true
            if (root._routedStreams[stream.index]) continue
            root._routedStreams[stream.index] = true
            const wanted = stream.key ? (root.routes || {})[stream.key] : ""
            if (wanted && wanted !== stream.sinkName)
                moves.push({ index: stream.index, sink: wanted })
        }
        root._routedStreams = seen
        if (moves.length > 0) root._runMoves(moves)
    }

    function _shellQuote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    // One process for every stream that needs its saved sink; running them on
    // cmdProc one by one would overwrite the command while it is still busy.
    function _runMoves(moves) {
        const script = moves.map(function (move) {
            return "pactl move-sink-input " + move.index + " " + root._shellQuote(move.sink)
        }).join(" && ")
        batchProc.command = ["sh", "-c", script]
        batchProc.running = true
    }

    function refresh() {
        if (!infoProc.running) infoProc.running = true
    }

    // ---- Дії над Output (sinks) ----
    function setDefaultSink(name) {
        cmdProc.command = ["pactl", "set-default-sink", name]
        cmdProc.running = true
    }

    function setSinkVolume(nameOrIndex, pct) {
        const val = Math.max(0, Math.min(150, Math.round(pct)))
        cmdProc.command = ["pactl", "set-sink-volume", String(nameOrIndex), val + "%"]
        cmdProc.running = true
    }

    function toggleSinkMute(nameOrIndex) {
        cmdProc.command = ["pactl", "set-sink-mute", String(nameOrIndex), "toggle"]
        cmdProc.running = true
    }

    function setSinkPort(nameOrIndex, portName) {
        cmdProc.command = ["pactl", "set-sink-port", String(nameOrIndex), portName]
        cmdProc.running = true
    }

    // ---- Дії над Input (sources / mic) ----
    function setDefaultSource(name) {
        cmdProc.command = ["pactl", "set-default-source", name]
        cmdProc.running = true
    }

    function setSourceVolume(nameOrIndex, pct) {
        const val = Math.max(0, Math.min(100, Math.round(pct)))
        cmdProc.command = ["pactl", "set-source-volume", String(nameOrIndex), val + "%"]
        cmdProc.running = true
    }

    function toggleSourceMute(nameOrIndex) {
        cmdProc.command = ["pactl", "set-source-mute", String(nameOrIndex), "toggle"]
        cmdProc.running = true
    }

    function toggleDefaultMicMute() {
        if (root.defaultSource) {
            toggleSourceMute(root.defaultSource.name)
        }
    }

    // ---- Дії над додатками (sink-inputs) ----
    function moveStream(index, sinkName) {
        if (!sinkName) return
        cmdProc.command = ["pactl", "move-sink-input", String(index), sinkName]
        cmdProc.running = true
    }

    // Pin an app to a sink and remember it for future streams.
    function routeStream(stream, sinkName) {
        if (!stream || !sinkName) return
        root.moveStream(stream.index, sinkName)
        if (!stream.key) return
        const next = Object.assign({}, root.routes || {})
        next[stream.key] = sinkName
        root.routes = next
        routeProc.command = ["python3", root.helper, "route", stream.key, sinkName]
        routeProc.running = true
    }

    // Clear the pin and send the stream back to the default output.
    function followDefault(stream) {
        if (!stream) return
        if (root.defaultSink) root.moveStream(stream.index, root.defaultSink.name)
        if (!stream.key) return
        const next = Object.assign({}, root.routes || {})
        delete next[stream.key]
        root.routes = next
        routeProc.command = ["python3", root.helper, "route", stream.key, "auto"]
        routeProc.running = true
    }

    function routeFor(stream) {
        return stream && stream.key ? ((root.routes || {})[stream.key] || "") : ""
    }

    function setStreamVolume(index, pct) {
        const val = Math.max(0, Math.min(150, Math.round(pct)))
        cmdProc.command = ["pactl", "set-sink-input-volume", String(index), val + "%"]
        cmdProc.running = true
    }

    function toggleStreamMute(index) {
        cmdProc.command = ["pactl", "set-sink-input-mute", String(index), "toggle"]
        cmdProc.running = true
    }

    function muteAllStreams() {
        const list = root.streams || []
        if (list.length === 0) return
        const script = list.map(function (stream) {
            return "pactl set-sink-input-mute " + stream.index + " 1"
        }).join(" && ")
        batchProc.command = ["sh", "-c", script]
        batchProc.running = true
    }

    Process {
        id: cmdProc
        onExited: root.refresh()
    }

    Process {
        id: batchProc
        command: []
        onExited: root.refresh()
    }

    // Route commands already move the running stream; persist the pin, then
    // re-read so the UI shows the sink chosen by pactl.
    Process {
        id: routeProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || !text.trim()) return
                try {
                    const data = JSON.parse(text)
                    if (data.routes && typeof data.routes === "object") root.routes = data.routes
                } catch (e) {
                    console.warn("AudioService route parse error:", e)
                }
            }
        }
        onExited: root.refresh()
    }

    Component.onCompleted: refresh()
}
