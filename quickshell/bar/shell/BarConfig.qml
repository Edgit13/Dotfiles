pragma Singleton
import "root:/settings"
import "root:/theme"
import Quickshell
import QtQuick

// BarConfig — тонкий фасад над Settings (категорії "bar", "modules").
Singleton {
    id: root

    readonly property var positions: ["top", "bottom", "left", "right"]
    readonly property var modes: ["compact", "expanded", "morphing"]
    readonly property var styles: ["full", "pill", "islands"]
    // як відкриваються модулі (поверхні): morph — ростуть із бару/пілла, window — плаваюча картка біля бару,
    // spotlight — по центру екрана зі затемненням, drawer — бокова шторка
    readonly property var openModes: ["morph", "window", "spotlight", "drawer"]

    readonly property string position: _valid(Settings.get("bar", "position"), positions, "top")
    readonly property string mode:     _valid(Settings.get("bar", "mode"), modes, "compact")
    readonly property string style:    _valid(Settings.get("bar", "style"), styles, "full")
    readonly property bool islands:     style === "islands"
    readonly property string openMode: _valid(Settings.get("bar", "openMode"), openModes, "morph")
    // морф працює для КОЖНОГО дизайну: смуга, пілл і острівці (кожна капсула окремо)
    readonly property bool pillMorph:    style === "pill" && openMode === "morph"
    readonly property bool fullMorph:    style === "full" && openMode === "morph"
    readonly property bool islandsMorph: style === "islands" && openMode === "morph"

    // Панелі, які вміє морфити бар (решта йде через SurfaceOverlay).
    readonly property var morphPanels: ["launcher", "wallpaper", "clipboard", "mixer", "audio", "media",
                                        "wifi", "bluetooth", "power", "updates", "diagnostics",
                                        "binds", "resources", "dashboard"]
    function canMorph(name) {
        return morphPanels.indexOf(name) >= 0 || String(name || "").indexOf("plugin:") === 0
    }
    readonly property int elevation:   Math.max(0, Math.min(5, Math.round(Settings.get("bar", "elevation"))))
    readonly property bool pillHover:         Settings.get("bar", "pillHover") !== false
    readonly property int pillEdgeGap:        Math.max(0, Math.min(32, Math.round(Settings.get("bar", "pillEdgeGap") ?? 8)))
    readonly property bool pillCloseOnEscape: Settings.get("bar", "pillCloseOnEscape") !== false
    readonly property var perMonitor:  Settings.get("bar", "perMonitor") || ({})
    // трей-іконки, сховані з бару (показуються в overflow-панелі за шевроном)
    readonly property var trayHidden:  Settings.get("bar", "trayHidden") || []
    function toggleTrayHidden(key) {
        if (!key) return
        const cur = trayHidden.slice()
        const i = cur.indexOf(key)
        if (i >= 0) cur.splice(i, 1); else cur.push(key)
        Settings.set("bar", "trayHidden", cur)
    }
    readonly property string mainMonitor: Settings.get("bar", "mainMonitor") || ""

    function _valid(v, list, fb) { return list.indexOf(v) >= 0 ? v : fb }
    function _mon(name) { return perMonitor[name] || ({}) }

    function positionFor(name) { return _valid(_mon(name).position, positions, position) }
    function modeFor(name)     { return _valid(_mon(name).mode, modes, mode) }

    function thicknessFor(name) {
        return modeFor(name) === "expanded" ? Theme.components.islandExpressive : Theme.components.islandCompact
    }

    // Тепер модулі слухаються перемикачів у Settings
    function moduleEnabled(key) {
        return Settings.get("modules", key) !== false
    }

    function set(key, value) {
        if (key === "position" && positions.indexOf(value) < 0) return console.warn("[Bar] position: " + positions.join("|"))
        if (key === "style" && styles.indexOf(value) < 0) return console.warn("[Bar] style: " + styles.join("|"))
        if (key === "openMode" && openModes.indexOf(value) < 0) return console.warn("[Bar] openMode: " + openModes.join("|"))
        if (key === "mode" && modes.indexOf(value) < 0) return console.warn("[Bar] mode: " + modes.join("|"))
        Settings.set("bar", key, value)
    }

    function setMonitor(name, key, value) {
        const next = JSON.parse(JSON.stringify(perMonitor))
        const cur = next[name] || {}
        if (value === "") delete cur[key]; else cur[key] = value
        if (Object.keys(cur).length === 0) delete next[name]; else next[name] = cur
        Settings.set("bar", "perMonitor", next)
    }
}
