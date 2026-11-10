import "root:/theme"
import QtQuick
import QtQuick.Effects

// ArtBackdrop — розмита обкладинка як фон картки (dux-style). Без обкладинки — порожньо.
Item {
    id: root
    property url source: ""
    property real radius: Theme.shape.cardLarge
    property real strength: 0.55                 // 0..1 — наскільки видно кольори обкладинки

    readonly property bool ready: img.status === Image.Ready

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.radius }
    }

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 96
        sourceSize.height: 96
        opacity: root.ready ? root.strength : 0
        Behavior on opacity { MotionAnimation { role: "enter" } }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            saturation: Theme.settings.nothing ? -0.9 : 0.35
        }
    }
}
