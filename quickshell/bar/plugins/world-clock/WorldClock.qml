import qs.theme
import Quickshell
import QtQuick
import QtQuick.Layouts

// Sample plugin surface. Plugin QML may import any Quickshell module and the
// shell's own `qs.theme`, `qs.shell`, `qs.modules.common` modules.
Item {
    id: root

    readonly property var cities: [
        { name: "Kyiv", zone: "Europe/Kyiv" },
        { name: "London", zone: "Europe/London" },
        { name: "New York", zone: "America/New_York" },
        { name: "Tokyo", zone: "Asia/Tokyo" }
    ]

    function timeIn(zone) {
        try {
            return new Intl.DateTimeFormat("en-GB", {
                timeZone: zone,
                hour: "2-digit",
                minute: "2-digit",
                hour12: false
            }).format(clock.date)
        } catch (e) {
            return "--:--"
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.md

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: local.implicitHeight + Theme.space.xl * 2
            radius: Theme.shape.cardLarge
            color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainer
            border.width: Theme.settings.nothing ? ThemeNothing.hairline : 0
            border.color: Theme.color.outlineVariant

            ColumnLayout {
                id: local
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: Theme.space.xl
                }
                spacing: Theme.space.xxs

                ThemedText {
                    Layout.fillWidth: true
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM").toUpperCase()
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                    font.letterSpacing: (Theme.settings.nothing ? 2.5 : 1.2) * Theme.space.k
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    style: Theme.type.displayLarge
                    emphasized: true
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: "Local time"
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                }
            }
        }

        Repeater {
            model: root.cities

            Rectangle {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: cityRow.implicitHeight + Theme.space.lg * 2
                radius: Theme.shape.card
                color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainerLow
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.12)

                RowLayout {
                    id: cityRow
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.space.lg
                    }
                    spacing: Theme.space.md

                    ThemedText {
                        Layout.fillWidth: true
                        text: modelData.name
                        style: Theme.type.bodyLarge
                    }
                    ThemedText {
                        text: root.timeIn(modelData.zone)
                        style: Theme.type.titleMedium
                        emphasized: true
                        color: Theme.color.primary
                    }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
