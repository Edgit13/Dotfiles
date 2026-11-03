pragma Singleton
import "root:/settings"
import QtQuick
import Quickshell

// ReliefState — «режим розвантаження» шелла.
// Тимчасово (на N хвилин) знімає навантаження з Quickshell:
//   • reduceMotion — анімації;
//   • effects      — тіні/розмиття (ElevationShadow, lock-екран): для КРИТИЧНИХ частин (lock, сам бар) лише це;
//   • hideHeavy    — ховає необов'язкові важкі компоненти (віджети робочого столу, док, ігровий оверлей,
//                    важкі модулі бару), у порядку виміряної вартості (MonitorService.costs), найважчі першими.
// Запускається за згодою користувача зі сповіщення (procwatch), кнопкою у меню ресурсів або IPC.
Singleton {
    id: root

    property bool active: false
    property real untilMs: 0
    property real nowMs: Date.now()
    property string reason: ""
    readonly property int remainingSec: active ? Math.max(0, Math.round((untilMs - nowMs) / 1000)) : 0

    function _opt(key) { return Settings.get("monitor", key) !== false }
    readonly property bool motion:    active && _opt("reliefMotion")
    readonly property bool hideHeavy: active && _opt("reliefHide")
    // сканування вартості компонентів вмикає ті самі перемикачі точково
    property var scanOff: ({})
    readonly property bool effects: (active && _opt("reliefEffects")) || scanOff.effects === true

    // необов'язкові компоненти, які можна ховати; критичні (lockscreen, bar) — ніколи, лише ефекти
    readonly property var hideable: ["widgets", "gameoverlay", "dock", "barmodules"]
    readonly property var critical: ["lockscreen", "bar"]

    // кого ховати зараз: за виміряною вартістю (спадання); без вимірів — усі з hideable
    property var hiddenIds: ({})
    function _rebuildHidden(costs) {
        const order = hideable.slice()
        if (costs && Object.keys(costs).length > 0) {
            order.sort((a, b) => (costs[b] || 0) - (costs[a] || 0))
            hiddenIds = order.filter(id => (costs[id] || 0) >= 0.3).reduce((m, id) => { m[id] = true; return m }, {})
            // якщо вимірювання нічого не знайшли — все одно ховаємо найважчі два
            if (Object.keys(hiddenIds).length === 0)
                hiddenIds = order.slice(0, 2).reduce((m, id) => { m[id] = true; return m }, {})
        } else {
            hiddenIds = order.reduce((m, id) => { m[id] = true; return m }, {})
        }
    }

    function hidden(id) {
        if (critical.indexOf(id) >= 0) return false
        return (hideHeavy && hiddenIds[id] === true) || scanOff[id] === true
    }

    signal started(int minutes, string why)
    signal stopped()

    function start(minutes, why, costs) {
        const m = Math.max(1, Math.round(minutes || 10))
        _rebuildHidden(costs)
        untilMs = Date.now() + m * 60000
        nowMs = Date.now()
        reason = why || ""
        active = true
        started(m, reason)
    }
    function stop() {
        if (!active) return
        active = false
        hiddenIds = ({})
        stopped()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: {
            root.nowMs = Date.now()
            if (root.nowMs >= root.untilMs) root.stop()
        }
    }
}
