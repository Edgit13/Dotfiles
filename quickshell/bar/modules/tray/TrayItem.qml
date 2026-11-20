pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/settings"
import "root:/modules/common"
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// TrayItem — одна іконка StatusNotifier-айтема в барі.
//   ЛКМ            — activate()
//   ПКМ            — DBusMenu (або secondaryActivate(), якщо меню немає)
//   СКМ            — secondaryActivate()
//   колесо         — scroll() (гучність/перемикання у деяких апів)
//   onlyMenu: true — ЛКМ теж відкриває меню (так роблять багато індикаторів)
BarButton {
    id: root

    required property var item
    property string placement: "top"        // top | bottom | left | right
    property bool hiddenInBar: false        // true — іконка лежить в overflow-панелі, а не в барі
    signal hideToggled()                    // Ctrl+клік або пункт меню «Сховати / Показувати в барі»
    signal interacted()                     // після activate()/secondaryActivate() — overflow-панель закривається

    readonly property int glyphSize: Theme.type.iconS
    readonly property int cell: glyphSize + Theme.space.xs * 2
    readonly property bool needsAttention: item.status === Status.NeedsAttention
    readonly property string tipTitle: item.tooltipTitle || item.title || ""
    readonly property string tipDesc: item.tooltipDescription || ""

    implicitWidth: cell
    implicitHeight: cell

    // поява нового айтема: fade + легкий pop
    property bool _entered: false
    Component.onCompleted: _entered = true
    opacity: _entered ? 1 : 0
    Behavior on opacity { MotionAnimation { role: "fade" } }
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    accent: needsAttention
    accentColor: Theme.color.errorContainer

    property double closedAt: 0             // коли меню закрилось (клік по кнопці не має його одразу відкривати знову)

    function openMenu() {
        if (!root.item.hasMenu) return
        if (menu.visible) { menu.close(); return }
        if (Date.now() - root.closedAt < 250) return
        tipTimer.stop()
        tip.visible = false
        menu.openAt(root.item.menu, root.tipTitle)
    }

    // обгортка для анімацій іконки: поява, hover-«підйом», пульс при NeedsAttention
    Item {
        id: glyph
        anchors.fill: parent
        scale: root.hovered ? 1.12 : 1.0
        Behavior on scale { MotionAnimation { role: "hover" } }

        SequentialAnimation {
            running: root.needsAttention && ThemeMotion.enabled && !ThemeMotion.reduced
            loops: Animation.Infinite
            onRunningChanged: if (!running) glyph.opacity = 1
            NumberAnimation { target: glyph; property: "opacity"; to: 0.4; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { target: glyph; property: "opacity"; to: 1.0; duration: 650; easing.type: Easing.InOutSine }
        }

        Image {
            id: icon
            anchors.centerIn: parent
            width: root.glyphSize
            height: root.glyphSize
            source: root.item.icon || ""
            sourceSize.width: root.glyphSize * 2
            sourceSize.height: root.glyphSize * 2
            fillMode: Image.PreserveAspectFit
            smooth: true
            visible: status === Image.Ready
        }

        // деякі індикатори віддають іконку, яку провайдер не знаходить
        BarIcon {
            anchors.centerIn: parent
            visible: icon.status !== Image.Ready
            text: "\ue5c3"                      // apps
            size: root.glyphSize
            color: Theme.color.fgSurfaceVariant
        }
    }

    onClicked: mouse => {
        if (mouse.modifiers & Qt.ControlModifier) {          // Ctrl+клік — сховати / повернути в бар
            root.hideToggled()
            return
        }
        if (mouse.button === Qt.MiddleButton) {
            root.item.secondaryActivate()
            root.interacted()
        } else if (mouse.button === Qt.RightButton) {
            if (root.item.hasMenu) root.openMenu()
            else { root.item.secondaryActivate(); root.interacted() }
        } else {
            if (root.item.onlyMenu && root.item.hasMenu) root.openMenu()
            else { root.item.activate(); root.interacted() }
        }
    }

    onWheeled: event => {
        const dy = event.angleDelta.y || event.pixelDelta.y
        const dx = event.angleDelta.x || event.pixelDelta.x
        const d = dy !== 0 ? dy : dx
        if (d !== 0) root.item.scroll(d > 0 ? 1 : -1, dy === 0)
    }

    onHoveredChanged: {
        if (hovered && tipTitle.length + tipDesc.length > 0) tipTimer.restart()
        else {
            tipTimer.stop()
            tip.visible = false
        }
    }

    Timer {
        id: tipTimer
        interval: 550
        onTriggered: if (root.hovered && !menu.visible) tip.visible = true
    }

    TrayMenu {
        id: menu
        anchorItem: root
        placement: root.placement
        pinLabel: root.hiddenInBar ? Lang.t("tray.show") : Lang.t("tray.hide")
        pinIcon: root.hiddenInBar ? "\ue8f4" : "\ue8f5"        // visibility / visibility_off
        onPinClicked: root.hideToggled()
        onMenuDismissed: root.closedAt = Date.now()
    }

    PopupWindow {
        id: tip

        color: "transparent"
        implicitWidth: tipBg.implicitWidth
        implicitHeight: tipBg.implicitHeight
        visible: false
        onVisibleChanged: if (visible) tipIn.restart()

        ParallelAnimation {
            id: tipIn
            NumberAnimation { target: tipBg; property: "opacity"; from: 0; to: 1; duration: ThemeMotion.duration("fade"); easing.type: Easing.OutCubic }
            NumberAnimation { target: tipBg; property: "scale"; from: 0.94; to: 1; duration: ThemeMotion.duration("enter"); easing.type: Easing.OutCubic }
        }

        anchor.item: root
        anchor.edges: root.placement === "bottom" ? Edges.Top
                    : root.placement === "left"   ? Edges.Right
                    : root.placement === "right"  ? Edges.Left
                    : Edges.Bottom
        anchor.gravity: anchor.edges
        anchor.adjustment: PopupAdjustment.Slide
        anchor.margins.top: 6
        anchor.margins.bottom: 6
        anchor.margins.left: 6
        anchor.margins.right: 6

        Rectangle {
            id: tipBg
            implicitWidth: tipCol.implicitWidth + Theme.space.md * 2
            implicitHeight: tipCol.implicitHeight + Theme.space.sm * 2
            radius: Theme.settings.nothing ? Theme.shape.sm : Theme.shape.md
            color: Theme.settings.nothing
                ? Theme.color.surfaceContainerHigh
                : Theme.color.inverseSurface
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant

            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: 2

                ThemedText {
                    visible: root.tipTitle.length > 0
                    text: root.tipTitle
                    style: Theme.type.bodyMedium
                    color: Theme.settings.nothing
                        ? Theme.color.fgSurface : Theme.color.inverseOnSurface
                    width: Math.min(implicitWidth, Theme.components.dp(240))
                    wrapMode: Text.WordWrap
                }
                ThemedText {
                    visible: root.tipDesc.length > 0
                    text: root.tipDesc
                    style: Theme.type.labelSmall
                    color: Theme.settings.nothing
                        ? Theme.color.fgSurfaceVariant : Theme.color.inverseOnSurface
                    width: Math.min(implicitWidth, Theme.components.dp(240))
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
