pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import Quickshell
import QtQuick
import QtQuick.Layouts

// NotificationGroup — сповіщення одного застосунку: шапка з іконкою, лічильниками
// й меню «⋮», далі connected-картки. У згорнутому вигляді — найновіша картка
// і «стопка» під нею; шапка розгортає/згортає групу.
// modelData: { key, items, unread, pinned, latest } з NotificationService.appGroups()
ColumnLayout {
    id: group
    required property var modelData
    // Repeater у центрі передає індекс як required-властивість (ComponentBehavior: Bound)
    required property int index
    readonly property string gkey: modelData.key
    readonly property var gItems: modelData.items || []
    readonly property var gLatest: modelData.latest
    readonly property int gUnread: modelData.unread || 0
    readonly property bool muted: NotificationService.isAppMuted(gkey)
    readonly property bool priority: NotificationService.hasRule("priority", gkey)
    readonly property bool blocked: NotificationService.hasRule("blocked", gkey)
    readonly property bool multi: gItems.length > 1

    // вибір з клавіатури в центрі
    property var selectedItem: null
    // staggered-вхід: центр передає index у списку, active — чи відкрита панель
    property bool active: false
    property int stackIndex: 0
    property bool entered: false
    property bool expanded: false
    signal menuRequested(var anchor, var actions)

    Layout.fillWidth: true
    spacing: Theme.space.xs
    opacity: group.entered ? 1 : 0
    transform: Translate {
        y: group.entered ? 0 : -Theme.components.dp(10)
        Behavior on y { MotionStagger { role: "enter"; delay: group.delay } }
    }
    Behavior on opacity { MotionStagger { role: "enter"; delay: group.delay } }
    readonly property int delay: Math.min(group.stackIndex, 6) * 40

    function replay() {
        group.entered = false
        enterTimer.restart()
    }
    onActiveChanged: if (group.active) group.replay()
    // якщо клавіатура вибрала картку зі згорнутої групи — розгортаємо її
    onSelectedItemChanged: {
        if (group.selectedItem && group.gItems.indexOf(group.selectedItem) > 0)
            group.expanded = true
    }
    Component.onCompleted: if (group.active) enterTimer.start()
    Timer {
        id: enterTimer
        interval: 16
        onTriggered: group.entered = true
    }

    // M3 overflow: замість п'яти іконок у шапці — одне меню
    readonly property var headerActions: {
        const list = []
        if (group.gUnread > 0)
            list.push({ icon: "done_all", label: Lang.t("ui.notif.markRead"),
                        run: function () { NotificationService.markAppRead(group.gkey) } })
        list.push({ icon: group.muted ? "volume_up" : "volume_off",
                    label: group.muted ? Lang.t("ui.notif.unmuteApp") : Lang.t("ui.notif.muteApp"),
                    active: group.muted,
                    run: function () { NotificationService.toggleMuteApp(group.gkey) } })
        list.push({ icon: "star",
                    label: group.priority ? Lang.t("ui.notif.unpriorityApp") : Lang.t("ui.notif.priorityShort"),
                    active: group.priority,
                    run: function () { NotificationService.toggleRule("priority", group.gkey) } })
        list.push({ icon: "block",
                    label: group.blocked ? Lang.t("ui.notif.unblockApp") : Lang.t("ui.notif.blockApp"),
                    danger: !group.blocked,
                    run: function () { NotificationService.toggleBlockApp(group.gkey) } })
        list.push({ icon: "close", label: Lang.t("ui.notif.clear"), danger: true,
                    run: function () { NotificationService.clearApp(group.gkey) } })
        return list
    }

    // ---- шапка ----
    Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(Theme.components.dp(44),
                                 headerRow.implicitHeight + Theme.space.xs * 2)
        Behavior on implicitHeight { MotionAnimation { role: "morph" } }

        Rectangle {
            id: headerBg
            anchors.fill: parent
            radius: Theme.shape.cardLarge
            color: headerMa.containsMouse && !Theme.settings.nothing
                ? Theme.color.surfaceContainerHigh : "transparent"
            border.width: Theme.settings.nothing && headerMa.containsMouse ? ThemeNothing.hairline : 0
            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.18)
            Behavior on color { MotionColorAnimation { role: "hover" } }
        }

        MouseArea {
            id: headerMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: group.multi ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (group.multi) group.expanded = !group.expanded
        }

        RowLayout {
            id: headerRow
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: parent.bottom
                leftMargin: Theme.space.sm
                rightMargin: Theme.space.xs
                topMargin: Theme.space.xs
                bottomMargin: Theme.space.xs
            }
            spacing: Theme.space.sm

            NotifIcon {
                Layout.preferredWidth: Theme.components.dp(28)
                Layout.preferredHeight: Theme.components.dp(28)
                Layout.alignment: Qt.AlignVCenter
                notif: group.gLatest
                appOnly: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                ThemedText {
                    Layout.fillWidth: true
                    text: group.gkey
                    style: Theme.type.labelLarge
                    emphasized: true
                    color: group.muted ? Theme.color.fgSurfaceVariant : Theme.color.fgSurface
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.xs
                    ThemedText {
                        text: group.gUnread > 0
                            ? Lang.tn("ui.notif.unreadCount", group.gUnread) + " · " + Lang.tn("ui.notif.total", group.gItems.length)
                            : Lang.tn("ui.notif.total", group.gItems.length)
                        style: Theme.type.labelSmall
                        color: group.gUnread > 0 ? Theme.color.primary : Theme.color.fgSurfaceVariant
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: group.muted
                        text: "\ue04f"      // volume_off
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                        color: Theme.color.fgSurfaceVariant
                    }
                    Text {
                        visible: group.priority
                        text: "\ue838"      // star
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                        color: Theme.color.primary
                    }
                }
            }

            MaterialIconButton {
                id: expandBtn
                visible: group.multi
                icon: group.expanded ? "expand_less" : "expand_more"
                width: Theme.components.dp(30)
                height: width
                tooltip: ""
                onClicked: group.expanded = !group.expanded
            }

            MaterialIconButton {
                id: menuBtn
                icon: "more_vert"
                width: Theme.components.dp(30)
                height: width
                tooltip: Lang.t("ui.notif.moreActions")
                onClicked: group.menuRequested(menuBtn, group.headerActions)
            }
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
                    selected: group.selectedItem === slot.modelData
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
                    onMenuRequested: (anchor, actions) => group.menuRequested(anchor, actions)
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
