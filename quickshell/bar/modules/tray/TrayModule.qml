import "root:/theme"
import "root:/shell"
import "root:/modules/common"
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// TrayModule — StatusNotifier-трей просто в барі (без nm-applet / окремого хоста).
// Quickshell сам стає org.kde.StatusNotifierWatcher, тож сюди потрапляють усі
// застосунки, що вміють SNI/AppIndicator: Telegram, Steam, Discord, Syncthing…
// У вертикальному барі іконки складаються в стовпчик.
//
// Як у Windows: іконку можна сховати з бару (Ctrl+клік по ній або пункт «Сховати з бару» в її меню).
// Сховані лежать за шевроном ⌄ у картці «приховані значки»; там само вони повертаються в бар.
// Список схованих зберігається в налаштуваннях (bar.trayHidden).
BarModule {
    id: root

    property string placement: "top"        // top | bottom | left | right

    readonly property var allItems: SystemTray.items ? SystemTray.items.values : []
    readonly property var hiddenKeys: BarConfig.trayHidden
    function keyOf(it) { return String((it && (it.id || it.title)) || "") }
    readonly property var barItems: allItems.filter(it => hiddenKeys.indexOf(keyOf(it)) < 0)
    readonly property var overflowItems: allItems.filter(it => hiddenKeys.indexOf(keyOf(it)) >= 0)

    readonly property int count: allItems.length
    readonly property int glyphSize: Theme.type.iconS
    readonly property int cell: glyphSize + Theme.space.xs * 2

    shown: barItems.length + (overflowItems.length > 0 ? 1 : 0) > 0
    animate: true
    contentW: flow.implicitWidth
    contentH: flow.implicitHeight

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: Theme.space.xxs

        Repeater {
            model: root.barItems

            delegate: TrayItem {
                required property var modelData
                item: modelData
                placement: root.placement
                onHideToggled: BarConfig.toggleTrayHidden(root.keyOf(modelData))
            }
        }

        // шеврон «приховані значки»
        BarButton {
            id: more
            visible: root.overflowItems.length > 0
            implicitWidth: root.cell
            implicitHeight: root.cell

            BarIcon {
                anchors.centerIn: parent
                size: root.glyphSize
                color: overflow.shown ? Theme.color.fgSurface : Theme.color.fgSurfaceVariant
                text: root.placement === "bottom" ? "\ue5ce"      // expand_less
                    : root.placement === "left"   ? "\ue5cc"      // chevron_right
                    : root.placement === "right"  ? "\ue5cb"      // chevron_left
                    : "\ue5cf"                                    // expand_more
            }
            onClicked: overflow.toggleAt(more)
        }
    }

    TrayOverflow {
        id: overflow
        placement: root.placement
        items: root.overflowItems
        onHideToggled: item => BarConfig.toggleTrayHidden(root.keyOf(item))
    }
}
