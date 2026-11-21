import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/shell"
import "root:/modules/common"
import Quickshell
import Quickshell.Wayland
import QtQuick

// PrivacyModule — «security pill» у стилі Android: зелена крапка з м'якою
// хвилею, коли якийсь застосунок зараз використовує камеру або мікрофон.
// Поруч — гліфи активних пристроїв; наведення показує, хто саме тримає
// пристрій. З'являється лише під час реального захоплення (PrivacyService).
BarModule {
    id: root

    readonly property bool cam: PrivacyService.camera.length > 0
    readonly property bool mic: PrivacyService.mic.length > 0

    readonly property int dotSize: Theme.components.dp(9)
    readonly property int glyphSize: Math.max(12, Math.min(Theme.components.dp(16), root.cross - Theme.space.xs))

    // активні пристрої — один рядок тултіпа на кожен
    readonly property var rows: {
        const out = []
        if (root.mic) out.push({ key: "mic", glyph: "\ue029", label: Lang.t("privacy.mic"), names: PrivacyService.micNames })
        if (root.cam) out.push({ key: "cam", glyph: "\ue04b", label: Lang.t("privacy.camera"), names: PrivacyService.cameraNames })
        return out
    }

    readonly property color tintBg: Theme.settings.nothing ? Theme.color.surfaceContainerHigh : Theme.color.successContainer
    readonly property color tintFg: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgSuccessContainer
    readonly property color tipFg: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.inverseOnSurface
    readonly property color tipMuted: Theme.settings.nothing ? Theme.color.fgSurfaceVariant : Theme.color.inverseOnSurface
    readonly property color tipAccent: Theme.settings.nothing ? Theme.color.success : Theme.color.inversePrimary

    shown: PrivacyService.active
    animate: true
    contentW: row.implicitWidth + Theme.space.sm * 2
    contentH: col.implicitHeight + Theme.space.xs * 2

    BarButton {
        id: btn
        anchors.fill: parent
        accent: true
        accentColor: root.tintBg
        stateColor: root.tintFg

        onHoveredChanged: {
            if (hovered) tipTimer.restart()
            else { tipTimer.stop(); tip.visible = false }
        }
        onClicked: tip.visible = !tip.visible

        // горизонтальний бар: крапка + гліфи активних пристроїв
        Row {
            id: row
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Theme.space.xs

            PrivDot {
                anchors.verticalCenter: parent.verticalCenter
                dotSize: root.dotSize
                dotColor: Theme.color.success
                haloColor: Theme.color.success
            }
            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mic
                text: "\ue029"                    // mic
                size: root.glyphSize
                color: root.tintFg
            }
            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.cam
                text: "\ue04b"                    // videocam
                size: root.glyphSize
                color: root.tintFg
            }
        }

        // вертикальний бар: крапка над гліфами
        Column {
            id: col
            visible: root.vertical
            anchors.centerIn: parent
            spacing: Theme.space.xxs

            PrivDot {
                anchors.horizontalCenter: parent.horizontalCenter
                dotSize: root.dotSize
                dotColor: Theme.color.success
                haloColor: Theme.color.success
            }
            BarIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.mic
                text: "\ue029"
                size: root.glyphSize
                color: root.tintFg
            }
            BarIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.cam
                text: "\ue04b"
                size: root.glyphSize
                color: root.tintFg
            }
        }
    }

    Timer {
        id: tipTimer
        interval: 420
        onTriggered: if (btn.hovered) tip.visible = true
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
        anchor.edges: BarConfig.position === "bottom" ? Edges.Top
                    : BarConfig.position === "left"   ? Edges.Right
                    : BarConfig.position === "right"  ? Edges.Left
                    : Edges.Bottom
        anchor.gravity: anchor.edges
        anchor.adjustment: PopupAdjustment.Slide
        anchor.margins.top: 6
        anchor.margins.bottom: 6
        anchor.margins.left: 6
        anchor.margins.right: 6

        Rectangle {
            id: tipBg
            implicitWidth: Math.min(tipCol.implicitWidth, Theme.components.dp(300)) + Theme.space.md * 2
            implicitHeight: tipCol.implicitHeight + Theme.space.md * 2
            radius: Theme.settings.nothing ? Theme.shape.sm : Theme.shape.md
            color: Theme.settings.nothing
                ? Theme.color.surfaceContainerHigh
                : Theme.color.inverseSurface
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant

            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: Theme.space.sm

                Repeater {
                    model: root.rows

                    Column {
                        spacing: Theme.space.xxs

                        Row {
                            spacing: Theme.space.xs

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Theme.components.dp(5)
                                height: width
                                radius: width / 2
                                color: root.tipAccent
                            }
                            ThemedText {
                                text: modelData.label
                                style: Theme.type.labelSmall
                                color: root.tipMuted
                            }
                        }
                        ThemedText {
                            // імена застосунків; ширина обмежена, довгі назви переносяться
                            text: modelData.names
                            style: Theme.type.bodyMedium
                            color: root.tipFg
                            width: Math.min(implicitWidth, Theme.components.dp(260))
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
