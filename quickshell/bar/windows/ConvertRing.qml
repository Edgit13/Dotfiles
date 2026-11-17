pragma ComponentBehavior: Bound

import "root:/theme"
import "root:/settings"
import "root:/services"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

// ==========================================================================
// ConvertRing — кільце конвертації біля курсора.
//
// SUPER + правий клік у файловому менеджері (scripts/convert-ring.sh) кладе
// список виділених файлів у ConvertService. Кільце питає те саме, що й
// AngelOS: спершу тип (картинки / відео / звук), потім формат — навів, натиснув.
// У центрі — кількість файлів; клік по центру, Esc або правий клік — на рівень
// назад. Цифри 1–9 вибирають слот, Enter — підсвічений.
// ==========================================================================
PanelWindow {
    id: win

    readonly property bool nothing: Theme.settings.nothing
    readonly property bool animated: Theme.motion.enabled && !Theme.motion.reduced

    readonly property var targetScreen: {
        const list = Quickshell.screens
        if (ConvertService.anchorMonitor.length > 0)
            for (let i = 0; i < list.length; i++)
                if (list[i].name === ConvertService.anchorMonitor) return list[i]
        const name = MangoService.focusedMonitor
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        return list.length > 0 ? list[0] : null
    }

    screen: win.targetScreen
    visible: ConvertService.open
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "edots-convert"
    WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function dp(v) { return Theme.components.dp(v) }
    function bytes(n) {
        if (n < 0) return "…"
        if (n < 1000) return n + " B"
        if (n < 1000000) return (n / 1000).toFixed(0) + " KB"
        if (n < 1000000000) return (n / 1000000).toFixed(n < 10000000 ? 1 : 0) + " MB"
        return (n / 1000000000).toFixed(1) + " GB"
    }

    // ── геометрія ──
    readonly property real slotSize: win.dp(64)
    readonly property real gap: win.dp(16)
    readonly property var slots: ConvertService.level === ""
        ? ConvertService.ringKinds.map(k => ({ id: k, kind: k, label: Lang.t("ui.convert.kind." + k), big: "",
                                               count: ConvertService.filesFor(k).length, same: false, size: -1 }))
        : (ConvertService.formats[ConvertService.level] || []).map(f => ({ id: f.id, kind: ConvertService.level,
                                                                          label: f.label, big: f.label,
                                                                          count: 1, same: ConvertService.same.indexOf(f.id) >= 0,
                                                                          size: ConvertService.sizes[f.id] !== undefined
                                                                              ? ConvertService.sizes[f.id] : -1 }))
    readonly property real r1: Math.max(win.dp(112), win.slots.length * (win.slotSize + win.gap) / (2 * Math.PI))
    readonly property real reach: win.r1 + win.slotSize / 2 + win.dp(34)

    readonly property real px: win.screen
        ? Math.max(win.reach, Math.min(win.width - win.reach, ConvertService.anchorX - win.screen.x))
        : win.width / 2
    readonly property real py: win.screen
        ? Math.max(win.reach, Math.min(win.height - win.reach, ConvertService.anchorY - win.screen.y))
        : win.height / 2

    property int current: -1
    property real reveal: 0

    function angleOf(i) { return -Math.PI / 2 + i * 2 * Math.PI / Math.max(1, win.slots.length) }
    function pick(i) {
        const s = win.slots[i]
        if (!s || s.same) return
        if (ConvertService.level === "") ConvertService.level = s.id
        else ConvertService.pick(s.id)
    }
    function hoverText() {
        if (win.current >= 0 && win.slots[win.current]) {
            const s = win.slots[win.current]
            const name = ConvertService.level === "" ? s.label + " · " + s.count : s.label
            if (ConvertService.level === "")
                return name
            if (s.same) return name + " · " + Lang.t("ui.convert.already")
            return name + " · ≈" + win.bytes(s.size) + " (" + Lang.t("ui.convert.now") + " " + win.bytes(ConvertService.now) + ")"
        }
        if (ConvertService.level === "") {
            const base = Lang.t("ui.convert.what")
            return ConvertService.skipped > 0 ? base + " · " + Lang.t("ui.convert.skipped").replace("{n}", ConvertService.skipped) : base
        }
        return Lang.t("ui.convert.format")
    }

    onVisibleChanged: {
        if (!visible) return
        win.current = -1
        if (win.animated) {
            win.reveal = 0
            grow.restart()
        } else {
            win.reveal = 1
        }
    }
    Connections {
        target: ConvertService
        function onLevelChanged() {
            win.current = -1
            if (win.animated) { win.reveal = 0; grow.restart() }
            else win.reveal = 1
        }
        function onOpenChanged() {
            if (ConvertService.open) focusItem.forceActiveFocus()
        }
    }
    NumberAnimation {
        id: grow
        target: win
        property: "reveal"
        from: 0
        to: 1
        duration: 200
        easing.type: Easing.OutBack
    }

    Item {
        id: focusItem
        anchors.fill: parent
        focus: win.visible
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) ConvertService.back()
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) win.pick(e.key - Qt.Key_1)
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (win.current >= 0) win.pick(win.current)
            } else return
            e.accepted = true
        }
        Component.onCompleted: if (win.visible) forceActiveFocus()
    }

    // ── затемнення — маленьке коло під кільцем, а не весь екран ──
    // Радіальний градієнт: у центрі щільніше, до краю — прозоро. Прозорість
    // живе в кольорах градієнта, тож reveal анімується без окремого шару.
    // (У mango цей namespace має no_blur — інакше композитор розмиває фон
    // під колом і воно виглядає світлою плямою.)
    Shape {
        id: shade
        anchors.fill: parent
        antialiasing: true

        readonly property real disc: win.reach + win.dp(8)
        readonly property real tint: win.reveal * (win.nothing ? 0.66 : 0.52)

        ShapePath {
            strokeWidth: 0
            fillGradient: RadialGradient {
                centerX: win.px
                centerY: win.py
                centerRadius: shade.disc
                focalX: win.px
                focalY: win.py
                focalRadius: 0
                GradientStop { position: 0.00; color: Qt.rgba(0, 0, 0, 0.99 * shade.tint) }
                GradientStop { position: 0.84; color: Qt.rgba(0, 0, 0, 0.95 * shade.tint) }
                GradientStop { position: 0.92; color: Qt.rgba(0, 0, 0, 0.68 * shade.tint) }
                GradientStop { position: 0.97; color: Qt.rgba(0, 0, 0, 0.24 * shade.tint) }
                GradientStop { position: 1.00; color: Qt.rgba(0, 0, 0, 0.00) }
            }
            startX: win.px - shade.disc
            startY: win.py
            PathAngleArc {
                centerX: win.px
                centerY: win.py
                radiusX: shade.disc
                radiusY: shade.disc
                startAngle: 0
                sweepAngle: 360
            }
        }
    }

    // прозорий перехоплювач (нічого не малює): клік поза кільцем закриває,
    // правий — на рівень назад
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: m => m.button === Qt.RightButton ? ConvertService.back() : ConvertService.close()
    }

    Item {
        anchors.fill: parent
        opacity: win.reveal

        // підпис угорі: що робимо / що буде з файлами
        Rectangle {
            id: hint
            x: win.px - width / 2
            y: win.py - win.r1 - win.slotSize / 2 - height - win.dp(14)
            width: hintText.implicitWidth + win.dp(28)
            height: win.dp(32)
            radius: Theme.shape.chip
            color: win.nothing ? Qt.rgba(0, 0, 0, 0.72) : Theme.color.surfaceContainerHigh
            border.width: win.nothing ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.25)
            opacity: win.reveal > 0.6 ? 1 : 0

            ThemedText {
                id: hintText
                anchors.centerIn: parent
                text: win.hoverText()
                style: Theme.type.labelMedium
                color: Theme.color.fgSurface
                font.capitalization: win.nothing ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: win.nothing ? 1 : style.tracking
            }
        }

        // центр: скільки файлів, клік — назад
        Rectangle {
            id: hub
            x: win.px - width / 2
            y: win.py - height / 2
            width: win.dp(76)
            height: width
            radius: Theme.shape.badge
            color: hubMouse.containsMouse
                ? (win.nothing ? Qt.rgba(1, 1, 1, 0.14) : Theme.color.primaryContainer)
                : (win.nothing ? Qt.rgba(0, 0, 0, 0.72) : Theme.color.surfaceContainerHighest)
            border.width: win.nothing ? 1 : 0
            border.color: Qt.rgba(1, 1, 1, 0.3)

            Column {
                anchors.centerIn: parent
                spacing: 0

                ThemedText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: hubMouse.containsMouse && ConvertService.level ? "←" : String(ConvertService.count)
                    style: Theme.type.titleMedium
                    emphasized: true
                    color: win.nothing ? "#FFFFFF" : Theme.color.fgSurface
                }
                ThemedText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: ConvertService.level
                        ? Lang.t("ui.convert.kind." + ConvertService.level)
                        : Lang.t("ui.convert.files")
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                    font.capitalization: win.nothing ? Font.AllUppercase : Font.MixedCase
                }
            }
            HoverHandler { id: hubMouse }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: ConvertService.back()
            }
        }

        // слоти
        Repeater {
            model: win.slots
            Item {
                id: slot
                required property var modelData
                required property int index

                readonly property real a: win.angleOf(index)
                readonly property bool sel: win.current === index
                readonly property real out: Math.max(0, Math.min(1, win.reveal * 1.25 - index * 0.04))

                width: win.slotSize + win.dp(56)
                height: win.slotSize + win.dp(26)
                x: win.px + Math.cos(a) * win.r1 * out - width / 2
                y: win.py + Math.sin(a) * win.r1 * out - win.slotSize / 2
                opacity: Math.min(1, out) * (modelData.same ? 0.45 : 1)

                Rectangle {
                    id: tile
                    width: win.slotSize
                    height: win.slotSize
                    anchors.horizontalCenter: parent.horizontalCenter
                    radius: Theme.shape.badge
                    scale: slot.sel ? 1.12 : 1
                    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

                    color: slot.sel
                        ? (win.nothing ? Qt.rgba(1, 1, 1, 0.16) : Theme.color.primaryContainer)
                        : (win.nothing ? Qt.rgba(0, 0, 0, 0.72) : Theme.color.surfaceContainerHigh)
                    border.width: win.nothing ? 1 : 0
                    border.color: Qt.rgba(1, 1, 1, slot.sel ? 0.7 : 0.25)

                    ThemedText {
                        anchors.centerIn: parent
                        visible: slot.modelData.big === ""
                        text: slot.modelData.kind === "image" ? "image" : slot.modelData.kind === "video" ? "movie" : "music_note"
                        color: slot.sel
                            ? (win.nothing ? "#FFFFFF" : Theme.color.fgPrimaryContainer)
                            : (win.nothing ? "#FFFFFF" : Theme.color.fgSurface)
                        font.family: Theme.type.icons
                        font.pixelSize: win.dp(28)
                    }
                    ThemedText {
                        anchors.centerIn: parent
                        visible: slot.modelData.big !== ""
                        text: slot.modelData.big
                        style: Theme.type.labelLarge
                        emphasized: true
                        color: slot.sel
                            ? (win.nothing ? "#FFFFFF" : Theme.color.fgPrimaryContainer)
                            : (win.nothing ? "#FFFFFF" : Theme.color.fgSurface)
                    }
                    // скільки файлів цього типу
                    Rectangle {
                        visible: !ConvertService.level && slot.modelData.count > 0
                        width: Math.max(win.dp(20), badgeText.implicitWidth + win.dp(12))
                        height: win.dp(20)
                        radius: height / 2
                        anchors { top: parent.top; right: parent.right; margins: -win.dp(2) }
                        color: win.nothing ? ThemeNothing.red : Theme.color.primary

                        ThemedText {
                            id: badgeText
                            anchors.centerIn: parent
                            text: String(slot.modelData.count)
                            style: Theme.type.labelSmall
                            emphasized: true
                            color: win.nothing ? "#FFFFFF" : Theme.color.fgPrimary
                        }
                    }
                }

                ThemedText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: tile.bottom
                    anchors.topMargin: win.dp(6)
                    text: win.slotCaption(slot.modelData, slot.index)
                    style: Theme.type.labelSmall
                    color: slot.sel ? Theme.color.fgSurface : Theme.color.fgSurfaceVariant
                    font.capitalization: win.nothing ? Font.AllUppercase : Font.MixedCase
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: slot.modelData.same ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                    onEntered: win.current = slot.index
                    onExited: if (win.current === slot.index) win.current = -1
                    onClicked: win.pick(slot.index)
                }
            }
        }
    }

    function slotCaption(s, i) {
        if (!ConvertService.level) return s.label
        if (s.same) return Lang.t("ui.convert.same")
        return "≈" + win.bytes(s.size)
    }
}
