pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Settings.qml — єдиний кор для всіх розділених JSON-файлів.
Singleton {
    id: root

    readonly property string base: Quickshell.env("HOME") + "/.config/quickshell/"

    property var data: ({})
    property var _raw: ({})
    property bool loaded: false
    signal changed(string cat, string key, var value)

    // blockLoading lets _disk() block on a read when it re-reads a file just
    // before writing it, so a manual edit can never be overwritten by state
    // this singleton loaded earlier.
    FileView { id: rGeneral;    path: root.base + "general.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("general.json", text()) }
    FileView { id: rTheme;      path: root.base + "theme.json";      watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("theme.json", text()) }
    FileView { id: rBar;        path: root.base + "bar.json";        watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("bar.json", text()) }
    FileView { id: rClock;      path: root.base + "clock.json";      watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("clock.json", text()) }
    FileView { id: rMonitor;    path: root.base + "monitor.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("monitor.json", text()) }
    FileView { id: rWidgets;    path: root.base + "widgets.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("widgets.json", text()) }
    FileView { id: rLock;       path: root.base + "lockscreen.json"; watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("lockscreen.json", text()) }
    FileView { id: rSession;    path: root.base + "session.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("session.json", text()) }
    FileView { id: rCapture;    path: root.base + "capture.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("capture.json", text()) }
    FileView { id: rNight;      path: root.base + "nightlight.json"; watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("nightlight.json", text()) }
    FileView { id: rUpdates;    path: root.base + "updates.json";    watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("updates.json", text()) }
    FileView { id: rColors;     path: root.base + "colors.json";     watchChanges: true; printErrors: false; blockLoading: true
               onFileChanged: reload(); onTextChanged: root._onFile("colors.json", text()) }

    FileView { id: wGeneral; path: root.base + "general.json";   atomicWrites: true; printErrors: false }
    FileView { id: wTheme;  path: root.base + "theme.json";      atomicWrites: true; printErrors: false }
    FileView { id: wBar;    path: root.base + "bar.json";        atomicWrites: true; printErrors: false }
    FileView { id: wClock;  path: root.base + "clock.json";      atomicWrites: true; printErrors: false }
    FileView { id: wMonitor; path: root.base + "monitor.json";   atomicWrites: true; printErrors: false }
    FileView { id: wWidgets; path: root.base + "widgets.json";   atomicWrites: true; printErrors: false }
    FileView { id: wLock;   path: root.base + "lockscreen.json"; atomicWrites: true; printErrors: false }
    FileView { id: wSession; path: root.base + "session.json";   atomicWrites: true; printErrors: false }
    FileView { id: wCapture; path: root.base + "capture.json";   atomicWrites: true; printErrors: false }
    FileView { id: wNight;   path: root.base + "nightlight.json"; atomicWrites: true; printErrors: false }
    FileView { id: wUpdates; path: root.base + "updates.json";    atomicWrites: true; printErrors: false }
    FileView { id: wColors; path: root.base + "colors.json";     atomicWrites: true; printErrors: false }

    function _writer(file) {
        switch (file) {
        case "general.json":    return wGeneral
        case "theme.json":      return wTheme
        case "bar.json":        return wBar
        case "clock.json":      return wClock
        case "monitor.json":    return wMonitor
        case "widgets.json":    return wWidgets
        case "lockscreen.json": return wLock
        case "session.json":    return wSession
        case "capture.json":    return wCapture
        case "nightlight.json": return wNight
        case "updates.json":    return wUpdates
        case "colors.json":     return wColors
        }
        return null
    }

    function _reader(file) {
        switch (file) {
        case "general.json":    return rGeneral
        case "theme.json":      return rTheme
        case "bar.json":        return rBar
        case "clock.json":      return rClock
        case "monitor.json":    return rMonitor
        case "widgets.json":    return rWidgets
        case "lockscreen.json": return rLock
        case "session.json":    return rSession
        case "capture.json":    return rCapture
        case "nightlight.json": return rNight
        case "updates.json":    return rUpdates
        case "colors.json":     return rColors
        }
        return null
    }

    // Файли, які читає Settings (без дублів), — для refresh().
    function _files() {
        var out = []
        for (var cat in Schema.schema) {
            var f = Schema.schema[cat].file
            if (f && out.indexOf(f) < 0) out.push(f)
        }
        return out
    }

    // Перечитує всі файли з диска. Викликається при відкритті вікна: якщо
    // watcher пропустив зміну (редактор зберіг файл атомарно, або запис
    // прийшов частинами), UI однаково покаже актуальні значення.
    function refresh() {
        var files = _files()
        for (var i = 0; i < files.length; i++) {
            var r = _reader(files[i])
            if (r) r.reload()
        }
    }

    // Свіжий вміст файлу з диска. Повертає {} для порожнього файлу і null,
    // якщо JSON не парситься: у такому разі писати не можна, інакше затерли б
    // те, що користувач щойно правив вручну.
    function _disk(file) {
        var r = _reader(file)
        if (!r) return Object.assign({}, root._raw[file] || {})
        r.reload()
        r.waitForJob()
        var text = r.text()
        if (!text || text.trim().length === 0) return {}
        try {
            var parsed = JSON.parse(text)
            return (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : {}
        } catch (e) {
            console.warn("[Settings] not writing " + file + ", invalid JSON: " + e)
            return null
        }
    }

    function _getPath(obj, path) {
        var parts = path.split(".")
        var cur = obj
        for (var i = 0; i < parts.length; i++) {
            if (cur === undefined || cur === null) return undefined
            cur = cur[parts[i]]
        }
        return cur
    }
    function _setPath(obj, path, value) {
        var parts = path.split(".")
        var cur = obj
        for (var i = 0; i < parts.length - 1; i++) {
            if (typeof cur[parts[i]] !== "object" || cur[parts[i]] === null) cur[parts[i]] = {}
            cur = cur[parts[i]]
        }
        cur[parts[parts.length - 1]] = value
    }

    function _onFile(name, text) {
        var parsed = {}
        if (text && text.trim().length > 0) {
            try { parsed = JSON.parse(text) }
            catch (e) { console.warn("[Settings] parse", name, e); _retryLater(name); return }
        }
        var raw = Object.assign({}, root._raw)
        raw[name] = parsed
        root._raw = raw
        root._rebuild()
    }

    function _rebuild() {
        var merged = {}
        for (var cat in Schema.schema) {
            var cs = Schema.schema[cat]
            if (!cs.fields) continue
            merged[cat] = {}
            var fileData = root._raw[cs.file] || {}
            for (var key in cs.fields) {
                var f = cs.fields[key]
                var v = _getPath(fileData, f.path || key)
                merged[cat][key] = (v === undefined) ? f.default : _clamp(f, v)
            }
        }
        root.data = merged
        root.loaded = true
    }

    function _clamp(f, v) {
        switch (f.type) {
        case "bool":  return !!v
        case "num": {
            if (f.nullable && (v === null || v === undefined)) return null
            var n = Number(v)
            if (isNaN(n)) return f.default
            if (f.min !== undefined) n = Math.max(f.min, n)
            if (f.max !== undefined) n = Math.min(f.max, n)
            return n
        }
        case "enum":  return f.options.indexOf(v) >= 0 ? v : f.default
        case "str":   return String(v)
        case "color": return (typeof v === "string" && /^#[0-9a-fA-F]{3,8}$/.test(v)) ? v : f.default
        case "arr":   return Array.isArray(v) ? v : f.default
        case "map":   return (v && typeof v === "object" && !Array.isArray(v)) ? v : f.default
        }
        return v
    }

    function get(cat, key) {
        if (root.data[cat] && root.data[cat][key] !== undefined) return root.data[cat][key]
        var s = Schema.schema[cat]
        return (s && s.fields && s.fields[key]) ? s.fields[key].default : undefined
    }
    function defaults(cat, key) {
        var s = Schema.schema[cat]
        return (s && s.fields && s.fields[key]) ? s.fields[key].default : undefined
    }
    function isDirty(cat, key) {
        return JSON.stringify(get(cat, key)) !== JSON.stringify(defaults(cat, key))
    }
    function schemaFor(cat, key) {
        var s = Schema.schema[cat]
        return (s && s.fields) ? (s.fields[key] || null) : null
    }

    function fieldsForPage(idx) {
        var p = Schema.pages[idx]
        if (!p) return []
        var out = []
        for (var ci = 0; ci < p.cats.length; ci++) {
            var cat = p.cats[ci]
            var cs = Schema.schema[cat]
            if (!cs || !cs.fields) continue
            for (var key in cs.fields) {
                var f = cs.fields[key]
                if (f.hidden) continue
                out.push({ cat: cat, key: key, field: f })
            }
        }
        return out
    }

    function sectionsForPage(idx) {
        var p = Schema.pages[idx]
        if (!p) return []
        var out = []
        for (var ci = 0; ci < p.cats.length; ci++) {
            var cat = p.cats[ci]
            var cs = Schema.schema[cat]
            if (!cs || !cs.fields) continue
            // Сусідні поля з однаковим group утворюють окрему секцію.
            // Поля без group збираються в одну секцію з назвою категорії.
            var cur = null
            for (var key in cs.fields) {
                var f = cs.fields[key]
                if (f.hidden) continue
                var g = f.group || ""
                if (!cur || g !== cur.group) {
                    cur = { cat: cat, label: g || cs.label || cat, group: g, fields: [] }
                    out.push(cur)
                }
                cur.fields.push({ cat: cat, key: key, field: f })
            }
        }
        return out
    }

    function set(cat, key, value) {
        var s = Schema.schema[cat]
        if (!s || !s.fields || !s.fields[key]) {
            console.warn("[Settings] unknown", cat + "." + key); return false
        }
        var v = _clamp(s.fields[key], value)
        var file = s.file
        var path = s.fields[key].path || key

        // Берімо файл з диска, а не _raw: поки вікно було відкрите, користувач
        // міг правити його вручну, і тоді запис затер би ці зміни.
        var fileData = _disk(file)
        if (fileData === null) return false
        _setPath(fileData, path, v)
        var raw = Object.assign({}, root._raw)
        raw[file] = fileData
        root._raw = raw

        var merged = Object.assign({}, root.data)
        var catObj = Object.assign({}, merged[cat] || {}, { [key]: v })
        merged[cat] = catObj
        root.data = merged

        var w = _writer(file)
        if (w) { w.setText(JSON.stringify(fileData, null, 2)); w.waitForJob() }
        changed(cat, key, v)
        return true
    }

    // Кілька ключів однієї категорії за один запис файлу (пресети, перетягування)
    function setMany(cat, values) {
        var s = Schema.schema[cat]
        if (!s || !s.fields) return false
        var file = s.file
        var fileData = _disk(file)
        if (fileData === null) return false
        var catObj = Object.assign({}, (root.data[cat] || {}))
        var applied = []
        for (var key in values) {
            var f = s.fields[key]
            if (!f) continue
            var v = _clamp(f, values[key])
            _setPath(fileData, f.path || key, v)
            catObj[key] = v
            applied.push([key, v])
        }
        var raw = Object.assign({}, root._raw)
        raw[file] = fileData
        root._raw = raw
        var merged = Object.assign({}, root.data)
        merged[cat] = catObj
        root.data = merged
        var w = _writer(file)
        if (w) { w.setText(JSON.stringify(fileData, null, 2)); w.waitForJob() }
        for (var i = 0; i < applied.length; i++) changed(cat, applied[i][0], applied[i][1])
        return true
    }

    function resetKey(cat, key) { return set(cat, key, defaults(cat, key)) }
    function resetCategory(cat) {
        var cs = Schema.schema[cat]
        if (!cs || !cs.fields) return false
        // Один запис на файл замість одного на кожен ключ.
        var values = {}
        for (var k in cs.fields) values[k] = cs.fields[k].default
        return setMany(cat, values)
    }
    function resetAll() {
        for (var cat in Schema.schema) resetCategory(cat)
        return true
    }

    // Якщо файл прийшов частинами (редактор спершу обрізає його, бекап
    // копіюється не атомарно), перший текст може бути невалідним JSON.
    // Один повторний reload через коротку паузу зазвичай ловить уже цілий файл.
    property var _retry: ({})
    function _retryLater(file) {
        var m = Object.assign({}, root._retry)
        m[file] = true
        root._retry = m
        retryTimer.restart()
    }
    Timer {
        id: retryTimer
        interval: 200
        repeat: false
        onTriggered: {
            var pending = root._retry
            root._retry = ({})
            for (var f in pending) {
                var r = root._reader(f)
                if (r) r.reload()
            }
        }
    }

    Component.onCompleted: root.refresh()
}
