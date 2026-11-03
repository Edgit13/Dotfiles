pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/settings"
import "root:/services"
import "root:/settings/material"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// NotificationCenter — M3 side sheet: не турбувати, очистити, групи за застосунками.
// Сторона (ліворуч / праворуч) — за позицією сповіщень у налаштуваннях.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property bool target: NotificationService.isCenterTarget(win.screen)
    readonly property bool open: NotificationService.centerOpen && target
    // центр має власну позицію (Settings → Notifications); "same" = як вікна
    readonly property string pos: NotificationService.centerPosition
    readonly property bool atLeft: pos === "left" || pos.indexOf("-left") > 0
    readonly property bool atRight: pos === "right" || pos.indexOf("-right") > 0
    readonly property bool atTop: pos.indexOf("top") === 0
    readonly property bool atBottom: pos.indexOf("bottom") === 0
    readonly property bool atMiddle: !win.atTop && !win.atBottom
    readonly property real m: Theme.space.md

    // компактна картка, як інші модулі: висота за вмістом, не на весь екран
    readonly property real maxPanelH: win.screen.height - win.m * 2
    readonly property real maxListH: Math.max(Theme.components.dp(96),
        win.maxPanelH - Theme.space.lg * 2 - headerRow.implicitHeight
        - dndRow.implicitHeight - bodyCol.spacing * 2)

    // як у end-4: просто плаваюча панель біля краю — без scrim і без повноекранної поверхні
    visible: open || panel.opacity > 0.01
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: !win.atBottom
        bottom: win.atBottom
        left: win.atLeft
        right: win.atRight
    }
    margins {
        // середні рядки/стовпці центруються, кути й краї тримають відступ
        top: win.atBottom ? 0
           : win.atMiddle ? Math.max(win.m, Math.round((win.screen.height - win.implicitHeight) / 2))
           : win.m
        bottom: win.atBottom ? win.m : 0
        left: win.atLeft ? win.m : 0
        right: win.atRight ? win.m : 0
    }
    implicitWidth: Math.min(Theme.components.dp(380), win.screen.width - win.m * 2)
    implicitHeight: Math.min(bodyCol.implicitHeight + Theme.space.lg * 2, win.maxPanelH)
    Behavior on implicitHeight { MotionAnimation { role: "morph" } }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "m3-notification-center"
    WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onOpenChanged: if (open) panel.forceActiveFocus()

    Rectangle {
        id: panel
        width: parent.width
        height: parent.height
        radius: Theme.shape.dialog
        color: Theme.color.surfaceContainerLow
        border.width: 1
        border.color: Theme.color.outlineVariant

        // виїжджає від краю екрана (для центру — лише поява/масштаб)
        x: win.open ? 0 : (win.atLeft ? -width - win.m : win.atRight ? width + win.m : 0)
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.97
        transformOrigin: win.atLeft ? Item.Left : win.atRight ? Item.Right : Item.Center
        Behavior on x { MotionAnimation { role: win.open ? "move" : "exit" } }
        Behavior on opacity { MotionAnimation { role: win.open ? "enter" : "exit" } }
        Behavior on scale { MotionAnimation { role: win.open ? "move" : "exit" } }

        focus: true
        Keys.onEscapePressed: NotificationService.closeCenter()

        ColumnLayout {
            id: bodyCol
            anchors.fill: parent
            anchors.margins: Theme.space.lg
            spacing: Theme.space.md
            opacity: win.open ? 1 : 0

            // контент з'являється трохи пізніше за панель — ефект шару
            transform: Translate {
                x: win.open ? 0 : (win.atLeft ? -Theme.space.lg : Theme.space.lg)
                Behavior on x { MotionAnimation { role: win.open ? "contentIn" : "contentOut" } }
            }
            Behavior on opacity { MotionAnimation { role: win.open ? "contentIn" : "contentOut" } }

            // ---- заголовок (як в інших модулях: 36dp іконка + titleMedium) ----
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Theme.space.sm

                Rectangle {
                    implicitWidth: Theme.components.dp(36)
                    implicitHeight: implicitWidth
                    radius: Theme.shape.radius("lg", height)
                    color: Theme.color.primaryContainer
                    Text {
                        anchors.centerIn: parent
                        text: "\ue7f4"
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                        color: Theme.color.fgPrimaryContainer
                    }
                }
                ThemedText {
                    text: Lang.t("ui.notif.title")
                    style: Theme.type.titleMedium
                    emphasized: true
                }
                Rectangle {
                    visible: NotificationService.count > 0
                    implicitWidth: total.implicitWidth + Theme.space.md
                    implicitHeight: Theme.components.dp(20)
                    radius: height / 2
                    color: Theme.color.primaryContainer
                    ThemedText {
                        id: total
                        anchors.centerIn: parent
                        text: NotificationService.count
                        style: Theme.type.labelMedium
                        emphasized: true
                        color: Theme.color.fgPrimaryContainer
                    }
                }
                Item { Layout.fillWidth: true }
                MaterialButton {
                    visible: NotificationService.count > 0
                    text: Lang.t("ui.notif.clear")
                    icon: "delete_sweep"
                    style: "tonal"
                    implicitHeight: Theme.components.buttonXS
                    onClicked: NotificationService.clearAll()
                }
                MaterialIconButton {
                    icon: "close"
                    width: Theme.components.dp(36)
                    height: width
                    onClicked: NotificationService.closeCenter()
                }
            }

            // ---- не турбувати ----
            Rectangle {
                id: dndRow
                Layout.fillWidth: true
                implicitHeight: Theme.components.dp(52)
                radius: Theme.shape.cardLarge
                color: Theme.settings.nothing ? "transparent"
                     : NotificationService.dnd ? Theme.color.primaryContainer : Theme.color.surfaceContainerHigh
                // Nothing: контурна картка; увімкнений DND — яскравіший контур
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, NotificationService.dnd ? 0.75 : 0.18)
                Behavior on color { MotionColorAnimation { role: "stateChange" } }
                Behavior on border.color { ColorAnimation { duration: 160 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space.md
                    anchors.rightMargin: Theme.space.md
                    spacing: Theme.space.sm
                    Text {
                        text: NotificationService.dnd ? "\ue7f6" : "\ue7f4"          // notifications_off / notifications
                        color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ThemedText {
                            text: Lang.t("ui.notif.dnd")
                            style: Theme.type.bodyLarge
                            color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurface
                        }
                        ThemedText {
                            text: Lang.t("ui.notif.dnd.desc")
                            style: Theme.type.bodySmall
                            color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant
                        }
                    }
                    MaterialSwitch {
                        checked: NotificationService.dnd
                        onToggled: NotificationService.setDnd(!NotificationService.dnd)
                    }
                }
            }

            // ---- список ----
            Item {
                id: listBox
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: win.maxListH
                implicitHeight: NotificationService.count === 0
                    ? Theme.components.dp(168)
                    : Math.min(Math.max(flick.contentHeight, Theme.components.dp(56)), win.maxListH)

                Flickable {
                    id: flick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: groupsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: groupsCol
                        width: flick.width
                        spacing: Theme.space.md

                        Repeater {
                            model: ScriptModel {
                                values: NotificationService.groups
                                objectProp: "key"
                            }
                            NotificationGroup {}
                        }
                    }
                }

                // порожній стан
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: opacity > 0.01
                    opacity: NotificationService.count === 0 ? 1 : 0
                    scale: NotificationService.count === 0 ? 1 : 0.96
                    spacing: Theme.space.sm
                    Behavior on opacity { MotionAnimation { role: NotificationService.count === 0 ? "enter" : "exit" } }
                    Behavior on scale { MotionAnimation { role: NotificationService.count === 0 ? "enter" : "exit" } }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Theme.components.dp(56)
                        implicitHeight: implicitWidth
                        radius: Theme.shape.radius("lg", height)
                        color: Theme.settings.nothing ? "transparent" : Theme.color.secondaryContainer
                        border.width: Theme.settings.nothing ? 1 : 0
                        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.22)
                        Text {
                            anchors.centerIn: parent
                            text: "\ue7f4"
                            color: Theme.color.fgSecondaryContainer
                            font { family: Theme.type.icons; pixelSize: Theme.type.iconL }
                        }
                    }
                    ThemedText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Lang.t("ui.notif.empty")
                        style: Theme.type.bodyMedium
                        color: Theme.color.fgSurfaceVariant
                    }
                }
            }
        }
    }
}
