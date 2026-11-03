pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ==========================================================================
// PluginService.qml — discovers Edots plugins and exposes them to the shell.
//
// The filesystem work lives in scripts/plugins.py:
//   • list  — validate plugin.json manifests and merge enable state
//   • set   — flip one plugin on/off in ~/.config/quickshell/plugins.json
//
// Plugins can contribute:
//   • a surface  (opened with `edots plugin open <id>` or `plugin:<id>`)
//   • a bar item (placed in leading / center / trailing)
//
// Plugin QML is trusted and runs with your user rights — there is no sandbox.
// ==========================================================================
Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("scripts/plugins.py")
    readonly property string statePath: Quickshell.env("HOME") + "/.config/quickshell/plugins.json"

    property var plugins: []
    property var errors: []
    property string userDir: Quickshell.env("HOME") + "/.config/edots/plugins"
    property string bundledDir: ""
    property bool loading: false
    property bool saving: false
    property string error: ""

    // Enabled plugins that can open a surface / add a bar item.
    readonly property var surfaces: (plugins || []).filter(function (p) {
        return p && p.enabled && p.surface
    })
    readonly property var barPlugins: (plugins || []).filter(function (p) {
        return p && p.enabled && p.bar
    })
    readonly property var barPluginsSorted: (barPlugins || []).slice().sort(function (a, b) {
        return (a.bar.order || 0) - (b.bar.order || 0)
            || String(a.name).localeCompare(String(b.name))
    })

    property string _listOut: ""
    property string _setOut: ""
    property string _setErr: ""

    function ensure() {}

    function byId(id) {
        return (plugins || []).find(function (p) { return p.id === id }) || null
    }

    // Only enabled plugins are allowed to open a surface.
    function surfaceFor(id) {
        return (surfaces || []).find(function (p) { return p.id === id }) || null
    }

    function hasSurface(id) {
        return !!surfaceFor(id)
    }

    function surfaceQml(id) {
        const plugin = surfaceFor(id)
        return (plugin && plugin.surface && plugin.surface.qml)
            ? encodeURI("file://" + plugin.surface.qml) : ""
    }

    function barQml(plugin) {
        return (plugin && plugin.bar && plugin.bar.qml)
            ? encodeURI("file://" + plugin.bar.qml) : ""
    }

    function barPluginsFor(position) {
        return (barPluginsSorted || []).filter(function (p) {
            return p.bar && p.bar.position === position
        })
    }

    function surfaceId(plugin) {
        return plugin ? "plugin:" + plugin.id : ""
    }

    function surfaceUrl(plugin) {
        return plugin && plugin.surface && plugin.surface.qml
            ? encodeURI("file://" + plugin.surface.qml) : ""
    }

    function refresh() {
        if (listProc.running) return
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
                error = "Plugin scan failed (" + code + ")"
            return
        }

        let data
        try { data = JSON.parse(raw) }
        catch (e) {
            error = "Could not parse the plugin list"
            plugins = []
            errors = []
            return
        }

        if (!data || data.ok === false) {
            error = (data && data.error) ? data.error : "Plugin scan failed"
            plugins = []
            errors = []
            return
        }

        plugins = data.plugins || []
        errors = data.errors || []
        if (typeof data.userDir === "string" && data.userDir.length > 0)
            userDir = data.userDir
        if (typeof data.bundledDir === "string")
            bundledDir = data.bundledDir
    }

    function setEnabled(id, enabled) {
        if (saving) return false
        const plugin = byId(id)
        if (!plugin) return false

        const next = !!enabled
        // Optimistic update so the switch reacts immediately; a failed write
        // is corrected by the refresh below.
        plugins = (plugins || []).map(function (p) {
            return p.id === id ? Object.assign({}, p, { enabled: next }) : p
        })

        saving = true
        error = ""
        _setOut = ""
        _setErr = ""
        setProc.command = ["python3", root.helper, "set", id, next ? "on" : "off"]
        setProc.running = true
        return true
    }

    function _finishSet(code) {
        saving = false
        let data = null
        try { data = JSON.parse(String(_setOut || "")) }
        catch (e) { data = null }

        if (code === 0 && data && data.ok === true) {
            debounce.restart()
            return
        }

        error = (data && data.error) ? data.error
            : (String(_setErr || "").trim() || ("Could not update the plugin (" + code + ")"))
        debounce.restart()
    }

    function openFolder() {
        Quickshell.execDetached(["python3", helper, "open"])
    }

    Component.onCompleted: refresh()

    Process {
        id: listProc
        command: ["python3", root.helper, "list"]
        stdout: StdioCollector { onStreamFinished: root._listOut = text }
        stderr: StdioCollector {
            onStreamFinished: {
                const message = text.trim()
                if (message.length > 0) root.error = message
            }
        }
        onExited: (code, status) => root._finishList(code)
    }

    Process {
        id: setProc
        command: []
        stdout: StdioCollector { onStreamFinished: root._setOut = text }
        stderr: StdioCollector { onStreamFinished: root._setErr = text }
        onExited: (code, status) => root._finishSet(code)
    }

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }

    Timer {
        id: debounce
        interval: 180
        repeat: false
        onTriggered: root.refresh()
    }
}
