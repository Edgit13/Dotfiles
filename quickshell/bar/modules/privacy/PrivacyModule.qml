import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/shell"
import "root:/modules/common"
import Quickshell
import Quickshell.Wayland
import QtQuick

// PrivacyModule — «security pill» в стилі Android: зелена крапка, коли
// якийсь застосунок зараз використовує камеру або мікрофон. Поруч — гліфи
// активних пристроїв; наведення показує список застосунків.
// З'являється лише під час реального захоплення (PrivacyService).
BarModule {
    id: root

    readonly property bool cam: PrivacyService.camera.length > 0
    readonly property bool mic: PrivacyService.mic.length > 0
    readonly property int dot: Math.max(6, Math.round(Theme.space.xs * 1.5))
    readonly property int glyph: Math.max(12, Math.min(Theme.type.iconS, root.cross))
    readonly property string tipTitle: {
        const parts = []
        if (root.cam) parts.push(Lang.t("privacy.camera") + ": " + PrivacyService.cameraNames)
        if (root.mic) parts.push(Lang.t("privacy.mic") + ": " + PrivacyService.micNames)
        return parts.join("\n")
    }

    shown: PrivacyService.active
    animate: true
    contentW: row.implicitWidth + Theme.space.sm * 2
    contentH: col.implicitHeight + Theme.space.sm * 2

    BarButton {
        id: btn
        anchors.fill: parent
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

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: root.dot; height: root.dot; radius: width / 2
                color: Theme.color.success
            }
            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.mic
                text: "\ue029"                    // mic
                size: root.glyph
                color: Theme.color.success
            }
            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.cam
                text: "\ue04b"                    // videocam
                size: root.glyph
                color: Theme.color.success
            }
        }

        // вертикальний бар: те саме стовпчиком
        Column {
            id: col
            visible: root.vertical
            anchors.centerIn: parent
            spacing: Theme.space.xxs

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.dot; height: root.dot; radius: width / 2
                color: Theme.color.success
            }
            BarIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.mic
                text: "\ue029"
                size: root.glyph
                color: Theme.color.success
            }
            BarIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.cam
                text: "\ue04b"
                size: root.glyph
                color: Theme.color.success
            }
        }
    }

    Timer {
        id: tipTimer
        interval: 550
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
            implicitWidth: tipCol.implicitWidth + Theme.space.md * 2
            implicitHeight: tipCol.implicitHeight + Theme.space.sm * 2
            radius: Theme.settings.nothing ? Theme.shape.sm : Theme.shape.md
            color: Theme.settings.nothing
                ? Theme.color.surfaceContainerHigh
                : Theme.color.inverseSurface
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant

            Column {
                id: tipCol
                anchors.centerIn: parent
                spacing: 2
                ThemedText {
                    text: root.tipTitle
                    style: Theme.type.bodyMedium
                    color: Theme.settings.nothing
                        ? Theme.color.fgSurface : Theme.color.inverseOnSurface
                    width: Math.min(implicitWidth, Theme.components.dp(280))
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
