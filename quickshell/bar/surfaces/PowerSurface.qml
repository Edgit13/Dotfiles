import "root:/theme"
import "root:/settings"
import "root:/settings/material"
import "root:/services"
import "root:/surfaces"
import Quickshell
import QtQuick
import QtQuick.Layouts

// PowerSurface — живлення: батарея, профіль, поточні споживачі, дії сеансу.
// Дані процесів ідуть із PowerService (powerwatch.py) лише поки це меню відкрите.
Item {
    id: root

    signal requestClose()

    Component.onCompleted: PowerService.subscribe()
    Component.onDestruction: PowerService.unsubscribe()

    readonly property bool nothing: Theme.settings.nothing

    // ───────── форматування ─────────
    function fmtDuration(sec) {
        if (!sec || sec < 30)
            return ""
        let h = Math.floor(sec / 3600)
        let m = Math.round((sec % 3600) / 60)
        if (m === 60) { h += 1; m = 0 }
        if (h > 0)
            return Lang.t("ui.power.durHM").replace("{h}", h).replace("{m}", m)
        return Lang.t("ui.power.durM").replace("{m}", Math.max(1, m))
    }
    function fmtMem(mb) {
        if (!mb)
            return "0 MB"
        return mb >= 1024 ? (mb / 1024).toFixed(1) + " GB" : Math.round(mb) + " MB"
    }
    function run(cmd) {
        const c = cmd === "lock"
            ? "qs -p $HOME/.config/quickshell/bar/shell.qml ipc call ilock relock"
            : cmd === "sleep"
                ? "python3 $HOME/.config/quickshell/bar/scripts/sessionidle.py suspend"
                : cmd
        Quickshell.execDetached(["sh", "-c", c])
        root.requestClose()
    }

    // ───────── статус батареї ─────────
    readonly property color batteryColor: {
        if (!PowerService.hasBattery)
            return Theme.color.fgSurfaceVariant
        if (PowerService.level <= 15 && !PowerService.charging)
            return Theme.color.error
        if (PowerService.level <= 30 && !PowerService.charging)
            return Theme.color.warning
        if (PowerService.charging)
            return Theme.color.success
        return Theme.color.primary
    }
    readonly property string statusKey: {
        if (!PowerService.hasBattery)
            return "ui.power.noBattery"
        if (PowerService.charging)
            return "ui.power.charging"
        if (PowerService.full)
            return "ui.power.full"
        if (PowerService.discharging)
            return "ui.power.discharging"
        return PowerService.onBattery ? "ui.power.discharging" : "ui.power.plugged"
    }
    readonly property string timeLine: {
        if (!PowerService.hasBattery || PowerService.secondsLeft < 30)
            return ""
        if (PowerService.charging)
            return Lang.t("ui.power.toFull") + " · " + root.fmtDuration(PowerService.secondsLeft)
        if (PowerService.discharging)
            return Lang.t("ui.power.toEmpty") + " · " + root.fmtDuration(PowerService.secondsLeft)
        return ""
    }
    readonly property string wattsText: {
        if (!PowerService.hasBattery)
            return ""
        const w = PowerService.drawWatts
        if (w < 0.05)
            return "—"
        return w.toFixed(1) + " " + Lang.t("ui.power.wUnit")
    }
    readonly property string consumerNote: {
        if (!PowerService.hasBattery)
            return Lang.t("ui.power.estimateNoBattery")
        if (PowerService.estimating)
            return Lang.t("ui.power.estimateBattery")
        return Lang.t("ui.power.estimateCharging")
    }

    // ───────── повторно використовувані блоки ─────────
    component Card: Rectangle {
        Layout.fillWidth: true
        radius: Theme.shape.cardLarge
        color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainer
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                              Theme.color.fgSurface.b, 0.16)
        implicitHeight: body.implicitHeight + Theme.space.md * 2
        default property alias content: body.data

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Theme.space.md
            spacing: Theme.space.sm
        }
    }

    component MiniStat: ColumnLayout {
        property string label: ""
        property string value: ""
        property color accent: Theme.color.fgSurface
        Layout.fillWidth: true
        spacing: 0

        ThemedText {
            Layout.fillWidth: true
            text: parent.value
            style: Theme.type.titleSmall
            emphasized: true
            color: parent.accent
            horizontalAlignment: Text.AlignHCenter
        }
        ThemedText {
            Layout.fillWidth: true
            text: parent.label
            style: Theme.type.labelSmall
            color: Theme.color.fgSurfaceVariant
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    component ProcRow: RowLayout {
        id: pr
        property var p: null
        Layout.fillWidth: true
        spacing: Theme.space.sm

        readonly property real cpuShare: pr.p ? Math.max(0, Math.min(1, Number(pr.p.cpu || 0) / 100)) : 0
        readonly property real watts: PowerService.wattsFor(pr.p)

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Theme.components.dp(30)
            implicitHeight: implicitWidth
            radius: Theme.shape.radius("sm", height)
            color: pr.cpuShare > 0.5 ? Theme.color.errorContainer : Theme.color.secondaryContainer
            Behavior on color { MotionColorAnimation { role: "stateChange" } }
            ThemedText {
                anchors.centerIn: parent
                text: (pr.p && pr.p.name ? String(pr.p.name).charAt(0).toUpperCase() : "?")
                style: Theme.type.labelLarge
                emphasized: true
                color: pr.cpuShare > 0.5 ? Theme.color.fgErrorContainer : Theme.color.fgSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space.xs

                ThemedText {
                    Layout.fillWidth: true
                    text: pr.p ? pr.p.name : ""
                    style: Theme.type.labelLarge
                    emphasized: true
                    elide: Text.ElideRight
                }
                ThemedText {
                    text: pr.p ? Number(pr.p.cpu || 0).toFixed(0) + "%" : "—"
                    style: Theme.type.labelMedium
                    color: pr.cpuShare > 0.5 ? Theme.color.error : Theme.color.fgSurfaceVariant
                }
            }

            UsageBar {
                Layout.fillWidth: true
                value: pr.cpuShare
                active: pr.cpuShare > 0.5 ? Theme.color.error : Theme.color.primary
                track: Theme.color.surfaceContainerHighest
                thickness: Theme.components.dp(4)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space.xs

                ThemedText {
                    Layout.fillWidth: true
                    text: pr.p
                          ? (pr.p.n > 1 ? pr.p.n + " " + Lang.t("ui.power.procUnit") + " · " : "")
                            + root.fmtMem(Number(pr.p.mem || 0))
                          : ""
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                    elide: Text.ElideRight
                }
                ThemedText {
                    visible: pr.watts >= 0
                    text: "≈ " + pr.watts.toFixed(1) + " " + Lang.t("ui.power.wUnit")
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                }
            }
        }
    }

    component Action: Rectangle {
        id: act
        property string glyph: ""
        property string label: ""
        property string command: ""
        property bool danger: false
        readonly property bool hovered: actMa.containsMouse
        readonly property color tint: act.danger ? Theme.color.error : Theme.color.fgSurface

        Layout.fillWidth: true
        Layout.preferredHeight: Theme.components.dp(64)
        radius: act.hovered ? Theme.shape.md : Theme.shape.card
        color: Theme.settings.nothing
            ? (act.hovered ? Qt.rgba(act.tint.r, act.tint.g, act.tint.b, 0.08) : "transparent")
            : (act.hovered
                ? (act.danger ? Theme.color.errorContainer : Theme.color.surfaceContainerHighest)
                : Theme.color.surfaceContainerHighest)
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: act.hovered
            ? Qt.rgba(act.tint.r, act.tint.g, act.tint.b, 0.5)
            : Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.16)
        Behavior on color { MotionColorAnimation { role: "hover" } }
        Behavior on border.color { MotionColorAnimation { role: "hover" } }
        Behavior on radius { MotionAnimation { role: "morph" } }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 2

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: act.glyph
                color: act.danger
                    ? (act.hovered ? Theme.color.fgErrorContainer : Theme.color.error)
                    : Theme.color.fgSurfaceVariant
                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
            }
            ThemedText {
                Layout.alignment: Qt.AlignHCenter
                text: act.label
                style: Theme.type.labelSmall
                color: act.danger && act.hovered ? Theme.color.fgErrorContainer : Theme.color.fgSurface
            }
        }

        MouseArea {
            id: actMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.run(act.command)
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Theme.space.md

            // ───────── батарея ─────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: batBody.implicitHeight + Theme.space.md * 2
                radius: Theme.shape.cardLarge
                color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainer
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                                      Theme.color.fgSurface.b, 0.16)

                ColumnLayout {
                    id: batBody
                    anchors.fill: parent
                    anchors.margins: Theme.space.md
                    spacing: Theme.space.sm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.md

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            RowLayout {
                                spacing: Theme.space.xs
                                Rectangle {
                                    implicitWidth: 8
                                    implicitHeight: 8
                                    radius: 4
                                    color: root.batteryColor
                                    Behavior on color { MotionColorAnimation { role: "stateChange" } }
                                }
                                ThemedText {
                                    text: Lang.t(root.statusKey)
                                    style: Theme.type.labelMedium
                                    color: Theme.color.fgSurfaceVariant
                                }
                            }

                            ThemedText {
                                text: PowerService.hasBattery ? Math.round(PowerService.level) + "%" : "—"
                                style: Theme.type.displaySmall
                                emphasized: true
                                color: PowerService.hasBattery ? root.batteryColor : Theme.color.fgSurfaceVariant
                                Behavior on color { MotionColorAnimation { role: "stateChange" } }
                            }

                            ThemedText {
                                visible: text.length > 0
                                text: root.timeLine
                                style: Theme.type.bodySmall
                                color: Theme.color.fgSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            spacing: Theme.space.xs

                            Item {
                                implicitWidth: Theme.components.dp(108)
                                implicitHeight: Theme.components.dp(44)

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.rightMargin: Theme.components.dp(7)
                                    radius: Theme.shape.radius("sm", height)
                                    color: "transparent"
                                    border.width: 2
                                    border.color: root.nothing
                                        ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                                                  Theme.color.fgSurface.b, 0.45)
                                        : root.batteryColor
                                    Behavior on border.color { MotionColorAnimation { role: "stateChange" } }
                                }
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: parent.height - 8
                                    width: Math.max(0, (parent.width - 7 - 8) * PowerService.level / 100)
                                    radius: Theme.shape.radius("xs", height)
                                    color: root.batteryColor
                                    Behavior on width { MotionAnimation { role: "move" } }
                                    Behavior on color { MotionColorAnimation { role: "stateChange" } }
                                }
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    implicitWidth: 5
                                    implicitHeight: 16
                                    radius: 2
                                    color: root.nothing
                                        ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                                                  Theme.color.fgSurface.b, 0.45)
                                        : root.batteryColor
                                }
                            }

                            ColumnLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 0
                                ThemedText {
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: root.wattsText.length > 0
                                    text: root.wattsText
                                    style: Theme.type.titleSmall
                                    emphasized: true
                                }
                                ThemedText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: Lang.t("ui.power.power")
                                    style: Theme.type.labelSmall
                                    color: Theme.color.fgSurfaceVariant
                                }
                            }
                        }
                    }

                    UsageBar {
                        Layout.fillWidth: true
                        value: PowerService.level / 100
                        active: root.batteryColor
                        track: Theme.color.surfaceContainerHighest
                        thickness: Theme.components.dp(6)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.space.sm
                        visible: PowerService.hasBattery

                        MiniStat {
                            label: Lang.t("ui.power.health")
                            value: PowerService.health >= 0 ? Math.round(PowerService.health) + "%" : "—"
                            accent: PowerService.health >= 0 && PowerService.health < 70
                                    ? Theme.color.warning : Theme.color.success
                        }
                        MiniStat {
                            label: Lang.t("ui.power.cycles")
                            value: PowerService.cycles > 0 ? String(PowerService.cycles) : "—"
                        }
                        MiniStat {
                            label: Lang.t("ui.power.capacity")
                            value: PowerService.capacityWh > 0
                                   ? PowerService.capacityWh.toFixed(1) + " " + Lang.t("ui.power.whUnit")
                                   : "—"
                        }
                    }

                    ThemedText {
                        Layout.fillWidth: true
                        visible: !PowerService.hasBattery
                        text: Lang.t("ui.power.noBatteryHint")
                        style: Theme.type.bodySmall
                        color: Theme.color.fgSurfaceVariant
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ───────── профіль живлення ─────────
            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.xs
                    Text {
                        text: "\ue8ac"
                        color: Theme.color.primary
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: Lang.t("ui.power.profile")
                        style: Theme.type.labelLarge
                        color: Theme.color.fgSurfaceVariant
                    }
                }
                MaterialSegmented {
                    id: profileSeg
                    options: {
                        const o = [
                            { label: Lang.t("ui.power.profile.saver") },
                            { label: Lang.t("ui.power.profile.balanced") }
                        ]
                        if (PowerService.hasPerformance)
                            o.push({ label: Lang.t("ui.power.profile.performance") })
                        return o
                    }
                    selectedIndex: Math.min(PowerService.profileIndex, options.length - 1)
                    onSelected: index => PowerService.setProfileIndex(index)
                }
            }

            // ───────── що споживає ─────────
            Card {
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.xs
                    Text {
                        text: "\ue322"
                        color: Theme.color.primary
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: Lang.t("ui.power.consumers")
                        style: Theme.type.titleSmall
                        emphasized: true
                    }
                    ThemedText {
                        text: "CPU " + PowerService.cpu.toFixed(0) + "%"
                              + (PowerService.temp > 0 ? " · " + PowerService.temp + "°C" : "")
                        style: Theme.type.labelSmall
                        color: Theme.color.fgSurfaceVariant
                    }
                }

                ThemedText {
                    Layout.fillWidth: true
                    visible: !PowerService.ready || PowerService.ticks <= 1
                    text: Lang.t("ui.power.collecting")
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                }

                Repeater {
                    model: PowerService.top.length > 5 ? PowerService.top.slice(0, 5) : PowerService.top
                    ProcRow { p: modelData; visible: PowerService.ticks > 1 }
                }

                ThemedText {
                    Layout.fillWidth: true
                    visible: PowerService.ready && PowerService.ticks > 1 && PowerService.top.length > 0
                    text: root.consumerNote
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }

            // ───────── дії сеансу ─────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space.sm

                Action {
                    glyph: "\ue899"; label: Lang.t("ui.power.aLock"); command: "lock"
                }
                Action {
                    glyph: "bedtime"; label: Lang.t("ui.power.aSleep"); command: "sleep"
                }
                Action {
                    glyph: "\ue9ba"; label: Lang.t("ui.power.aLogout")
                    command: "loginctl terminate-user $USER"
                }
                Action {
                    glyph: "\uf053"; label: Lang.t("ui.power.aReboot"); command: "systemctl reboot"
                }
                Action {
                    glyph: "\ue8ac"; label: Lang.t("ui.power.aShutdown")
                    command: "systemctl poweroff"; danger: true
                }
            }
        }
    }
}
