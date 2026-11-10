import QtQuick
import "root:/theme"

// LockDevBadge — значок «DEV» + тост останньої дії (лише коли ввімкнено режим розробника).
Item {
    id: root
    property var ctl
    readonly property var dev: (ctl && ctl.devKeys !== undefined) ? ctl.devKeys : null
    readonly property bool nothing: Theme.settings.nothing

    visible: dev !== null && dev.enabled
    z: 100
    width: row.implicitWidth
    height: 30

    Row {
        id: row
        spacing: 8
        Rectangle {
            width: tag.implicitWidth + 20; height: 30; radius: 15
            color: root.nothing ? "transparent" : Theme.color.tertiaryContainer
            border.width: root.nothing ? 1 : 0
            border.color: ThemeNothing.red
            Text {
                id: tag
                anchors.centerIn: parent
                text: "DEV"
                color: root.nothing ? ThemeNothing.red : Theme.color.fgTertiaryContainer
                font { family: Theme.type.mono; pixelSize: 13; weight: Font.Bold; letterSpacing: 2 }
            }
        }
        Rectangle {
            visible: root.dev !== null && root.dev.toast.length > 0
            width: toastTxt.implicitWidth + 24; height: 30; radius: 15
            color: Theme.color.surfaceContainerHigh
            border.width: 1
            border.color: Theme.color.outlineVariant
            Text {
                id: toastTxt
                anchors.centerIn: parent
                text: root.dev ? root.dev.toast : ""
                color: Theme.color.fgSurface
                font { family: Theme.type.mono; pixelSize: 13 }
            }
        }
    }
}
