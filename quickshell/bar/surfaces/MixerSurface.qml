import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/shell"
import "root:/settings/material"
import "root:/widgets"
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// MixerSurface.qml — Material 3 Expressive & Nothing OS Audio Device Manager.
// Вкладки:
//   0: Головна (Master volume hero, Brightness, Battery card)
//   1: Пристрої відтворення (Output sinks, вибір основного, гучність, mute, порти)
//   2: Пристрої запису (Input sources, вибір мікрофона, повзунок, mute)
//   3: Гучність додатків (Streams, потік для кожного застосунку)
// ==========================================================================

Item {
    id: root

    property var sink: Pipewire.defaultAudioSink
    readonly property bool sinkReady: sink && sink.ready
    readonly property int vol: sinkReady ? Math.round(sink.audio.volume * 100) : 0

    readonly property bool nothing: Theme.settings.nothing
    property int brightnessVal: 50
    property int currentTab: 0

    Component.onCompleted: {
        AudioService.subscribe()
        if (!brightnessQuery.running) brightnessQuery.running = true
    }
    Component.onDestruction: AudioService.unsubscribe()

    Process {
        id: brightnessQuery
        command: ["sh", "-c", "brightnessctl -m | cut -d, -f4 | tr -d '%'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let val = parseInt(text.trim())
                if (!isNaN(val)) root.brightnessVal = val
            }
        }
    }
    Process { id: brightnessSetProc; command: [] }

    // Optional PipeWire DSP integration through EasyEffects.
    property bool effectsInstalled: false
    property bool effectsRunning: false
    Process {
        id: effectsDetect
        command: ["sh", "-c", "command -v easyeffects"]
        stdout: StdioCollector {
            onStreamFinished: root.effectsInstalled = text.trim().length > 0
        }
    }
    Process {
        id: effectsStatus
        command: ["sh", "-c", "pgrep -x easyeffects >/dev/null && printf running || printf stopped"]
        stdout: StdioCollector {
            onStreamFinished: root.effectsRunning = text.trim() === "running"
        }
    }
    Process { id: effectsLaunch; command: ["easyeffects"] }

    Timer {
        interval: 2500
        repeat: true
        running: root.currentTab === 4
        triggeredOnStart: true
        onTriggered: {
            if (!effectsDetect.running) effectsDetect.running = true
            if (!effectsStatus.running) effectsStatus.running = true
        }
    }

    function setBrightness(val) {
        let clamped = Math.max(5, Math.min(100, val))
        root.brightnessVal = clamped
        brightnessSetProc.command = ["brightnessctl", "s", clamped + "%"]
        brightnessSetProc.running = true
    }

    PwObjectTracker { objects: [root.sink] }

    // ---- M3 Expressive slider: товстий round-трек + велика ручка + drag ----
    component XSlider: RowLayout {
        id: xs
        property string icon: ""
        property color accent: Md.primary
        property real fraction: 0
        property string valueLabel: ""
        property bool big: false
        readonly property bool nothing: Theme.settings.nothing
        signal setFraction(real pct)

        Layout.fillWidth: true
        spacing: 10

        Text {
            visible: xs.icon.length > 0
            text: xs.icon
            color: xs.accent
            font { family: "Material Symbols Rounded"; pixelSize: 15 }
        }

        // ---- Nothing: сегментований слайдер (рядок «пігулок») ----
        Item {
            id: seg
            visible: xs.nothing
            Layout.fillWidth: true
            Layout.preferredHeight: xs.nothing ? (xs.big ? 28 : 20) : 0
            readonly property int count: Math.max(8, Math.floor((width + 4) / 9))

            Row {
                anchors.fill: parent
                spacing: 5
                Repeater {
                    model: seg.count
                    delegate: Rectangle {
                        required property int index
                        readonly property bool lit: (index + 0.5) / seg.count <= xs.fraction
                        width: (seg.width - (seg.count - 1) * 5) / seg.count
                        height: xs.big ? 24 : 16
                        anchors.verticalCenter: parent.verticalCenter
                        radius: width / 2
                        color: lit ? xs.accent : Colors.fg
                        opacity: lit ? 1.0 : ThemeNothing.dotOpacityOff
                        Behavior on opacity { NumberAnimation { duration: 90 } }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onPressed: (m) => xs.setFraction(Math.max(0, Math.min(1, (m.x - 6) / seg.width)))
                onPositionChanged: (m) => { if (pressed) xs.setFraction(Math.max(0, Math.min(1, (m.x - 6) / seg.width))) }
            }
        }

        Rectangle {
            id: track
            visible: !xs.nothing
            Layout.fillWidth: true
            Layout.preferredHeight: xs.big ? 8 : 6
            radius: height / 2
            color: Md.surfaceContainerHighest

            Rectangle {
                width: track.width * xs.fraction
                height: parent.height
                radius: parent.radius
                color: xs.accent
            }

            Rectangle {
                id: handle
                width: xs.big ? 18 : 16
                height: width
                radius: width / 2
                x: track.width * xs.fraction - width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: Colors.fg
                border.width: 3
                border.color: xs.accent
                scale: trackMa.pressed ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: Md.durFast } }
            }

            MouseArea {
                id: trackMa
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onPressed: (m) => xs.setFraction(Math.max(0, Math.min(1, m.x / width)))
                onPositionChanged: (m) => { if (pressed) xs.setFraction(Math.max(0, Math.min(1, m.x / width))) }
            }
        }

        Text {
            text: xs.valueLabel
            color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.7)
            font { family: Colors.monoFont; pixelSize: 11 }
            Layout.preferredWidth: 38
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.sm

        // ---- ПЕРЕМИКАЧ ВКЛАДОК ----
        MaterialSegmented {
            options: [
                { label: Lang.t("mixer.tab.main") },
                { label: Lang.t("mixer.tab.output") },
                { label: Lang.t("mixer.tab.input") },
                { label: Lang.t("mixer.tab.apps") },
                { label: "Effects" }
            ]
            selectedIndex: root.currentTab
            onSelected: index => root.currentTab = index
        }

        // ==================================================================
        // ВКЛАДКА 0: ГОЛОВНА (HERO VOLUME + BRIGHTNESS + BATTERY)
        // ==================================================================
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0
            spacing: 14

            // ---- HERO: volume ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    visible: !root.nothing
                    text: root.sinkReady && root.sink.audio.muted ? "\ue04f" : "\ue050"
                    color: root.sinkReady && root.sink.audio.muted ? Md.error : Md.primary
                    font { family: "Material Symbols Rounded"; pixelSize: 18 }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.nothing ? Lang.t("mixer.volume").toUpperCase() : Lang.t("mixer.volume")
                    color: root.nothing ? Colors.grey1 : Colors.fg
                    font {
                        family: root.nothing ? Theme.type.mono : Colors.uiFont
                        pixelSize: root.nothing ? 10 : 13
                        weight: root.nothing ? 400 : 600
                        letterSpacing: root.nothing ? 2.5 : 0
                    }
                }
                Text {
                    text: root.sinkReady ? root.vol + (root.nothing ? "" : "%") : "-"
                    color: root.nothing ? Colors.fg : Md.primary
                    font {
                        family: root.nothing ? Theme.type.dot : Colors.monoFont
                        pixelSize: root.nothing ? 30 : 14
                        weight: root.nothing ? 400 : 600
                    }
                }
            }

            XSlider {
                big: true
                icon: ""
                fraction: root.vol / 100
                valueLabel: ""
                onSetFraction: (pct) => { if (root.sinkReady) root.sink.audio.volume = pct }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                height: 1
                color: Md.outlineVariant
            }

            // ---- row: brightness + battery card ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                XSlider {
                    Layout.fillWidth: true
                    icon: "\ue3ab"
                    accent: Md.error
                    fraction: root.brightnessVal / 100
                    valueLabel: root.brightnessVal + "%"
                    onSetFraction: (pct) => root.setBrightness(Math.round(pct * 100))
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: batRow.implicitWidth + 20
                    implicitHeight: batRow.implicitHeight + 14
                    radius: root.nothing ? ThemeNothing.corners.sm : Md.rM
                    color: root.nothing ? "transparent" : Qt.rgba(Colors.bg2.r, Colors.bg2.g, Colors.bg2.b, 0.6)
                    border.width: root.nothing ? 1 : 0
                    border.color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.18)

                    RowLayout {
                        id: batRow
                        anchors.centerIn: parent
                        spacing: 6
                        Battery {}
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // ==================================================================
        // ВКЛАДКА 1: ПРИСТРОЇ ВІДТВОРЕННЯ (OUTPUT SINKS)
        // ==================================================================
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1
            clip: true
            contentWidth: width
            contentHeight: sinksCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: sinksCol
                width: parent.width
                spacing: Theme.space.sm

                ThemedText {
                    text: Lang.t("mixer.output.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                Repeater {
                    model: AudioService.sinks
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: sinkItemCol.implicitHeight + Theme.space.md * 2
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: modelData.isDefault
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.08) : Theme.color.primaryContainer)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainer)
                        border.width: 1
                        border.color: modelData.isDefault
                                      ? (root.nothing ? ThemeNothing.red : Theme.color.primary)
                                      : Theme.color.outlineVariant

                        ColumnLayout {
                            id: sinkItemCol
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.sm

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm

                                Text {
                                    text: modelData.name.indexOf("bluez") >= 0 ? "\ue310" : "\ue050"
                                    color: modelData.isDefault ? (root.nothing ? ThemeNothing.red : Theme.color.fgPrimaryContainer) : Theme.color.outline
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    ThemedText {
                                        text: modelData.description || modelData.name
                                        style: Theme.type.titleSmall
                                        emphasized: true
                                        color: modelData.isDefault ? (root.nothing ? Colors.fg : Theme.color.fgPrimaryContainer) : Theme.color.fgSurface
                                        elide: Text.ElideRight
                                    }
                                    ThemedText {
                                        text: modelData.ports.length > 0 ? modelData.ports.join(" • ") : (modelData.activePort || "")
                                        style: Theme.type.labelSmall
                                        color: modelData.isDefault ? (root.nothing ? Colors.grey2 : Theme.color.fgPrimaryContainer) : Theme.color.outline
                                    }
                                }

                                // Mute toggle
                                MaterialIconButton {
                                    icon: modelData.muted ? "volume_off" : "volume_up"
                                    color: modelData.muted ? Theme.color.error : Theme.color.primary
                                    onClicked: AudioService.toggleSinkMute(modelData.index)
                                }

                                // Default selection button
                                MaterialButton {
                                    text: modelData.isDefault ? Lang.t("mixer.default") : Lang.t("mixer.setDefault")
                                    style: modelData.isDefault ? "filled" : "outlined"
                                    enabled_: !modelData.isDefault
                                    onClicked: AudioService.setDefaultSink(modelData.name)
                                }
                            }

                            // Device volume slider
                            XSlider {
                                Layout.fillWidth: true
                                fraction: modelData.volume / 100
                                valueLabel: modelData.volume + "%"
                                onSetFraction: pct => AudioService.setSinkVolume(modelData.index, pct * 100)
                            }
                        }
                    }
                }
            }
        }

        // ==================================================================
        // ВКЛАДКА 2: ПРИСТРОЇ ЗАПИСУ (INPUT SOURCES / MIC)
        // ==================================================================
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2
            clip: true
            contentWidth: width
            contentHeight: sourcesCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: sourcesCol
                width: parent.width
                spacing: Theme.space.sm

                ThemedText {
                    text: Lang.t("mixer.input.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                Repeater {
                    model: AudioService.sources
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: srcItemCol.implicitHeight + Theme.space.md * 2
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: modelData.isDefault
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.08) : Theme.color.secondaryContainer)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainer)
                        border.width: 1
                        border.color: modelData.isDefault
                                      ? (root.nothing ? ThemeNothing.red : Theme.color.secondary)
                                      : Theme.color.outlineVariant

                        ColumnLayout {
                            id: srcItemCol
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.sm

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm

                                Text {
                                    text: modelData.muted ? "\ue02b" : "\ue029" // mic_off : mic
                                    color: modelData.muted ? Theme.color.error : (modelData.isDefault ? (root.nothing ? ThemeNothing.red : Theme.color.fgSecondaryContainer) : Theme.color.outline)
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    ThemedText {
                                        text: modelData.description || modelData.name
                                        style: Theme.type.titleSmall
                                        emphasized: true
                                        color: modelData.isDefault ? (root.nothing ? Colors.fg : Theme.color.fgSecondaryContainer) : Theme.color.fgSurface
                                        elide: Text.ElideRight
                                    }
                                    ThemedText {
                                        text: modelData.ports.length > 0 ? modelData.ports.join(" • ") : (modelData.activePort || "")
                                        style: Theme.type.labelSmall
                                        color: modelData.isDefault ? (root.nothing ? Colors.grey2 : Theme.color.fgSecondaryContainer) : Theme.color.outline
                                    }
                                }

                                // Mute toggle
                                MaterialIconButton {
                                    icon: modelData.muted ? "mic_off" : "mic"
                                    color: modelData.muted ? Theme.color.error : Theme.color.primary
                                    onClicked: AudioService.toggleSourceMute(modelData.index)
                                }

                                // Set Default
                                MaterialButton {
                                    text: modelData.isDefault ? Lang.t("mixer.default") : Lang.t("mixer.setDefault")
                                    style: modelData.isDefault ? "filled" : "outlined"
                                    enabled_: !modelData.isDefault
                                    onClicked: AudioService.setDefaultSource(modelData.name)
                                }
                            }

                            XSlider {
                                Layout.fillWidth: true
                                fraction: modelData.volume / 100
                                valueLabel: modelData.volume + "%"
                                onSetFraction: pct => AudioService.setSourceVolume(modelData.index, pct * 100)
                            }
                        }
                    }
                }
            }
        }

        // ==================================================================
        // ВКЛАДКА 3: ГУЧНІСТЬ ДОДАТКІВ (SINK-INPUTS)
        // ==================================================================
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3
            clip: true
            contentWidth: width
            contentHeight: streamsCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: streamsCol
                width: parent.width
                spacing: Theme.space.sm

                ThemedText {
                    text: Lang.t("mixer.apps.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                Item {
                    visible: AudioService.streams.length === 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.components.dp(120)

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space.sm
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\ue405" // music_off
                            color: Theme.color.outline
                            font { family: Theme.type.icons; pixelSize: Theme.components.dp(36) }
                        }
                        ThemedText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Lang.t("mixer.apps.empty")
                            style: Theme.type.bodyMedium
                            color: Theme.color.outline
                        }
                    }
                }

                Repeater {
                    model: AudioService.streams
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: stCol.implicitHeight + Theme.space.md * 2
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                        border.width: 1
                        border.color: Theme.color.outlineVariant

                        ColumnLayout {
                            id: stCol
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.xs

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.space.sm

                                Text {
                                    text: "\ue405"
                                    color: modelData.muted ? Theme.color.error : Theme.color.primary
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    ThemedText {
                                        text: modelData.name || modelData.binary
                                        style: Theme.type.titleSmall
                                        emphasized: true
                                        elide: Text.ElideRight
                                    }
                                    ThemedText {
                                        visible: modelData.media.length > 0 && modelData.media !== modelData.name
                                        text: modelData.media
                                        style: Theme.type.labelSmall
                                        color: Theme.color.outline
                                        elide: Text.ElideRight
                                    }
                                }

                                MaterialIconButton {
                                    icon: modelData.muted ? "volume_off" : "volume_up"
                                    color: modelData.muted ? Theme.color.error : Theme.color.primary
                                    onClicked: AudioService.toggleStreamMute(modelData.index)
                                }
                            }

                            XSlider {
                                Layout.fillWidth: true
                                fraction: modelData.volume / 100
                                valueLabel: modelData.volume + "%"
                                onSetFraction: pct => AudioService.setStreamVolume(modelData.index, pct * 100)
                            }
                        }
                    }
                }
            }
        }

        // ==================================================================
        // ВКЛАДКА 4: PIPEWIRE DSP / EASYEFFECTS
        // ==================================================================
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 4
            clip: true
            contentWidth: width
            contentHeight: effectsCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: effectsCol
                width: parent.width
                spacing: Theme.space.md

                MaterialButton {
                    Layout.fillWidth: true
                    text: "Open Audio Studio · EQ & mic"
                    icon: "graphic_eq"
                    style: "filled"
                    onClicked: ShellState.openSurface("audio")
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 112
                    radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.lg
                    color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                    border.width: 1
                    border.color: root.effectsRunning ? Theme.color.primary : Theme.color.outlineVariant

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space.md
                        spacing: Theme.space.md

                        Rectangle {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            radius: root.nothing ? 8 : Theme.shape.md
                            color: root.effectsRunning ? Theme.color.primaryContainer : Theme.color.surfaceContainerHigh
                            Text {
                                anchors.centerIn: parent
                                text: "\\ue050"
                                color: root.effectsRunning ? Theme.color.fgPrimaryContainer : Theme.color.primary
                                font { family: Theme.type.icons; pixelSize: 24 }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            ThemedText {
                                text: "EasyEffects"
                                style: Theme.type.titleMedium
                                emphasized: true
                            }
                            ThemedText {
                                Layout.fillWidth: true
                                text: !root.effectsInstalled ? "Not installed"
                                      : root.effectsRunning ? "DSP processing is running"
                                      : "Installed · DSP processing is stopped"
                                style: Theme.type.bodySmall
                                color: root.effectsRunning ? Theme.color.primary : Theme.color.outline
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }

                ThemedText {
                    Layout.fillWidth: true
                    text: "PipeWire audio processing"
                    style: Theme.type.titleSmall
                    emphasized: true
                }
                ThemedText {
                    Layout.fillWidth: true
                    text: "Use EasyEffects for a real-time equalizer, bass enhancement, compressor, limiter, noise reduction and microphone effects. Processing runs through PipeWire and applies system-wide to the selected playback or capture chain."
                    style: Theme.type.bodySmall
                    color: Theme.color.outline
                    wrapMode: Text.WordWrap
                }

                MaterialButton {
                    Layout.fillWidth: true
                    text: !root.effectsInstalled ? "Install EasyEffects (Arch Linux)"
                          : root.effectsRunning ? "Open EasyEffects" : "Launch EasyEffects"
                    icon: "equalizer"
                    style: "filled"
                    onClicked: {
                        if (!root.effectsInstalled) {
                            const term = Settings.get("general", "terminalCommand") || "ghostty"
                            Quickshell.execDetached([term, "-e", "sh", "-lc", "sudo pacman -S easyeffects"])
                        } else {
                            effectsLaunch.running = true
                        }
                    }
                }

                MaterialButton {
                    Layout.fillWidth: true
                    text: "Open presets folder"
                    icon: "folder_open"
                    style: "tonal"
                    enabled_: root.effectsInstalled
                    onClicked: Quickshell.execDetached(["sh", "-c", "xdg-open \"$HOME/.config/easyeffects\""])
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 76
                    radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                    color: root.nothing ? "transparent" : Theme.color.surfaceContainerLow
                    border.width: 1
                    border.color: Theme.color.outlineVariant
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.space.md
                        spacing: 3
                        ThemedText {
                            text: "Useful starting point"
                            style: Theme.type.labelLarge
                            emphasized: true
                        }
                        ThemedText {
                            Layout.fillWidth: true
                            text: "For headphones: start with Equalizer + Limiter. For a microphone: start with Noise Reduction + Compressor. Keep the output limiter enabled to avoid clipping."
                            style: Theme.type.bodySmall
                            color: Theme.color.outline
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
