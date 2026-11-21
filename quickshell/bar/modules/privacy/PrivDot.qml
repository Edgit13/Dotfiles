import "root:/theme"
import QtQuick

// PrivDot — «крапка приватності»: рівне зелене ядро і м'яка хвиля, що розходиться
// раз на ~2.6 с, наче живий індикатор, а не статична піксельна точка.
// Хвиля й «подих» ядра вимикаються при reduce-motion або вимкнених анімаціях.
Item {
    id: root

    property real dotSize: Theme.components.dp(9)
    property color dotColor: Theme.color.success
    property color haloColor: Theme.color.success
    property bool pulsing: true

    readonly property bool _pulse: pulsing && ThemeMotion.enabled && !ThemeMotion.reduced

    implicitWidth: dotSize
    implicitHeight: dotSize

    Rectangle {
        id: core
        anchors.centerIn: parent
        width: root.dotSize
        height: width
        radius: width / 2
        color: root.dotColor

        SequentialAnimation on opacity {
            id: breath
            running: root._pulse
            loops: Animation.Infinite
            onRunningChanged: if (!running) core.opacity = 1
            NumberAnimation { to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.72; duration: 1300; easing.type: Easing.InOutSine }
        }
    }

    // хвиля: тонке кільце повільно виходить за межі крапки й тане
    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: root.dotSize
        height: width
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Math.round(root.dotSize / 5))
        border.color: root.haloColor
        opacity: 0

        SequentialAnimation {
            id: wave
            running: root._pulse
            loops: Animation.Infinite
            PauseAnimation { duration: 1000 }
            ParallelAnimation {
                NumberAnimation { target: halo; property: "scale"; from: 1.0; to: 2.6; duration: 1500; easing.type: Easing.OutCubic }
                NumberAnimation { target: halo; property: "opacity"; from: 0.5; to: 0.0; duration: 1500; easing.type: Easing.OutCubic }
            }
            PropertyAction { target: halo; property: "scale"; value: 1.0 }
            PropertyAction { target: halo; property: "opacity"; value: 0 }
        }
    }
}
