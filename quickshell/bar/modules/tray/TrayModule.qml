import "root:/theme"
import "root:/modules/common"
import Quickshell
import Quickshell.Services.SystemTray
import QtQuick

// TrayModule — StatusNotifier-трей просто в барі (без nm-applet / окремого хоста).
// Quickshell сам стає org.kde.StatusNotifierWatcher, тож сюди потрапляють усі
// застосунки, що вміють SNI/AppIndicator: Telegram, Steam, Discord, Syncthing…
// У вертикальному барі іконки складаються в стовпчик.
BarModule {
    id: root

    property string placement: "top"        // top | bottom | left | right

    readonly property int count: SystemTray.items ? SystemTray.items.values.length : 0
    readonly property int glyphSize: Theme.type.iconS
    readonly property int cell: glyphSize + Theme.space.xs * 2

    shown: count > 0
    animate: true
    contentW: flow.implicitWidth
    contentH: flow.implicitHeight

    Flow {
        id: flow
        anchors.centerIn: parent
        flow: root.vertical ? Flow.TopToBottom : Flow.LeftToRight
        spacing: Theme.space.xxs

        Repeater {
            model: SystemTray.items

            delegate: TrayItem {
                required property var modelData
                item: modelData
                placement: root.placement
            }
        }
    }
}
