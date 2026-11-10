pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "root:/theme"
import "root:/settings"
import "root:/shell"
import "material"

// LockDesktopEditor — повноекранний редактор локскріну: справжній екран блокування, віджети тягнуться
// прямо по ньому; плаваюча панель (теж рухома) для форми / кольору / розміру. Esc або «Готово» — вийти.
PanelWindow {
    id: win
    visible: LockEditorState.open

    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    color: "black"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property bool uk: Lang.current.indexOf("uk") === 0

    function done() { LockEditorState.open = false; ShellState.openSettings() }

    Loader {
        anchors.fill: parent
        active: win.visible
        sourceComponent: Item {
            id: stage
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: win.done()
            Component.onCompleted: forceActiveFocus()

            LockPreview { id: prev; anchors.fill: parent; full: true }

            // підказка
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 20
                height: 40
                width: hint.implicitWidth + 40
                radius: 20
                color: Qt.rgba(Theme.color.surfaceContainer.r, Theme.color.surfaceContainer.g, Theme.color.surfaceContainer.b, 0.92)
                ThemedText {
                    id: hint
                    anchors.centerIn: parent
                    text: win.uk ? "Тягни віджети де завгодно  ·  Esc — готово" : "Drag widgets anywhere  ·  Esc to finish"
                    style: Theme.type.labelLarge
                }
            }

            // плаваюча панель
            Rectangle {
                id: panel
                width: 380
                height: Math.min(flick.contentHeight + head.height + 32, stage.height - 40)
                x: stage.width - width - 24
                y: (stage.height - height) / 2
                radius: Theme.shape.cardLarge
                color: Qt.rgba(Theme.color.surface.r, Theme.color.surface.g, Theme.color.surface.b, 0.96)
                border.width: 1
                border.color: Theme.color.outlineVariant

                // шапка = ручка перетягування
                Item {
                    id: head
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 56
                    Text {
                        id: grip
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "drag_indicator"
                        font { family: "Material Symbols Rounded"; pixelSize: 22 }
                        color: Theme.color.fgSurfaceVariant
                    }
                    ThemedText {
                        anchors.left: grip.right
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.uk ? "Локскрін" : "Lock screen"
                        style: Theme.type.titleMedium
                        emphasized: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.rightMargin: 110
                        cursorShape: Qt.SizeAllCursor
                        drag.target: panel
                        drag.axis: Drag.XAndYAxis
                        drag.minimumX: 0
                        drag.maximumX: stage.width - panel.width
                        drag.minimumY: 0
                        drag.maximumY: stage.height - panel.height
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: doneRow.implicitWidth + 28
                        height: 36
                        radius: doneMa.pressed ? 12 : 18
                        color: Theme.color.primary
                        Behavior on radius { MotionAnimation { role: "morph" } }
                        Row {
                            id: doneRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { anchors.verticalCenter: parent.verticalCenter; text: "check"; font.family: "Material Symbols Rounded"; font.pixelSize: 18; color: Theme.color.fgPrimary }
                            ThemedText { anchors.verticalCenter: parent.verticalCenter; text: win.uk ? "Готово" : "Done"; style: Theme.type.labelLarge; color: Theme.color.fgPrimary }
                        }
                        MouseArea { id: doneMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.done() }
                    }
                }

                Flickable {
                    id: flick
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: head.bottom
                    anchors.bottom: parent.bottom
                    anchors.margins: 16
                    anchors.topMargin: 0
                    clip: true
                    contentWidth: width
                    contentHeight: pnl.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    LockWidgetPanel { id: pnl; width: flick.width; pv: prev }
                }
            }
        }
    }
}
