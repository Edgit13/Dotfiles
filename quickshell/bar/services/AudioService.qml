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
    property var streams: [] // [{ index, name, binary, media, volume, muted, sink }]

    readonly property var defaultSink: sinks.find(s => s.isDefault) || (sinks.length > 0 ? sinks[0] : null)
    readonly property var defaultSource: sources.find(s => s.isDefault) || (sources.length > 0 ? sources[0] : null)

    readonly property bool micMuted: defaultSource ? defaultSource.muted : false
    readonly property int micVolume: defaultSource ? defaultSource.volume : 0

    property int subscribers: 0
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
        command: ["python3", Quickshell.env("HOME") + "/Dotfiles/quickshell/bar/scripts/audioinfo.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || !text.trim()) return
                try {
                    const data = JSON.parse(text)
                    if (data.defaultSink) root.defaultSinkName = data.defaultSink
                    if (data.defaultSource) root.defaultSourceName = data.defaultSource
                    if (Array.isArray(data.sinks)) root.sinks = data.sinks
                    if (Array.isArray(data.sources)) root.sources = data.sources
                    if (Array.isArray(data.streams)) root.streams = data.streams
                } catch (e) {
                    console.warn("AudioService parse error:", e)
                }
            }
        }
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
    function setStreamVolume(index, pct) {
        const val = Math.max(0, Math.min(150, Math.round(pct)))
        cmdProc.command = ["pactl", "set-sink-input-volume", String(index), val + "%"]
        cmdProc.running = true
    }

    function toggleStreamMute(index) {
        cmdProc.command = ["pactl", "set-sink-input-mute", String(index), "toggle"]
        cmdProc.running = true
    }

    Process {
        id: cmdProc
        onExited: root.refresh()
    }

    Component.onCompleted: refresh()
}
