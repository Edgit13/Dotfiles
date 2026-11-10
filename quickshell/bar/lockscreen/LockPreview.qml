import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "root:/theme"
import "root:/settings"
import "material"

// LockPreview — живий прев'ю локскріну 16:9 (для Settings → Локскрін).
// Малює справжню LockM3 у 1920×1080 і масштабує; сам виступає як «ctl» для неї.
Item {
    id: root

    // ── імітація ctl ─────────────────────────────────────
    property bool faceEnabled: Settings.get("lockscreen", "faceUnlock") === true
    property bool faceEnrolled: true
    property string faceState: "idle"
    readonly property string faceLabel: Lang.t("lock.face.idle")
    property string passText: "edots"
    property bool showPassword: false
    property bool statusWorking: false
    property bool statusError: false
    property int errorCount: 0
    property int shakeTick: 0
    property int successTick: 0
    property var powerExec: []

    // ── редактор віджетів ────────────────────────────────
    property bool editable: true
    property bool full: false                    // true → на весь екран (робочий стіл), без масштабування й рамки
    property string selected: ""                 // нічого не вибрано → чисте прев'ю без рамок
    // сцена сама каже, у якій мапі зберігати розкладку (M3 → widgets, Nothing → widgetsNothing)
    readonly property string widgetKey: (sceneLoader.item && sceneLoader.item.widgetsKey)
                                        ? sceneLoader.item.widgetsKey : "widgets"
    function select(id) { selected = id }
    function saveWidget(id, props) {
        const cur = Settings.get("lockscreen", widgetKey)
        const m = JSON.parse(JSON.stringify(cur && typeof cur === "object" ? cur : {}))
        const o = m[id] || {}
        for (const k in props) o[k] = props[k]
        m[id] = o
        Settings.set("lockscreen", widgetKey, m)
    }
    function resetWidget(id, keys) {
        const cur = Settings.get("lockscreen", widgetKey)
        const m = JSON.parse(JSON.stringify(cur && typeof cur === "object" ? cur : {}))
        if (!m[id]) return
        if (!keys) delete m[id]
        else { for (let i = 0; i < keys.length; i++) delete m[id][keys[i]] }
        Settings.set("lockscreen", widgetKey, m)
    }
    function resetAll() { Settings.set("lockscreen", widgetKey, {}) }
    property string wallpaperUrl: ""
    function retryFace() {}
    function tryUnlock() {}

    readonly property string greeting: {
        var h = new Date().getHours()
        if (h < 5)  return Lang.t("lock.greet.night")
        if (h < 12) return Lang.t("lock.greet.morning")
        if (h < 18) return Lang.t("lock.greet.afternoon")
        return Lang.t("lock.greet.evening")
    }
    readonly property string greetingIcon: {
        var h = new Date().getHours()
        if (h < 5)  return "bedtime"
        if (h < 12) return "wb_sunny"
        if (h < 18) return "wb_twilight"
        return "dark_mode"
    }
    readonly property var dotCatalog: ["cookie","sunny","burst","star","clover","flower","pentagon","hexagon","square","oval","pill","pill_diag","blob","circle"]
    readonly property var floaters: [
        { shape: "blob",   size: 260, x: 0.08, y: 0.18, ax: 0.05, ay: 0.02, dur: 32000 },
        { shape: "cookie", size: 200, x: 0.82, y: 0.28, ax: 0.05, ay: 0.03, dur: 38000 },
        { shape: "flower", size: 180, x: 0.72, y: 0.78, ax: 0.04, ay: 0.04, dur: 42000 }
    ]

    FileView {
        path: Quickshell.shellPath("../current-wallpaper.txt")
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onTextChanged: { const t = text().trim(); root.wallpaperUrl = t.length > 0 ? "file://" + t : "" }
    }

    // ── рамка ────────────────────────────────────────────
    Item {
        id: frame
        anchors.fill: parent
        layer.enabled: !root.full
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frameMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // сцена залежить від дизайну: Nothing → LockNothing, інакше — LockM3.
        // Loader тримає «віртуальний» екран 1920×1080, а масштаб — на самому Loader,
        // щоб сцена не отримала розмір рамки (інакше все з'їжджає в кут).
        Loader {
            id: sceneLoader
            width: root.full ? root.width : 1920
            height: root.full ? root.height : 1080
            scale: root.full ? 1 : frame.width / 1920
            transformOrigin: Item.TopLeft
            sourceComponent: Theme.settings.nothing ? cNothing : cM3
        }
        Component {
            id: cM3
            LockM3 {
                anchors.fill: parent
                ctl: root
                preview: true
                editable: root.editable
            }
        }
        Component {
            id: cNothing
            LockNothing {
                anchors.fill: parent
                ctl: root
                preview: true
                editable: root.editable
            }
        }
    }
    Item {
        id: frameMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: Theme.shape.cardLarge * 0.7 }
    }
    Rectangle {
        visible: !root.full
        anchors.fill: parent
        radius: Theme.shape.cardLarge * 0.7
        color: "transparent"
        border.width: 1
        border.color: Theme.color.outlineVariant
    }
}
