pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick

// ==========================================================================
// ConvertService.qml — конвертація файлів (кільце ConvertRing).
//
// Уся робота з файлами — в scripts/convert.py (ImageMagick для картинок,
// ffmpeg для відео й звуку, результат у теці «Converted» поруч із файлами).
// Тут — лише стан кільця: що виділено, які формати показати, скільки
// приблизно важитиме результат і як минула конвертація.
//
// Відкривається з scripts/convert-ring.sh (SUPER + правий клік): той кладе
// JSON {files, x, y, monitor} у $XDG_RUNTIME_DIR і кличе IPC convert open.
// ==========================================================================
Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("scripts/convert.py")

    // ── кільце ──
    property bool open: false
    property string level: ""              // "" — типи файлів, інакше id типу
    property var files: []
    property var groups: ({ image: [], video: [], audio: [] })
    property int skipped: 0
    property real anchorX: 0
    property real anchorY: 0
    property string anchorMonitor: ""

    // ── оцінки розміру для поточного рівня ──
    property real now: 0
    property var sizes: ({})
    property var same: []

    // ── довідник форматів (з convert.py) ──
    property var kinds: ({})
    property var formats: ({})
    property bool kindsReady: false

    // ── конвертація ──
    property bool busy: false
    property real progress: 0
    property int made: 0
    property string failure: ""

    property string payloadPath: ""
    property string pendingPayload: ""

    // ── похідні ──
    readonly property var ringKinds: ["image", "video", "audio"].filter(k =>
        (root.groups[k] || []).length > 0 || (k === "audio" && (root.groups.video || []).length > 0))
    readonly property int count: root.level
        ? root.filesFor(root.level).length
        : (root.groups.image || []).length + (root.groups.video || []).length + (root.groups.audio || []).length

    function ensure() {
        if (root.kindsReady || kindsProc.running) return
        kindsProc.running = true
    }

    function kindOf(path) {
        const ext = String(path).split("/").pop().split(".").pop().toLowerCase()
        for (const k in root.kinds) if (root.kinds[k].indexOf(ext) >= 0) return k
        return ""
    }

    function filesFor(kind) {
        if (kind === "audio") return (root.groups.audio || []).concat(root.groups.video || [])
        return root.groups[kind] || []
    }

    // ── відкриття з JSON-файлу, який підготував convert-ring.sh ──
    function openFrom(path) {
        root.payloadPath = path
        if (!root.kindsReady) {
            root.pendingPayload = path
            root.ensure()
            return
        }
        payloadProc.running = false
        payloadProc.running = true
    }

    function loadPayload(text) {
        let j = {}
        try { j = JSON.parse(text) } catch (e) { return }
        const list = (j.files || []).filter(f => typeof f === "string" && f.length > 0)

        const g = { image: [], video: [], audio: [] }
        let skip = 0
        for (const f of list) {
            const k = root.kindOf(f)
            if (k) g[k].push(f)
            else skip += 1
        }

        root.files = list
        root.groups = g
        root.skipped = skip
        root.anchorX = j.x || 0
        root.anchorY = j.y || 0
        root.anchorMonitor = j.monitor || ""
        root.sizes = {}
        root.same = []
        root.now = 0

        if (root.ringKinds.length === 0) {
            root.notify(Lang.t("ui.convert.nothing"), Lang.t("ui.convert.nothingHint"))
            return
        }
        root.level = root.ringKinds.length === 1 ? root.ringKinds[0] : ""
        root.open = true
    }

    function close() { root.open = false }
    function back() {
        if (root.level && root.ringKinds.length > 1) root.level = ""
        else root.close()
    }

    // ── запуск конвертації ──
    function pick(fmt) {
        if (!root.level || root.same.indexOf(fmt) >= 0) return
        const list = root.filesFor(root.level)
        if (list.length === 0) return
        root.busy = true
        root.progress = 0
        root.made = 0
        root.failure = ""
        runner.command = ["python3", root.helper, "convert", fmt].concat(list)
        runner.running = true
        root.close()
    }

    function notify(title, body) {
        const cmd = ["notify-send", "-a", "Edots", "-i", "document-save", title]
        if (body && body.length > 0) cmd.push(body)
        Quickshell.execDetached(cmd)
    }

    onLevelChanged: {
        root.sizes = {}
        root.same = []
        root.now = 0
        if (!root.level) return
        sizer.command = ["python3", root.helper, "sizes", root.level].concat(root.filesFor(root.level))
        sizer.running = true
    }

    // ── довідник форматів ──
    Process {
        id: kindsProc
        command: ["python3", root.helper, "kinds"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim())
                    root.kinds = j.kinds || {}
                    root.formats = j.formats || {}
                    root.kindsReady = true
                } catch (e) { return }
                if (root.pendingPayload !== "") {
                    const p = root.pendingPayload
                    root.pendingPayload = ""
                    root.openFrom(p)
                }
            }
        }
    }

    Process {
        id: payloadProc
        command: ["cat", root.payloadPath]
        stdout: StdioCollector {
            onStreamFinished: root.loadPayload(text)
        }
    }

    Process {
        id: sizer
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const line = text.trim().split("\n").pop()
                    const j = JSON.parse(line)
                    if (j.ev !== "sizes") return
                    root.now = j.now || 0
                    root.sizes = j.sizes || {}
                    root.same = j.same || []
                } catch (e) {}
            }
        }
    }

    Process {
        id: runner
        stdout: SplitParser {
            onRead: line => {
                let j = {}
                try { j = JSON.parse(line) } catch (e) { return }
                if (j.ev === "progress") {
                    root.progress = j.total > 0 ? j.got / j.total : 0
                } else if (j.ev === "done") {
                    root.made += 1
                } else if (j.ev === "error") {
                    root.failure = j.text || ""
                }
            }
        }
        onExited: (code, status) => {
            root.busy = false
            root.progress = 0
            if (code === 0 && root.made > 0) {
                root.notify(Lang.t("ui.convert.done").replace("{n}", root.made),
                            Lang.t("ui.convert.doneHint").replace("{n}", root.made))
            } else if (root.failure.length > 0) {
                root.notify(Lang.t("ui.convert.failed"), root.failure)
            }
            root.failure = ""
        }
    }
}
