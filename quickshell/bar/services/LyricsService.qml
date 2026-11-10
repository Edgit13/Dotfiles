pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// LyricsService — синхронізовані тексти (LRC) з lrclib.net для активного MPRIS-треку.
// Працює лише поки є глядач (LyricsView ставить wanted = true). Потрібен `curl`.
//   lines  : [{ t: секунди (-1 якщо без синхронізації), text }]
//   index  : поточний рядок (-1 до початку)
//   status : idle | loading | ok | none
Singleton {
    id: root

    property bool wanted: false
    property var lines: []
    property bool synced: false
    property string status: "idle"

    readonly property string trackKey: MediaService.title + "|" + MediaService.artist
    property string _loadedKey: ""
    property var _cache: ({})

    readonly property int index: {
        if (!synced || lines.length === 0) return -1
        const p = MediaService.position + 0.2          // трохи наперед, щоб рядок встигав підсвітитись
        let lo = 0, hi = lines.length - 1, res = -1
        while (lo <= hi) {
            const mid = (lo + hi) >> 1
            if (lines[mid].t <= p) { res = mid; lo = mid + 1 } else hi = mid - 1
        }
        return res
    }

    onWantedChanged: if (wanted) debounce.restart()
    onTrackKeyChanged: if (wanted) debounce.restart()

    Timer { id: debounce; interval: 350; onTriggered: root._load() }

    function _clean(s) {
        return String(s || "").replace(/\s*[\(\[].*?[\)\]]\s*/g, " ").replace(/\s+-\s+(remaster|live|radio|single|mono|stereo).*$/i, "").trim()
    }

    function _parse(rec) {
        if (!rec) return false
        const lrc = rec.syncedLyrics || ""
        const out = []
        if (lrc) {
            const rows = lrc.split("\n")
            for (let i = 0; i < rows.length; i++) {
                const re = /\[(\d+):(\d+(?:\.\d+)?)\]/g
                const stamps = []
                let m
                while ((m = re.exec(rows[i])) !== null) stamps.push(parseInt(m[1]) * 60 + parseFloat(m[2]))
                if (stamps.length === 0) continue
                const text = rows[i].replace(/\[[^\]]*\]/g, "").trim()
                for (let k = 0; k < stamps.length; k++) out.push({ t: stamps[k], text: text })
            }
            out.sort((a, b) => a.t - b.t)
            if (out.length > 0) { synced = true; lines = out; return true }
        }
        const plain = (rec.plainLyrics || "").split("\n")
        if (plain.join("").trim().length > 0) {
            synced = false
            lines = plain.map(s => ({ t: -1, text: s.trim() }))
            return true
        }
        return false
    }

    function _apply(rec) {
        if (_parse(rec)) { status = "ok"; _cache[_loadedKey] = rec }
        else { lines = []; synced = false; status = "none" }
    }

    function _load() {
        if (!MediaService.has || MediaService.title.length === 0) {
            lines = []; synced = false; status = "idle"; _loadedKey = ""; return
        }
        if (_loadedKey === trackKey && status !== "idle") return
        _loadedKey = trackKey
        const hit = _cache[trackKey]
        if (hit) { _apply(hit); return }
        lines = []; synced = false; status = "loading"
        getProc.command = ["curl", "-sfL", "--max-time", "8", "-G", "https://lrclib.net/api/get",
            "--data-urlencode", "track_name=" + MediaService.title,
            "--data-urlencode", "artist_name=" + MediaService.artist,
            "--data-urlencode", "album_name=" + MediaService.album,
            "--data-urlencode", "duration=" + Math.round(MediaService.length)]
        getProc.running = true
    }

    function _search() {
        searchProc.command = ["curl", "-sfL", "--max-time", "8", "-G", "https://lrclib.net/api/search",
            "--data-urlencode", "track_name=" + _clean(MediaService.title),
            "--data-urlencode", "artist_name=" + _clean(MediaService.artist)]
        searchProc.running = true
    }

    Process {
        id: getProc
        stdout: StdioCollector {
            onStreamFinished: {
                let rec = null
                try { rec = JSON.parse(text) } catch (e) {}
                if (rec && (rec.syncedLyrics || rec.plainLyrics)) root._apply(rec)
                else root._search()
            }
        }
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                try { arr = JSON.parse(text) } catch (e) {}
                if (!Array.isArray(arr)) arr = []
                let best = arr.find(r => r.syncedLyrics) || arr.find(r => r.plainLyrics) || null
                root._apply(best)
            }
        }
    }
}
