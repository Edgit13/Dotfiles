pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import Quickshell
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// AudioStudioSurface.qml — Аудіостудія: 10-смуговий еквалайзер, пресети,
// глобальний bypass і шумозаглушення мікрофона (RNNoise) через EasyEffects.
// Бекенд: services/AudioStudioService.qml + scripts/audio-studio.py.
// ==========================================================================
Item {
    id: root

    readonly property bool nothing: Theme.settings.nothing
    readonly property bool active: AudioStudioService.running && !AudioStudioService.bypassed
    readonly property int bandCount: 10
    readonly property var presetOptions: {
        const out = []
        const source = AudioStudioService.presets || []
        const current = AudioStudioService.preset
        let found = false
        for (let i = 0; i < source.length; i++) {
            const p = source[i]
            if (p.name === current) found = true
            out.push({ value: p.name, label: presetLabel(p.name, p.builtin === true) })
        }
        if (!found && current && current.length > 0)
            out.unshift({ value: current, label: presetLabel(current, false) })
        return out
    }

    function presetLabel(name, builtin) {
        if (name === "Custom") return Lang.t("audio.custom")
        const key = "audio.preset." + name.toLowerCase().replace(/\s+/g, "")
        const translated = Lang.t(key)
        return translated !== key ? translated : (builtin ? name : name)
    }

    Component.onCompleted: {
        AudioStudioService.watching = true
        AudioStudioService.refresh()
    }
    Component.onDestruction: {
        AudioStudioService.watching = false
        AudioStudioService.dragging = false
    }

    Connections {
        target: AudioStudioService
        function onPresetChanged() { presetDd.value = AudioStudioService.preset }
    }

    Flickable {
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: parent.width
            spacing: Theme.space.md

            // ── стан аудіодвигуна ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: engineRow.implicitHeight + Theme.space.lg * 2
                radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.cardLarge
                color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                border.width: 1
                border.color: root.active ? Theme.color.primary : Theme.color.outlineVariant

                RowLayout {
                    id: engineRow
                    anchors.fill: parent
                    anchors.margins: Theme.space.lg
                    spacing: Theme.space.md

                    Rectangle {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        radius: root.nothing ? 8 : Theme.shape.md
                        color: root.active ? Theme.color.primaryContainer
                                           : Theme.color.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "\ue050"
                            color: root.active ? Theme.color.fgPrimaryContainer
                                               : Theme.color.primary
                            font { family: Theme.type.icons; pixelSize: 24 }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        ThemedText {
                            text: Lang.t("audio.engine")
                            style: Theme.type.titleSmall
                            emphasized: true
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: !AudioStudioService.installed
                                  ? Lang.t("audio.engineMissing")
                                  : !AudioStudioService.running
                                    ? Lang.t("audio.engineOff")
                                    : AudioStudioService.bypassed
                                      ? Lang.t("audio.engineBypass")
                                      : Lang.t("audio.engineOn")
                            style: Theme.type.bodySmall
                            color: root.active ? Theme.color.primary : Theme.color.outline
                            wrapMode: Text.WordWrap
                        }
                    }

                    MaterialSwitch {
                        visible: AudioStudioService.installed && AudioStudioService.running
                        checked: root.active
                        onToggled: AudioStudioService.toggleBypass()
                    }
                }
            }

            MaterialButton {
                Layout.fillWidth: true
                visible: AudioStudioService.installed && !AudioStudioService.running
                text: Lang.t("audio.start")
                icon: "play_arrow"
                style: "filled"
                onClicked: AudioStudioService.startEngine()
            }

            MaterialButton {
                Layout.fillWidth: true
                visible: !AudioStudioService.installed
                text: "Install EasyEffects"
                icon: "download"
                style: "tonal"
                onClicked: {
                    const term = Settings.get("general", "terminalCommand") || "ghostty"
                    Quickshell.execDetached([term, "-e", "sh", "-lc", "sudo pacman -S easyeffects"])
                }
            }

            // ── еквалайзер ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: eqCol.implicitHeight + Theme.space.lg * 2
                radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.cardLarge
                color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                border.width: 1
                border.color: Theme.color.outlineVariant

                ColumnLayout {
                    id: eqCol
                    anchors.fill: parent
                    anchors.margins: Theme.space.lg
                    spacing: Theme.space.md

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        ThemedText {
                            text: Lang.t("audio.eq")
                            style: Theme.type.titleSmall
                            emphasized: true
                        }
                        Item { Layout.fillWidth: true }
                        ThemedText {
                            text: Lang.t("audio.eqDesc")
                            style: Theme.type.bodySmall
                            color: Theme.color.outline
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.md
                        ThemedText {
                            text: Lang.t("audio.preset")
                            style: Theme.type.bodySmall
                            color: Theme.color.fgSurfaceVariant
                        }
                        MaterialDropdown {
                            id: presetDd
                            Layout.fillWidth: true
                            options: root.presetOptions
                            value: AudioStudioService.preset
                            onSelected: v => AudioStudioService.loadPreset(v)
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.components.dp(204)

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            Repeater {
                                model: root.bandCount
                                delegate: Item {
                                    id: band
                                    required property int index

                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    readonly property real db: Number(AudioStudioService.gains[index] ?? 0)
                                    readonly property real topPad: Theme.components.dp(28)
                                    readonly property real bottomPad: Theme.components.dp(22)
                                    readonly property real areaH: Math.max(1, height - topPad - bottomPad)
                                    readonly property real zeroY: topPad + areaH / 2
                                    readonly property real handleY: topPad + (1 - (db + 12) / 24) * areaH
                                    readonly property color accent: root.nothing ? ThemeNothing.red : Theme.color.primary

                                    // нульова лінія
                                    Rectangle {
                                        x: 0
                                        y: band.zeroY
                                        width: band.width
                                        height: 1
                                        color: Theme.color.outlineVariant
                                        opacity: 0.65
                                    }

                                    // трек
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: band.topPad
                                        width: Theme.components.dp(6)
                                        height: band.areaH
                                        radius: width / 2
                                        color: root.nothing
                                            ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.12)
                                            : Theme.color.surfaceContainerHighest
                                    }

                                    // заповнення від нуля до ручки
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Theme.components.dp(6)
                                        y: Math.min(band.zeroY, band.handleY)
                                        height: Math.abs(band.handleY - band.zeroY)
                                        radius: width / 2
                                        color: band.accent
                                        opacity: 0.9
                                    }

                                    // ручка
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Theme.components.dp(26)
                                        height: Theme.components.dp(13)
                                        y: band.handleY - height / 2
                                        radius: height / 2
                                        color: band.accent
                                        border.width: 2
                                        border.color: Theme.color.surfaceContainer
                                        scale: bandMa.pressed ? 1.12 : bandMa.containsMouse ? 1.06 : 1.0
                                        Behavior on scale { MotionAnimation { role: "press" } }
                                    }

                                    ThemedText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        y: Math.max(0, band.handleY - Theme.components.dp(24))
                                        text: (band.db > 0 ? "+" : "") + band.db.toFixed(1)
                                        style: Theme.type.labelSmall
                                        color: band.db === 0 ? Theme.color.outline : band.accent
                                        opacity: bandMa.pressed || bandMa.containsMouse ? 1 : 0.72
                                    }

                                    ThemedText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        text: AudioStudioService.freqLabels[index] || ""
                                        style: Theme.type.labelSmall
                                        color: Theme.color.outline
                                    }

                                    MouseArea {
                                        id: bandMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.SizeVerCursor

                                        function setFromY(y) {
                                            const ratio = 1 - (y - band.topPad) / band.areaH
                                            AudioStudioService.setGain(band.index, ratio * 24 - 12)
                                        }

                                        onPressed: m => {
                                            AudioStudioService.beginDrag()
                                            setFromY(m.y)
                                        }
                                        onPositionChanged: m => { if (pressed) setFromY(m.y) }
                                        onReleased: AudioStudioService.endDrag()
                                        onCanceled: AudioStudioService.endDrag()
                                        onDoubleClicked: AudioStudioService.setGain(band.index, 0)
                                    }
                                }
                            }
                        }
                    }

                    // ── preamp ─────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.md
                        ThemedText {
                            text: Lang.t("audio.preamp")
                            style: Theme.type.bodySmall
                            color: Theme.color.fgSurfaceVariant
                        }
                        MaterialSlider {
                            Layout.fillWidth: true
                            value: (AudioStudioService.preamp + 12) / 24
                            showValue: true
                            suffix: " dB"
                            decimals: 1
                            onMoved: v => AudioStudioService.setPreamp(v * 24 - 12)
                        }
                        ThemedText {
                            text: (AudioStudioService.preamp > 0 ? "+" : "")
                                  + AudioStudioService.preamp.toFixed(1) + " dB"
                            style: Theme.type.monoSmall
                            color: Theme.color.fgSurface
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Theme.components.dp(56)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        ThemedText {
                            Layout.fillWidth: true
                            text: Lang.t("audio.dragHint")
                            style: Theme.type.bodySmall
                            color: Theme.color.outline
                            wrapMode: Text.WordWrap
                        }
                        MaterialButton {
                            text: Lang.t("audio.reset")
                            icon: "restart_alt"
                            style: "text"
                            onClicked: AudioStudioService.resetEq()
                        }
                    }
                }
            }

            // ── мікрофон ───────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                visible: AudioStudioService.installed
                implicitHeight: micRow.implicitHeight + Theme.space.lg * 2
                radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.cardLarge
                color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                border.width: 1
                border.color: AudioStudioService.mic ? Theme.color.primary : Theme.color.outlineVariant

                RowLayout {
                    id: micRow
                    anchors.fill: parent
                    anchors.margins: Theme.space.lg
                    spacing: Theme.space.md

                    Rectangle {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        radius: root.nothing ? 8 : Theme.shape.md
                        color: AudioStudioService.mic ? Theme.color.primaryContainer
                                                      : Theme.color.surfaceContainerHigh
                        Text {
                            anchors.centerIn: parent
                            text: "\ue029"
                            color: AudioStudioService.mic ? Theme.color.fgPrimaryContainer
                                                          : Theme.color.primary
                            font { family: Theme.type.icons; pixelSize: 24 }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        ThemedText {
                            text: Lang.t("audio.mic")
                            style: Theme.type.titleSmall
                            emphasized: true
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: Lang.t("audio.micDesc")
                            style: Theme.type.bodySmall
                            color: Theme.color.outline
                            wrapMode: Text.WordWrap
                        }
                        ThemedText {
                            visible: AudioStudioService.mic && AudioStudioService.bypassed
                            text: Lang.t("audio.engineBypass")
                            style: Theme.type.labelSmall
                            color: Theme.color.error
                        }
                    }

                    MaterialSwitch {
                        checked: AudioStudioService.mic
                        onToggled: AudioStudioService.toggleMic()
                    }
                }
            }

            // ── дії / помилки ──────────────────────────────────────────
            MaterialButton {
                Layout.fillWidth: true
                visible: AudioStudioService.installed
                text: Lang.t("audio.open")
                icon: "open_in_new"
                style: "tonal"
                onClicked: AudioStudioService.openEasyEffects()
            }

            ThemedText {
                Layout.fillWidth: true
                visible: AudioStudioService.error.length > 0
                text: AudioStudioService.error
                style: Theme.type.bodySmall
                color: Theme.color.error
                wrapMode: Text.WordWrap
            }
        }
    }
}
