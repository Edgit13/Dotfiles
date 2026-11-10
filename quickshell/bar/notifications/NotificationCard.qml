pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/settings"
import "root:/services"
import QtQuick
import QtQuick.Layouts

// NotificationCard — M3 Expressive картка сповіщення (спливаюча і в центрі).
//  • свайп ліворуч — прибрати; свайп праворуч — закріпити (у центрі) / відкласти (у попапі)
//  • тап — дія за замовчуванням / розгорнути
//  • швидкі дії: закріпити, відкласти, копіювати, вимкнути застосунок, закрити
//  • popup: тінь, прогрес таймера, пауза при hover; critical — errorContainer + акцентна смуга
Item {
    id: card

    required property var notif
    property bool popup: false
    property bool expanded: false
    property real topR: Theme.shape.cardLarge
    property real bottomR: Theme.shape.cardLarge
    signal removed()

    readonly property bool critical: notif.urgency === 2
    readonly property bool pinned: !!notif.pinned
    readonly property bool muted: NotificationService.appMuted(card.notif)
    readonly property bool unread: !notif.read
    readonly property string appKey: NotificationService.appKey(card.notif)
    readonly property real pad: NotificationService.densePad
    readonly property real iconPx: Math.max(28, NotificationService.iconSize)
    readonly property bool accented: NotificationService.accent && (card.critical || card.pinned)

    implicitWidth: NotificationService.cardWidth
    implicitHeight: surface.height

    // у popup показуємо всі дії крім default (він = тап); у центрі — усі
    readonly property var shownActions: {
        if (!NotificationService.showActions) return []
        const out = []
        for (let i = 0; i < notif.actions.length; i++) {
            const a = notif.actions[i]
            if (a.id === "default") { if (!card.popup) out.push({ id: a.id, text: a.text || Lang.t("ui.notif.open") }) }
            else out.push(a)
        }
        return out
    }

    property bool copied: false
    Timer { id: copiedTimer; interval: 1200; onTriggered: card.copied = false }

    function activate() {
        NotificationService.markRead(notif)
        if (card.popup) {
            if (notif.hasDefault()) { notif.invoke("default"); card.removed() }
            else notif.popup = false                 // сховати у центр
        } else card.expanded = !card.expanded
    }
    function release() {
        const w = Math.max(1, surface.width)
        if (surface.x < -w * 0.28) {
            surface.flying = true
            flyOut.to = -w * 1.15
            flyOut.start()
        } else if (surface.x > w * 0.28) {
            // праворуч: попап — відкласти, центр — закріпити
            if (card.popup) NotificationService.snooze(notif)
            else NotificationService.togglePin(notif)
            surface.x = 0
        } else surface.x = 0
    }

    HoverHandler {
        id: hover
        enabled: card.popup
        onHoveredChanged: card.notif.paused = hovered
    }

    Item {
        id: surface
        width: card.width
        height: bg.height
        property bool flying: false
        readonly property real swipe: Math.max(-1, Math.min(1, x / Math.max(1, width)))
        opacity: 1 - Math.min(1, Math.abs(x) / (width * 0.95)) * 0.8
        rotation: surface.swipe * 2.5
        scale: drag.active ? 0.985 : 1
        transformOrigin: Item.Center

        Behavior on x { enabled: !drag.active && !surface.flying; MotionAnimation { role: "morph" } }
        Behavior on scale { enabled: !drag.active; MotionAnimation { role: "press" } }
        MotionAnimation { id: flyOut; target: surface; property: "x"; role: "exit"; onFinished: card.removed() }

        DragHandler {
            id: drag
            target: surface
            xAxis.enabled: true
            yAxis.enabled: false
            onActiveChanged: if (!active) card.release()
        }
        TapHandler { onTapped: card.activate() }

        ElevationShadow {
            visible: card.popup
            anchors.fill: bg
            level: 0.5
            radius: Theme.shape.cardLarge
            color: card.critical ? Theme.color.errorContainer : Theme.color.surfaceContainerHigh
        }

        Rectangle {
            id: bg
            width: parent.width
            height: content.implicitHeight + card.pad * 2
            color: card.critical ? Theme.color.errorContainer : Theme.color.surfaceContainerHigh
            border.width: (Theme.settings.nothing && card.popup) ? ThemeNothing.hairline : 0
            border.color: card.critical ? Theme.color.error : Theme.color.outlineVariant
            topLeftRadius: card.topR
            topRightRadius: card.topR
            bottomLeftRadius: card.bottomR
            bottomRightRadius: card.bottomR
            clip: true
            Behavior on color { MotionColorAnimation { role: "stateChange" } }
            Behavior on topLeftRadius { MotionAnimation { role: "morph" } }
            Behavior on topRightRadius { MotionAnimation { role: "morph" } }
            Behavior on bottomLeftRadius { MotionAnimation { role: "morph" } }
            Behavior on bottomRightRadius { MotionAnimation { role: "morph" } }
            Behavior on height { MotionAnimation { role: "morph" } }

            // акцентна смуга важливості / закріплення
            Rectangle {
                visible: card.accented
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: Theme.components.dp(4)
                color: card.critical ? Theme.color.error
                     : (Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.primary)
                opacity: 0.95
            }

            ColumnLayout {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    leftMargin: card.pad + (card.accented ? Theme.components.dp(6) : 0)
                    rightMargin: card.pad
                    topMargin: card.pad
                }
                spacing: NotificationService.denseGap

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm

                    NotifIcon {
                        Layout.preferredWidth: card.iconPx
                        Layout.preferredHeight: card.iconPx
                        Layout.maximumWidth: card.iconPx
                        Layout.alignment: Qt.AlignTop
                        notif: card.notif
                        critical: card.critical
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.space.xs

                            Rectangle {
                                visible: card.unread
                                implicitWidth: Theme.components.dp(7)
                                implicitHeight: implicitWidth
                                radius: width / 2
                                color: card.critical ? Theme.color.error : Theme.color.primary
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                text: card.notif.appName
                                style: Theme.type.labelSmall
                                color: card.critical ? Theme.color.fgErrorContainer : Theme.color.fgSurfaceVariant
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: card.pinned
                                text: "\ue840"      // push_pin
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                                color: card.critical ? Theme.color.fgErrorContainer : Theme.color.primary
                            }
                            ThemedText {
                                visible: !(card.popup && hover.hovered)
                                text: NotificationService.rel(card.notif.time)
                                style: Theme.type.labelSmall
                                color: card.critical ? Theme.color.fgErrorContainer : Theme.color.fgSurfaceVariant
                            }
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: card.notif.summary
                            style: Theme.type.titleSmall
                            emphasized: true
                            color: card.critical ? Theme.color.fgErrorContainer : Theme.color.fgSurface
                            elide: Text.ElideRight
                            maximumLineCount: card.expanded ? 4 : 2
                            wrapMode: Text.Wrap
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: card.notif.body
                            style: Theme.type.bodyMedium
                            color: card.critical ? Theme.color.fgErrorContainer : Theme.color.fgSurfaceVariant
                            textFormat: Text.StyledText
                            linkColor: Theme.color.primary
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                            maximumLineCount: card.expanded ? 16 : 2
                            onLinkActivated: link => Qt.openUrlExternally(link)
                        }
                    }

                    // швидкі дії в центрі (у поп-апі — компактний оверлей нижче)
                    Column {
                        visible: !card.popup
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: Theme.components.dp(26)
                        Layout.maximumWidth: Theme.components.dp(26)
                        spacing: 2

                        QuickAction {
                            glyph: card.pinned ? "\ue840" : "\ue840"
                            tip: card.pinned ? Lang.t("ui.notif.unpin") : Lang.t("ui.notif.pin")
                            active: card.pinned
                            onActivated: NotificationService.togglePin(card.notif)
                        }
                        QuickAction {
                            glyph: card.copied ? "\ue5ca" : "\ue14d"   // check / content_copy
                            tip: Lang.t("ui.notif.copy")
                            active: card.copied
                            onActivated: {
                                NotificationService.copy(card.notif)
                                card.copied = true
                                copiedTimer.restart()
                            }
                        }
                        QuickAction {
                            glyph: card.muted ? "\ue04f" : "\ue04f"   // volume_off
                            tip: card.muted ? Lang.t("ui.notif.unmuteApp") : Lang.t("ui.notif.muteApp")
                            active: card.muted
                            onActivated: NotificationService.toggleMuteApp(card.appKey)
                        }
                        QuickAction {
                            glyph: "\ue8b5"                           // schedule
                            tip: Lang.t("ui.notif.snooze")
                            onActivated: NotificationService.snooze(card.notif)
                        }
                        QuickAction {
                            glyph: "\ue5cd"                           // close
                            tip: Lang.t("ui.notif.remove")
                            onActivated: card.removed()
                        }
                    }
                }

                // дії застосунку
                Flow {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.iconPx + Theme.space.sm
                    visible: card.shownActions.length > 0
                    spacing: Theme.space.xs

                    Repeater {
                        model: card.shownActions
                        Rectangle {
                            id: act
                            required property var modelData
                            implicitHeight: Theme.components.dp(30)
                            implicitWidth: actTxt.implicitWidth + Theme.space.xl
                            radius: actMa.pressed ? Theme.shape.buttonPressed : height / 2
                            color: card.critical ? Theme.color.error : Theme.color.secondaryContainer
                            scale: actMa.pressed ? 0.96 : 1
                            Behavior on radius { MotionAnimation { role: "morph" } }
                            Behavior on scale { MotionAnimation { role: "press" } }
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                color: card.critical ? Theme.color.fgError : Theme.color.fgSecondaryContainer
                                opacity: actMa.pressed ? Theme.components.statePressed
                                       : actMa.containsMouse ? Theme.components.stateHover : 0
                            }
                            ThemedText {
                                id: actTxt
                                anchors.centerIn: parent
                                text: act.modelData.text
                                style: Theme.type.labelLarge
                                color: card.critical ? Theme.color.fgError : Theme.color.fgSecondaryContainer
                            }
                            MouseArea {
                                id: actMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    NotificationService.markRead(card.notif)
                                    card.notif.invoke(act.modelData.id)
                                    card.removed()
                                }
                            }
                        }
                    }
                }

                // підпис стану
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: card.iconPx + Theme.space.sm
                    visible: card.pinned || card.muted || card.notif.snoozedUntil > 0
                    spacing: Theme.space.xs
                    ThemedText {
                        visible: card.pinned
                        text: Lang.t("ui.notif.pinnedTag")
                        style: Theme.type.labelSmall
                        color: card.critical ? Theme.color.fgErrorContainer : Theme.color.primary
                    }
                    ThemedText {
                        visible: card.muted
                        text: "· " + Lang.t("ui.notif.muteApp")
                        style: Theme.type.labelSmall
                        color: Theme.color.fgSurfaceVariant
                    }
                    ThemedText {
                        visible: card.notif.snoozedUntil > 0
                        text: "· " + Lang.t("ui.notif.snoozed")
                        style: Theme.type.labelSmall
                        color: Theme.color.fgSurfaceVariant
                    }
                }
            }

            // швидкі дії в поп-апі — оверлей поверх картки, не збільшує її висоту
            Rectangle {
                id: popupActionsBg
                visible: card.popup
                anchors.fill: popupActionsRow
                anchors.margins: -Theme.space.xs
                radius: height / 2
                color: card.critical ? Theme.color.errorContainer : Theme.color.surfaceContainerHigh
                border.width: Theme.settings.nothing ? ThemeNothing.hairline : 0
                border.color: Theme.color.outlineVariant
                opacity: hover.hovered ? 0.97 : 0
                Behavior on opacity { MotionAnimation { role: "hover" } }
            }
            Row {
                id: popupActionsRow
                visible: card.popup
                enabled: hover.hovered
                anchors.top: bg.top
                anchors.right: bg.right
                anchors.topMargin: card.pad - 4
                anchors.rightMargin: card.pad - 4
                spacing: 2
                opacity: hover.hovered ? 1 : 0
                Behavior on opacity { MotionAnimation { role: "hover" } }

                QuickAction {
                    glyph: "\ue840"      // push_pin
                    tip: card.pinned ? Lang.t("ui.notif.unpin") : Lang.t("ui.notif.pin")
                    active: card.pinned
                    onActivated: NotificationService.togglePin(card.notif)
                }
                QuickAction {
                    glyph: card.copied ? "\ue5ca" : "\ue14d"   // check / content_copy
                    tip: Lang.t("ui.notif.copy")
                    active: card.copied
                    onActivated: {
                        NotificationService.copy(card.notif)
                        card.copied = true
                        copiedTimer.restart()
                    }
                }
                QuickAction {
                    glyph: "\ue04f"      // volume_off
                    tip: card.muted ? Lang.t("ui.notif.unmuteApp") : Lang.t("ui.notif.muteApp")
                    active: card.muted
                    onActivated: NotificationService.toggleMuteApp(card.appKey)
                }
                QuickAction {
                    glyph: "\ue8b5"      // schedule
                    tip: Lang.t("ui.notif.snooze")
                    onActivated: NotificationService.snooze(card.notif)
                }
                QuickAction {
                    glyph: "\ue5cd"      // close
                    tip: Lang.t("ui.notif.remove")
                    onActivated: card.removed()
                }
            }

            // прогрес таймера (popup)
            Rectangle {
                visible: card.popup && card.notif.totalMs > 0
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.components.dp(4)
                x: Theme.space.lg
                height: Theme.components.dp(card.notif.paused ? 4 : 3)
                radius: height / 2
                width: (parent.width - Theme.space.lg * 2) * Math.max(0, card.notif.remainingMs / card.notif.totalMs)
                color: card.critical ? Theme.color.error : Theme.color.primary
                opacity: card.notif.paused ? 1 : 0.8
                Behavior on height { MotionAnimation { role: "hover" } }
                Behavior on opacity { MotionAnimation { role: "hover" } }
                Behavior on width { NumberAnimation { duration: 40 } }
            }
        }
    }

    // маленька кнопка швидкої дії
    component QuickAction: Rectangle {
        id: qa
        property string glyph: ""
        property string tip: ""
        property bool active: false
        signal activated()

        implicitWidth: Theme.components.dp(26)
        implicitHeight: implicitWidth
        width: implicitWidth
        height: implicitHeight
        radius: qaMa.pressed ? Theme.shape.iconButtonPressed : height / 2
        color: qa.active ? Qt.rgba(Theme.color.primary.r, Theme.color.primary.g, Theme.color.primary.b, 0.14)
             : (qaMa.containsMouse ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.08) : "transparent")
        scale: qaMa.pressed ? 0.9 : 1
        Behavior on radius { MotionAnimation { role: "morph" } }
        Behavior on color { MotionColorAnimation { role: "hover" } }
        Behavior on scale { MotionAnimation { role: "press" } }

        Text {
            anchors.centerIn: parent
            text: qa.glyph
            color: qa.active ? Theme.color.primary
                 : (card.critical ? Theme.color.fgErrorContainer : Theme.color.fgSurfaceVariant)
            font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
        }
        MouseArea {
            id: qaMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: qa.activated()
        }
    }
}
