pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import Quickshell
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// DisplaySurface.qml — display control centre (roadmap #3).
//
// Per output: on/off, resolution, refresh rate, scale, rotation, arrangement
// and adaptive sync. Everything is staged locally first. Apply = a real
// wlr-randr change with an 18-second keep/revert countdown, so a bad mode can
// never leave you without a screen for long.
// ==========================================================================
Item {
    id: root

    readonly property bool nothing: Theme.settings.nothing
    readonly property var draft: DisplayService.draft
    readonly property bool multiple: (DisplayService.outputs || []).length > 1
    readonly property string pendingText: {
        let count = 0
        for (const out of root.draft)
            if (DisplayService.isChanged(out.name)) count++
        return Lang.t("display.pending").replace("%1", count)
    }

    Component.onCompleted: DisplayService.refresh()

    // ── helpers ─────────────────────────────────────────────────────────

    function modeOf(out) {
        if (!out) return null
        const modes = out.modes || []
        return modes.find(function (m) { return m.id === out.currentMode })
            || modes.find(function (m) { return m.preferred })
            || modes[0] || null
    }

    function resolutionValue(out) {
        const mode = root.modeOf(out)
        return mode ? (mode.width + "x" + mode.height) : ""
    }

    function resolutionOptions(out) {
        const seen = {}
        const options = []
        for (const mode of (out.modes || [])) {
            const key = mode.width + "x" + mode.height
            if (seen[key]) continue
            seen[key] = true
            options.push({ value: key, label: mode.width + " × " + mode.height })
        }
        return options
    }

    function refreshOptions(out) {
        const key = root.resolutionValue(out)
        return (out.modes || [])
            .filter(function (mode) { return mode.width + "x" + mode.height === key })
            .map(function (mode) {
                return {
                    value: Number(mode.refresh),
                    label: Number(mode.refresh).toFixed(2) + " Hz"
                }
            })
    }

    function selectResolution(out, key) {
        const candidates = (out.modes || []).filter(function (mode) {
            return mode.width + "x" + mode.height === key
        })
        const pick = candidates.find(function (mode) { return mode.current })
            || candidates.find(function (mode) { return mode.preferred })
            || candidates[0]
        if (pick) DisplayService.setMode(out.name, pick.id)
    }

    function selectRefresh(out, refresh) {
        const key = root.resolutionValue(out)
        const pick = (out.modes || []).find(function (mode) {
            return mode.width + "x" + mode.height === key
                && Math.abs(Number(mode.refresh) - Number(refresh)) < 0.05
        })
        if (pick) DisplayService.setMode(out.name, pick.id)
    }

    function transformOptions() {
        return [
            { value: "normal",      label: Lang.t("display.transform.normal") },
            { value: "90",          label: "90°" },
            { value: "180",         label: "180°" },
            { value: "270",         label: "270°" },
            { value: "flipped",     label: Lang.t("display.transform.flipped") },
            { value: "flipped-90",  label: Lang.t("display.transform.flipped") + " 90°" },
            { value: "flipped-180", label: Lang.t("display.transform.flipped") + " 180°" },
            { value: "flipped-270", label: Lang.t("display.transform.flipped") + " 270°" }
        ]
    }

    function scaleOptions() {
        return [1, 1.25, 1.5, 1.75, 2, 2.5, 3].map(function (value) {
            return { value: value, label: Math.round(value * 100) + "%" }
        })
    }

    function relativeValue(out) {
        return out.relative ? (out.relative.where + ":" + out.relative.to) : "current"
    }

    function relativeOptions(out) {
        const options = [{ value: "current", label: Lang.t("display.keepCurrent") }]
        for (const other of root.draft) {
            if (other.name === out.name) continue
            for (const where of ["left", "right", "above", "below"]) {
                options.push({
                    value: where + ":" + other.name,
                    label: Lang.t("display.relative." + where).replace("%1", other.name)
                })
            }
        }
        return options
    }

    function selectRelative(out, value) {
        if (value === "current") {
            DisplayService.setRelative(out.name, null)
            return
        }
        const split = String(value).indexOf(":")
        if (split < 0) return
        DisplayService.setRelative(out.name, {
            where: String(value).slice(0, split),
            to: String(value).slice(split + 1)
        })
    }

    // ── layout ─────────────────────────────────────────────────────────

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.sm

        // header
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                ThemedText { text: Lang.t("display.outputs"); style: Theme.type.titleMedium; emphasized: true }
                ThemedText {
                    text: DisplayService.outputs.length + " " + Lang.t("display.connectedRuntime")
                    style: Theme.type.labelSmall
                    color: Theme.color.outline
                }
            }

            MaterialIconButton {
                icon: "refresh"
                tooltip: Lang.t("display.refresh")
                enabled_: !DisplayService.locked && !DisplayService.loading
                onClicked: DisplayService.refresh()
            }
        }

        // keep / revert countdown
        Rectangle {
            visible: DisplayService.confirming
            Layout.fillWidth: true
            implicitHeight: confirmColumn.implicitHeight + Theme.space.md * 2
            radius: Theme.shape.lg
            color: Theme.color.errorContainer
            border.width: root.nothing ? 1 : 0
            border.color: Theme.color.error

            ColumnLayout {
                id: confirmColumn
                anchors.fill: parent
                anchors.margins: Theme.space.md
                spacing: Theme.space.sm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm

                    Text {
                        text: "timer"
                        color: Theme.color.fgErrorContainer
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        ThemedText {
                            text: Lang.t("display.keepTitle")
                            style: Theme.type.titleSmall
                            emphasized: true
                            color: Theme.color.fgErrorContainer
                        }
                        ThemedText {
                            text: Lang.t("display.keepBody").replace("%1", DisplayService.confirmSeconds)
                            style: Theme.type.bodySmall
                            color: Theme.color.fgErrorContainer
                            opacity: 0.85
                        }
                    }

                    MaterialButton {
                        text: Lang.t("display.keep")
                        icon: "check"
                        style: "tonal"
                        onClicked: DisplayService.keepChanges()
                    }
                    MaterialButton {
                        text: Lang.t("display.revert")
                        style: "outlined"
                        onClicked: DisplayService.revertNow()
                    }
                }

                // progress
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Qt.rgba(Theme.color.fgErrorContainer.r, Theme.color.fgErrorContainer.g, Theme.color.fgErrorContainer.b, 0.20)

                    Rectangle {
                        height: parent.height
                        radius: 2
                        color: Theme.color.fgErrorContainer
                        width: parent.width * Math.max(0, Math.min(1, DisplayService.confirmSeconds / DisplayService.confirmTimeout))
                        Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                    }
                }
            }
        }

        // error
        Rectangle {
            visible: DisplayService.error.length > 0
            Layout.fillWidth: true
            implicitHeight: errorText.implicitHeight + Theme.space.md
            radius: Theme.shape.md
            color: Theme.color.errorContainer
            ThemedText {
                id: errorText
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                text: DisplayService.error
                style: Theme.type.bodySmall
                color: Theme.color.fgErrorContainer
                wrapMode: Text.WordWrap
            }
        }

        // info
        Rectangle {
            visible: DisplayService.message.length > 0 && DisplayService.error.length === 0
            Layout.fillWidth: true
            implicitHeight: msgText.implicitHeight + Theme.space.md
            radius: Theme.shape.md
            color: Theme.color.secondaryContainer
            ThemedText {
                id: msgText
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                text: DisplayService.message
                style: Theme.type.bodySmall
                color: Theme.color.fgSecondaryContainer
                wrapMode: Text.WordWrap
            }
        }

        Item {
            visible: DisplayService.loading && DisplayService.outputs.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            ThemedText { anchors.centerIn: parent; text: Lang.t("display.detecting"); style: Theme.type.bodyMedium; color: Theme.color.outline }
        }

        Item {
            visible: !DisplayService.loading && DisplayService.outputs.length === 0 && DisplayService.error.length === 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            ThemedText { anchors.centerIn: parent; text: Lang.t("display.none"); style: Theme.type.bodyMedium; color: Theme.color.outline }
        }

        // outputs
        Flickable {
            visible: DisplayService.outputs.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: outputsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: outputsColumn
                width: parent.width
                spacing: Theme.space.sm

                Repeater {
                    model: root.draft

                    delegate: Rectangle {
                        id: outputCard
                        required property var modelData
                        readonly property var out: modelData
                        readonly property bool changed: DisplayService.isChanged(out.name)
                        readonly property bool hasControls: out.enabled

                        Layout.fillWidth: true
                        implicitHeight: outputColumn.implicitHeight + Theme.space.md * 2
                        radius: Theme.shape.lg
                        color: Theme.color.surfaceContainer
                        border.width: changed ? 2 : 1
                        border.color: changed ? Theme.color.primary : Theme.color.outlineVariant
                        Behavior on border.color { ColorAnimation { duration: 160 } }

                        ColumnLayout {
                            id: outputColumn
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.sm

                            // name + switch
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm

                                Text {
                                    text: "\ue30f"
                                    color: outputCard.out.enabled ? Theme.color.primary : Theme.color.outline
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconL }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    RowLayout {
                                        spacing: Theme.space.xs
                                        ThemedText { text: outputCard.out.name; style: Theme.type.titleSmall; emphasized: true }
                                        Rectangle {
                                            visible: outputCard.changed
                                            implicitWidth: changedLabel.implicitWidth + Theme.space.sm
                                            implicitHeight: changedLabel.implicitHeight + 2
                                            radius: Theme.shape.full
                                            color: Theme.color.primary
                                            ThemedText {
                                                id: changedLabel
                                                anchors.centerIn: parent
                                                text: root.nothing ? Lang.t("display.changed").toUpperCase() : Lang.t("display.changed")
                                                style: Theme.type.labelSmall
                                                color: Theme.color.fgPrimary
                                            }
                                        }
                                    }
                                    ThemedText {
                                        text: (outputCard.out.model || outputCard.out.description || Lang.t("display.output"))
                                              + (outputCard.out.enabled ? " · " + Lang.t("display.active") : " · " + Lang.t("display.disabled"))
                                        style: Theme.type.labelSmall
                                        color: Theme.color.outline
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                ThemedText {
                                    text: outputCard.out.enabled ? Lang.t("display.on") : Lang.t("display.off")
                                    style: Theme.type.labelSmall
                                    color: outputCard.out.enabled ? Theme.color.primary : Theme.color.outline
                                }
                                MaterialSwitch {
                                    checked: outputCard.out.enabled
                                    enabled_: !DisplayService.locked
                                    onToggled: DisplayService.setEnabled(outputCard.out.name, !outputCard.out.enabled)
                                }
                            }

                            ThemedText {
                                visible: !outputCard.hasControls
                                Layout.fillWidth: true
                                text: Lang.t("display.offHint")
                                style: Theme.type.bodySmall
                                color: Theme.color.outline
                                wrapMode: Text.WordWrap
                            }

                            // resolution + refresh
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm
                                visible: outputCard.hasControls

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    ThemedText { text: Lang.t("display.resolution"); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                                    MaterialDropdown {
                                        Layout.fillWidth: true
                                        options: root.resolutionOptions(outputCard.out)
                                        value: root.resolutionValue(outputCard.out)
                                        enabled_: !DisplayService.locked
                                        onSelected: v => root.selectResolution(outputCard.out, v)
                                    }
                                }

                                ColumnLayout {
                                    Layout.preferredWidth: Theme.components.dp(150)
                                    spacing: 2
                                    ThemedText { text: Lang.t("display.refreshRate"); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                                    MaterialDropdown {
                                        Layout.fillWidth: true
                                        options: root.refreshOptions(outputCard.out)
                                        value: Number(root.modeOf(outputCard.out) ? root.modeOf(outputCard.out).refresh : 0)
                                        enabled_: !DisplayService.locked
                                        onSelected: v => root.selectRefresh(outputCard.out, v)
                                    }
                                }
                            }

                            // scale + rotation
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm
                                visible: outputCard.hasControls

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    ThemedText { text: Lang.t("display.scale"); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                                    MaterialDropdown {
                                        Layout.fillWidth: true
                                        options: root.scaleOptions()
                                        value: Number(outputCard.out.scale || 1)
                                        enabled_: !DisplayService.locked
                                        onSelected: v => DisplayService.setScale(outputCard.out.name, v)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    ThemedText { text: Lang.t("display.rotation"); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                                    MaterialDropdown {
                                        Layout.fillWidth: true
                                        options: root.transformOptions()
                                        value: outputCard.out.transform || "normal"
                                        enabled_: !DisplayService.locked
                                        onSelected: v => DisplayService.setTransform(outputCard.out.name, v)
                                    }
                                }
                            }

                            // arrangement (multi-monitor only)
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                visible: outputCard.hasControls && root.multiple
                                ThemedText { text: Lang.t("display.arrangement"); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                                MaterialDropdown {
                                    Layout.fillWidth: true
                                    options: root.relativeOptions(outputCard.out)
                                    value: root.relativeValue(outputCard.out)
                                    enabled_: !DisplayService.locked
                                    onSelected: v => root.selectRelative(outputCard.out, v)
                                }
                            }

                            // adaptive sync
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm
                                visible: outputCard.hasControls
                                ThemedText {
                                    Layout.fillWidth: true
                                    text: Lang.t("display.adaptiveSync")
                                    style: Theme.type.bodySmall
                                    color: Theme.color.fgSurfaceVariant
                                }
                                MaterialSwitch {
                                    checked: !!outputCard.out.adaptiveSync
                                    enabled_: !DisplayService.locked
                                    onToggled: DisplayService.setAdaptiveSync(outputCard.out.name, !outputCard.out.adaptiveSync)
                                }
                            }

                            // current summary
                            ThemedText {
                                Layout.fillWidth: true
                                text: Lang.t("display.current") + ": "
                                      + (outputCard.out.enabled ? (root.modeOf(outputCard.out) ? root.modeOf(outputCard.out).label : "—") : Lang.t("display.disabled"))
                                      + " · " + Number(outputCard.out.scale || 1).toFixed(2) + "×"
                                      + (outputCard.out.adaptiveSync ? " · VRR" : "")
                                style: Theme.type.labelSmall
                                color: Theme.color.outline
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // right padding for the scrollbar-free flickable
                Item { implicitHeight: Theme.space.xs }
            }
        }

        // action bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm
            visible: DisplayService.outputs.length > 0

            ThemedText {
                Layout.fillWidth: true
                text: DisplayService.hasPending ? root.pendingText : ""
                style: Theme.type.labelMedium
                color: Theme.color.fgSurfaceVariant
                elide: Text.ElideRight
            }

            MaterialButton {
                visible: DisplayService.canRevert && !DisplayService.confirming
                text: Lang.t("display.revertLast")
                icon: "undo"
                style: "text"
                onClicked: DisplayService.revertNow()
            }

            MaterialButton {
                visible: DisplayService.hasPending
                text: Lang.t("display.discard")
                style: "text"
                enabled_: !DisplayService.locked
                onClicked: DisplayService.resetPending()
            }

            MaterialButton {
                text: DisplayService.applying ? Lang.t("display.applying") : Lang.t("display.apply")
                icon: "check"
                enabled_: DisplayService.hasPending && !DisplayService.locked
                onClicked: DisplayService.applyAll()
            }
        }
    }
}
