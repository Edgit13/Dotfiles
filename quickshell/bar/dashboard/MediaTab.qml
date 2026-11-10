import "root:/theme"
import "root:/settings"
import "root:/services"
import "root:/media"
import QtQuick
import QtQuick.Layouts

// MediaTab — dux-style: розмита обкладинка на фоні, зліва синхронізовані тексти, справа плеєр.
Item {
    id: root

    property bool active: true
    property bool showLyrics: true
    readonly property bool has: MediaService.has
    readonly property bool uk: Lang.current.indexOf("uk") === 0
    readonly property real cardR: Theme.shape.cardLarge

    // фон
    Rectangle {
        anchors.fill: parent
        radius: root.cardR
        color: Theme.settings.nothing ? Theme.color.surfaceContainerLow : Theme.color.surfaceContainerHigh
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.22)
    }
    ArtBackdrop {
        anchors.fill: parent
        source: MediaService.artUrl
        radius: root.cardR
        strength: Theme.settings.nothing ? 0.22 : 0.5
    }

    component PlayerChip: Rectangle {
        id: chip
        property string label: ""
        property bool selected: false
        signal clicked()
        implicitHeight: Theme.components.dp(32)
        implicitWidth: chipText.implicitWidth + Theme.space.xl
        radius: selected ? height / 2 : Theme.shape.chip
        color: selected ? Theme.color.secondaryContainer : "transparent"
        border.width: selected ? 0 : 1
        border.color: Theme.color.outlineVariant
        Behavior on radius { MotionAnimation { role: "morph" } }
        Behavior on color  { MotionColorAnimation { role: "hover" } }
        ThemedText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            style: Theme.type.labelLarge
            color: chip.selected ? Theme.color.fgSecondaryContainer : Theme.color.fgSurfaceVariant
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.clicked() }
    }

    // порожній стан
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.has
        spacing: Theme.space.sm
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "\ue405"
            font { family: Theme.type.icons; pixelSize: Theme.type.iconXL * 1.5 }
            color: Theme.color.fgSurfaceVariant
        }
        ThemedText {
            Layout.alignment: Qt.AlignHCenter
            text: Lang.t("ui.media.none")
            style: Theme.type.bodyLarge
            color: Theme.color.fgSurfaceVariant
        }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.space.xl
        visible: root.has
        spacing: Theme.space.xl

        // ── зліва: тексти / обкладинка ──────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.44

            LyricsView {
                anchors.fill: parent
                visible: root.showLyrics
                active: root.active && root.showLyrics
            }
            MediaArt {
                anchors.centerIn: parent
                visible: !root.showLyrics
                width: Math.min(parent.width, parent.height, Theme.components.dp(300))
                height: width
                source: MediaService.artUrl
                playing: MediaService.playing
                morphOnPause: true
                iconSize: Theme.type.iconXL * 1.5
            }
        }

        // ── справа: плеєр ───────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: parent.width * 0.56
            spacing: Theme.space.md

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space.sm
                ThemedText {
                    text: root.uk ? "Слухаєте з" : "Listening from"
                    style: Theme.type.bodyMedium
                    color: Theme.color.fgSurfaceVariant
                }
                Repeater {
                    model: MediaService.players
                    PlayerChip {
                        required property var modelData
                        label: modelData.identity || Lang.t("ui.media.player")
                        selected: modelData === MediaService.player
                        onClicked: MediaService.manual = modelData
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: MediaService.title || Lang.t("ui.media.unknown")
                color: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.primary
                font.family: Theme.settings.nothing ? Theme.type.dot : Theme.type.sans
                font.weight: Font.Bold
                font.pixelSize: Math.round(Theme.type.headlineLarge.size * 1.3)
                fontSizeMode: Text.Fit
                minimumPixelSize: 18
                maximumLineCount: 1
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: MediaService.artist + (MediaService.album ? (MediaService.artist ? " · " : "") + MediaService.album : "")
                style: Theme.type.bodyMedium
                color: Theme.color.fgSurfaceVariant
                elide: Text.ElideRight
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.space.sm
                spacing: 0
                MediaProgress {
                    Layout.fillWidth: true
                    value: MediaService.fraction
                    playing: MediaService.playing
                    seekable: MediaService.canSeek
                    onSeeked: f => MediaService.seek(f)
                }
                RowLayout {
                    Layout.fillWidth: true
                    ThemedText { text: MediaService.fmt(MediaService.position); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                    Item { Layout.fillWidth: true }
                    ThemedText { text: MediaService.length > 0 ? MediaService.fmt(MediaService.length) : "--:--"; style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                }
            }

            // prev · play · next — широкі M3E-кнопки, ширшають при натисканні
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space.sm

                MediaButton {
                    id: prevBtn
                    icon: "\ue045"; variant: "tonal"
                    size: Theme.components.dp(56)
                    Layout.preferredWidth: Theme.components.dp(88) + (pressed ? Theme.components.dp(12) : 0)
                    Behavior on Layout.preferredWidth { MotionAnimation { role: "press" } }
                    enabled: MediaService.canPrev
                    onClicked: MediaService.previous()
                }
                MediaButton {
                    id: playBtn
                    icon: MediaService.playing ? "\ue034" : "\ue037"
                    variant: "filled"
                    morphed: MediaService.playing
                    size: Theme.components.dp(56)
                    Layout.preferredWidth: Theme.components.dp(160) + (pressed ? Theme.components.dp(12) : 0)
                    Behavior on Layout.preferredWidth { MotionAnimation { role: "press" } }
                    enabled: MediaService.canToggle
                    onClicked: MediaService.togglePlay()
                }
                MediaButton {
                    id: nextBtn
                    icon: "\ue044"; variant: "tonal"
                    size: Theme.components.dp(56)
                    Layout.preferredWidth: Theme.components.dp(88) + (pressed ? Theme.components.dp(12) : 0)
                    Behavior on Layout.preferredWidth { MotionAnimation { role: "press" } }
                    enabled: MediaService.canNext
                    onClicked: MediaService.next()
                }
            }

            // lyrics · shuffle · loop
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.space.sm
                MediaButton {
                    icon: "\uec0b"; variant: "toggle"
                    size: Theme.components.dp(44)
                    Layout.preferredWidth: Theme.components.dp(64)
                    toggled: root.showLyrics
                    onClicked: root.showLyrics = !root.showLyrics
                }
                MediaButton {
                    icon: "\ue043"; variant: "toggle"
                    size: Theme.components.dp(44)
                    Layout.preferredWidth: Theme.components.dp(64)
                    toggled: MediaService.shuffle
                    enabled: MediaService.shuffleSupported
                    onClicked: MediaService.toggleShuffle()
                }
                MediaButton {
                    icon: MediaService.loopTrack ? "\ue041" : "\ue040"; variant: "toggle"
                    size: Theme.components.dp(44)
                    Layout.preferredWidth: Theme.components.dp(64)
                    toggled: MediaService.loopOn
                    enabled: MediaService.loopSupported
                    onClicked: MediaService.cycleLoop()
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
