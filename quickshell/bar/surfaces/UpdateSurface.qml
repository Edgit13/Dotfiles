import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import "root:/widgets"
import Quickshell
import QtQuick
import QtQuick.Layouts

// UpdateSurface — repo / AUR / Flatpak updates. Never installs anything itself:
// "Update all" opens a terminal running upkg update.
Item {
    id: root

    readonly property bool nothing: Theme.settings.nothing
    readonly property var rows: UpdateService.rows

    Component.onCompleted: if (UpdateService.lastCheck === 0 && !UpdateService.checking) UpdateService.refresh()

    function lastCheckText() {
        if (UpdateService.lastCheck <= 0) return Lang.t("updates.never")
        const d = new Date(UpdateService.lastCheck * 1000)
        return Lang.t("updates.last").replace("{t}", Qt.formatDateTime(d, "dd.MM HH:mm"))
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.md

        // ---- header ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.components.dp(58)
            radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
            color: root.nothing ? "transparent" : Theme.color.surfaceContainer
            border.width: root.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.md
                anchors.rightMargin: Theme.space.sm
                spacing: Theme.space.sm

                Rectangle {
                    implicitWidth: Theme.components.dp(34)
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: UpdateService.hasUpdates
                           ? (root.nothing ? ThemeNothing.red : Theme.color.primaryContainer)
                           : Theme.color.surfaceContainerHighest

                    Text {
                        anchors.centerIn: parent
                        text: "\ue5d5" // refresh
                        color: UpdateService.hasUpdates
                               ? (root.nothing ? Colors.fg : Theme.color.fgPrimaryContainer)
                               : Theme.color.outline
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    ThemedText {
                        text: Lang.t("ui.surface.updates")
                        style: Theme.type.titleSmall
                        emphasized: true
                    }
                    ThemedText {
                        text: UpdateService.checking
                              ? Lang.t("updates.checking")
                              : (UpdateService.error.length > 0
                                 ? UpdateService.error
                                 : (UpdateService.hasUpdates
                                    ? Lang.t("updates.total").replace("{n}", UpdateService.total)
                                    : Lang.t("updates.empty")))
                        style: Theme.type.bodySmall
                        color: UpdateService.error.length > 0 ? Theme.color.error
                             : UpdateService.hasUpdates ? Theme.color.primary
                             : Theme.color.fgSurfaceVariant
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                MaterialIconButton {
                    icon: "\ue5d5"
                    enabled_: !UpdateService.checking
                    tooltip: Lang.t("updates.refresh")
                    onClicked: UpdateService.refresh()
                }
            }
        }

        // ---- list ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
            color: root.nothing ? "transparent" : Theme.color.surfaceContainer
            border.width: root.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant
            clip: true

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                clip: true
                spacing: Theme.space.xs
                model: root.rows

                delegate: Rectangle {
                    required property var modelData
                    width: list.width
                    height: Theme.components.dp(44)
                    radius: root.nothing ? ThemeNothing.corners.sm : Theme.shape.sm
                    color: rowHover.hovered ? Theme.color.surfaceContainerHigh : "transparent"
                    HoverHandler { id: rowHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.space.sm
                        anchors.rightMargin: Theme.space.sm
                        spacing: Theme.space.sm

                        ThemedText {
                            text: modelData.source === "repo" ? Lang.t("updates.repo")
                                : modelData.source === "aur" ? Lang.t("updates.aur")
                                : Lang.t("updates.flatpak")
                            style: Theme.type.labelSmall
                            color: Theme.color.outline
                            Layout.preferredWidth: Theme.components.dp(72)
                        }
                        ThemedText {
                            text: modelData.name
                            style: Theme.type.bodyMedium
                            emphasized: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        ThemedText {
                            visible: modelData.old.length > 0
                            text: modelData.old + " →"
                            style: Theme.type.monoSmall
                            color: Theme.color.fgSurfaceVariant
                        }
                        ThemedText {
                            text: modelData.new
                            style: Theme.type.monoSmall
                            color: Theme.color.primary
                        }
                    }
                }

            }

            // empty / loading state
            ThemedText {
                anchors.centerIn: parent
                width: parent.width - Theme.space.xl
                horizontalAlignment: Text.AlignHCenter
                visible: list.count === 0
                text: UpdateService.checking
                      ? Lang.t("updates.checking")
                      : (UpdateService.error.length > 0
                         ? Lang.t("updates.error")
                         : Lang.t("updates.empty"))
                style: Theme.type.bodyMedium
                color: UpdateService.error.length > 0 ? Theme.color.error : Theme.color.fgSurfaceVariant
            }
        }

        // ---- footer ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm

            ThemedText {
                text: root.lastCheckText()
                style: Theme.type.labelSmall
                color: Theme.color.outline
                Layout.fillWidth: true
            }
            MaterialButton {
                text: Lang.t("updates.updateAll")
                icon: "\ue923" // system_update
                enabled_: UpdateService.hasUpdates
                onClicked: UpdateService.updateAll()
            }
        }
    }
}
