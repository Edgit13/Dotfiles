import "root:/theme"
import "root:/services"
import "root:/settings"
import QtQuick
import QtQuick.Layouts

// NotifCard — сповіщення на Overview: список, «Усе опрацьовано», історія / Очистити все / DND.
DashCard {
    id: root

    readonly property bool uk: Lang.current.indexOf("uk") === 0
    readonly property int count: NotificationService.count

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.sm

        // ── вміст ───────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                visible: root.count === 0
                spacing: Theme.space.sm
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "\uea23"
                    font { family: Theme.type.icons; pixelSize: Theme.type.iconXL }
                    color: Theme.color.fgSurfaceVariant
                }
                ThemedText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.uk ? "Усе опрацьовано" : "You're all caught up"
                    style: Theme.type.titleSmall
                    color: Theme.color.fgSurfaceVariant
                    font.family: Theme.settings.nothing ? Theme.type.dot : style.family
                    font.capitalization: Theme.settings.nothing ? Font.AllUppercase : Font.MixedCase
                }
            }

            ListView {
                id: list
                anchors.fill: parent
                visible: root.count > 0
                clip: true
                spacing: Theme.space.xs
                boundsBehavior: Flickable.StopAtBounds
                model: NotificationService.items

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    width: list.width
                    height: rowCol.implicitHeight + Theme.space.md * 2
                    radius: Theme.shape.radius("lg", height)
                    color: Theme.settings.nothing ? (ma.containsMouse ? Theme.color.surfaceContainerHigh : "transparent")
                         : ma.containsMouse ? Theme.color.surfaceContainerHighest
                                            : Theme.color.surfaceContainer
                    border.width: Theme.settings.nothing ? 1 : 0
                    border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.16)
                    Behavior on color { MotionColorAnimation { role: "hover" } }

                    ColumnLayout {
                        id: rowCol
                        anchors.fill: parent
                        anchors.margins: Theme.space.md
                        spacing: 1

                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle {
                                visible: !row.modelData.read
                                width: 6; height: 6; radius: 3
                                color: Theme.settings.nothing ? ThemeNothing.red : Theme.color.primary
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                text: NotificationService.appKey(row.modelData)
                                style: Theme.type.labelSmall
                                color: Theme.settings.nothing ? Theme.color.fgSurfaceVariant : Theme.color.primary
                                elide: Text.ElideRight
                            }
                            ThemedText {
                                text: NotificationService.rel(row.modelData.time)
                                style: Theme.type.labelSmall
                                color: Theme.color.outline
                            }
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: row.modelData.summary
                            style: Theme.type.bodyMedium
                            emphasized: true
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            visible: text.length > 0
                            text: row.modelData.body
                            style: Theme.type.bodySmall
                            color: Theme.color.fgSurfaceVariant
                            maximumLineCount: 2
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationService.dismiss(row.modelData)
                    }
                }
            }
        }

        // ── низ: історія · Очистити все · DND ───────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm

            DashButton {
                variant: "tonal"
                size: Theme.components.dp(48)
                icon: "\ue889"
                onClicked: NotificationService.toggleCenter()
            }
            DashButton {
                Layout.fillWidth: true
                variant: "subtle"
                size: Theme.components.dp(48)
                enabled: root.count > 0
                label: root.uk ? "Очистити все" : "Clear All"
                onClicked: NotificationService.clearAll()
            }
            DashButton {
                variant: "tonal"
                size: Theme.components.dp(48)
                toggled: NotificationService.dnd
                icon: NotificationService.dnd ? "\ue7f6" : "\ue7f4"
                onClicked: NotificationService.toggleDnd()
            }
        }
    }
}
