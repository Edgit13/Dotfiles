import "root:/theme"
import QtQuick

// DashButton — M3 Expressive кнопка: коло/пігулка, при натисканні радіус стискається.
// variant: filled | tonal | subtle.  toggled → заливка primary.
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property string variant: "tonal"
    property bool toggled: false
    property real size: Theme.components.dp(40)
    signal clicked()

    readonly property bool nothing: Theme.settings.nothing
    readonly property bool _filled: variant === "filled" || toggled
    readonly property color base: _filled ? Theme.color.primary
                                : variant === "tonal" ? Theme.color.secondaryContainer
                                : Theme.color.surfaceContainerHighest
    readonly property color fg: _filled ? Theme.color.fgPrimary
                              : variant === "tonal" ? Theme.color.fgSecondaryContainer
                              : Theme.color.fgSurfaceVariant

    implicitHeight: size
    implicitWidth: label.length > 0 ? content.implicitWidth + Theme.space.xl : size
    radius: ma.pressed ? Theme.shape.radius("md", height) : height / 2
    opacity: enabled ? 1 : 0.38
    color: Theme.stateLayer(base, fg, ma.pressed ? Theme.components.statePressed
                                   : ma.containsMouse ? Theme.components.stateHover : 0)
    border.width: nothing ? 1 : 0
    border.color: Qt.rgba(fg.r, fg.g, fg.b, 0.28)

    Behavior on radius { MotionAnimation { role: "morph" } }
    Behavior on color  { MotionColorAnimation { role: "hover" } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: Theme.space.xs
        Text {
            visible: root.icon.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
            color: root.fg
        }
        ThemedText {
            visible: root.label.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            style: Theme.type.labelLarge
            color: root.fg
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
