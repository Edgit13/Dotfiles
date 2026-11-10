import "root:/theme"
import QtQuick

Rectangle {
    id: chip
    property string icon: ""
    property string label: ""
    implicitHeight: Theme.components.dp(28)
    implicitWidth: chipRow.implicitWidth + Theme.space.md * 2
    radius: height / 2
    color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainerHighest
    border.width: Theme.settings.nothing ? 1 : 0
    border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.28)
    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: Theme.space.xs
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.icon
            font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
            color: Theme.settings.nothing ? ThemeNothing.red : Theme.color.primary
        }
        ThemedText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.label
            style: Theme.type.labelMedium
            color: Theme.color.fgSurfaceVariant
        }
    }
}
