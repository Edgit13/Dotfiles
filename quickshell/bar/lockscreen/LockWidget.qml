import QtQuick
import "root:/theme"
import "material"

// LockWidget — вільний віджет локскріну: позиція (нормалізована), M3-форма фону, колір, масштаб.
// У режимі редагування (host.editable) його можна тягнути мишею; позиція зберігається в Settings.
Item {
    id: w

    required property var host            // LockM3
    required property string wid
    property bool shapeable: true
    property bool shown: true
    default property alias content: holder.data

    readonly property var conf: host.wc(wid)
    readonly property string shape: shapeable ? conf.shape : "default"
    readonly property bool shaped: shape !== "default"
    readonly property color bg: host.tintBg(conf.color)
    readonly property color fg: shaped ? host.tintFg(conf.color) : M3.m3OnSurface
    readonly property bool selected: host.selectedId === wid
    readonly property color selColor: Theme.settings.nothing ? ThemeNothing.red : M3.primary

    readonly property real inner: Math.max(holder.width, holder.height)
    readonly property real side: Math.max(inner / 0.64, 96 * host.k)

    width: shaped ? side : holder.width
    height: shaped ? side : holder.height
    visible: shown

    property bool dragging: false
    property real dcx: 0.5
    property real dcy: 0.5
    x: (dragging ? dcx : conf.x) * host.width - width / 2
    y: (dragging ? dcy : conf.y) * host.height - height / 2
    Behavior on x { enabled: !w.dragging; MotionAnimation { role: "move" } }
    Behavior on y { enabled: !w.dragging; MotionAnimation { role: "move" } }

    scale: conf.scale
    transformOrigin: Item.Center
    Behavior on scale { MotionAnimation { role: "morph" } }

    // фон-форма
    ExpressiveDot {
        visible: w.shaped
        anchors.centerIn: parent
        dotSize: w.side
        shape: w.shaped ? w.shape : "circle"
        dotColor: w.bg
        morph: 1.0
        opacity: 0.94
        Behavior on dotSize { MotionAnimation { role: "morph" } }
    }

    Item {
        id: holder
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }

    // ── режим редагування ───────────────────────────────
    // рамку показуємо лише для вибраного віджета або під курсором,
    // щоб прев'ю виглядало як справжній локскрін, а не як сітка
    Rectangle {
        visible: w.host.editable && (w.selected || dragMa.containsMouse)
        anchors.fill: parent
        anchors.margins: -6
        radius: 14
        color: w.selected ? Qt.rgba(w.selColor.r, w.selColor.g, w.selColor.b, 0.08) : "transparent"
        border.width: w.selected ? 2 : 1
        border.color: w.selected ? w.selColor : Qt.rgba(M3.m3OnSurface.r, M3.m3OnSurface.g, M3.m3OnSurface.b, 0.30)
        z: 50
        Behavior on border.color { MotionColorAnimation { role: "hover" } }
    }
    MouseArea {
        id: dragMa
        enabled: w.host.editable
        visible: w.host.editable
        hoverEnabled: true
        anchors.fill: parent
        anchors.margins: -6
        z: 51
        cursorShape: Qt.SizeAllCursor
        property real offx: 0
        property real offy: 0

        function clamp(v) { return Math.max(0.03, Math.min(0.97, v)) }
        function snap(v) { return Math.abs(v - 0.5) < 0.012 ? 0.5 : v }

        onPressed: m => {
            w.host.select(w.wid)
            const p = mapToItem(w.host, m.x, m.y)
            offx = p.x / w.host.width - w.conf.x
            offy = p.y / w.host.height - w.conf.y
            w.dcx = w.conf.x
            w.dcy = w.conf.y
            w.dragging = true
        }
        onPositionChanged: m => {
            if (!pressed) return
            const p = mapToItem(w.host, m.x, m.y)
            w.dcx = snap(clamp(p.x / w.host.width - offx))
            w.dcy = snap(clamp(p.y / w.host.height - offy))
        }
        onReleased: {
            w.host.saveWidget(w.wid, { x: w.dcx, y: w.dcy })
            w.dragging = false
        }
    }
}
