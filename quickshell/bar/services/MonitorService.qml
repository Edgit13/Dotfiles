pragma Singleton
import "root:/settings"
import "root:/states"
import Quickshell
import Quickshell.Io
import QtQuick

// MonitorService — міст до scripts/procwatch.py (окремий легкий процес-монітор).
//  • запускає демон, шле йому налаштування (monitor.*), приймає знімки/події;
//  • дає UI: top процесів, розклад Quickshell (потоки/діти), накладні витрати монітора;
//  • вимірює вартість компонентів шелла «скануванням»: по черзі вимикає компонент і дивиться, наскільки впав CPU;
//  • за подією relief від демона (користувач погодився у сповіщенні) вмикає ReliefState.
Singleton {
    id: root

    // скрипт шукаємо поруч із шеллом (~/.config/quickshell/bar/scripts) і в ~/.config/quickshell/scripts
    readonly property string launcher:
        'for d in "$HOME/.config/quickshell/bar/scripts" "$HOME/.config/quickshell/scripts"; do ' +
        '[ -f "$d/procwatch.py" ] && exec python3 "$d/procwatch.py"; done; ' +
        'echo "procwatch.py not found in ~/.config/quickshell/{bar/,}scripts" >&2; exit 127'
    function _g(key) { return Settings.get("monitor", key) }
    readonly property bool enabled: _g("enabled") !== false

    // ---- стан демона ----
    property bool ready: false
    property var top: []
    property var shell: null
    property var frozenList: []
    property real selfCpu: 0
    property real selfMem: 0
    property int ncpu: 1
    property string scope: "shell"
    property var events: []            // останні події: {ts, kind, name, ...}
    property bool reliefSuggested: false

    // ---- UI-підписники (швидкий режим 1 с, поки відкрито меню ресурсів) ----
    property int uiSubscribers: 0
    function uiSubscribe()   { uiSubscribers += 1 }
    function uiUnsubscribe() { uiSubscribers = Math.max(0, uiSubscribers - 1) }
    readonly property bool fast: uiSubscribers > 0 || scanning
    onFastChanged: send({ cmd: "ui", fast: fast })

    function ensure() { /* торкнутися singleton — запускає демон */ }

    // ---- конфіг → демон ----
    readonly property var cfgObj: ({
        cmd: "config",
        scope: _g("scope") || "shell",
        interval: Number(_g("interval") ?? 2),
        cpuLimit: Number(_g("cpuLimit") ?? 90),
        memLimit: Number(_g("memLimit") ?? 0),
        sustain: Number(_g("sustain") ?? 15),
        shellCpuLimit: Number(_g("shellCpuLimit") ?? 25),
        shellMemLimit: Number(_g("shellMemLimit") ?? 0),
        notify: _g("notify") !== false,
        cooldown: Number(_g("cooldown") ?? 180),
        action: _g("action") || "ask",
        freezeSeconds: Number(_g("freezeSeconds") ?? 30),
        protectSystem: _g("protectSystem") !== false,
        whitelist: String(_g("whitelist") || ""),
        overrides: String(_g("overrides") || ""),
        paused: GameModeState.active && _g("pauseInGame") !== false,
        reliefEnabled: _g("reliefEnabled") !== false,
        reliefAsk: _g("reliefAsk") !== false,
        reliefMinutes: Number(_g("reliefMinutes") ?? 10),
        lang: Settings.get("general", "language") || "uk"
    })
    onCfgObjChanged: pushConfig()
    function pushConfig() { send(cfgObj) }

    function send(o) { if (proc.running) proc.write(JSON.stringify(o) + "\n") }

    // ---- дії з UI ----
    function freeze(key, secs) { send({ cmd: "freeze", key: key, secs: secs || Number(_g("freezeSeconds") ?? 30) }) }
    function thaw(key)         { send({ cmd: "thaw", key: key }) }
    function thawAll()         { send({ cmd: "thawall" }) }
    function isUserWhitelisted(name) {
        return String(_g("whitelist") || "").split(",").map(s => s.trim().toLowerCase()).indexOf(String(name).toLowerCase()) >= 0
    }
    function toggleWhitelist(name) {
        const cur = String(_g("whitelist") || "").split(",").map(s => s.trim()).filter(s => s.length > 0)
        const i = cur.findIndex(s => s.toLowerCase() === String(name).toLowerCase())
        if (i >= 0) cur.splice(i, 1); else cur.push(name)
        Settings.set("monitor", "whitelist", cur.join(", "))
    }
    function startRelief(minutes) {
        ReliefState.start(minutes || Number(_g("reliefMinutes") ?? 10), "manual", costs)
        reliefSuggested = false
    }

    Connections {
        target: ReliefState
        function onStarted() { root.send({ cmd: "relief", active: true }) }
        function onStopped() { root.send({ cmd: "relief", active: false }) }
    }

    // ---- вимірювання вартості компонентів ----
    property var costs: ({})           // id → зекономлений CPU, % одного ядра
    property real costsTime: 0
    property bool scanning: false
    property string scanStep: ""
    property int scanProgress: 0       // 0..100
    readonly property var scanIds: ["widgets", "gameoverlay", "dock", "barmodules", "effects"]
    property var _scanSamples: []
    property int _scanIdx: -1          // -1 = базова лінія, 0..n-1 = компоненти, n = фінальна лінія
    property int _scanTicks: 0
    property real _base: 0
    property var _scanCosts: ({})

    property string scanError: ""      // "" | noready | noshell
    function startScan() {
        if (scanning) return
        if (!ready)  { scanError = "noready"; return }
        if (!shell)  { scanError = "noshell"; return }
        scanError = ""
        ReliefState.scanOff = ({})
        _scanCosts = ({}); _scanIdx = -1; _scanTicks = 0; _scanSamples = []
        scanning = true; scanProgress = 0; scanStep = "base"
    }
    function cancelScan() {
        scanning = false; scanStep = ""; ReliefState.scanOff = ({})
    }
    function _scanFeed(cpu) {
        // 2 тіки «осідання» + 3 виміри на крок
        _scanTicks += 1
        if (_scanTicks > 2) _scanSamples.push(cpu)
        if (_scanTicks < 5) return
        const avg = _scanSamples.reduce((a, b) => a + b, 0) / Math.max(1, _scanSamples.length)
        _scanSamples = []; _scanTicks = 0
        if (_scanIdx === -1) {
            _base = avg
        } else if (_scanIdx < scanIds.length) {
            _scanCosts[scanIds[_scanIdx]] = Math.max(0, _base - avg)
        }
        _scanIdx += 1
        scanProgress = Math.round(100 * _scanIdx / (scanIds.length + 1))
        if (_scanIdx >= scanIds.length) {
            ReliefState.scanOff = ({})
            costs = _scanCosts; costsTime = Date.now()
            scanning = false; scanStep = ""; scanProgress = 100
            return
        }
        const id = scanIds[_scanIdx]
        scanStep = id
        const m = {}; m[id] = true
        ReliefState.scanOff = m
    }

    // ---- обробка виводу ----
    function _line(text) {
        let o
        try { o = JSON.parse(text) } catch (e) { return }
        if (o.t === "snap") {
            top = o.top || []
            shell = o.shell || null
            frozenList = o.frozen || []
            selfCpu = o.self ? o.self.cpu : 0
            selfMem = o.self ? o.self.mem : 0
            ncpu = o.ncpu || 1
            scope = o.scope || "shell"
            if (scanning && shell) _scanFeed(shell.cpu)
        } else if (o.t === "event") {
            if (o.kind === "ready") {
                ready = true; pushConfig()
                send({ cmd: "ui", fast: fast })
                if (ReliefState.active) send({ cmd: "relief", active: true })
            } else if (o.kind === "relief") {
                ReliefState.start(o.minutes, o.auto ? "auto" : "user", costs)
            } else if (o.kind === "relief_suggest") {
                reliefSuggested = true
            } else if (o.kind === "whitelist") {
                if (!isUserWhitelisted(o.name)) toggleWhitelist(o.name)
            }
            if (["exceed", "frozen", "thawed", "relief"].indexOf(o.kind) >= 0) {
                o.ts = Date.now()
                const e = events.concat([o])
                events = e.length > 12 ? e.slice(e.length - 12) : e
            }
        }
    }

    Process {
        id: proc
        command: ["sh", "-c", root.launcher]
        running: root.enabled && root._alive
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root._line(data) }
        stderr: SplitParser { onRead: data => console.warn("[Monitor] " + data) }
        onExited: (code, status) => {
            console.warn("[Monitor] procwatch exited, code " + code)
            root.ready = false
            root.top = []; root.shell = null
            if (root.enabled) { root._alive = false; restart.start() }
        }
    }
    // перезапуск демона після збою (через 4 с)
    property bool _alive: true
    Timer { id: restart; interval: 4000; onTriggered: root._alive = true }
}
