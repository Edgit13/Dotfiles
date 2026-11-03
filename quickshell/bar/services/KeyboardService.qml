pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// KeyboardService — розкладки клавіатури системи (MangoWC) + яка зараз активна.
//   • список:  xkb_rules_layout з ~/.config/mango/input.conf  (fallback: $XKB_DEFAULT_LAYOUT → "us")
//   • активна: `mmsg get keyboardlayout` (JSON; старий mmsg: `mmsg -g -k`), опитується раз на ~1 с
//   • зміна:   `mmsg dispatch switch_keyboard_layout` (новий mmsg) / `mmsg -d switch_keyboard_layout` (старий)
// EDOTS_BAR_DEBUG=1 → у лог пишеться сирий вивід mmsg.
Singleton {
    id: root

    property var layouts: ["us"]          // коди з конфіга, напр. ["us","ua"]
    property string activeRaw: ""         // як відповів mmsg (напр. "Ukrainian")
    readonly property bool debug: Quickshell.env("EDOTS_BAR_DEBUG") === "1"

    // назва/код з mmsg → код зі списку layouts
    readonly property var _names: ({
        "english": "us", "us": "us", "en": "us",
        "ukrainian": "ua", "ua": "ua", "uk": "ua",
        "russian": "ru", "ru": "ru",
        "polish": "pl", "pl": "pl",
        "german": "de", "de": "de",
        "french": "fr", "fr": "fr",
        "spanish": "es", "es": "es"
    })
    readonly property var _full: ({
        "us": "English", "ua": "Українська", "ru": "Русский", "pl": "Polski",
        "de": "Deutsch", "fr": "Français", "es": "Español", "gb": "English (UK)"
    })

    function _toCode(raw) {
        const s = String(raw).trim().toLowerCase()
        if (!s) return ""
        if (layouts.indexOf(s) >= 0) return s
        for (const k in _names) if (s.indexOf(k) === 0 || s.indexOf("(" + k) >= 0) return _names[k]
        return s
    }

    readonly property string activeCode: _toCode(activeRaw)
    readonly property int activeIndex: layouts.indexOf(activeCode)
    function nameOf(code) { return _full[code] || code.toUpperCase() }
    readonly property string activeName: activeRaw ? nameOf(activeCode) : ""

    // json: {"keyboardlayout":"us"} / "us" / {"layout":"ua"};  legacy: `eDP-1 kb_layout us`
    function _parse(body) {
        try {
            const o = JSON.parse(body)
            if (typeof o === "string") return o.trim()
            if (o && typeof o === "object") {
                for (const k in o) if (typeof o[k] === "string" && o[k].length > 0) return o[k].trim()
            }
        } catch (e) {}
        const m = body.match(/kb_layout\s*[:=]?\s*(.*)$/i)
        return (m ? m[1] : body).trim()
    }

    function refresh() { if (!probe.running) probe.running = true }

    function next() {
        if (MangoService.backend === "legacy") Quickshell.execDetached(["mmsg", "-d", "switch_keyboard_layout"])
        else Quickshell.execDetached(["mmsg", "dispatch", "switch_keyboard_layout"])
        refreshSoon.restart()
    }

    Timer { id: refreshSoon; interval: 120; onTriggered: root.refresh() }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }

    Process {
        id: probe
        command: ["sh", "-c",
            "f=\"$HOME/.config/mango/input.conf\"; " +
            "l=$(grep -E '^[[:space:]]*xkb_rules_layout[[:space:]]*=' \"$f\" 2>/dev/null | tail -n1 | cut -d= -f2 | tr -d ' \\r'); " +
            "[ -z \"$l\" ] && l=\"$XKB_DEFAULT_LAYOUT\"; [ -z \"$l\" ] && l=us; " +
            "echo \"LAYOUTS:$l\"; " +
            "if [ \"$1\" = json ]; then mmsg get keyboardlayout 2>/dev/null; else mmsg -g -k 2>/dev/null | grep -i kb_layout; fi | head -n1 | sed 's/^/ACTIVE:/'",
            "sh", MangoService.backend === "legacy" ? "legacy" : "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const ln = lines[i]
                    if (ln.indexOf("LAYOUTS:") === 0) {
                        const arr = ln.substring(8).split(",").map(x => x.trim()).filter(x => x.length > 0)
                        if (arr.length > 0 && arr.join() !== root.layouts.join()) root.layouts = arr
                    } else if (ln.indexOf("ACTIVE:") === 0) {
                        const body = ln.substring(7)
                        const v = root._parse(body)
                        if (v !== root.activeRaw) {
                            root.activeRaw = v
                            if (root.debug) console.log("[Keyboard] raw:", body, "→", root.activeCode)
                        }
                    }
                }
            }
        }
    }
}
