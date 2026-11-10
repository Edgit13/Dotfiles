import "root:/theme"
import "root:/settings"
import "root:/services"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// NotificationPopups — стек спливаючих сповіщень у вибраному куті/краї (Settings → Notifications).
// Нове: щільність/розміри з налаштувань, м'якший stagger, лічильник прихованих попапів.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property string pos: NotificationService.position
    readonly property bool atTop: pos.indexOf("top") === 0
    readonly property bool atBottom: pos.indexOf("bottom") === 0
    readonly property bool atLeft: pos === "left" || pos.indexOf("-left") > 0
    readonly property bool atRight: pos === "right" || pos.indexOf("-right") > 0

    readonly property real pad: Math.max(8, Math.round(NotificationService.densePad * 0.85))
    readonly property real gap: Math.max(4, Math.round(NotificationService.denseGap * 0.85))
    readonly property real edge: Math.max(0, Math.round(NotificationService.margin * Theme.space.k) - pad)
    readonly property real offX: atLeft ? -1 : (atRight ? 1 : 0)
    readonly property bool hasMore: NotificationService.hiddenPopupCount > 0

    readonly property bool target: NotificationService.isPopupTarget(win.screen)
    visible: target && NotificationService.toasts
             && (NotificationService.popups.length > 0 || stack.height > 1)

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { top: true; bottom: true; left: win.atLeft; right: win.atRight }
    margins { top: win.edge; bottom: win.edge; left: win.edge; right: win.edge }
    implicitWidth: Math.round(NotificationService.cardWidth) + pad * 2
    mask: Region { item: stack }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "m3-notifications"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Column {
        id: stack
        x: win.pad
        width: parent.width - win.pad * 2
        y: win.atTop ? 0
         : win.atBottom ? parent.height - height
         : (parent.height - height) / 2
        spacing: 0

        Repeater {
            model: ScriptModel {
                values: win.atBottom ? NotificationService.items.slice().reverse() : NotificationService.items
            }

            Item {
                id: slot
                required property var modelData
                required property int index
                readonly property bool inPopups: NotificationService.popups.indexOf(modelData) >= 0
                readonly property bool shown: inPopups && !leaving
                readonly property int stagger: Math.min(index, 5) * 30
                property bool entered: false
                property bool leaving: false
                Component.onCompleted: entered = true

                width: stack.width
                height: shown ? card.implicitHeight + win.gap : 0
                visible: height > 0.5
                Behavior on height { MotionAnimation { role: slot.shown ? "expand" : "collapse" } }

                NotificationCard {
                    id: card
                    width: parent.width
                    notif: slot.modelData
                    popup: true
                    y: win.gap / 2
                    opacity: (slot.entered && slot.shown) ? 1 : 0
                    scale: (slot.entered && slot.shown) ? 1 : 0.94
                    transform: Translate {
                        x: (slot.entered && slot.shown) ? 0 : win.offX * Theme.components.dp(56)
                        y: (slot.entered && slot.shown) || win.offX !== 0 ? 0
                           : (win.atBottom ? 1 : -1) * Theme.components.dp(32)
                        Behavior on x { MotionStagger { role: (slot.entered && slot.shown) ? "move" : "exit"; delay: slot.shown ? slot.stagger : 0 } }
                        Behavior on y { MotionStagger { role: (slot.entered && slot.shown) ? "move" : "exit"; delay: slot.shown ? slot.stagger : 0 } }
                    }
                    Behavior on scale { MotionStagger { role: (slot.entered && slot.shown) ? "move" : "exit"; delay: slot.shown ? slot.stagger : 0 } }
                    Behavior on opacity { MotionStagger { role: (slot.entered && slot.shown) ? "enter" : "exit"; delay: slot.shown ? slot.stagger : 0 } }

                    onRemoved: {
                        if (slot.leaving) return
                        slot.leaving = true
                        leaveTimer.start()
                    }
                    Timer {
                        id: leaveTimer
                        interval: ThemeMotion.duration("collapse") + 60
                        onTriggered: NotificationService.dismiss(slot.modelData)
                    }
                }
            }
        }

        // «+N» — відкрити центр, коли попапів більше, ніж дозволено
        Item {
            width: stack.width
            height: win.hasMore ? moreChip.implicitHeight + win.gap : 0
            visible: height > 0.5
            Behavior on height { MotionAnimation { role: win.hasMore ? "expand" : "collapse" } }

            Rectangle {
                id: moreChip
                width: parent.width
                height: Theme.components.dp(36)
                radius: height / 2
                color: Theme.color.surfaceContainerHigh
                border.width: Theme.settings.nothing ? ThemeNothing.hairline : 0
                border.color: Theme.color.outlineVariant
                opacity: win.hasMore ? 1 : 0
                scale: win.hasMore ? 1 : 0.96
                Behavior on opacity { MotionAnimation { role: win.hasMore ? "enter" : "exit" } }
                Behavior on scale { MotionAnimation { role: win.hasMore ? "enter" : "exit" } }

                ThemedText {
                    anchors.centerIn: parent
                    text: Lang.tn("ui.notif.more", NotificationService.hiddenPopupCount)
                    style: Theme.type.labelLarge
                    color: Theme.color.primary
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: NotificationService.openCenter()
                }
            }
        }
    }
}
