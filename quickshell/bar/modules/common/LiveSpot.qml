import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/shell"
import "root:/states"
import "root:/notifications"
import QtQuick

// LiveSpot — «жива капсула» всередині пігулки (bar.style = pill).
// Замість того, щоб показувати все підряд, пігулка підсвічує одну поточну подію:
//   • нове сповіщення — іконка застосунку + заголовок (кілька секунд);
//   • таймер, що спливає найближчим часом — зворотний відлік;
//   • музика, що грає — еквалайзер + назва треку.
// Подія зникає сама, пігулка плавно звужується. Клік відкриває відповідну
// поверхню: центр сповіщень, Dashboard із таймером або медіа-плеєр.
// Вмикається в Settings → Бар → «Жива капсула» (bar.live).
BarModule {
    id: root

    signal mediaRequested()
    signal timerRequested()

    readonly property bool nothing: Theme.settings.nothing
    readonly property bool motion: Theme.motion.enabled && !Theme.motion.reduced
    readonly property bool liveOn: Settings.get("bar", "live") !== false

    // ── сповіщення: стан і відлік живе в NotificationService ──
    // Тож compact- і hover-пігулка показують ту саму подію, а hover не «з'їдає» капсулу.
    readonly property var notifItem: NotificationService.liveItem
    readonly property bool notifVisible: root.notifItem !== null && !NotificationService.centerOpen

    // ── таймер: показуємо, коли до спрацювання менше 30 хвилин ──
    property double now: Date.now()
    readonly property var timerNext: TimerService.next
    readonly property real timerLeft: root.timerNext ? (root.timerNext.at - root.now) / 1000 : -1
    readonly property bool timerActive: !!root.timerNext && root.timerLeft >= 0 && root.timerLeft <= 1800
    readonly property real timerWindow: 1800

    Connections {
        target: TimerService
        function onTimersChanged() { root.now = Date.now() }
    }
    Timer {
        interval: 1000
        repeat: true
        running: !!root.timerNext
        onTriggered: root.now = Date.now()
    }

    function fmtLeft(sec) {
        const t = Math.max(0, Math.ceil(Number(sec) || 0))
        const m = Math.floor(t / 60)
        const s = t % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    // ── музика ──
    readonly property bool mediaOn: MediaService.playing && MediaService.title.length > 0
        && BarConfig.moduleEnabled("media") && !ReliefState.hidden("barmodules")

    // ── що показуємо зараз ──
    readonly property string kind: !liveOn ? ""
        : notifVisible ? "notif"
        : timerActive ? "timer"
        : mediaOn ? "media" : ""

    readonly property string glyph: kind === "notif" && root.notifItem && root.notifItem.summary.length > 0
        ? root.notifItem.summary
        : kind === "notif" && root.notifItem && root.notifItem.body.length > 0
        ? root.notifItem.body
        : kind === "notif" ? NotificationService.appKey(root.notifItem)
        : kind === "media" ? MediaService.title
        : kind === "timer" ? fmtLeft(root.timerLeft) : ""

    readonly property bool critical: kind === "notif" && !!root.notifItem && root.notifItem.urgency === 2
    // NotifIcon читає поля навіть коли прихований, тож даємо порожній знімок
    readonly property var emptyNotif: ({ appName: "", appIcon: "", image: "", desktopEntry: "" })
    readonly property color chipFill: nothing ? Qt.rgba(1, 1, 1, 0.08) : Theme.color.secondaryContainer
    readonly property color chipFg: nothing ? Theme.color.fgSurface : Theme.color.fgSecondaryContainer
    readonly property color accent: nothing ? ThemeNothing.red : Theme.color.primary

    shown: kind !== ""
    animate: true
    contentW: chipRow.implicitWidth + Theme.space.md * 2
    contentH: cross

    // еквалайзер: одна анімована фаза, висоти кульок виводяться з неї
    property real eqPulse: 0
    NumberAnimation on eqPulse {
        running: root.motion && root.kind === "media"
        from: 0; to: 1; duration: 1100; loops: Animation.Infinite
        easing.type: Easing.InOutSine
    }

    BarButton {
        anchors.fill: parent
        accent: true
        accentColor: root.chipFill
        stateColor: root.chipFg
        onClicked: {
            if (root.kind === "notif") NotificationService.openCenter()
            else if (root.kind === "timer") root.timerRequested()
            else if (root.kind === "media") root.mediaRequested()
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.space.sm

            // ── іконка / еквалайзер ──
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.components.dp(20)
                height: width

                NotifIcon {
                    anchors.fill: parent
                    visible: root.kind === "notif"
                    notif: root.notifItem || root.emptyNotif
                    critical: root.critical
                }

                Item {
                    anchors.fill: parent
                    visible: root.kind === "media"
                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.components.dp(2)
                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: Theme.components.dp(3)
                                height: root.motion
                                    ? Theme.components.dp(3) + Theme.components.dp(10)
                                      * (0.5 + 0.5 * Math.sin(root.eqPulse * 2 * Math.PI + index * 1.9))
                                    : Theme.components.dp(9)
                                radius: width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.nothing ? ThemeNothing.red : root.chipFg
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.kind === "timer"
                    text: "timer"
                    color: root.chipFg
                    font { family: Theme.type.icons; pixelSize: Theme.components.dp(19) }
                }
            }

            // ── текст ──
            ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, Theme.components.dp(root.kind === "timer" ? 64 : 190))
                text: root.glyph
                style: root.kind === "timer" ? Theme.type.monoMedium : Theme.type.labelLarge
                emphasized: !root.nothing
                color: root.chipFg
                elide: Text.ElideRight
            }

            // ── крапка небезпеки ──
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.critical
                width: Theme.components.dp(6); height: width; radius: width / 2
                color: root.nothing ? ThemeNothing.red : Theme.color.error
            }
        }
    }
}
