pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/shell"
import "root:/modules/common"
import Quickshell
import Quickshell.Wayland
import QtQuick

// TrayOverflow — «приховані значки» (як у Windows): картка з іконками, які користувач сховав з бару.
// Так само, як TrayMenu, це оверлей на весь екран без popup-grab'ів (xdg_popup на dwl-композиторах
// закривається непередбачувано): клік поза карткою / Esc закривають, а клік по іконці — активує її
// й закриває панель. Іконки — звичайні TrayItem (ПКМ — меню, Ctrl+клік / пункт меню — повернути в бар).
PanelWindow {
    id: root

    property Item anchorItem: null
    property string placement: "top"        // сторона бару: top | bottom | left | right
    property var items: []                  // SystemTrayItem[], що лежать в overflow
    property bool shown: false

    property real _ax: 0
    property real _ay: 0
    property real _aw: 0
    property real _ah: 0
    property real _sw: 1920
    property real _sh: 1080

    readonly property real edge: 8
    readonly property real gap: 6
    readonly property int cell: Theme.type.iconS + Theme.space.xs * 2 + Theme.space.xs
    readonly property int spacing: Theme.space.xxs
    readonly property int cols: Math.max(1, Math.min(items.length, 6))
    readonly property int rows: Math.max(1, Math.ceil(items.length / cols))

    signal hideToggled(var item)

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "edots-trayoverflow"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown || card.opacity > 0.01

    function openAt(anchor) {
        if (!anchor || items.length === 0) return
        const w = anchor.QsWindow.window
        if (!w || !w.screen) return
        const scr = w.screen
        const a = w.anchors
        const m = w.margins
        const p = anchor.mapToItem(null, 0, 0)
        const ox = a.left ? m.left : (a.right ? scr.width - w.width - m.right : (scr.width - w.width) / 2)
        const oy = a.top ? m.top : (a.bottom ? scr.height - w.height - m.bottom : (scr.height - w.height) / 2)
        anchorItem = anchor
        _sw = scr.width
        _sh = scr.height
        _ax = ox + p.x
        _ay = oy + p.y
        _aw = anchor.width
        _ah = anchor.height
        screen = scr
        shown = true
    }
    function close() { shown = false }
    function toggleAt(anchor) { if (shown) close(); else openAt(anchor) }

    onItemsChanged: if (items.length === 0) close()
    // поки панель відкрита, пілл бару не згортається (див. ShellState.setHold)
    readonly property string _holdKey: "trayoverflow-" + Math.random().toString(36).slice(2)
    onShownChanged: {
        if (shown) scope.forceActiveFocus()
        ShellState.setHold(_holdKey, shown, root.screen ? root.screen.name : "")
    }
    Component.onDestruction: ShellState.setHold(_holdKey, false, "")
    onVisibleChanged: if (visible) scope.forceActiveFocus()

    Item {
        id: scope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.close()

        // клік будь-де поза карткою закриває панель
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.close()
        }

        ElevationShadow {
            id: card
            width: root.cols * root.cell + (root.cols - 1) * root.spacing + Theme.space.sm * 2
            height: root.rows * root.cell + (root.rows - 1) * root.spacing + Theme.space.sm * 2
            radius: Theme.shape.menu
            level: 3

            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.9
            transformOrigin: root.placement === "bottom" ? Item.Bottom
                           : root.placement === "left"   ? Item.Left
                           : root.placement === "right"  ? Item.Right
                           : Item.Top
            Behavior on opacity { MotionAnimation { role: root.shown ? "fade" : "exit" } }
            Behavior on scale   { MotionAnimation { role: root.shown ? "enter" : "exit" } }
            Behavior on width   { enabled: root.shown; MotionAnimation { role: "morph" } }
            Behavior on height  { enabled: root.shown; MotionAnimation { role: "morph" } }

            x: {
                let v
                if (root.placement === "left") v = root._ax + root._aw + root.gap
                else if (root.placement === "right") v = root._ax - width - root.gap
                else v = root._ax + root._aw / 2 - width / 2
                return Math.max(root.edge, Math.min(v, root._sw - width - root.edge))
            }
            y: {
                let v
                if (root.placement === "bottom") v = root._ay - height - root.gap
                else if (root.placement === "top") v = root._ay + root._ah + root.gap
                else v = root._ay + root._ah / 2 - height / 2
                return Math.max(root.edge, Math.min(v, root._sh - height - root.edge))
            }

            // клік по порожньому місцю картки не закриває панель
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Flow {
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                spacing: root.spacing

                Repeater {
                    model: root.items

                    delegate: TrayItem {
                        required property var modelData
                        item: modelData
                        placement: root.placement
                        hiddenInBar: true
                        implicitWidth: root.cell
                        implicitHeight: root.cell
                        onHideToggled: root.hideToggled(modelData)
                        onInteracted: root.close()
                    }
                }
            }
        }
    }
}
