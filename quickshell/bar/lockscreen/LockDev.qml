import Quickshell
import Quickshell.Io
import QtQuick
import "root:/settings"
import "root:/services"

// LockDev — «режим розробника» локскріну: невеликий білий список БЕЗПЕЧНИХ гарячих клавіш,
// що працюють поки екран заблоковано. Нічого з цього не розблоковує сесію й не запускає довільних команд.
//   Print / Ctrl+Print  → скріншот (у файл / ще й у буфер)
//   медіа-клавіші       → пауза, наступний, попередній
//   гучність            → ±5 % (до 100 %), mute
//   яскравість          → ±5 %
// Увімкнення: Settings → Локскрін → «Режим розробника». Вимкнено за замовчуванням.
Item {
    id: dev
    visible: false

    readonly property bool enabled: Settings.get("lockscreen", "devMode") === true
    function on(key) { return Settings.get("lockscreen", key) !== false }

    property string toast: ""
    Timer { id: toastTimer; interval: 2200; onTriggered: dev.toast = "" }
    function say(t) { toast = t; toastTimer.restart() }
    function run(cmd) { Quickshell.execDetached(cmd) }

    readonly property string shotDir: String(Settings.get("capture", "screenshotDir") || "~/Pictures/Screenshots")
        .replace("~", Quickshell.env("HOME"))

    function shot(copy) {
        run(["bash", "-c",
             'mkdir -p "$1"; f="$1/lockscreen-$(date +%Y%m%d-%H%M%S).png"; ' +
             'exec >>/tmp/edots-lockdev.log 2>&1; echo "--- $(date)"; if grim "$f"; then [ "$2" = 1 ] && wl-copy --type image/png < "$f"; ' +
             'notify-send -a Edots "Screenshot" "$f"; else notify-send -u critical -a Edots "Screenshot failed"; fi',
             "_", shotDir, copy ? "1" : "0"])
        say(copy ? "Screenshot → file + clipboard" : "Screenshot → file")
    }

    function volume(up) {
        if (up) run(["bash", "-c", 'v=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -o "[0-9]*%" | head -1 | tr -d %); [ "${v:-0}" -lt 100 ] && pactl set-sink-volume @DEFAULT_SINK@ +5%'])
        else run(["pactl", "set-sink-volume", "@DEFAULT_SINK@", "-5%"])
        say(up ? "Volume +5%" : "Volume −5%")
    }
    function brightness(up) {
        run(["brightnessctl", "-c", "backlight", "set", up ? "5%+" : "5%-"])
        say(up ? "Brightness +5%" : "Brightness −5%")
    }

    // Назва «службової» клавіші/комбінації для показу (символи пароля НІКОЛИ не показуються)
    function describe(ev) {
        const k = ev.key
        const mods = ev.modifiers
        const pretty = []
        if (mods & Qt.ControlModifier) pretty.push("Ctrl")
        if (mods & Qt.AltModifier)     pretty.push("Alt")
        if (mods & Qt.MetaModifier)    pretty.push("Super")
        if (mods & Qt.ShiftModifier)   pretty.push("Shift")
        if (k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Meta || k === Qt.Key_Shift
            || k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Backspace
            || k === Qt.Key_Escape || k === Qt.Key_Tab || k === Qt.Key_Space) return ""
        let name = ""
        if (k >= Qt.Key_F1 && k <= Qt.Key_F35) name = "F" + (k - Qt.Key_F1 + 1)
        else if (k === Qt.Key_Print) name = "Print"
        else if (k >= 0x01000000) name = "key 0x" + k.toString(16)
        else if ((mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && k >= 0x20 && k < 0x7f)
            name = String.fromCharCode(k).toUpperCase()
        else return ""                                   // звичайний друк → це може бути пароль
        pretty.push(name)
        return pretty.join(" + ")
    }


    // ── комбінації: власні + з конфігу Mango ─────────────
    readonly property int modMask: Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier | Qt.MetaModifier
    property var imported: []          // [{ mods, key, action }] з ~/.config/mango/config.conf

    function keyFromName(n) {
        n = String(n).trim().toLowerCase()
        const table = {
            "print": Qt.Key_Print, "sysrq": Qt.Key_Print,
            "xf86audioplay": Qt.Key_MediaTogglePlayPause, "xf86audiopause": Qt.Key_MediaTogglePlayPause,
            "xf86audionext": Qt.Key_MediaNext, "xf86audioprev": Qt.Key_MediaPrevious,
            "xf86audioraisevolume": Qt.Key_VolumeUp, "xf86audiolowervolume": Qt.Key_VolumeDown,
            "xf86audiomute": Qt.Key_VolumeMute,
            "xf86monbrightnessup": Qt.Key_MonBrightnessUp, "xf86monbrightnessdown": Qt.Key_MonBrightnessDown
        }
        if (table[n] !== undefined) return table[n]
        if (/^f([1-9]|1[0-2])$/.test(n)) return Qt.Key_F1 + parseInt(n.substring(1)) - 1
        if (n.length === 1) return n.toUpperCase().charCodeAt(0)
        return -1
    }
    function modsFromString(m) {
        let mask = 0
        const parts = String(m).toLowerCase().split(/[+\s]+/)
        for (let i = 0; i < parts.length; i++) {
            const p = parts[i]
            if (p === "super" || p === "mod4" || p === "logo" || p === "win" || p === "meta") mask |= Qt.MetaModifier
            else if (p === "shift") mask |= Qt.ShiftModifier
            else if (p === "ctrl" || p === "control") mask |= Qt.ControlModifier
            else if (p === "alt" || p === "mod1") mask |= Qt.AltModifier
        }
        return mask
    }
    // "Super+Shift+U" → { mods, key } або null
    function parseCombo(str) {
        str = String(str || "").trim()
        if (str.length === 0) return null
        const parts = str.split("+")
        const key = keyFromName(parts[parts.length - 1])
        if (key < 0) return null
        return { mods: modsFromString(parts.slice(0, -1).join("+")), key: key }
    }

    function classify(cmd) {
        const c = String(cmd)
        if (/screenshot|screentool|\bgrim\b|flameshot|shotgun|scrot/i.test(c)) return /clip|copy/i.test(c) ? "shotcopy" : "shot"
        if (/brightness|backlight/i.test(c)) return /(\+|up|raise|inc)/i.test(c) ? "brup" : "brdown"
        if (/(pactl|wpctl|pamixer|volume)/i.test(c)) {
            if (/mute/i.test(c)) return "mute"
            return /(\+|up|raise|inc)/i.test(c) ? "volup" : "voldown"
        }
        if (/play-?pause|play_pause|togglePlay/i.test(c)) return "playpause"
        if (/\bnext\b/i.test(c) && /(player|media|track|mpris)/i.test(c)) return "next"
        if (/(prev|previous)\b/i.test(c) && /(player|media|track|mpris)/i.test(c)) return "prev"
        return ""
    }

    function parseMango(txt) {
        const out = []
        const lines = String(txt).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const m = lines[i].match(/^\s*bind[a-z]*\s*=\s*([^,]*),\s*([^,]+),\s*([^,]+),\s*(.*)$/i)
            if (!m || !/exec|spawn/i.test(m[3])) continue
            const action = classify(m[4])
            const key = keyFromName(m[2])
            if (action === "" || key < 0) continue
            out.push({ mods: modsFromString(m[1]), key: key, action: action })
        }
        imported = out
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/mango/config.conf"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onTextChanged: dev.parseMango(text())
    }

    function allCombos() {
        const list = []
        if (Settings.get("lockscreen", "devImportMango") !== false) for (let i = 0; i < imported.length; i++) list.push(imported[i])
        const a = parseCombo(Settings.get("lockscreen", "devKeyScreenshot"))
        if (a) list.push({ mods: a.mods, key: a.key, action: "shot" })
        const b = parseCombo(Settings.get("lockscreen", "devKeyScreenshotCopy"))
        if (b) list.push({ mods: b.mods, key: b.key, action: "shotcopy" })
        return list
    }

    // виконати дію; false якщо вимкнена відповідною опцією
    function perform(action) {
        switch (action) {
        case "shot":      if (!on("devScreenshot")) return false; shot(false); return true
        case "shotcopy":  if (!on("devScreenshot")) return false; shot(true); return true
        case "playpause": if (!on("devMedia")) return false; MediaService.togglePlay(); say("Play / Pause"); return true
        case "next":      if (!on("devMedia")) return false; MediaService.next(); say("Next track"); return true
        case "prev":      if (!on("devMedia")) return false; MediaService.previous(); say("Previous track"); return true
        case "volup":     if (!on("devVolume")) return false; volume(true); return true
        case "voldown":   if (!on("devVolume")) return false; volume(false); return true
        case "mute":      if (!on("devVolume")) return false; run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]); say("Mute toggle"); return true
        case "brup":      if (!on("devBrightness")) return false; brightness(true); return true
        case "brdown":    if (!on("devBrightness")) return false; brightness(false); return true
        }
        return false
    }

    // true → клавішу оброблено
    function handle(ev) {
        if (!enabled) return false
        // діагностика: лише службові/комбіновані клавіші, ніколи звичайні символи пароля
        if (ev.key >= 0x01000000 || (ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            console.log("[lockdev] key=0x" + ev.key.toString(16) + " mods=0x" + ev.modifiers.toString(16))
        const combos = allCombos()
        for (let i = 0; i < combos.length; i++) {
            if (ev.key === combos[i].key && (ev.modifiers & modMask) === combos[i].mods && !ev.isAutoRepeat
                || (ev.key === combos[i].key && (ev.modifiers & modMask) === combos[i].mods
                    && ev.isAutoRepeat && /^(volup|voldown|brup|brdown)$/.test(combos[i].action))) {
                if (perform(combos[i].action)) { ev.accepted = true; return true }
            }
        }
        const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0
        switch (ev.key) {
        case Qt.Key_Print:
            if (on("devScreenshot")) { shot(ctrl); ev.accepted = true; return true }
            break
        case Qt.Key_MediaTogglePlayPause:
        case Qt.Key_MediaPlay:
        case Qt.Key_MediaPause:
            if (on("devMedia")) { MediaService.togglePlay(); say("Play / Pause"); ev.accepted = true; return true }
            break
        case Qt.Key_MediaNext:
            if (on("devMedia")) { MediaService.next(); say("Next track"); ev.accepted = true; return true }
            break
        case Qt.Key_MediaPrevious:
            if (on("devMedia")) { MediaService.previous(); say("Previous track"); ev.accepted = true; return true }
            break
        case Qt.Key_VolumeUp:
            if (on("devVolume")) { volume(true); ev.accepted = true; return true }
            break
        case Qt.Key_VolumeDown:
            if (on("devVolume")) { volume(false); ev.accepted = true; return true }
            break
        case Qt.Key_VolumeMute:
            if (on("devVolume")) { run(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"]); say("Mute toggle"); ev.accepted = true; return true }
            break
        case Qt.Key_MonBrightnessUp:
            if (on("devBrightness")) { brightness(true); ev.accepted = true; return true }
            break
        case Qt.Key_MonBrightnessDown:
            if (on("devBrightness")) { brightness(false); ev.accepted = true; return true }
            break
        }
        if (Settings.get("lockscreen", "devShowKeys") === true) {
            const d = describe(ev)
            if (d.length > 0) say("⌨  " + d)
        }
        return false
    }
}
