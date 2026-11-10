import "root:/theme"
import Quickshell
import QtQuick

// ClockTile — великий годинник. Material: primaryContainer. Nothing: dot-matrix + червоне блимаюче «:».
DashCard {
    id: root
    fill: Theme.color.primaryContainer
    cornerRadius: Theme.shape.radius("xl", height)
    readonly property bool nothing: Theme.settings.nothing

    SystemClock { id: clk; precision: SystemClock.Seconds }

    // Material
    Text {
        visible: !root.nothing
        anchors.fill: parent
        anchors.bottomMargin: Theme.components.dp(20)
        text: Qt.formatDateTime(clk.date, "HH:mm")
        color: Theme.color.fgPrimaryContainer
        font.family: Theme.type.sans
        font.weight: Font.Bold
        font.pixelSize: height
        fontSizeMode: Text.Fit
        minimumPixelSize: 24
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    // Nothing
    Row {
        id: dotClock
        visible: root.nothing
        readonly property real fs: Math.min(root.height * 0.62, root.width / 3.3)
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -Theme.components.dp(10)
        spacing: 0
        Text { text: Qt.formatDateTime(clk.date, "HH"); font.family: Theme.type.dot; font.pixelSize: dotClock.fs; color: Theme.color.fgSurface }
        Text {
            text: ":"
            font.family: Theme.type.dot; font.pixelSize: dotClock.fs
            color: ThemeNothing.red
            opacity: clk.date.getSeconds() % 2 === 0 ? 1 : 0.15
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Text { text: Qt.formatDateTime(clk.date, "mm"); font.family: Theme.type.dot; font.pixelSize: dotClock.fs; color: Theme.color.fgSurface }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        spacing: Theme.space.xs
        Rectangle {
            visible: root.nothing
            width: 5; height: 5; radius: 2.5
            anchors.verticalCenter: parent.verticalCenter
            color: ThemeNothing.red
        }
        ThemedText {
            text: Qt.formatDate(clk.date, "dddd, d MMMM")
            style: Theme.type.labelMedium
            color: root.nothing ? Theme.color.fgSurfaceVariant : Theme.color.fgPrimaryContainer
            opacity: root.nothing ? 1 : 0.72
            font.letterSpacing: root.nothing ? 2 : style.tracking
            font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
        }
    }
}
