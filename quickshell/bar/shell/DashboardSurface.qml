import "root:/theme"
import "root:/dashboard"
import "root:/services"
import "root:/shell"
import "root:/settings"
import Quickshell
import QtQuick
import QtQuick.Layouts

// DashboardSurface — M3 Expressive dashboard overlay.
//
// Layout: identity + environment → control → time → media.
// Animation: surface slides from bar direction + fades + scales;
// cards cascade in with per-index delay; tabs crossfade with slide.
Item {
    id: root

    property string hostMonitor: ""
    property real maxHeight: 100000
    property bool occupies: false
    property bool listenShell: true          // false — коли поверхнею керує хост (pill)
    property string revealDirection: "top"   // top|bottom|left|right

    readonly property real desiredHeight: 840
    readonly property real effectiveHeight: Math.min(desiredHeight, maxHeight)

    implicitWidth: 920
    implicitHeight: occupies ? effectiveHeight : 0

    // ---- Interface consumed by BarWindow.morphModules ----
    readonly property real overflowBottom: occupies ? effectiveHeight : 0
    readonly property real overflowTop:    occupies ? effectiveHeight : 0
    readonly property real overflowLeft:   occupies ? implicitWidth  : 0
    readonly property real overflowRight:  occupies ? implicitWidth  : 0

    visible: occupies || opacity > 0.01

    Connections {
        target: ShellState
        function onOpenDashboardRequested(monitor) {
            if (root.listenShell && (monitor === "" || monitor === root.hostMonitor)) root.occupies = true
        }
        function onToggleDashboardRequested(monitor) {
            if (root.listenShell && (monitor === "" || monitor === root.hostMonitor)) root.occupies = !root.occupies
        }
        function onCloseDashboardRequested() { if (root.listenShell) root.occupies = false }
    }

    property int currentTab: 0

    readonly property int contentHeight: Math.max(300, Math.round(effectiveHeight) - 120)

    readonly property var tabs: [
        { glyph: "\ue871", label: Lang.t("ui.tab.overview") },
        { glyph: "\ue405", label: Lang.t("ui.tab.media") },
        { glyph: "\ue85c", label: Lang.t("ui.tab.performance") },
        { glyph: "\uef4c", label: Lang.t("ui.tab.workspaces") },
        { glyph: "\ue935", label: Lang.t("ui.tab.planner") }
    ]

    // Slide offset when hidden — depends on bar side.
    readonly property real _offsetX: {
        if (occupies) return 0
        if (revealDirection === "left")  return -32
        if (revealDirection === "right") return  32
        return 0
    }
    readonly property real _offsetY: {
        if (occupies) return 0
        if (revealDirection === "top")    return -32
        if (revealDirection === "bottom") return  32
        return 0
    }
    readonly property int _origin: {
        if (revealDirection === "left")   return Item.Left
        if (revealDirection === "right")  return Item.Right
        if (revealDirection === "bottom") return Item.Bottom
        return Item.Top
    }

    // ── Animated stage: slides + fades + scales as one unit ──────
    Item {
        id: stage
        anchors.fill: parent
        x: root._offsetX
        y: root._offsetY
        opacity: root.occupies ? 1 : 0
        scale:   root.occupies ? 1 : 0.96
        transformOrigin: root._origin

        Behavior on x       { NumberAnimation { duration: 440; easing.type: Easing.OutCubic } }
        Behavior on y       { NumberAnimation { duration: 440; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 440; easing.type: Easing.OutCubic } }

        ElevationShadow {
            anchors.fill: parent
            level: Theme.elevation.resting
            radius: Theme.shape.cardLarge
            color: Theme.color.surfaceContainer
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.space.lg
            spacing: Theme.space.md

            // ── Tab bar (M3 navigation bar: pill під іконкою, підпис нижче) ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space.xs

                Repeater {
                    model: root.tabs
                    Item {
                        id: tabItem
                        required property var modelData
                        required property int index
                        readonly property bool current: index === root.currentTab

                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.components.dp(60)

                        Column {
                            anchors.centerIn: parent
                            spacing: Theme.space.xs

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tabItem.current ? Theme.components.dp(64) : Theme.components.dp(40)
                                height: Theme.components.dp(32)
                                radius: height / 2
                                color: tabItem.current
                                    ? Theme.color.secondaryContainer
                                    : tabMa.pressed
                                        ? Theme.stateLayer(Theme.color.surfaceContainerHighest, Theme.color.fgSurface, Theme.components.statePressed)
                                        : tabMa.containsMouse
                                            ? Theme.stateLayer(Theme.color.surfaceContainerHighest, Theme.color.fgSurface, Theme.components.stateHover)
                                            : "transparent"
                                Behavior on width { MotionAnimation { role: "morph" } }
                                Behavior on color { MotionColorAnimation { role: "hover" } }

                                Text {
                                    anchors.centerIn: parent
                                    text: tabItem.modelData.glyph
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                                    color: tabItem.current ? Theme.color.fgSecondaryContainer : Theme.color.fgSurfaceVariant
                                }
                            }
                            ThemedText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: tabItem.modelData.label
                                style: Theme.type.labelMedium
                                emphasized: tabItem.current
                                color: tabItem.current ? Theme.color.fgSurface : Theme.color.fgSurfaceVariant
                            }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: Theme.settings.nothing
                                width: 4; height: 4; radius: 2
                                color: ThemeNothing.red
                                opacity: tabItem.current ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                            }
                        }
                        MouseArea {
                            id: tabMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentTab = tabItem.index
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: Theme.components.dp(32)
                    implicitHeight: Theme.components.dp(32)
                    radius: height / 2
                    color: closeMa.pressed
                        ? Theme.stateLayer(Theme.color.surfaceContainerHighest, Theme.color.fgSurface, Theme.components.statePressed)
                        : closeMa.containsMouse
                            ? Theme.stateLayer(Theme.color.surfaceContainerHighest, Theme.color.fgSurface, Theme.components.stateHover)
                            : "transparent"
                    Behavior on color { MotionColorAnimation { role: "hover" } }
                    Text {
                        anchors.centerIn: parent
                        text: "\ue5cd"
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                        color: Theme.color.fgSurface
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ShellState.closeDashboard()
                    }
                }
            }

            // ── Page stack with crossfade + slide ────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: root.contentHeight
                clip: true

                Repeater {
                    model: root.tabs.length
                    Item {
                        id: pageWrap
                        required property int index
                        anchors.fill: parent
                        readonly property bool isCurrent: index === root.currentTab
                        visible: opacity > 0.01
                        opacity: isCurrent ? 1 : 0
                        x: isCurrent ? 0 : (index < root.currentTab ? -28 : 28)
                        scale: isCurrent ? 1 : 0.97
                        transformOrigin: Item.Center

                        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on x       { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                        Behavior on scale   { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

                        Loader {
                            anchors.fill: parent
                            active: pageWrap.isCurrent || pageWrap.opacity > 0.01
                            sourceComponent: [
                                pageOverview,
                                pageMedia,
                                pagePerformance,
                                pageWorkspaces,
                                pagePlanner
                            ][pageWrap.index]
                        }
                    }
                }
            }
        }
    }

    // ── Page components ─────────────────────────────────────

    Component {
        id: pageOverview
        Flickable {
            id: flick
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: col.implicitHeight

            ColumnLayout {
                id: col
                width: flick.width
                spacing: Theme.space.md

                // Row A — годинник · погода · профіль
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.components.dp(148)
                    spacing: Theme.space.md
                    readonly property real usable: width - spacing * 2

                    Reveal {
                        index: 0; shown: root.occupies
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: parent.usable * 0.32
                        ClockTile { anchors.fill: parent }
                    }
                    Reveal {
                        index: 1; shown: root.occupies
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: parent.usable * 0.20
                        WeatherCard { anchors.fill: parent }
                    }
                    Reveal {
                        index: 2; shown: root.occupies
                        Layout.fillWidth: true; Layout.fillHeight: true
                        Layout.preferredWidth: parent.usable * 0.48
                        SystemCard { anchors.fill: parent }
                    }
                }

                // Row B — календар + плеєр | сповіщення + таймер
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.space.md
                    readonly property real usable: width - spacing

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignTop
                        Layout.preferredWidth: parent.usable * 0.5
                        spacing: Theme.space.md

                        Reveal {
                            index: 3; shown: root.occupies
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.components.dp(316)
                            CalendarCard { anchors.fill: parent }
                        }
                        Reveal {
                            index: 4; shown: root.occupies
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.components.dp(100)
                            MiniMediaCard { anchors.fill: parent }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: parent.usable * 0.5
                        spacing: Theme.space.md

                        Reveal {
                            index: 5; shown: root.occupies
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            NotifCard { anchors.fill: parent }
                        }
                        Reveal {
                            index: 6; shown: root.occupies
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.components.dp(120)
                            TimerCard { anchors.fill: parent }
                        }
                    }
                }

                // Row C — яскравість (усі дисплеї)
                Reveal {
                    index: 7; shown: root.occupies
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(Theme.components.dp(136), brightnessCard.implicitHeight)
                    BrightnessCard { id: brightnessCard; anchors.fill: parent }
                }
            }
        }
    }

    Component { id: pageMedia;       MediaTab       { active: root.occupies } }
    Component { id: pagePerformance; PerformanceTab { } }
    Component { id: pageWorkspaces;  WorkspacesTab  { } }
    Component { id: pagePlanner;     PlannerTab     { } }

    // ── Reveal helper: staggered fade + scale-in ────────────
    component Reveal: Item {
        id: reveal
        property int index: 0
        property bool shown: false
        property int startDelay: 140
        property int stagger: 55
        property int enterDuration: 460
        property int exitDuration: 200

        default property alias content: holder.data

        readonly property int _delay: reveal.shown
            ? (reveal.startDelay + reveal.index * reveal.stagger)
            : 0

        opacity: shown ? 1 : 0
        scale:   shown ? 1 : 0.95
        transformOrigin: Item.Center

        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: reveal._delay }
                NumberAnimation {
                    duration: reveal.shown ? reveal.enterDuration : reveal.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }
        Behavior on scale {
            SequentialAnimation {
                PauseAnimation { duration: reveal._delay }
                NumberAnimation {
                    duration: reveal.shown ? reveal.enterDuration : reveal.exitDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Item {
            id: holder
            anchors.fill: parent
        }
    }
}
