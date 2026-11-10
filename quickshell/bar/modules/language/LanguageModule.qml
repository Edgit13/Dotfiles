import "root:/theme"
import "root:/shell"
import "root:/services"
import "root:/modules/common"
import QtQuick

// LanguageModule — розкладки клавіатури системи (з конфіга MangoWC), активна підсвічена.
// Клік — наступна розкладка.
BarModule {
    id: root

    readonly property var layouts: KeyboardService.layouts
    readonly property string active: KeyboardService.activeCode

    animate: true
    contentW: row.implicitWidth + Theme.space.md * 2
    contentH: col.implicitHeight + Theme.space.xs * 2

    BarButton {
        anchors.fill: parent
        onClicked: KeyboardService.next()

        // горизонтальний бар: US · UA, активна — жирна й яскрава
        Row {
            id: row
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Theme.space.xs
            Repeater {
                model: root.layouts
                delegate: Row {
                    id: item
                    required property int index
                    required property string modelData
                    readonly property bool isActive: modelData === root.active
                    spacing: Theme.space.xs
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        visible: item.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3; height: 3; radius: 1.5
                        color: Theme.settings.nothing ? ThemeNothing.red : Theme.color.outline
                    }
                    ThemedText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: item.modelData.toUpperCase()
                        style: Theme.type.labelLarge
                        emphasized: item.isActive
                        color: item.isActive ? Theme.color.fgSurface : Theme.color.fgSurfaceVariant
                        opacity: item.isActive ? 1 : 0.6
                        scale: item.isActive ? 1.0 : 0.92
                        transformOrigin: Item.Center
                        Behavior on color { MotionColorAnimation { role: "stateChange" } }
                        Behavior on opacity { MotionAnimation { role: "stateChange" } }
                        Behavior on scale { MotionAnimation { role: "stateChange" } }
                    }
                }
            }
        }

        // вертикальний бар: лише активна
        Column {
            id: col
            visible: root.vertical
            anchors.centerIn: parent
            ThemedText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (root.active || "??").toUpperCase()
                style: Theme.type.monoSmall
                emphasized: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }
}
