import QtQuick
import QtQuick.Layouts
import "root:/theme"
import "root:/settings"
import "material"

// LockWidgetPanel — вибір віджета + форма / колір / розмір / видимість / скидання.
Item {
    id: root
    required property var pv
    implicitHeight: col.implicitHeight

    readonly property bool uk: Lang.current.indexOf("uk") === 0
    readonly property bool nothing: Theme.settings.nothing
    readonly property var defs: [
        { id: "clock",    uk: "Годинник",         en: "Clock",            shape: true,  toggle: "" },
        { id: "date",     uk: "Дата",             en: "Date",             shape: true,  toggle: "showDate" },
        { id: "weather",  uk: "Погода",           en: "Weather",          shape: true,  toggle: "weatherWidget" },
        { id: "media",    uk: "Зараз грає",       en: "Now playing",      shape: true,  toggle: "mediaWidget" },
        { id: "user",     uk: "Профіль / Face ID", en: "Profile / Face ID", shape: true, toggle: "" },
        { id: "password", uk: "Пароль",           en: "Password",         shape: false, toggle: "" },
        { id: "power",    uk: "Живлення",         en: "Power",            shape: false, toggle: "powerButtons" }
    ]
    // у Nothing форма — це коло / квадрат / капсула, без M3-фігур
    readonly property var shapes: nothing
        ? ["default", "circle", "square", "pill", "oval"]
        : ["default","circle","square","pill","oval","cookie","sunny","burst","star","clover","flower","pentagon","hexagon","blob","pill_diag"]
    readonly property var tints: ["primary", "secondary", "tertiary", "surface"]
    readonly property var defColors: nothing
        ? ({ clock: "primary", date: "tertiary", weather: "secondary", media: "secondary", user: "primary" })
        : ({ clock: "primary", date: "tertiary", weather: "tertiary", media: "secondary", user: "primary" })

    readonly property var wmap: {
        const key = nothing ? "widgetsNothing" : "widgets"
        const m = Settings.get("lockscreen", key)
        return (m && typeof m === "object") ? m : ({})
    }
    readonly property string sid: pv.selected !== "" ? pv.selected : "clock"
    readonly property var def: { for (let i = 0; i < defs.length; i++) if (defs[i].id === sid) return defs[i]; return defs[0] }
    readonly property var cur: wmap[sid] || ({})
    readonly property string curShape: cur.shape !== undefined ? cur.shape : "default"
    readonly property string curColor: cur.color !== undefined ? cur.color : (defColors[sid] || "surface")
    readonly property real curScale: cur.scale !== undefined ? cur.scale : 1.0

    function tintBg(n) {
        if (nothing) {
            switch (n) {
            case "primary":   return "#FFFFFF"
            case "secondary": return "#242424"
            case "tertiary":  return ThemeNothing.red
            default:          return "#101010"
            }
        }
        return n === "secondary" ? Theme.color.secondaryContainer : n === "tertiary" ? Theme.color.tertiaryContainer
             : n === "surface" ? Theme.color.surfaceContainerHighest : Theme.color.primaryContainer
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.space.md

        // ── вибір віджета ──
        Flow {
            Layout.fillWidth: true
            spacing: Theme.space.xs
            Repeater {
                model: root.defs
                Rectangle {
                    required property var modelData
                    readonly property bool on: pv.selected === modelData.id
                    implicitHeight: Theme.components.dp(34)
                    implicitWidth: chipTxt.implicitWidth + Theme.space.xl
                    radius: on ? height / 2 : Theme.shape.radius("md", height)
                    color: on ? Theme.color.secondaryContainer : Theme.color.surfaceContainerHigh
                    Behavior on radius { MotionAnimation { role: "morph" } }
                    Behavior on color { MotionColorAnimation { role: "hover" } }
                    ThemedText {
                        id: chipTxt
                        anchors.centerIn: parent
                        text: root.uk ? modelData.uk : modelData.en
                        style: Theme.type.labelLarge
                        color: parent.on ? Theme.color.fgSecondaryContainer : Theme.color.fgSurfaceVariant
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pv.select(modelData.id) }
                }
            }
        }

        // ── властивості вибраного ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: props.implicitHeight + Theme.space.lg * 2
            radius: Theme.shape.cardLarge
            color: Theme.color.surfaceContainer

            ColumnLayout {
                id: props
                anchors.fill: parent
                anchors.margins: Theme.space.lg
                spacing: Theme.space.md

                ThemedText {
                    text: root.uk ? root.def.uk : root.def.en
                    style: Theme.type.titleMedium
                    emphasized: true
                }

                // видимість
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.def.toggle !== ""
                    ThemedText { Layout.fillWidth: true; text: root.uk ? "Показувати" : "Show"; style: Theme.type.bodyMedium }
                    Rectangle {
                        readonly property bool on: Settings.get("lockscreen", root.def.toggle) === true
                        implicitWidth: 52; implicitHeight: 30; radius: 15
                        color: on ? Theme.color.primary : Theme.color.surfaceContainerHighest
                        Behavior on color { MotionColorAnimation { role: "hover" } }
                        Rectangle {
                            width: parent.on ? 22 : 16; height: width; radius: width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.on ? parent.width - width - 4 : 7
                            color: parent.on ? Theme.color.fgPrimary : Theme.color.outline
                            Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: 160 } }
                        }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: Settings.set("lockscreen", root.def.toggle, !parent.on) }
                    }
                }

                // форма
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.def.shape
                    spacing: Theme.space.xs
                    ThemedText { text: root.uk ? "Форма" : "Shape"; style: Theme.type.labelLarge; color: Theme.color.fgSurfaceVariant }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.space.xs
                        Repeater {
                            model: root.shapes
                            Rectangle {
                                required property string modelData
                                readonly property bool on: root.curShape === modelData
                                width: Theme.components.dp(48); height: width
                                radius: on ? 24 : 14
                                color: on ? Theme.color.secondaryContainer : Theme.color.surfaceContainerHigh
                                Behavior on radius { MotionAnimation { role: "morph" } }
                                ExpressiveDot {
                                    visible: modelData !== "default"
                                    anchors.centerIn: parent
                                    dotSize: 28
                                    shape: modelData
                                    dotColor: parent.on ? Theme.color.fgSecondaryContainer : Theme.color.fgSurfaceVariant
                                }
                                Text {
                                    visible: modelData === "default"
                                    anchors.centerIn: parent
                                    text: "block"
                                    font { family: "Material Symbols Rounded"; pixelSize: 22 }
                                    color: parent.on ? Theme.color.fgSecondaryContainer : Theme.color.fgSurfaceVariant
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: pv.saveWidget(root.sid, { shape: modelData })
                                }
                            }
                        }
                    }
                }

                // колір
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: root.def.shape
                    spacing: Theme.space.xs
                    ThemedText { text: root.uk ? "Колір форми" : "Shape color"; style: Theme.type.labelLarge; color: Theme.color.fgSurfaceVariant }
                    Row {
                        spacing: Theme.space.sm
                        Repeater {
                            model: root.tints
                            Rectangle {
                                required property string modelData
                                readonly property bool on: root.curColor === modelData
                                width: 34; height: 34; radius: 17
                                color: root.tintBg(modelData)
                                border.width: on ? 3 : 1
                                border.color: on ? Theme.color.primary : Theme.color.outlineVariant
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: pv.saveWidget(root.sid, { color: modelData })
                                }
                            }
                        }
                    }
                }

                // розмір
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.xs
                    RowLayout {
                        Layout.fillWidth: true
                        ThemedText { Layout.fillWidth: true; text: root.uk ? "Розмір" : "Size"; style: Theme.type.labelLarge; color: Theme.color.fgSurfaceVariant }
                        ThemedText { text: Math.round(root.curScale * 100) + "%"; style: Theme.type.labelLarge }
                    }
                    Item {
                        id: sld
                        Layout.fillWidth: true
                        implicitHeight: 28
                        readonly property real lo: 0.5
                        readonly property real hi: 2.0
                        readonly property real frac: (root.curScale - lo) / (hi - lo)
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 8; radius: 4; color: Theme.color.surfaceContainerHighest }
                        Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width * sld.frac; height: 8; radius: 4; color: Theme.color.primary }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: (sld.width - 20) * sld.frac
                            width: 20; height: 20; radius: 10
                            color: Theme.color.primary
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            function setFrom(mx) {
                                const f = Math.max(0, Math.min(1, mx / width))
                                const v = Math.round((sld.lo + f * (sld.hi - sld.lo)) * 20) / 20
                                pv.saveWidget(root.sid, { scale: v })
                            }
                            onPressed: m => setFrom(m.x)
                            onPositionChanged: m => { if (pressed) setFrom(m.x) }
                        }
                    }
                }

                // скидання
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.sm
                    Repeater {
                        model: [
                            { t: root.uk ? "Скинути віджет" : "Reset widget", act: 0 },
                            { t: root.uk ? "Скинути все" : "Reset all", act: 1 }
                        ]
                        Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: 38
                            radius: ma2.pressed ? 12 : 19
                            color: modelData.act === 1 ? Theme.color.errorContainer : Theme.color.secondaryContainer
                            Behavior on radius { MotionAnimation { role: "morph" } }
                            ThemedText {
                                anchors.centerIn: parent
                                text: modelData.t
                                style: Theme.type.labelLarge
                                color: modelData.act === 1 ? Theme.color.fgErrorContainer : Theme.color.fgSecondaryContainer
                            }
                            MouseArea {
                                id: ma2
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.act === 1 ? pv.resetAll() : pv.resetWidget(root.sid)
                            }
                        }
                    }
                }
            }
        }
    }
}
