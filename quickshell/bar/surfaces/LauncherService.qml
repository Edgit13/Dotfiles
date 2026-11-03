pragma Singleton
import "root:/settings"
import "LauncherCalc.js" as Calc
import Quickshell
import Quickshell.Io
import QtQuick

// ==========================================================================
// LauncherService.qml — дані та дії розширеного лаунчера.
//
// Один рядок пошуку, кілька провайдерів:
//   (порожньо)   застосунки
//   2+2 / =2+2   калькулятор (Enter копіює результат)
//   :smile       емодзі (Enter копіює)
//   /report      файли (Enter відкриває, fd під капотом)
//   >htop        команда (Enter запускає, Ctrl+Enter — у терміналі)
//   f:term       файли без ведучого слеша
//
// Результат — плаский масив typed-записів {kind: app|calc|emoji|file|command|info}.
// Важкі провайдери (файли, емодзі) живуть у scripts/launcher-kit.py.
// ==========================================================================
Singleton {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts/launcher-kit.py"

    property string query: ""
    property int selectedIndex: 0
    property var appIndex: []

    property var emojiIndex: []
    property bool emojiReady: false
    property bool emojiLoading: false

    property var fileResults: []
    property bool filesBusy: false
    property string fileError: ""

    property var _pendingFile: null
    property string _lastFileQuery: ""

    // ── розбір запиту ──────────────────────────────────────────────────

    readonly property var parsed: {
        const raw = query
        const q = raw.trim()

        if (q.startsWith(">"))
            return { mode: "command", payload: q.slice(1).trim() }
        if (q.startsWith(":"))
            return { mode: "emoji", payload: q.slice(1).trim() }
        if (q.startsWith("@"))
            return { mode: "emoji", payload: q.slice(1).trim() }
        if (q.startsWith("=")) {
            const body = q.slice(1).trim()
            const result = Calc.evaluate(body)
            return {
                mode: "calc",
                payload: body,
                value: result.ok ? result.value : "",
                calcError: result.ok ? "" : result.error
            }
        }
        if (q.startsWith("f:"))
            return { mode: "files", payload: q.slice(2).trim() }
        if (q.startsWith("/")) {
            // "/" is the mode trigger, not part of the pattern. A pasted
            // absolute path (start /home, /etc…) keeps its leading slash.
            const rest = q.slice(1)
            const top = rest.split("/")[0]
            const absolute = ["home", "root", "etc", "usr", "var", "opt", "tmp",
                              "mnt", "media", "srv", "run", "boot"].indexOf(top) >= 0
            return { mode: "files", payload: absolute ? "/" + rest : rest }
        }
        if (q.startsWith("~/"))
            return { mode: "files", payload: q }

        // Автоматичний калькулятор: 2+2, sqrt(16), 3*(4+1)…
        if (q.length > 0 && Calc.looksLikeMath(q)) {
            const result = Calc.evaluate(q)
            if (result.ok)
                return { mode: "calc", payload: q, value: result.value, calcError: "" }
        }

        if (q.indexOf("/") >= 0)
            return { mode: "files", payload: q }

        return { mode: "apps", payload: q }
    }

    readonly property string mode: parsed.mode

    // ── результати ─────────────────────────────────────────────────────

    readonly property var results: {
        const p = parsed
        if (p.mode === "command") return commandResults(p.payload)
        if (p.mode === "calc") return calcResults(p)
        if (p.mode === "emoji") return emojiResults(p.payload)
        if (p.mode === "files") return fileResults
        return appResults(p.payload)
    }

    onQueryChanged: selectedIndex = 0

    onParsedChanged: root._updateMode()

    onResultsChanged: {
        if (results.length === 0) {
            selectedIndex = 0
        } else if (selectedIndex >= results.length) {
            selectedIndex = results.length - 1
        } else if (selectedIndex < 0) {
            selectedIndex = 0
        }
    }

    function _updateMode() {
        // Use parsed.mode, not the derived `mode` property: when `parsed`
        // changes this handler can run before the dependent binding updates.
        const p = parsed
        if (p.mode === "files") {
            if (p.payload.length === 0) {
                fileResults = []
                return
            }
            fileDebounce.restart()
        } else {
            fileDebounce.stop()
            _pendingFile = null
            if (fileResults.length > 0) fileResults = []
        }

        if (p.mode === "emoji") ensureEmoji()
    }

    // ── застосунки ─────────────────────────────────────────────────────

    function appScore(app, q) {
        if (!q) return 0
        const name = String(app.name || "").toLowerCase()
        const generic = String(app.genericName || "").toLowerCase()
        const id = String(app.id || "").toLowerCase()
        const exec = String(app.exec || "").toLowerCase()
        const categories = String(app.categories || "").toLowerCase()

        if (name === q) return 1000
        if (name.startsWith(q)) return 850
        if (generic.startsWith(q)) return 650
        if (name.split(/[\s\-_.]+/).some(word => word.startsWith(q))) return 700
        if (id.startsWith(q)) return 500
        if (name.indexOf(q) >= 0) return 450
        if (generic.indexOf(q) >= 0) return 350
        if (id.indexOf(q) >= 0 || exec.indexOf(q) >= 0) return 250
        if (categories.indexOf(q) >= 0) return 120
        return -1
    }

    function appResults(term) {
        const q = String(term || "").trim().toLowerCase()
        const apps = (appIndex || []).filter(app => !!app && !!app.name)
        if (!q) return apps.map(app => Object.assign({ kind: "app" }, app))

        const scored = []
        for (let i = 0; i < apps.length; i++) {
            const score = appScore(apps[i], q)
            if (score < 0) continue
            scored.push({ score: score, index: i, app: apps[i] })
        }
        scored.sort((a, b) => b.score - a.score || a.index - b.index)
        return scored.map(item => Object.assign({ kind: "app" }, item.app))
    }

    // ── калькулятор ────────────────────────────────────────────────────

    function calcResults(p) {
        if (p.value !== undefined && p.value !== "") {
            return [{
                kind: "calc",
                title: p.value,
                value: p.value,
                expression: p.payload
            }]
        }
        return [{
            kind: "info",
            title: p.payload.length > 0 ? "Invalid expression" : "Type an expression",
            subtitle: p.calcError || "Example: 12 * (3 + 4)"
        }]
    }

    // ── емодзі ─────────────────────────────────────────────────────────

    function ensureEmoji() {
        if (emojiReady || emojiLoading) return
        emojiLoading = true
        emojiProc.running = true
    }

    function emojiResults(term) {
        if (!emojiReady) return []
        const q = String(term || "").trim().toLowerCase()
        const source = emojiIndex || []

        if (q.length === 0) {
            return source.slice(0, 80).map(item => ({
                kind: "emoji", char: item.char, name: item.name
            }))
        }

        const scored = []
        for (let i = 0; i < source.length; i++) {
            const item = source[i]
            const name = String(item.name || "").toLowerCase()
            const search = String(item.search || name)
            let score = -1

            if (name === q) score = 1000
            else if (name.startsWith(q)) score = 850
            else if (search.startsWith(q)) score = 750
            else if (name.split(/[\s\-]+/).some(word => word.startsWith(q))) score = 650
            else if (search.indexOf(" " + q) >= 0) score = 520
            else if (name.indexOf(q) >= 0) score = 420
            else if (search.indexOf(q) >= 0) score = 300

            if (score < 0) continue
            scored.push({ score: score, index: i, item: item })
        }
        scored.sort((a, b) => b.score - a.score || a.index - b.index)
        return scored.slice(0, 80).map(entry => ({
            kind: "emoji", char: entry.item.char, name: entry.item.name
        }))
    }

    // ── файли ──────────────────────────────────────────────────────────

    function _runFileSearch(term) {
        if (term.length === 0) {
            fileResults = []
            return
        }
        if (fileProc.running) {
            _pendingFile = term
            return
        }
        _lastFileQuery = term
        filesBusy = true
        fileError = ""
        fileProc.command = ["python3", helper, "files", "--query", term, "--limit", "48"]
        fileProc.running = true
    }

    function _consumeFiles(raw) {
        let data
        try { data = JSON.parse(raw) }
        catch (e) { fileError = "file search failed"; return }
        if (!data || data.ok === false) {
            fileError = (data && data.error) ? data.error : "file search failed"
            return
        }
        // Відповідь на застарілий запит ігноруємо: pending перезапустить пошук.
        if (parsed.mode === "files" && parsed.payload === _lastFileQuery)
            fileResults = data.items || []
    }

    // ── команди ────────────────────────────────────────────────────────

    function commandResults(command) {
        if (!command || command.length === 0) return []
        return [
            { kind: "command", command: command, terminal: false, title: command },
            { kind: "command", command: command, terminal: true, title: command }
        ]
    }

    // ── дії ────────────────────────────────────────────────────────────

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = (selectedIndex + delta + results.length) % results.length
    }

    function activate(entry) {
        if (!entry) return false
        switch (entry.kind) {
        case "calc":
            copyText(entry.value)
            return true
        case "emoji":
            copyText(entry.char)
            return true
        case "file":
            if (entry.path) Quickshell.execDetached(["xdg-open", entry.path])
            return true
        case "command":
            runCommand(entry.command, entry.terminal === true)
            return true
        case "info":
            return false
        default:
            launch(entry)
            return true
        }
    }

    function activateSelected(preferTerminal) {
        if (results.length === 0) return false
        const index = Math.max(0, Math.min(selectedIndex, results.length - 1))
        let entry = results[index]
        if (preferTerminal && entry.kind === "command" && !entry.terminal)
            entry = { kind: "command", command: entry.command, terminal: true, title: entry.command }
        return activate(entry)
    }

    function copyText(text) {
        if (text === undefined || text === null || text === "") return
        Quickshell.execDetached(["wl-copy", String(text)])
    }

    function runCommand(command, terminal) {
        if (!command) return
        if (terminal) {
            const term = Settings.get("general", "terminalCommand") || "ghostty"
            Quickshell.execDetached([term, "-e", "sh", "-lc", command])
        } else {
            Quickshell.execDetached(["sh", "-lc", command])
        }
    }

    function launch(app) {
        if (!app || !app.path)
            return

        // Беремо команду з .desktop файлу і прибираємо заповнювачі (наприклад, %U, %f)
        let cmd = app.exec ? app.exec.replace(/%[fFuUdDnNickvm]/g, "").trim() : ""

        if (cmd.length > 0) {
            Quickshell.execDetached(["sh", "-c", cmd])
        } else {
            Quickshell.execDetached(["gtk-launch", app.id.replace(/\.desktop$/, "")])
        }
    }

    function reset() {
        query = ""
        selectedIndex = 0
        fileResults = []
        if (!scanAppsProc.running)
            scanAppsProc.running = true
    }

    // ── процеси ────────────────────────────────────────────────────────

    Timer {
        id: fileDebounce
        interval: 220
        repeat: false
        onTriggered: root._runFileSearch(root.parsed.payload)
    }

    Process {
        id: scanAppsProc

        command: ["sh", "-c", "python3 - <<'PY'\nimport configparser, json, os, shlex\nfrom pathlib import Path\n\nsearch_dirs = []\nfor env_var in ('XDG_DATA_HOME',):\n    value = os.environ.get(env_var)\n    if value:\n        search_dirs.append(Path(value) / 'applications')\nsearch_dirs.append(Path.home() / '.local/share/applications')\nfor base in os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share').split(':'):\n    if base:\n        search_dirs.append(Path(base) / 'applications')\n\napps_by_id = {}\nfor directory in search_dirs:\n    if not directory.is_dir():\n        continue\n    for path in directory.rglob('*.desktop'):\n        desktop_id = path.name\n        cp = configparser.ConfigParser(interpolation=None, strict=False)\n        cp.optionxform = str\n        try:\n            cp.read(path, encoding='utf-8')\n        except Exception:\n            continue\n        if 'Desktop Entry' not in cp:\n            continue\n        sec = cp['Desktop Entry']\n        if sec.get('Type', '').strip() != 'Application':\n            continue\n        if sec.get('NoDisplay', '').strip().lower() == 'true':\n            continue\n        if sec.get('Hidden', '').strip().lower() == 'true':\n            continue\n        name = sec.get('Name', '').strip()\n        exec_line = sec.get('Exec', '').strip()\n        if not name or not exec_line:\n            continue\n        if desktop_id in apps_by_id and str(path).startswith(str(Path.home())):\n            pass\n        apps_by_id[desktop_id] = {\n            'id': desktop_id,\n            'name': name,\n            'genericName': sec.get('GenericName', '').strip(),\n            'icon': sec.get('Icon', '').strip(),\n            'exec': exec_line,\n            'categories': sec.get('Categories', '').strip(),\n            'path': str(path),\n        }\n\napps = sorted(apps_by_id.values(), key=lambda app: app['name'].lower())\nprint(json.dumps(apps, ensure_ascii=False))\nPY"]

        stdout: SplitParser {
            onRead: data => {
                try {
                    const parsed = JSON.parse(data)
                    root.appIndex = Array.isArray(parsed) ? parsed : []
                } catch (error) {
                    console.warn("LauncherService: failed to parse app index", error)
                    root.appIndex = []
                }
            }
        }
    }

    Process {
        id: fileProc
        command: ["python3", root.helper, "files", "--query", "", "--limit", "48"]
        stdout: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root._consumeFiles(text)
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim().length > 0) root.fileError = text.trim()
        }
        onExited: (code, status) => {
            root.filesBusy = false
            if (root._pendingFile !== null) {
                const next = root._pendingFile
                root._pendingFile = null
                if (next !== root._lastFileQuery)
                    root._runFileSearch(next)
            }
        }
    }

    Process {
        id: emojiProc
        command: ["python3", root.helper, "emoji"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    if (data && data.ok && Array.isArray(data.items)) {
                        root.emojiIndex = data.items
                        root.emojiReady = true
                    }
                } catch (error) {
                    console.warn("LauncherService: failed to parse emoji index", error)
                }
            }
        }
        onExited: (code, status) => { root.emojiLoading = false }
    }

    Component.onCompleted: scanAppsProc.running = true
}
