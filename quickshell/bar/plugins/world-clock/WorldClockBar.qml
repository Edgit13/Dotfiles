import qs.theme
import qs.shell
import Quickshell
import QtQuick
import QtQuick.Layouts

// Sample bar plugin. The host injects `vertical` and `cross` when the module
// is loaded; define them with defaults so the module also works standalone.
Item {
    id: root

    property bool vertical: false
    property real cross: Theme.components.dp(32)

    readonly property real size: Math.max(Theme.components.dp(20), cross)
    readonly property color fg: mouse.containsMouse ? Theme.color.primary : Theme.color.fgSurface

    implicitWidth: vertical ? size : row.implicitWidth + Theme.space.sm * 2
    implicitHeight: vertical ? size : size

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Theme.space.xs
        visible: !root.vertical

        Text {
            text: "public"
            color: root.fg
            font { family: Theme.type.icons; pixelSize: Math.round(root.size * 0.52) }
        }
        ThemedText {
            text: Qt.formatDateTime(clock.date, "HH:mm")
            style: Theme.type.labelLarge
            color: root.fg
        }
    }

    ThemedText {
        anchors.centerIn: parent
        visible: root.vertical
        text: Qt.formatDateTime(clock.date, "HH:mm")
        style: Theme.type.labelMedium
        color: root.fg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: ShellState.toggleSurface("plugin:world-clock")
    }
}
