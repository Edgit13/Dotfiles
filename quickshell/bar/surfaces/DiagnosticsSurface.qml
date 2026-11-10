import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import "root:/widgets"
import Quickshell
import QtQuick
import QtQuick.Layouts

// DiagnosticsSurface — the `edots doctor` report as a readable list.
// The CLI runs the checks; this is read-only.
Item {
    id: root

    readonly property bool nothing: Theme.settings.nothing

    readonly property var rows: {
        const out = []
        for (let gi = 0; gi < DiagnosticsService.groups.length; gi++) {
            const g = DiagnosticsService.groups[gi]
            out.push({ kind: "head", name: g.name || "", status: "", text: "" })
            const items = g.items || []
            for (let ii = 0; ii < items.length; ii++) {
                out.push({
                    kind: "item",
                    name: "",
                    status: items[ii].status || "ok",
                    text: items[ii].text || ""
                })
            }
        }
        return out
    }

    Component.onCompleted: if (DiagnosticsService.lastRun === 0) DiagnosticsService.refresh()

    function statusColor(s) {
        if (s === "fail") return Theme.color.error
        if (s === "warn") return Theme.color.warning
        return Theme.color.tertiary
    }

    function statusIcon(s) {
        if (s === "fail") return "\ue000"   // error
        if (s === "warn") return "\ue002"   // warning
        return "\ue5ca"                     // check
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
                    color: DiagnosticsService.failCount > 0
                           ? (root.nothing ? ThemeNothing.red : Theme.color.errorContainer)
                           : Theme.color.surfaceContainerHighest

                    Text {
                        anchors.centerIn: parent
                        text: "\ue5d5" // refresh
                        color: DiagnosticsService.failCount > 0
                               ? (root.nothing ? Colors.fg : Theme.color.fgErrorContainer)
                               : Theme.color.outline
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    ThemedText {
                        text: Lang.t("ui.surface.diagnostics")
                        style: Theme.type.titleSmall
                        emphasized: true
                    }
                    ThemedText {
                        text: DiagnosticsService.running
                              ? Lang.t("diag.running")
                              : (DiagnosticsService.error.length > 0
                                 ? DiagnosticsService.error
                                 : Lang.t("diag.summary")
                                    .replace("{ok}", DiagnosticsService.okCount)
                                    .replace("{warn}", DiagnosticsService.warnCount)
                                    .replace("{fail}", DiagnosticsService.failCount))
                        style: Theme.type.bodySmall
                        color: DiagnosticsService.error.length > 0 ? Theme.color.error
                             : DiagnosticsService.failCount > 0 ? Theme.color.error
                             : DiagnosticsService.warnCount > 0 ? Theme.color.warning
                             : Theme.color.tertiary
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                MaterialIconButton {
                    icon: "\ue5d5"
                    enabled_: !DiagnosticsService.running
                    tooltip: Lang.t("diag.refresh")
                    onClicked: DiagnosticsService.refresh()
                }
            }
        }

        // ---- report ----
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

                delegate: Item {
                    required property var modelData
                    width: list.width
                    height: modelData.kind === "head"
                            ? Theme.components.dp(30)
                            : Theme.components.dp(32)

                    // group heading
                    ThemedText {
                        visible: modelData.kind === "head"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        text: modelData.name
                        style: Theme.type.labelSmall
                        emphasized: true
                        color: Theme.color.outline
                        elide: Text.ElideRight
                    }

                    // one check
                    RowLayout {
                        visible: modelData.kind === "item"
                        anchors.fill: parent
                        spacing: Theme.space.sm

                        Text {
                            text: root.statusIcon(modelData.status)
                            color: root.statusColor(modelData.status)
                            font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            Layout.alignment: Qt.AlignVCenter
                        }
                        ThemedText {
                            text: modelData.text
                            style: Theme.type.bodySmall
                            color: modelData.status === "fail" ? Theme.color.error
                                 : modelData.status === "warn" ? Theme.color.fgSurface
                                 : Theme.color.fgSurfaceVariant
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }

            }

            ThemedText {
                anchors.centerIn: parent
                width: parent.width - Theme.space.xl
                horizontalAlignment: Text.AlignHCenter
                visible: list.count === 0
                text: DiagnosticsService.running
                      ? Lang.t("diag.running")
                      : (DiagnosticsService.error.length > 0
                         ? Lang.t("diag.error")
                         : Lang.t("diag.empty"))
                style: Theme.type.bodyMedium
                color: DiagnosticsService.error.length > 0 ? Theme.color.error : Theme.color.fgSurfaceVariant
            }
        }
    }
}
