pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "material"
import QtQuick
import QtQuick.Layouts

// Settings → Plugins. A plugin is a folder with plugin.json; it can provide a
// surface panel, a bar module, or both. See quickshell/bar/plugins/README.md.
Item {
    id: root

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + Theme.space.xl

    function openPlugin(plugin) {
        if (!plugin || !plugin.enabled || !plugin.surface) return
        ShellState.closeSettings()
        ShellState.openSurface("plugin:" + plugin.id)
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""

        implicitWidth: chipText.implicitWidth + Theme.space.md * 2
        implicitHeight: chipText.implicitHeight + Theme.space.xs * 2
        radius: height / 2
        color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainerHighest
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.18)

        ThemedText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            style: Theme.type.labelSmall
            color: Theme.color.fgSurfaceVariant
        }
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.space.md

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Theme.space.md
            Layout.leftMargin: Theme.space.md
            Layout.rightMargin: Theme.space.sm
            spacing: Theme.space.sm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("page.plugins").toUpperCase()
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.settings.nothing ? Theme.color.fgSurfaceVariant : Theme.color.primary
                    font.letterSpacing: (Theme.settings.nothing ? 2.5 : 1.2) * Theme.space.k
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: PluginService.loading
                        ? Lang.t("plugins.loading")
                        : Lang.tn("plugins.count", (PluginService.plugins || []).length)
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                }
            }

            MaterialButton {
                text: Lang.t("plugins.refresh")
                icon: "refresh"
                style: "tonal"
                enabled_: !PluginService.loading
                onClicked: PluginService.refresh()
            }
            MaterialButton {
                text: Lang.t("plugins.openFolder")
                icon: "folder_open"
                style: "outlined"
                onClicked: PluginService.openFolder()
            }
        }

        ThemedText {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space.lg
            Layout.rightMargin: Theme.space.lg
            visible: !!PluginService.error && PluginService.error.length > 0
            text: PluginService.error
            style: Theme.type.bodySmall
            color: Theme.color.error
            wrapMode: Text.Wrap
        }

        // Broken manifests — show them instead of silently dropping folders.
        Rectangle {
            Layout.fillWidth: true
            visible: (PluginService.errors || []).length > 0
            implicitHeight: errorCol.implicitHeight + Theme.space.lg * 2
            radius: Theme.shape.cardLarge
            color: Theme.color.errorContainer
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Theme.color.error

            ColumnLayout {
                id: errorCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: Theme.space.lg
                }
                spacing: Theme.space.xs

                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.tn("plugins.errors", (PluginService.errors || []).length)
                    style: Theme.type.titleSmall
                    emphasized: true
                    color: Theme.color.fgErrorContainer
                }
                Repeater {
                    model: PluginService.errors || []
                    delegate: ThemedText {
                        Layout.fillWidth: true
                        text: modelData.name + " — " + modelData.error
                        style: Theme.type.bodySmall
                        color: Theme.color.fgErrorContainer
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // Empty state.
        Rectangle {
            Layout.fillWidth: true
            visible: (PluginService.plugins || []).length === 0 && !PluginService.loading
            implicitHeight: emptyCol.implicitHeight + Theme.space.xl * 2
            radius: Theme.shape.cardLarge
            color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainer
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.16)

            ColumnLayout {
                id: emptyCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: Theme.space.xl
                }
                spacing: Theme.space.xs

                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("plugins.empty")
                    style: Theme.type.titleSmall
                    emphasized: true
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("plugins.emptyHint")
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
        }

        Repeater {
            model: PluginService.plugins || []
            delegate: Rectangle {
                id: card
                required property var modelData

                Layout.fillWidth: true
                implicitHeight: cardCol.implicitHeight + Theme.space.lg * 2
                radius: Theme.shape.cardLarge
                color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainer
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.16)

                ColumnLayout {
                    id: cardCol
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        margins: Theme.space.lg
                    }
                    spacing: Theme.space.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.md

                        Rectangle {
                            implicitWidth: Theme.components.dp(44)
                            implicitHeight: implicitWidth
                            radius: Theme.shape.radius("lg", height)
                            color: Theme.settings.nothing ? "transparent" : Theme.color.primaryContainer
                            border.width: Theme.settings.nothing ? 1 : 0
                            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.22)

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon || "extension"
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                                color: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgPrimaryContainer
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            ThemedText {
                                Layout.fillWidth: true
                                text: modelData.name
                                style: Theme.type.titleMedium
                                emphasized: true
                                elide: Text.ElideRight
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                text: (modelData.id + (modelData.version ? "  ·  v" + modelData.version : ""))
                                style: Theme.type.bodySmall
                                color: Theme.color.fgSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        MaterialSwitch {
                            Layout.alignment: Qt.AlignVCenter
                            checked: !!modelData.enabled
                            enabled_: !PluginService.saving
                            onToggled: PluginService.setEnabled(modelData.id, !modelData.enabled)
                        }
                    }

                    ThemedText {
                        Layout.fillWidth: true
                        visible: !!modelData.description && modelData.description.length > 0
                        text: modelData.description
                        style: Theme.type.bodyMedium
                        color: Theme.color.fgSurfaceVariant
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm

                        Chip {
                            visible: !!modelData.surface
                            label: modelData.surface
                                ? Lang.t("plugins.surface") + "  " + modelData.surface.w + "×" + modelData.surface.h
                                : ""
                        }
                        Chip {
                            visible: !!modelData.bar
                            label: modelData.bar
                                ? Lang.t("plugins.bar") + "  ·  " + modelData.bar.position
                                : ""
                        }
                        Chip {
                            label: Lang.t(modelData.source === "user" ? "plugins.user" : "plugins.bundled")
                        }
                        Item { Layout.fillWidth: true }

                        MaterialButton {
                            visible: !!modelData.surface
                            text: modelData.enabled ? Lang.t("plugins.open") : Lang.t("plugins.enableToOpen")
                            icon: modelData.enabled ? "open_in_new" : "power_settings_new"
                            style: "tonal"
                            enabled_: modelData.enabled
                            onClicked: root.openPlugin(modelData)
                        }
                    }

                    ThemedText {
                        Layout.fillWidth: true
                        visible: !!modelData.bar && !modelData.surface
                        text: Lang.t("plugins.barOnly")
                        style: Theme.type.bodySmall
                        color: Theme.color.outline
                        wrapMode: Text.Wrap
                        font.italic: true
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: footerCol.implicitHeight + Theme.space.lg * 2
            radius: Theme.shape.card
            color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainerLow
            border.width: Theme.settings.nothing ? 1 : 0
            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.12)

            ColumnLayout {
                id: footerCol
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: Theme.space.lg
                }
                spacing: Theme.space.xxs

                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("plugins.userDir")
                    style: Theme.type.labelLarge
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: PluginService.userDir
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                    elide: Text.ElideMiddle
                    wrapMode: Text.NoWrap
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("plugins.hint")
                    style: Theme.type.bodySmall
                    color: Theme.color.outline
                    wrapMode: Text.Wrap
                }
            }
        }

        Item { Layout.preferredHeight: Theme.space.md }
    }
}
