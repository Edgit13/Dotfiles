import "root:/theme"
import QtQuick

// NotifMenu — легке M3-меню всередині панелі сповіщень (не окреме вікно).
// Живе в координатах батьківського Item (панелі центру), тому не втрачає кліки
// на layer-shell поверхні й не потребує popup-surface.
//
// actions: [{ icon, label, hint, active, danger, visible, run }]
// run викликається перед закриттям.
Item {
    id: root

    property var actions: []
    property Item anchorItem: null
    property bool open: false
    property bool above: false

    readonly property int rowH: Theme.components.dp(38)
    readonly property int pad: Theme.space.xs
    readonly property var shown: (root.actions || []).filter(a => a.visible !== false)

    signal closed()

    width: Theme.components.dp(272)
    height: root.shown.length * root.rowH + root.pad * 2
    visible: root.open || opacity > 0.01
    enabled: root.open
    z: 950
    opacity: root.open ? 1 : 0
    scale: root.open ? 1 : 0.96
    transformOrigin: root.above ? Item.BottomRight : Item.TopRight
    Behavior on opacity { MotionAnimation { role: root.open ? "enter" : "exit" } }
    Behavior on scale { MotionAnimation { role: root.open ? "enter" : "exit" } }

    function show(anchor, list) {
        root.actions = list || []
        root.anchorItem = anchor
        if (!anchor || !root.parent) return
        const rows = root.shown.length
        const h = rows * root.rowH + root.pad * 2
        const p = anchor.mapToItem(root.parent, 0, 0)
        const spaceW = root.parent.width
        const spaceH = root.parent.height
        let x = p.x + anchor.width - root.width
        let y = p.y + anchor.height + Theme.space.xs
        root.above = y + h > spaceH - Theme.space.sm
        if (root.above) y = p.y - h - Theme.space.xs
        root.x = Math.max(Theme.space.sm, Math.min(x, spaceW - root.width - Theme.space.sm))
        root.y = Math.max(Theme.space.sm, y)
        root.open = true
    }

    function close() {
        if (!root.open) return
        root.open = false
        root.closed()
    }

    ElevationShadow {
        anchors.fill: parent
        level: 0.9
        radius: Theme.shape.menu
        color: Theme.color.surfaceContainerHigh
    }

    Column {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: 0

        Repeater {
            model: root.shown

            Rectangle {
                id: row
                required property var modelData
                readonly property bool hot: rowMa.containsMouse

                width: parent.width
                height: root.rowH
                radius: Theme.shape.listInner
                color: row.hot
                    ? (row.modelData.danger
                        ? Qt.rgba(Theme.color.error.r, Theme.color.error.g, Theme.color.error.b, 0.12)
                        : Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.08))
                    : "transparent"
                Behavior on color { MotionColorAnimation { role: "hover" } }

                Text {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.space.sm
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.components.dp(20)
                    horizontalAlignment: Text.AlignHCenter
                    text: row.modelData.icon || ""
                    color: row.modelData.danger ? Theme.color.error
                         : row.modelData.active ? Theme.color.primary
                         : Theme.color.fgSurfaceVariant
                    font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                }
                ThemedText {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: Theme.space.sm
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space.sm
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label || ""
                    style: Theme.type.bodyMedium
                    color: row.modelData.danger ? Theme.color.error
                         : row.modelData.active ? Theme.color.primary
                         : Theme.color.fgSurface
                    elide: Text.ElideRight
                }
                Text {
                    visible: !!row.modelData.hint
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.space.sm
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.hint || ""
                    color: Theme.color.fgSurfaceVariant
                    font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const run = row.modelData.run
                        root.close()
                        if (run) run()
                    }
                }
            }
        }
    }
}
