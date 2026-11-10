pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// NotificationService — власний демон сповіщень (замість swaync), як у end-4:
// NotificationServer → історія → спливаючі вікна + центр сповіщень. Не запускай swaync паралельно.
//
// Розширення (2026): непрочитані, закріплення, відкладання, mute застосунку, пошук,
// фільтри, ліміт історії, копіювання тексту. Пароль/інші сервіси не зачіпаються.
Singleton {
    id: root

    // ---- налаштування ----
    readonly property bool masterPopups: !!Settings.get("general", "notifEnabled")
    readonly property bool dnd: !!Settings.get("notif", "dnd")
    readonly property bool toasts: Settings.get("notif", "toasts") !== false      // спливаючі вікна
    readonly property bool barLive: Settings.get("notif", "bar") !== false        // сповіщення прямо в барі
    readonly property string position: String(Settings.get("notif", "position") || "top-right")
    // центр може стояти окремо ("same" = там само, де спливаючі вікна)
    readonly property string centerPosition: {
        const v = String(Settings.get("notif", "centerPosition") || "same")
        return v === "same" ? position : v
    }
    readonly property real margin: Number(Settings.get("notif", "margin") ?? 16)
    readonly property real cardWidth: Number(Settings.get("notif", "width") ?? 380)
    readonly property real centerWidth: Number(Settings.get("notif", "centerWidth") ?? 420)
    readonly property real timeoutNormal: Number(Settings.get("notif", "timeout") ?? 6)
    readonly property real timeoutLow: Number(Settings.get("notif", "timeoutLow") ?? 4)
    readonly property int maxVisible: Math.round(Number(Settings.get("notif", "maxVisible") ?? 4))
    readonly property int historyLimit: Math.round(Number(Settings.get("notif", "history") ?? 60))
    readonly property real snoozeMinutes: Number(Settings.get("notif", "snooze") ?? 15)
    readonly property bool grouped: Settings.get("notif", "group") !== false
    readonly property bool showActions: Settings.get("notif", "actions") !== false
    readonly property bool accent: Settings.get("notif", "accent") !== false
    readonly property real iconSize: Number(Settings.get("notif", "iconSize") ?? 40)
    readonly property string density: String(Settings.get("notif", "density") || "normal")
    readonly property var mutedApps: Settings.get("notif", "muted") || []
    readonly property real densePad: density === "compact" ? 10 : density === "spacious" ? 18 : 14
    readonly property real denseGap: density === "compact" ? 4 : density === "spacious" ? 10 : 7

    function setDnd(v) { Settings.set("notif", "dnd", v) }
    function toggleDnd() { setDnd(!dnd) }

    // ---- дані ----
    property var items: []                           // новіші першими
    readonly property int count: items.length
    readonly property int unreadCount: items.filter(i => !i.read).length
    readonly property var pinnedItems: items.filter(i => i.pinned)
    readonly property var popupQueue: items.filter(i => i.popup)
    readonly property var popups: popupQueue.slice(0, maxVisible)
    readonly property var latest: popups.length > 0 ? popups[0] : null
    readonly property int hiddenPopupCount: Math.max(0, popupQueue.length - maxVisible)
    readonly property var groups: appGroups("all", "")

    // ---- muted apps ----
    function isAppMuted(key) { return (mutedApps || []).indexOf(key) >= 0 }
    function muteApp(key) {
        if (!key || isAppMuted(key)) return
        const list = (mutedApps || []).slice()
        list.push(key)
        Settings.set("notif", "muted", list)
    }
    function unmuteApp(key) {
        const list = (mutedApps || []).filter(k => k !== key)
        Settings.set("notif", "muted", list)
    }
    function toggleMuteApp(key) { isAppMuted(key) ? unmuteApp(key) : muteApp(key) }
    function appKey(it) { return it ? (it.appName || it.desktopEntry || "—") : "—" }
    function appMuted(it) { return isAppMuted(appKey(it)) }

    // ---- пошук / фільтри ----
    function filteredItems(filter, query) {
        const q = String(query || "").trim().toLowerCase()
        return items.filter(it => {
            if (filter === "unread" && it.read) return false
            if (filter === "pinned" && !it.pinned) return false
            return q === "" || it.matches(q)
        })
    }
    // [{ key, items, unread, pinned, latest }] — для центру й групи
    function appGroups(filter, query) {
        const list = filteredItems(filter, query)
        if (!grouped) {
            return list.map(it => ({
                key: appKey(it), items: [it], unread: it.read ? 0 : 1,
                pinned: it.pinned ? 1 : 0, latest: it
            }))
        }
        const map = {}, out = []
        for (let i = 0; i < list.length; i++) {
            const it = list[i]
            const k = appKey(it)
            if (!map[k]) { map[k] = { key: k, items: [], unread: 0, pinned: 0, latest: it }; out.push(map[k]) }
            map[k].items.push(it)
            if (!it.read) map[k].unread += 1
            if (it.pinned) map[k].pinned += 1
        }
        return out
    }
    function itemsFor(key) {
        return items.filter(i => appKey(i) === key)
    }

    // ---- прочитане / закріплене / відкладене ----
    function markRead(it, value) { if (it) it.read = value !== false }
    function markAllRead() { for (let i = 0; i < items.length; i++) items[i].read = true }
    function togglePin(it) {
        if (!it) return
        it.pinned = !it.pinned
        if (it.pinned) { it.totalMs = 0; it.remainingMs = 0 }
        else if (it.popup) it.arm(_timeoutFor(it))
    }
    function snooze(it, minutes) {
        if (!it) return
        it.snooze(minutes === undefined ? snoozeMinutes : minutes)
    }
    function copy(it) {
        if (!it) return
        const text = String(it.summary || "") + (it.body ? "\n" + it.body : "")
        if (text.length === 0) return
        // без eval/інтерполяції в shell: текст передається окремим аргументом
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$1\" | wl-copy", "--", text])
    }

    // ---- відносний час ----
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: root.items.length > 0; onTriggered: root.now = Date.now() }
    function rel(date) {
        const s = Math.max(0, Math.floor((now - date.getTime()) / 1000))
        if (s < 45) return Lang.t("ui.time.now")
        const m = Math.round(s / 60)
        if (m < 60) return Lang.tn("ui.time.min", m)
        const h = Math.round(m / 60)
        if (h < 24) return Lang.tn("ui.time.hour", h)
        return Lang.tn("ui.time.day", Math.round(h / 24))
    }

    // ---- монітор: де сфокусоване вікно ----
    property string popupMonitor: ""
    property string centerMonitor: ""
    function _focusedMonitor() {
        return MangoService.focusedMonitor
    }
    function _fallbackMonitor() {
        return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : ""
    }
    function _targetMonitor() {
        return _focusedMonitor() || popupMonitor || _fallbackMonitor()
    }
    function isPopupTarget(scr) { return scr.name === (popupMonitor || _fallbackMonitor()) }
    function isCenterTarget(scr) { return scr.name === (centerMonitor || _fallbackMonitor()) }

    // ---- центр сповіщень ----
    property bool centerOpen: false
    function openCenter() {
        // фіксуємо монітор на момент відкриття: фокус може змінитися, а центр не має «стрибати»
        centerMonitor = _targetMonitor()
        for (let i = 0; i < items.length; i++) items[i].popup = false
        centerOpen = true
    }
    function closeCenter() { centerOpen = false }
    function toggleCenter() { centerOpen ? closeCenter() : openCenter() }

    // ---- сервер ----
    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        actionIconsSupported: false
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true
        onNotification: n => root._add(n)
    }

    Component { id: itemComp; NotifItem {} }

    function _timeoutFor(it) {
        if (it.pinned) return 0
        if (it.expireSec > 0) return it.expireSec * 1000
        if (it.urgency === 2) return 0
        return (it.urgency === 0 ? timeoutLow : timeoutNormal) * 1000
    }

    function _wrap(n) {
        const it = itemComp.createObject(root, { raw: n })
        it.sync()
        it.closedByApp.connect(() => root._remove(it, false))
        it.popupEnded.connect(() => { if (it.transient_) root._remove(it, true) })
        it.snoozeEnded.connect(() => root._rearm(it))
        return it
    }

    function _add(n) {
        n.tracked = true
        const it = _wrap(n)
        const muted = root.appMuted(it)
        const allowed = masterPopups && !centerOpen && (!dnd || it.urgency === 2) && (!muted || it.urgency === 2)
        if (allowed) { popupMonitor = _focusedMonitor() || _fallbackMonitor(); it.arm(_timeoutFor(it)) }
        else if (it.transient_) { it.close(); it.destroy(); return }
        let arr = [it].concat(items)
        // ліміт історії: закріплені не викидаємо
        while (arr.length > historyLimit) {
            let idx = arr.length - 1
            while (idx >= 0 && arr[idx].pinned) idx -= 1
            if (idx < 0) break
            const old = arr[idx]
            arr.splice(idx, 1)
            old.close()
            old.destroy(1500)
        }
        items = arr
    }

    function _rearm(it) {
        if (items.indexOf(it) < 0) return
        if (masterPopups && !centerOpen && (!dnd || it.urgency === 2) && (!appMuted(it) || it.urgency === 2)) {
            popupMonitor = _focusedMonitor() || _fallbackMonitor()
            it.arm(_timeoutFor(it))
        }
    }

    function _remove(it, notifyApp) {
        if (items.indexOf(it) < 0) return
        items = items.filter(x => x !== it)
        if (notifyApp) it.close()
        it.popup = false
        it.destroy(1500)
    }

    // ---- дії ----
    function dismiss(it) { _remove(it, true) }
    function hidePopup(it) { it.popup = false }
    function activate(it, id) { it.invoke(id); markRead(it); _remove(it, true) }
    function clearAll(includePinned) {
        const all = includePinned ? items : items.filter(i => !i.pinned)
        items = includePinned ? [] : items.filter(i => i.pinned)
        for (let i = 0; i < all.length; i++) { all[i].close(); all[i].destroy(1500) }
    }
    function clearRead() {
        const gone = items.filter(i => i.read && !i.pinned)
        items = items.filter(i => !(i.read && !i.pinned))
        for (let i = 0; i < gone.length; i++) { gone[i].close(); gone[i].destroy(1500) }
    }
    function clearApp(key) {
        const gone = items.filter(i => appKey(i) === key && !i.pinned)
        items = items.filter(i => !(appKey(i) === key && !i.pinned))
        for (let i = 0; i < gone.length; i++) { gone[i].close(); gone[i].destroy(1500) }
    }

    // після перезавантаження shell — відновлюємо з сервера
    Component.onCompleted: {
        const tracked = server.trackedNotifications.values
        const arr = []
        for (let i = 0; i < tracked.length; i++) arr.unshift(_wrap(tracked[i]))
        items = arr
    }
}
