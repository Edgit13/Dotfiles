import Quickshell
import Quickshell.Services.Notifications
import QtQuick

// NotifItem — обгортка над Notification: знімок даних для історії + таймер спливаючого вікна.
// Додано: прочитане, закріплення, відкладання, пошук.
Scope {
    id: item

    property var raw: null              // Notification | null (після закриття застосунком)
    property int nid: 0
    property string appName: ""
    property string appIcon: ""
    property string image: ""
    property string desktopEntry: ""
    property string summary: ""
    property string body: ""
    property int urgency: 1             // 0 low · 1 normal · 2 critical
    property var actions: []            // [{id, text}]
    property real expireSec: 0
    property bool transient_: false
    property date time: new Date()

    // стан користувача
    property bool read: false
    property bool pinned: false
    property real snoozedUntil: 0
    property bool restored: false       // відновлене після reload → не показувати як «нове» в барі

    // спливаюче вікно
    property bool popup: false
    property bool paused: false
    property real totalMs: 0            // 0 = липке (критичні / закріплені)
    property real remainingMs: 0

    signal closedByApp()
    signal popupEnded()
    signal touched()
    signal snoozeEnded()

    function sync() {
        if (!raw) return
        nid = raw.id
        appName = raw.appName || ""
        appIcon = raw.appIcon || ""
        // Quickshell загортає image-path у "image://icon/" (навіть абсолютний шлях),
        // тому знімаємо префікс: далі це або шлях до фото, або ім'я іконки теми.
        let im = String(raw.image || "")
        if (im.indexOf("image://icon/") === 0)
            im = im.substring("image://icon/".length)
        image = im
        desktopEntry = raw.desktopEntry || ""
        summary = raw.summary || ""
        body = raw.body || ""
        urgency = raw.urgency === NotificationUrgency.Critical ? 2
                : (raw.urgency === NotificationUrgency.Low ? 0 : 1)
        // D-Bus expire_timeout is in milliseconds; keep seconds here so
        // _timeoutFor() can multiply by 1000 safely.
        expireSec = raw.expireTimeout > 0 ? raw.expireTimeout / 1000 : 0
        transient_ = !!raw.transient
        const a = []
        for (let i = 0; i < raw.actions.length; i++)
            a.push({ id: raw.actions[i].identifier, text: raw.actions[i].text })
        actions = a
    }

    function arm(ms) {
        if (pinned) { totalMs = 0; remainingMs = 0; popup = true; paused = false; return }
        totalMs = ms
        remainingMs = ms
        paused = false
        popup = true
    }
    function touch() { time = new Date(); touched() }

    function hasDefault() {
        for (let i = 0; i < actions.length; i++) if (actions[i].id === "default") return true
        return false
    }
    function invoke(id) {
        if (!raw) return
        for (let i = 0; i < raw.actions.length; i++)
            if (raw.actions[i].identifier === id) { raw.actions[i].invoke(); return }
    }
    function close() { if (raw) raw.dismiss() }      // повідомити застосунок

    // Пошук у всьому, що бачить користувач.
    function matches(query) {
        const q = String(query || "").toLowerCase()
        if (q === "") return true
        const hay = String(appName + " " + summary + " " + body + " " + desktopEntry).toLowerCase()
        return hay.indexOf(q) >= 0
    }

    // Відкласти: сховати попап і показати його знову через N хвилин.
    function snooze(minutes) {
        const mins = Math.max(1, Number(minutes) || 15)
        snoozedUntil = Date.now() + mins * 60000
        popup = false
        paused = false
        touch()
    }

    readonly property Timer _tick: Timer {
        interval: 40
        repeat: true
        running: item.popup && !item.paused && !item.pinned && item.totalMs > 0
        onTriggered: {
            item.remainingMs -= 40
            if (item.remainingMs <= 0) { item.popup = false; item.popupEnded() }
        }
    }

    readonly property Timer _snooze: Timer {
        interval: 500
        repeat: true
        running: item.snoozedUntil > 0
        onTriggered: {
            if (Date.now() >= item.snoozedUntil) {
                item.snoozedUntil = 0
                item.snoozeEnded()
            }
        }
    }

    readonly property Connections _conn: Connections {
        target: item.raw
        ignoreUnknownSignals: true
        function onSummaryChanged() { item.sync(); item.touch() }
        function onBodyChanged()    { item.sync(); item.touch() }
        function onAppIconChanged() { item.sync() }
        function onImageChanged()   { item.sync() }
        function onActionsChanged() { item.sync() }
        function onClosed(reason)   { item.raw = null; item.popup = false; item.closedByApp() }
    }
}
