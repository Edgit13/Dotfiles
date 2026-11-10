import "root:/theme"
import "root:/services"
import "root:/notifications"
import "root:/modules/common"
import QtQuick

// NotificationModule — M3 Expressive: дзвіночок із бейджем непрочитаних, що при новому
// сповіщенні розгортається у пігулку з іконкою застосунку, заголовком, текстом,
// позначкою закріплення та прогресом таймера, а потім згортається назад.
// ЛКМ: центр сповіщень · ПКМ: сховати поточне / «Не турбувати» · СКМ: «Не турбувати».
BarModule {
    id: root

    readonly property int count: NotificationService.count
    readonly property int unread: NotificationService.unreadCount
    readonly property bool dnd: NotificationService.dnd
    readonly property var live: NotificationService.barLive ? NotificationService.latest : null
    readonly property bool expanded: !!live && !vertical

    // тримаємо останнє для анімації згортання
    property var shownItem: null
    onLiveChanged: if (live) shownItem = live
    readonly property bool critical: !!shownItem && shownItem.urgency === 2
    readonly property bool pinned: !!shownItem && !!shownItem.pinned
    readonly property bool unreadLive: !!shownItem && !shownItem.read

    readonly property bool active: count > 0 && !dnd
    readonly property string glyph: dnd ? "\ue7f6" : (count > 0 ? "\ue7f5" : "\ue7f4")
    // бейдж показує саме непрочитані; якщо всі прочитані — лише тиха крапка
    readonly property string badgeText: unread > 99 ? "99+" : String(unread)
    readonly property bool quietDot: count > 0 && unread === 0

    function esc(t) { return String(t || "").replace(/<[^>]*>/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;") }

    readonly property real bellW: bellRow.implicitWidth + Theme.space.sm * 2
    readonly property real liveW: Math.min(Theme.components.dp(360), liveRow.implicitWidth + Theme.space.md * 2)

    animate: true
    widthRole: expanded ? "expand" : "collapse"
    contentW: expanded ? liveW : bellW
    contentH: (root.count > 0 || live) ? (contentCol.implicitHeight + Theme.space.xs * 2) : cross

    // колір вмісту залежить від стану плашки (є непрочитані / критичне / DND)
    readonly property bool tinted: (expanded && critical) || dnd
    readonly property color fg: tinted ? Theme.color.fgErrorContainer
                              : (expanded || active) ? Theme.color.fgSecondaryContainer
                              : Theme.color.fgSurfaceVariant
    readonly property color badgeColor: critical ? Theme.color.error
                                     : (dnd ? Theme.color.fgSurfaceVariant : Theme.color.primary)

    HoverHandler { onHoveredChanged: if (root.live) root.live.paused = hovered }

    BarButton {
        id: btn
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        pressScale: 0.96
        fillColor: root.tinted ? Theme.color.errorContainer
                 : (root.expanded || root.active) ? Theme.color.secondaryContainer
                 : "transparent"
        stateColor: root.tinted ? Theme.color.fgErrorContainer
                  : (root.expanded || root.active) ? Theme.color.fgSecondaryContainer
                  : Theme.color.fgSurface
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                if (root.live) NotificationService.hidePopup(root.live)
                else NotificationService.setDnd(!NotificationService.dnd)
            } else if (mouse.button === Qt.MiddleButton) {
                NotificationService.setDnd(!NotificationService.dnd)
            } else NotificationService.toggleCenter()
        }

        // ---- дзвіночок (спокій) ----
        Row {
            id: bellRow
            visible: !root.vertical
            anchors.centerIn: parent
            spacing: Theme.space.xs
            opacity: root.expanded ? 0 : 1
            Behavior on opacity { MotionAnimation { role: "fade" } }

            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                text: root.glyph
                color: root.fg
                scale: root.unread > 0 ? 1 : 0.96
                Behavior on color { MotionColorAnimation { role: "hover" } }
                Behavior on scale { MotionAnimation { role: "press" } }
            }

            // бейдж непрочитаних
            Rectangle {
                visible: root.unread > 0 || scale > 0.01
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Math.max(Theme.components.dp(15), badgeTxt.implicitWidth + Theme.space.xs)
                implicitHeight: Theme.components.dp(15)
                radius: height / 2
                color: root.badgeColor
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Theme.color.fgSurface
                scale: root.unread > 0 ? 1 : 0
                Behavior on scale { MotionAnimation { role: "enter" } }
                Behavior on implicitWidth { MotionAnimation { role: "stateChange" } }
                Behavior on color { MotionColorAnimation { role: "stateChange" } }

                ThemedText {
                    id: badgeTxt
                    anchors.centerIn: parent
                    text: root.badgeText
                    style: Theme.type.labelSmall
                    emphasized: true
                    color: Theme.color.fgPrimary
                }
            }

            // усі прочитані, але історія не порожня — тиха крапка
            Rectangle {
                visible: root.quietDot || scale > 0.01
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: Theme.components.dp(5)
                implicitHeight: implicitWidth
                radius: width / 2
                color: root.fg
                opacity: 0.5
                scale: root.quietDot ? 1 : 0
                Behavior on scale { MotionAnimation { role: "enter" } }
            }
        }

        // ---- живе сповіщення ----
        Row {
            id: liveRow
            visible: !root.vertical && opacity > 0.01
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.space.sm
            spacing: Theme.space.sm
            opacity: root.expanded ? 1 : 0
            Behavior on opacity { MotionAnimation { role: root.expanded ? "enter" : "fade" } }

            Loader {
                anchors.verticalCenter: parent.verticalCenter
                active: !!root.shownItem
                sourceComponent: NotifIcon {
                    notif: root.shownItem
                    critical: root.critical
                    width: root.cross - Theme.space.sm
                    height: width
                }
            }
            ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.unreadLive
                text: "\u2022"
                style: Theme.type.labelLarge
                color: root.badgeColor
            }
            ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.shownItem
                textFormat: Text.StyledText
                text: root.shownItem
                      ? ("<b>" + root.esc(root.shownItem.summary) + "</b>"
                         + (root.shownItem.body ? "&nbsp;&nbsp;" + root.esc(root.shownItem.body) : ""))
                      : ""
                style: Theme.type.labelMedium
                color: root.fg
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(implicitWidth, Theme.components.dp(360) - root.cross - Theme.space.md * 3)
            }
            // закріплене сповіщення
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.pinned
                text: "\ue840"
                font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                color: root.fg
                opacity: 0.85
            }
            // скільки ще непрочитаних
            ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.unread > 1
                text: "+" + (root.unread - 1)
                style: Theme.type.labelSmall
                color: root.fg
                opacity: 0.75
            }
        }

        // ---- вертикальний бар ----
        Column {
            id: contentCol
            visible: root.vertical
            anchors.centerIn: parent
            spacing: 2

            Loader {
                anchors.horizontalCenter: parent.horizontalCenter
                active: root.vertical && !!root.live
                visible: active
                sourceComponent: NotifIcon {
                    notif: root.live
                    critical: root.live && root.live.urgency === 2
                    width: root.cross - Theme.space.sm
                    height: width
                }
            }
            BarIcon {
                visible: !root.live
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.glyph
                color: root.fg
                Behavior on color { MotionColorAnimation { role: "hover" } }
            }
            // бейдж / крапка
            Rectangle {
                visible: root.unread > 0 || scale > 0.01
                anchors.horizontalCenter: parent.horizontalCenter
                implicitWidth: Math.max(Theme.components.dp(14), badgeV.implicitWidth + Theme.space.xs)
                implicitHeight: Theme.components.dp(14)
                radius: height / 2
                color: root.badgeColor
                scale: root.unread > 0 ? 1 : 0
                Behavior on scale { MotionAnimation { role: "enter" } }
                Behavior on implicitWidth { MotionAnimation { role: "stateChange" } }
                Behavior on color { MotionColorAnimation { role: "stateChange" } }
                ThemedText {
                    id: badgeV
                    anchors.centerIn: parent
                    text: root.badgeText
                    style: Theme.type.labelSmall
                    emphasized: true
                    color: Theme.color.fgPrimary
                }
            }
            Rectangle {
                visible: root.quietDot || scale > 0.01
                anchors.horizontalCenter: parent.horizontalCenter
                width: 5; height: 5
                radius: 2.5
                color: root.fg
                opacity: 0.5
                scale: root.quietDot ? 1 : 0
                Behavior on scale { MotionAnimation { role: "enter" } }
            }
            Text {
                visible: root.pinned
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\ue840"
                font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                color: root.fg
            }
        }

        // ---- прогрес таймера ----
        Rectangle {
            visible: root.expanded && !!root.shownItem && root.shownItem.totalMs > 0
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.components.dp(3)
            x: btn.cornerRadius * 0.6
            height: Theme.components.dp(2)
            radius: height / 2
            width: root.shownItem && root.shownItem.totalMs > 0
                   ? (btn.width - btn.cornerRadius * 1.2) * Math.max(0, root.shownItem.remainingMs / root.shownItem.totalMs) : 0
            color: root.critical ? Theme.color.error : Theme.color.primary
            opacity: 0.85
            Behavior on width { NumberAnimation { duration: 40 } }
        }
    }
}
