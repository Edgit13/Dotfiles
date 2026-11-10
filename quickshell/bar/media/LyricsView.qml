import "root:/theme"
import "root:/services"
import "root:/settings"
import QtQuick
import QtQuick.Layouts

// LyricsView — синхронізовані рядки: поточний підсвічений (primary, жирний), решта згасають.
Item {
    id: root

    readonly property bool uk: Lang.current.indexOf("uk") === 0
    property bool active: true                     // false → дашборд закрито: не качаємо й не опитуємо
    readonly property bool live: active && visible
    readonly property bool hasLines: LyricsService.status === "ok" && LyricsService.lines.length > 0

    Component.onCompleted: LyricsService.wanted = Qt.binding(() => root.live)
    Component.onDestruction: LyricsService.wanted = false

    // позиція в MPRIS сама не оновлюється
    Timer {
        interval: 250
        repeat: true
        running: root.live && MediaService.playing
        onTriggered: MediaService.poll()
    }

    // ── стани ───────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.hasLines
        spacing: Theme.space.sm
        width: parent.width - Theme.space.xl * 2

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: LyricsService.status === "loading" ? "\ue627" : "\ue405"     // sync / music_note
            font { family: Theme.type.icons; pixelSize: Theme.type.iconXL }
            color: Theme.color.fgSurfaceVariant
            opacity: 0.7
        }
        ThemedText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: LyricsService.status === "loading" ? (root.uk ? "Шукаю текст…" : "Looking for lyrics…")
                : (root.uk ? "Тексту для цього треку немає" : "No lyrics for this track")
            style: Theme.type.bodyLarge
            color: Theme.color.fgSurfaceVariant
            wrapMode: Text.Wrap
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        visible: root.hasLines
        clip: true
        interactive: !LyricsService.synced
        boundsBehavior: Flickable.StopAtBounds
        model: LyricsService.lines
        spacing: Theme.space.lg

        currentIndex: Math.max(0, LyricsService.index)
        highlightRangeMode: LyricsService.synced ? ListView.StrictlyEnforceRange : ListView.NoHighlightRange
        preferredHighlightBegin: height / 2 - Theme.components.dp(36)
        preferredHighlightEnd: height / 2 + Theme.components.dp(36)
        highlightMoveDuration: Theme.motion.enabled ? 420 : 0
        highlightMoveVelocity: -1

        delegate: Item {
            id: line
            required property var modelData
            required property int index
            readonly property int dist: LyricsService.synced ? Math.abs(index - LyricsService.index) : 0
            readonly property bool current: LyricsService.synced && index === LyricsService.index

            width: list.width
            height: txt.implicitHeight

            ThemedText {
                id: txt
                width: parent.width
                text: line.modelData.text.length > 0 ? line.modelData.text : "♪"
                style: Theme.type.titleLarge
                emphasized: line.current
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
                color: line.current ? (Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.primary) : Theme.color.fgSurface
                opacity: !LyricsService.synced ? 0.9
                       : line.dist === 0 ? 1 : line.dist === 1 ? 0.5 : line.dist === 2 ? 0.28 : 0.14
                scale: line.current ? 1.0 : 0.88
                transformOrigin: Item.Center
                Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                Behavior on color   { MotionColorAnimation { role: "hover" } }
            }
            Rectangle {
                visible: Theme.settings.nothing && line.current
                width: 6; height: 6; radius: 3
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeNothing.red
            }
            MouseArea {
                anchors.fill: parent
                enabled: LyricsService.synced && MediaService.canSeek
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: MediaService.seek(line.modelData.t / MediaService.length)
            }
        }
    }
}
