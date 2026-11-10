import "root:/theme"
import "root:/settings"
import "root:/services"
import "root:/media"
import QtQuick
import QtQuick.Layouts

// MiniMediaCard — слим-плеєр на Overview: розмитий фон з обкладинки, назва · виконавець, хвиля, кнопки.
DashCard {
    id: root
    pad: 0
    implicitHeight: Theme.components.dp(100)

    ArtBackdrop {
        anchors.fill: parent
        source: MediaService.artUrl
        radius: root.cornerRadius
        strength: Theme.settings.nothing ? 0.22 : 0.5
    }

    RowLayout {
        anchors.centerIn: parent
        visible: !MediaService.has
        spacing: Theme.space.sm
        Text { text: "\ue405"; font { family: Theme.type.icons; pixelSize: Theme.type.iconL } color: Theme.color.fgSurfaceVariant }
        ThemedText { text: Lang.t("ui.media.none"); style: Theme.type.bodyLarge; color: Theme.color.fgSurfaceVariant }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.space.lg
        visible: MediaService.has
        spacing: Theme.space.md

        MediaArt {
            Layout.preferredWidth: Theme.components.dp(64)
            Layout.preferredHeight: Theme.components.dp(64)
            Layout.alignment: Qt.AlignVCenter
            source: MediaService.artUrl
            playing: MediaService.playing
            morphOnPause: true
            baseRadius: Theme.shape.radius("lg", Theme.components.dp(64))
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            ThemedText {
                Layout.fillWidth: true
                text: (MediaService.title || Lang.t("ui.media.unknown")) + (MediaService.artist ? " · " + MediaService.artist : "")
                style: Theme.type.titleSmall
                emphasized: true
                color: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.primary
                elide: Text.ElideRight
            }
            MediaProgress {
                Layout.fillWidth: true
                value: MediaService.fraction
                playing: MediaService.playing
                seekable: MediaService.canSeek
                onSeeked: f => MediaService.seek(f)
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.space.xs
            MediaButton {
                icon: "\ue045"; variant: "tonal"
                size: Theme.components.dp(40)
                enabled: MediaService.canPrev
                onClicked: MediaService.previous()
            }
            MediaButton {
                icon: MediaService.playing ? "\ue034" : "\ue037"
                variant: "filled"
                morphed: MediaService.playing
                size: Theme.components.dp(48)
                enabled: MediaService.canToggle
                onClicked: MediaService.togglePlay()
            }
            MediaButton {
                icon: "\ue044"; variant: "tonal"
                size: Theme.components.dp(40)
                enabled: MediaService.canNext
                onClicked: MediaService.next()
            }
        }
    }
}
