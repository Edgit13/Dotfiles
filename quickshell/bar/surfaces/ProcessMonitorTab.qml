pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import "root:/states"
import "root:/settings"
import "root:/settings/material"
import QtQuick
import QtQuick.Layouts

// ProcessMonitorTab — вкладка «Монітор» у меню ресурсів: процеси, розклад Quickshell,
// вартість його компонентів (скан), режим розвантаження, заморожені процеси, події.
ColumnLayout {
    id: tab

    Layout.fillWidth: true
    spacing: Theme.space.md

    Component.onCompleted: MonitorService.uiSubscribe()
    Component.onDestruction: MonitorService.uiUnsubscribe()

    readonly property var sh: MonitorService.shell
    function fmtTime(sec) {
        const m = Math.floor(sec / 60), s = sec % 60
        return m + ":" + (s < 10 ? "0" : "") + s
    }
    function threadLabel(n) {
        if (n === "quickshell" || n === "qs") return Lang.t("ui.mon.thMain")
        if (n.indexOf("QSGRender") >= 0) return Lang.t("ui.mon.thRender")
        return n
    }

    component Card: Rectangle {
        Layout.fillWidth: true
        radius: Theme.shape.md
        color: Theme.color.surfaceContainer
        implicitHeight: inner.implicitHeight + Theme.space.md * 2
        default property alias content: inner.data
        ColumnLayout {
            id: inner
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space.md }
            spacing: Theme.space.sm
        }
    }
    component Heading: ThemedText {
        Layout.fillWidth: true
        style: Theme.type.labelMedium
        emphasized: true
        color: Theme.color.primary
        font.letterSpacing: 1.2 * Theme.space.k
    }
    component Chip: Rectangle {
        property string text: ""
        property color bg: Theme.color.surfaceContainerHighest
        property color fg: Theme.color.fgSurfaceVariant
        implicitWidth: lbl.implicitWidth + Theme.space.md * 2
        implicitHeight: Theme.components.dp(24)
        radius: height / 2
        color: bg
        ThemedText { id: lbl; anchors.centerIn: parent; text: parent.text; style: Theme.type.labelSmall; color: parent.fg }
    }

    // ───────── вимкнено ─────────
    Card {
        visible: !MonitorService.enabled
        ThemedText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Lang.t("ui.mon.disabled")
            style: Theme.type.bodyMedium
            color: Theme.color.fgSurfaceVariant
        }
    }

    // ───────── демон не запущений ─────────
    Card {
        visible: MonitorService.enabled && !MonitorService.ready
        color: Theme.color.errorContainer
        ThemedText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: Lang.t("ui.mon.errNoReady")
            style: Theme.type.bodySmall
            color: Theme.color.fgErrorContainer
        }
    }

    // ───────── накладні витрати монітора ─────────
    RowLayout {
        Layout.fillWidth: true
        visible: MonitorService.enabled
        spacing: Theme.space.sm
        Chip {
            text: Lang.t("ui.mon.overhead") + " " + MonitorService.selfCpu.toFixed(1) + "% · " + Math.round(MonitorService.selfMem) + " MB"
            bg: Theme.color.tertiaryContainer; fg: Theme.color.fgTertiaryContainer
        }
        Chip { text: MonitorService.scope === "system" ? Lang.t("ui.mon.scopeSystem") : Lang.t("ui.mon.scopeShell") }
        Item { Layout.fillWidth: true }
        MaterialButton {
            text: Lang.t("ui.mon.thawAll")
            icon: "play_arrow"
            style: "tonal"
            visible: MonitorService.frozenList.length > 0
            onClicked: MonitorService.thawAll()
        }
    }

    // ───────── Quickshell ─────────
    Card {
        visible: MonitorService.enabled
        Heading { text: Lang.t("ui.mon.shell").toUpperCase() }

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.md
            ThemedText {
                text: tab.sh ? tab.sh.cpu.toFixed(1) + "%" : "—"
                style: Theme.type.headlineMedium
                emphasized: true
                color: tab.sh && tab.sh.cpu > Number(Settings.get("monitor", "shellCpuLimit") ?? 25) ? Theme.color.error : Theme.color.fgSurface
            }
            ThemedText {
                Layout.fillWidth: true
                text: tab.sh ? "CPU · " + tab.sh.mem + " MB · " + Lang.t("ui.mon.limit") + " " + (Settings.get("monitor", "shellCpuLimit") ?? 25) + "%" : ""
                style: Theme.type.bodySmall
                color: Theme.color.fgSurfaceVariant
            }
        }

        // потоки: main = логіка QML усіх компонентів, render = рендер вікон
        Flow {
            Layout.fillWidth: true
            spacing: Theme.space.xs
            visible: tab.sh && tab.sh.threads && tab.sh.threads.length > 0
            Repeater {
                model: tab.sh ? tab.sh.threads : []
                Chip {
                    required property var modelData
                    text: tab.threadLabel(modelData.n) + " " + modelData.cpu.toFixed(1) + "%"
                }
            }
        }
        Flow {
            Layout.fillWidth: true
            spacing: Theme.space.xs
            visible: tab.sh && tab.sh.children && tab.sh.children.length > 0
            Repeater {
                model: tab.sh ? tab.sh.children : []
                Chip {
                    required property var modelData
                    text: "↳ " + modelData.n + " " + modelData.cpu.toFixed(1) + "%"
                    bg: Theme.color.secondaryContainer; fg: Theme.color.fgSecondaryContainer
                }
            }
        }

        // вартість компонентів (скан)
        Heading { Layout.topMargin: Theme.space.xs; text: Lang.t("ui.mon.costs").toUpperCase() }
        Repeater {
            model: MonitorService.scanIds
            RowLayout {
                id: crow
                required property string modelData
                readonly property real cost: MonitorService.costs[modelData] || 0
                readonly property real maxCost: Math.max(1, ...MonitorService.scanIds.map(i => MonitorService.costs[i] || 0))
                Layout.fillWidth: true
                spacing: Theme.space.sm
                ThemedText {
                    Layout.preferredWidth: Theme.components.dp(130)
                    text: Lang.t("ui.mon.comp." + crow.modelData)
                    style: Theme.type.bodySmall
                    color: MonitorService.scanStep === crow.modelData ? Theme.color.primary : Theme.color.fgSurface
                    emphasized: MonitorService.scanStep === crow.modelData
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Theme.components.dp(8)
                    radius: height / 2
                    color: Theme.color.surfaceContainerHighest
                    Rectangle {
                        width: parent.width * Math.min(1, crow.cost / crow.maxCost)
                        height: parent.height
                        radius: height / 2
                        color: ReliefState.hiddenIds[crow.modelData] ? Theme.color.error : Theme.color.primary
                        Behavior on width { MotionAnimation { role: "stateChange" } }
                    }
                }
                ThemedText {
                    Layout.preferredWidth: Theme.components.dp(48)
                    horizontalAlignment: Text.AlignRight
                    text: crow.cost > 0 ? crow.cost.toFixed(1) + "%" : "—"
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm
            ThemedText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: MonitorService.scanError === "noready" ? Lang.t("ui.mon.errNoReady")
                    : MonitorService.scanError === "noshell" ? Lang.t("ui.mon.errNoShell")
                    : MonitorService.scanning ? Lang.t("ui.mon.scanning") + " " + MonitorService.scanProgress + "%"
                    : MonitorService.costsTime > 0
                      ? Lang.t("ui.mon.scanDone").replace("{m}", Math.round((Date.now() - MonitorService.costsTime) / 60000))
                      : Lang.t("ui.mon.scanHint")
                style: Theme.type.labelSmall
                color: Theme.color.fgSurfaceVariant
            }
            MaterialButton {
                text: MonitorService.scanning ? Lang.t("ui.mon.cancel") : Lang.t("ui.mon.scan")
                icon: MonitorService.scanning ? "close" : "radar"
                style: "tonal"
                onClicked: MonitorService.scanning ? MonitorService.cancelScan() : MonitorService.startScan()
            }
        }
    }

    // ───────── режим розвантаження ─────────
    Card {
        visible: MonitorService.enabled
        color: ReliefState.active || MonitorService.reliefSuggested ? Theme.color.primaryContainer : Theme.color.surfaceContainer
        Heading { text: Lang.t("ui.mon.relief").toUpperCase() }
        ThemedText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: ReliefState.active
                  ? Lang.t("ui.mon.reliefOn").replace("{t}", tab.fmtTime(ReliefState.remainingSec))
                  : MonitorService.reliefSuggested ? Lang.t("ui.mon.reliefSuggest") : Lang.t("ui.mon.reliefHint")
            style: Theme.type.bodySmall
            color: ReliefState.active || MonitorService.reliefSuggested ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            MaterialButton {
                text: ReliefState.active ? Lang.t("ui.mon.reliefStop")
                      : Lang.t("ui.mon.reliefStart").replace("{m}", Settings.get("monitor", "reliefMinutes") ?? 10)
                icon: ReliefState.active ? "stop_circle" : "bolt"
                style: ReliefState.active ? "tonal" : "filled"
                onClicked: ReliefState.active ? ReliefState.stop() : MonitorService.startRelief()
            }
        }
    }

    // ───────── заморожені ─────────
    Card {
        visible: MonitorService.frozenList.length > 0
        Heading { text: Lang.t("ui.mon.frozen").toUpperCase() }
        Repeater {
            model: MonitorService.frozenList
            RowLayout {
                id: frow
                required property var modelData
                Layout.fillWidth: true
                spacing: Theme.space.sm
                ThemedText { text: "❄"; style: Theme.type.titleMedium; color: Theme.color.primary }
                ThemedText { Layout.fillWidth: true; text: frow.modelData.name; style: Theme.type.bodyMedium; emphasized: true; elide: Text.ElideRight }
                ThemedText { text: tab.fmtTime(frow.modelData.left); style: Theme.type.labelSmall; color: Theme.color.fgSurfaceVariant }
                MaterialIconButton { icon: "play_arrow"; style: "tonal"; tooltip: Lang.t("ui.mon.thaw"); onClicked: MonitorService.thaw(frow.modelData.key) }
            }
        }
    }

    // ───────── процеси ─────────
    Heading { visible: MonitorService.enabled; Layout.leftMargin: Theme.space.sm; text: Lang.t("ui.res.procs").toUpperCase() }
    ColumnLayout {
        Layout.fillWidth: true
        visible: MonitorService.enabled
        spacing: Theme.space.listGap

        Repeater {
            model: MonitorService.top
            Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool isFirst: index === 0
                readonly property bool isLast: index === MonitorService.top.length - 1
                readonly property bool userWl: MonitorService.isUserWhitelisted(modelData.name)
                readonly property real ratio: modelData.limit > 0 ? Math.min(1, modelData.cpu / modelData.limit) : Math.min(1, modelData.cpu / 100)

                Layout.fillWidth: true
                implicitHeight: Theme.components.dp(52)
                color: modelData.over ? Theme.color.errorContainer : Theme.color.surfaceContainer
                topLeftRadius: isFirst ? Theme.shape.md : Theme.shape.listInner
                topRightRadius: isFirst ? Theme.shape.md : Theme.shape.listInner
                bottomLeftRadius: isLast ? Theme.shape.md : Theme.shape.listInner
                bottomRightRadius: isLast ? Theme.shape.md : Theme.shape.listInner
                Behavior on color { MotionColorAnimation { role: "stateChange" } }

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.space.md; rightMargin: Theme.space.sm }
                    spacing: Theme.space.sm

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        RowLayout {
                            spacing: Theme.space.xs
                            ThemedText {
                                Layout.fillWidth: true
                                text: row.modelData.name + (row.modelData.n > 1 ? "  ×" + row.modelData.n : "")
                                style: Theme.type.bodyMedium
                                emphasized: true
                                elide: Text.ElideRight
                                color: row.modelData.over ? Theme.color.fgErrorContainer : Theme.color.fgSurface
                            }
                            ThemedText { visible: row.modelData.frozen; text: "❄"; color: Theme.color.primary; style: Theme.type.labelLarge }
                            ThemedText { visible: row.modelData.prot; text: "🛡"; style: Theme.type.labelMedium; opacity: 0.8 }
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: Theme.components.dp(5)
                            radius: height / 2
                            color: Theme.color.surfaceContainerHighest
                            Rectangle {
                                width: parent.width * row.ratio
                                height: parent.height
                                radius: height / 2
                                color: row.modelData.over ? Theme.color.error : Theme.color.primary
                                Behavior on width { MotionAnimation { role: "stateChange" } }
                            }
                        }
                    }

                    ThemedText {
                        Layout.preferredWidth: Theme.components.dp(86)
                        horizontalAlignment: Text.AlignRight
                        text: "CPU " + Math.round(row.modelData.cpu) + "%" + (row.modelData.limit > 0 ? "/" + Math.round(row.modelData.limit) : "")
                        style: Theme.type.labelSmall
                        emphasized: row.modelData.over
                        color: Theme.color.fgSurfaceVariant
                    }
                    ThemedText {
                        Layout.preferredWidth: Theme.components.dp(64)
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData.mem + " MB"
                        style: Theme.type.labelSmall
                        color: Theme.color.fgSurfaceVariant
                    }
                    MaterialIconButton {
                        visible: row.modelData.canFreeze || row.modelData.frozen
                        icon: row.modelData.frozen ? "play_arrow" : "ac_unit"
                        tooltip: row.modelData.frozen ? Lang.t("ui.mon.thaw") : Lang.t("ui.mon.freeze")
                        onClicked: row.modelData.frozen ? MonitorService.thaw(row.modelData.key) : MonitorService.freeze(row.modelData.key)
                    }
                    MaterialIconButton {
                        icon: "shield"
                        selected: row.userWl
                        tooltip: row.userWl ? Lang.t("ui.mon.unwhitelist") : Lang.t("ui.mon.whitelist")
                        onClicked: MonitorService.toggleWhitelist(row.modelData.name)
                    }
                }
            }
        }
    }

    // ───────── події ─────────
    Card {
        visible: MonitorService.events.length > 0
        Heading { text: Lang.t("ui.mon.events").toUpperCase() }
        Repeater {
            model: MonitorService.events.slice().reverse().slice(0, 6)
            ThemedText {
                required property var modelData
                Layout.fillWidth: true
                elide: Text.ElideRight
                style: Theme.type.labelSmall
                color: Theme.color.fgSurfaceVariant
                text: Qt.formatTime(new Date(modelData.ts), "HH:mm:ss") + "  "
                      + (modelData.kind === "exceed" ? "⚠ " + modelData.name + " — CPU " + modelData.cpu + "%, " + modelData.mem + " MB"
                       : modelData.kind === "frozen" ? "❄ " + modelData.name + " — " + Lang.t("ui.mon.evFrozen").replace("{s}", modelData.secs)
                       : modelData.kind === "thawed" ? "▶ " + modelData.name + " — " + Lang.t("ui.mon.evThawed")
                       : "⚡ " + Lang.t("ui.mon.evRelief").replace("{m}", modelData.minutes))
            }
        }
    }
}
