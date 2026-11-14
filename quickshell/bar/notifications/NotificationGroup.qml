pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import Quickshell
import QtQuick
import QtQuick.Layouts

// NotificationGroup — сповіщення одного застосунку: заголовок + connected list карток.
// У згорнутому вигляді — найновіша картка і «стопка» під нею.
// modelData: { key, items, unread, pinned, latest } з NotificationService.appGroups()
ColumnLayout {
    id: group
    required property var modelData
    readonly property string gkey: modelData.key
    readonly property var gItems: modelData.items || []
    readonly property var gLatest: modelData.latest
    readonly property int gUnread: modelData.unread || 0
    readonly property bool muted: NotificationService.isAppMuted(gkey)
    property bool expanded: false

    Layout.fillWidth: true
    spacing: Theme.space.xs

    // ---- заголовок ----
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: Theme.space.xs
        spacing: Theme.space.xs

        Rectangle {
            implicitWidth: Theme.components.dp(18)
            implicitHeight: implicitWidth
            radius: width / 2
            color: group.muted ? "transparent" : Theme.color.primary
            border.width: group.muted ? 1 : 0
            border.color: Theme.color.outlineVariant
            opacity: group.muted ? 0.55 : 1
        }
        ThemedText {
            Layout.fillWidth: true
            text: group.gkey
            style: Theme.type.labelLarge
            emphasized: true
            color: group.muted ? Theme.color.fgSurfaceVariant : Theme.color.primary
            elide: Text.ElideRight
        }
        Rectangle {
            visible: group.gUnread > 0
            implicitWidth: unreadTxt.implicitWidth + Theme.space.sm
            implicitHeight: Theme.components.dp(18)
            radius: height / 2
            color: Theme.settings.nothing ? "transparent" : Theme.color.primaryContainer
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.35)
            ThemedText {
                id: unreadTxt
                anchors.centerIn: parent
                text: group.gUnread
                style: Theme.type.labelSmall
                color: Theme.color.fgPrimaryContainer
            }
        }
        Rectangle {
            visible: group.gItems.length > 1
            implicitWidth: cnt.implicitWidth + Theme.space.sm
            implicitHeight: Theme.components.dp(18)
            radius: height / 2
            color: Theme.settings.nothing ? "transparent" : Theme.color.secondaryContainer
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.35)
            ThemedText {
                id: cnt
                anchors.centerIn: parent
                text: group.gItems.length
                style: Theme.type.labelSmall
                color: Theme.color.fgSecondaryContainer
            }
        }
        MaterialIconButton {
            icon: group.muted ? "volume_off" : "volume_up"
            width: Theme.components.dp(30); height: width
            opacity: group.muted ? 1 : 0.6
            onClicked: NotificationService.toggleMuteApp(group.gkey)
        }
        MaterialIconButton {
            icon: "block"
            width: Theme.components.dp(30); height: width
            selected: NotificationService.hasRule("blocked", group.gkey)
            opacity: selected ? 1 : 0.6
            tooltip: selected ? Lang.t("ui.notif.unblockApp") : Lang.t("ui.notif.blockApp")
            onClicked: NotificationService.toggleBlockApp(group.gkey)
        }
        MaterialIconButton {
            icon: "star"
            width: Theme.components.dp(30); height: width
            selected: NotificationService.hasRule("priority", group.gkey)
            opacity: selected ? 1 : 0.6
            tooltip: selected ? Lang.t("ui.notif.unpriorityApp") : Lang.t("ui.notif.priorityApp")
            onClicked: NotificationService.toggleRule("priority", group.gkey)
        }
        MaterialIconButton {
            visible: group.gItems.length > 1
            icon: group.expanded ? "expand_less" : "expand_more"
            width: Theme.components.dp(30); height: width
            onClicked: group.expanded = !group.expanded
        }
        MaterialIconButton {
            icon: "close"
            width: Theme.components.dp(30); height: width
            onClicked: NotificationService.clearApp(group.gkey)
        }
    }

    // ---- картки ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: Theme.space.listGap

        Repeater {
            model: ScriptModel { values: group.gItems }

            Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool shown: (group.expanded || index === 0) && !leaving
                property bool leaving: false
                readonly property int lastShown: group.expanded ? group.gItems.length - 1 : 0
                readonly property int stagger: Math.min(index, 5) * 26

                Layout.fillWidth: true
                implicitHeight: shown ? card.implicitHeight : 0
                visible: implicitHeight > 0.5
                clip: true
                scale: slot.shown ? 1 : 0.97
                Behavior on implicitHeight { MotionAnimation { role: "morph" } }
                Behavior on scale { MotionStagger { role: slot.shown ? "enter" : "exit"; delay: slot.shown ? slot.stagger : 0 } }

                NotificationCard {
                    id: card
                    width: parent.width
                    notif: slot.modelData
                    expanded: group.expanded
                    topR: slot.index === 0 ? Theme.shape.cardLarge : Theme.shape.listInner
                    bottomR: slot.index === slot.lastShown ? Theme.shape.cardLarge : Theme.shape.listInner
                    opacity: slot.shown ? 1 : 0
                    Behavior on opacity { MotionStagger { role: slot.shown ? "enter" : "exit"; delay: slot.shown ? slot.stagger : 0 } }
                    onRemoved: {
                        if (slot.leaving) return
                        slot.leaving = true
                        leaveTimer.start()
                    }
                    Timer {
                        id: leaveTimer
                        interval: ThemeMotion.duration("morph") + 60
                        onTriggered: NotificationService.dismiss(slot.modelData)
                    }
                }
            }
        }

        // «стопка» під згорнутою групою
        Item {
            Layout.fillWidth: true
            implicitHeight: (!group.expanded && group.gItems.length > 1) ? Theme.components.dp(12) : 0
            visible: implicitHeight > 0.5
            clip: true
            opacity: group.expanded ? 0 : 1
            scale: group.expanded ? 0.94 : 1
            transformOrigin: Item.Top
            Behavior on implicitHeight { MotionAnimation { role: "morph" } }
            Behavior on opacity { MotionAnimation { role: group.expanded ? "exit" : "enter" } }
            Behavior on scale { MotionAnimation { role: group.expanded ? "exit" : "enter" } }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.components.dp(-8)
                width: parent.width * 0.93
                height: Theme.components.dp(16)
                radius: Theme.shape.md
                color: Theme.color.surfaceContainerHigh
                opacity: 0.7
            }
            Rectangle {
                visible: group.gItems.length > 2
                anchors.horizontalCenter: parent.horizontalCenter
                y: Theme.components.dp(-2)
                width: parent.width * 0.86
                height: Theme.components.dp(12)
                radius: Theme.shape.md
                color: Theme.color.surfaceContainerHigh
                opacity: 0.45
            }
        }
    }
}
