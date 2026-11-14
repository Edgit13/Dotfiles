import "root:/states"
import QtQuick
import QtQuick.Effects
import Quickshell
import "root:/theme"
import "root:/settings"
import "root:/services"
import "material"

// LockM3 — M3 Expressive сцена локскріну: гігантський двоколірний годинник, Face ID-блок,
// капсула пароля з фігурками, круглі кнопки живлення. Стан і дії — з LockScreen.qml (ctl).
Item {
    id: scene

    required property var ctl
    property bool preview: false                 // true → живий прев'ю в Settings (без фокусу/анімації входу)
    property bool editable: false                // true → віджети можна тягнути (редактор у Settings)
    readonly property string selectedId: scene.ctl.selected !== undefined ? scene.ctl.selected : ""

    // ── віджети: позиція / форма / колір / розмір ────────
    readonly property string widgetsKey: "widgets"     // у Nothing — окрема мапа, щоб розкладки не змішувались
    readonly property var wmap: { const m = cfg(widgetsKey); return (m && typeof m === "object") ? m : ({}) }
    readonly property var shapeList: ["default","circle","square","pill","oval","cookie","sunny","burst","star","clover","flower","pentagon","hexagon","blob","pill_diag"]

    function basePos(id) {
        const c = { clock: [0.5, 0.27], date: [0.5, 0.42], weather: [0.40, 0.50], media: [0.60, 0.50],
                    notif: [0.80, 0.46],
                    user: [0.5, 0.66], password: [0.5, 0.83], power: [0.93, 0.94] }[id] || [0.5, 0.5]
        let x = c[0], y = c[1]
        if (id === "power") return { x: x, y: y }
        if (layoutMode === "top")
            y = { clock: 0.15, date: 0.30, weather: 0.38, media: 0.38, notif: 0.38, user: 0.54, password: 0.72 }[id]
        else if (layoutMode === "bottom")
            y = { clock: 0.36, date: 0.50, weather: 0.58, media: 0.58, notif: 0.58, user: 0.72, password: 0.88 }[id]
        else if (layoutMode === "left" && id !== "notif")
            x = 0.22 + (x - 0.5) * 0.9
        return { x: x, y: y }
    }
    function defColor(id) {
        return { clock: "primary", date: "tertiary", weather: "tertiary", media: "secondary", notif: "surface", user: "primary" }[id] || "surface"
    }
    function wc(id) {
        const o = wmap[id] || {}
        const b = basePos(id)
        return {
            x: o.x !== undefined ? o.x : b.x,
            y: o.y !== undefined ? o.y : b.y,
            shape: (o.shape !== undefined && shapeList.indexOf(o.shape) >= 0) ? o.shape : "default",
            scale: o.scale !== undefined ? o.scale : 1,
            color: o.color !== undefined ? o.color : defColor(id)
        }
    }
    function tintBg(n) {
        return n === "secondary" ? M3.secondaryContainer : n === "tertiary" ? M3.tertiaryContainer
             : n === "surface" ? M3.surfaceContainerHigh : M3.primaryContainer
    }
    function tintFg(n) {
        return n === "secondary" ? Theme.color.fgSecondaryContainer : n === "tertiary" ? Theme.color.fgTertiaryContainer
             : n === "surface" ? Theme.color.fgSurface : Theme.color.fgPrimaryContainer
    }
    function select(id) { if (scene.ctl.select) scene.ctl.select(id) }
    function saveWidget(id, props) { if (scene.ctl.saveWidget) scene.ctl.saveWidget(id, props) }

    // ── кастомізація (Settings → Локскрін) ───────────────
    function cfg(key) { return Settings.get("lockscreen", key) }
    readonly property string layoutMode: cfg("layout")
    readonly property string clockStyle: cfg("clockStyle")
    readonly property int clockWeight: cfg("clockWeight")
    readonly property real clockPx: cfg("clockSize") * k
    readonly property bool clock24h: cfg("clock24h") !== false
    readonly property bool showSeconds: cfg("showSeconds") === true
    readonly property bool showDate: cfg("showDate") !== false
    readonly property bool showGreeting: cfg("greeting") !== false
    readonly property bool showUser: cfg("showUser") !== false
    readonly property bool weatherWidget: cfg("weatherWidget") === true
    readonly property bool mediaWidget: cfg("mediaWidget") === true
    readonly property string passStyle: cfg("passwordStyle")
    readonly property bool powerButtons: cfg("powerButtons") !== false
    readonly property bool floatingShapes: cfg("floatingShapes") !== false
    readonly property bool kenBurns: cfg("kenBurns") !== false && !preview
    readonly property bool parallax: cfg("parallax") !== false && !preview
    readonly property string fillMode: cfg("fillMode")

    readonly property real k: Math.max(0.75, height / 1080)
    readonly property bool faceShown: scene.ctl.faceEnabled === true && scene.ctl.faceEnrolled === true
    readonly property string user: Quickshell.env("USER") || "user"

    property real intro: 0
    property real parX: 0
    property real parY: 0
    property var now: new Date()

    function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }
    function stage(from, span) { return clamp01((intro - from) / span) }
    function focusInput() { if (!preview) passField.forceActiveFocus() }

    Keys.onPressed: ev => { if (!scene.preview && scene.ctl.devKeys) scene.ctl.devKeys.handle(ev) }

    LockDevBadge { ctl: scene.ctl; anchors.left: parent.left; anchors.top: parent.top; anchors.margins: 24 * scene.k }

    Component.onCompleted: {
        if (preview) { intro = 1; return }
        focusInput(); introAnim.start()
    }
    NumberAnimation { id: introAnim; target: scene; property: "intro"; from: 0; to: 1; duration: 1400; easing.type: Easing.OutCubic }
    Timer { interval: 1000; running: true; repeat: true; onTriggered: scene.now = new Date() }

    Connections {
        target: scene.ctl
        function onShakeTickChanged() { pillShake.restart(); errFlash.restart() }
    }

    // ================================================== фон
    Rectangle { anchors.fill: parent; color: M3.surface }

    Item {
        id: wpLayer
        readonly property int overscan: 60
        width: scene.width + overscan * 2
        height: scene.height + overscan * 2
        x: -overscan - (scene.parallax ? scene.parX : 0) * 16
        y: -overscan - (scene.parallax ? scene.parY : 0) * 16
        transformOrigin: Item.Center
        opacity: wpFx.visible ? scene.stage(0.0, 0.6) : 0

        property real kb: 1.0
        scale: kb
        SequentialAnimation on kb {
            running: scene.kenBurns
            alwaysRunToEnd: true
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.05; duration: 22000; easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.05; to: 1.0; duration: 22000; easing.type: Easing.InOutSine }
        }

        Image {
            id: wp
            anchors.fill: parent
            source: scene.ctl.wallpaperUrl
            fillMode: scene.fillMode === "fit" ? Image.PreserveAspectFit
                    : scene.fillMode === "stretch" ? Image.Stretch : Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect {
            id: wpFx
            anchors.fill: parent
            source: wp
            blurEnabled: !ReliefState.effects && scene.cfg("blurStrength") > 0
            blur: scene.cfg("blurStrength")
            blurMax: scene.cfg("blurRadius")
            visible: wp.status === Image.Ready
        }
    }

    // вуаль + градієнти для читабельності
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, wp.status === Image.Ready ? scene.cfg("scrimOpacity") : 0.92)
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(M3.primary.r, M3.primary.g, M3.primary.b, 0.12) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, 0.70) }
        }
    }

    // плаваючі фігури
    Repeater {
        model: scene.floatingShapes ? scene.ctl.floaters : []
        delegate: Item {
            required property var modelData
            anchors.fill: parent
            readonly property real baseX: scene.width * modelData.x - modelData.size / 2
            readonly property real baseY: scene.height * modelData.y - modelData.size / 2
            ExpressiveDot {
                x: parent.baseX; y: parent.baseY
                dotSize: modelData.size * scene.k
                shape: modelData.shape
                dotColor: M3.primary
                opacity: 0.06
                SequentialAnimation on x {
                    loops: Animation.Infinite
                    NumberAnimation { from: parent.baseX - scene.width * modelData.ax; to: parent.baseX + scene.width * modelData.ax; duration: modelData.dur; easing.type: Easing.InOutSine }
                    NumberAnimation { from: parent.baseX + scene.width * modelData.ax; to: parent.baseX - scene.width * modelData.ax; duration: modelData.dur; easing.type: Easing.InOutSine }
                }
                SequentialAnimation on rotation {
                    loops: Animation.Infinite
                    NumberAnimation { from: 0; to: 360; duration: modelData.dur * 4 }
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        enabled: !scene.preview
        hoverEnabled: true
        onClicked: scene.focusInput()
        onPositionChanged: { scene.parX = (mouseX / width - 0.5) * 2; scene.parY = (mouseY / height - 0.5) * 2 }
        onExited: { scene.parX = 0; scene.parY = 0 }
    }

    // ================================================== віджети
    // ── годинник ──
    LockWidget {
        id: wClock
        host: scene
        wid: "clock"
        opacity: scene.stage(0.0, 0.5)

        Column {
            spacing: 0
            // горизонтальний
            Row {
                visible: scene.clockStyle !== "stacked"
                spacing: 0
                Text {
                    text: Qt.formatDateTime(scene.now, scene.clock24h ? "HH" : "hh")
                    color: wClock.shaped ? wClock.fg : M3.m3OnSurface
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx); weight: scene.clockWeight }
                }
                Text {
                    text: ":"
                    color: wClock.shaped ? wClock.fg : (scene.clockStyle === "solid" ? M3.m3OnSurface : M3.tertiary)
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx * 0.9); weight: scene.clockWeight }
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -scene.clockPx * 0.06
                    SequentialAnimation on opacity {
                        running: !scene.preview
                        alwaysRunToEnd: true
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.25; duration: 1000; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0;  duration: 1000; easing.type: Easing.InOutQuad }
                    }
                }
                Text {
                    text: Qt.formatDateTime(scene.now, "mm")
                    color: wClock.shaped ? wClock.fg : (scene.clockStyle === "solid" ? M3.m3OnSurface : M3.primary)
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx); weight: scene.clockWeight }
                }
                Text {
                    visible: scene.showSeconds
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: scene.clockPx * 0.18
                    text: Qt.formatDateTime(scene.now, "ss")
                    color: wClock.shaped ? wClock.fg : M3.tertiary
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx * 0.28); weight: Font.Medium }
                    leftPadding: 8 * scene.k
                }
            }
            // стовпчиком
            Column {
                visible: scene.clockStyle === "stacked"
                spacing: -scene.clockPx * 0.16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(scene.now, scene.clock24h ? "HH" : "hh")
                    color: wClock.shaped ? wClock.fg : M3.m3OnSurface
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx); weight: scene.clockWeight }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(scene.now, "mm")
                    color: wClock.shaped ? wClock.fg : M3.primary
                    font { family: M3.clockFamily; pixelSize: Math.round(scene.clockPx); weight: scene.clockWeight }
                }
            }
        }
    }

    // ── привітання / дата ──
    LockWidget {
        id: wDate
        host: scene
        wid: "date"
        shown: scene.showDate || scene.showGreeting
        opacity: scene.stage(0.1, 0.5)

        Row {
            spacing: M3.s8
            Text {
                visible: scene.showGreeting
                anchors.verticalCenter: parent.verticalCenter
                text: scene.ctl.greetingIcon
                color: wDate.shaped ? wDate.fg : M3.tertiary
                font { family: "Material Symbols Rounded"; pixelSize: 19 * scene.k }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: (scene.showGreeting ? scene.ctl.greeting : "")
                    + (scene.showGreeting && scene.showDate ? "  ·  " : "")
                    + (scene.showDate ? Qt.formatDateTime(scene.now, "dddd, d MMMM") : "")
                color: wDate.shaped ? wDate.fg : M3.m3OnSurfaceVariant
                font { family: M3.fontFamily; pixelSize: Math.round(17 * scene.k); weight: Font.Medium; letterSpacing: 1 }
            }
        }
    }

    // ── погода ──
    LockWidget {
        id: wWeather
        host: scene
        wid: "weather"
        shown: scene.weatherWidget
        opacity: scene.stage(0.2, 0.5)

        Item {
            width: wRow.implicitWidth + M3.s24 * scene.k
            height: 34 * scene.k
            Rectangle {
                visible: !wWeather.shaped
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(M3.tertiaryContainer.r, M3.tertiaryContainer.g, M3.tertiaryContainer.b, 0.85)
            }
            Row {
                id: wRow
                anchors.centerIn: parent
                spacing: M3.s8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.iconGlyph
                    color: wWeather.fg
                    font { family: Theme.type.icons; pixelSize: 18 * scene.k }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: isNaN(WeatherService.temperatureC) ? "—" : Math.round(WeatherService.temperatureC) + "°C"
                    color: wWeather.fg
                    font: M3.labelLarge
                }
            }
        }
    }

    // ── «зараз грає» ──
    LockWidget {
        id: wMedia
        host: scene
        wid: "media"
        shown: scene.mediaWidget && (MediaService.has || scene.editable)
        opacity: scene.stage(0.2, 0.5)

        Item {
            width: mRow.implicitWidth + M3.s24 * scene.k
            height: 34 * scene.k
            Rectangle {
                visible: !wMedia.shaped
                anchors.fill: parent
                radius: height / 2
                color: Qt.rgba(M3.secondaryContainer.r, M3.secondaryContainer.g, M3.secondaryContainer.b, 0.85)
            }
            Row {
                id: mRow
                anchors.centerIn: parent
                spacing: M3.s8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaService.playing ? "graphic_eq" : "music_note"
                    color: wMedia.fg
                    font { family: "Material Symbols Rounded"; pixelSize: 18 * scene.k }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, (wMedia.shaped ? 150 : 260) * scene.k)
                    elide: Text.ElideRight
                    text: MediaService.has ? MediaService.title + (MediaService.artist ? " — " + MediaService.artist : "") : "—"
                    color: wMedia.fg
                    font: M3.labelLarge
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !scene.preview
                cursorShape: Qt.PointingHandCursor
                onClicked: MediaService.togglePlay()
            }
        }
    }

    // ── сповіщення на локскріні ──
    LockWidget {
        id: wNotif
        host: scene
        wid: "notif"
        shown: scene.editable || (String(scene.cfg("notifMode") || "count") !== "off"
                                  && NotificationService.count > 0)
        opacity: scene.stage(0.3, 0.4)

        LockNotifWidget {
            host: scene
            shaped: wNotif.shaped
            shapeFg: wNotif.fg
        }
    }

    // ── профіль: Face ID / аватар + ім'я ──
    LockWidget {
        id: wUser
        host: scene
        wid: "user"
        opacity: scene.stage(0.25, 0.4)

        Column {
            spacing: M3.s8

            Item {
                id: slot
                anchors.horizontalCenter: parent.horizontalCenter
                width: 92 * scene.k; height: width

                FaceIdMark {
                    anchors.centerIn: parent
                    visible: scene.faceShown
                    size: parent.width
                    mode: scene.ctl.faceState
                    onClicked: scene.ctl.retryFace()
                }
                Item {
                    anchors.fill: parent
                    visible: !scene.faceShown
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Qt.rgba(M3.primary.r, M3.primary.g, M3.primary.b, 0.35)
                        SequentialAnimation on rotation {
                            running: !scene.preview
                            alwaysRunToEnd: true
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 360; duration: 24000 }
                        }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width * 0.84; height: width
                        radius: width / 2
                        color: M3.primary
                        Text {
                            anchors.centerIn: parent
                            text: scene.user.substring(0, 1).toUpperCase()
                            color: M3.m3OnPrimary
                            font { family: M3.fontFamily; pixelSize: Math.round(parent.width * 0.46); weight: Font.DemiBold }
                        }
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: scene.showUser
                text: scene.user
                color: wUser.fg
                font { family: M3.fontFamily; pixelSize: Math.round(20 * scene.k); weight: Font.Medium }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: scene.faceShown
                text: scene.ctl.faceLabel
                color: scene.ctl.faceState === "fail" ? M3.error : scene.ctl.faceState === "ok" ? M3.primary : (wUser.shaped ? wUser.fg : M3.m3OnSurfaceVariant)
                font: M3.labelLarge
            }
        }
    }

    // ── пароль + статус ──
    LockWidget {
        id: wPass
        host: scene
        wid: "password"
        shapeable: false
        opacity: scene.stage(0.5, 0.4)

        Column {
            spacing: M3.s8

            Rectangle {
                id: pill
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.min(320 * scene.k + 20, scene.width - 48)
                height: 52 * scene.k
                radius: height / 2
                clip: true
                color: passField.activeFocus
                     ? Qt.rgba(M3.surfaceContainerHighest.r, M3.surfaceContainerHighest.g, M3.surfaceContainerHighest.b, 0.92)
                     : Qt.rgba(M3.surfaceContainer.r, M3.surfaceContainer.g, M3.surfaceContainer.b, 0.80)
                border.width: passField.activeFocus ? 2 : 1
                border.color: passField.activeFocus ? M3.primary : (scene.ctl.statusError ? M3.error : M3.outlineVariant)
                Behavior on border.color { ColorAnimation { duration: M3.durFast } }
                Behavior on color { ColorAnimation { duration: M3.durFast } }

                SequentialAnimation {
                    id: pillShake
                    NumberAnimation { target: pill; property: "anchors.horizontalCenterOffset"; to: -10; duration: 45 }
                    NumberAnimation { target: pill; property: "anchors.horizontalCenterOffset"; to: 10; duration: 60 }
                    NumberAnimation { target: pill; property: "anchors.horizontalCenterOffset"; to: -6; duration: 50 }
                    NumberAnimation { target: pill; property: "anchors.horizontalCenterOffset"; to: 6; duration: 50 }
                    NumberAnimation { target: pill; property: "anchors.horizontalCenterOffset"; to: 0; duration: 60 }
                }
                Rectangle {
                    id: errHalo
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 3
                    border.color: M3.error
                    opacity: 0
                    SequentialAnimation {
                        id: errFlash
                        NumberAnimation { target: errHalo; property: "opacity"; to: 0.9; duration: 90 }
                        NumberAnimation { target: errHalo; property: "opacity"; to: 0.0; duration: 420 }
                    }
                }

                TextInput {
                    id: passField
                    anchors.fill: parent
                    anchors.leftMargin: M3.s24
                    anchors.rightMargin: 56
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: (scene.passStyle === "text" && !scene.ctl.showPassword) ? TextInput.Password : TextInput.Normal
                    color: (scene.ctl.showPassword || scene.passStyle === "text") ? M3.m3OnSurface : "transparent"
                    selectedTextColor: "transparent"
                    selectionColor: "transparent"
                    cursorVisible: scene.ctl.showPassword
                    selectByMouse: scene.ctl.showPassword
                    font { family: M3.fontFamily; pixelSize: 18; weight: Font.Medium; letterSpacing: (scene.ctl.showPassword || scene.passStyle === "text") ? 0 : 4 }
                    focus: true
                    text: scene.ctl.passText
                    onTextChanged: if (text !== scene.ctl.passText) scene.ctl.passText = text
                    onAccepted: scene.ctl.tryUnlock()
                    Keys.onPressed: ev => {
                        if (!scene.preview && scene.ctl.devKeys && scene.ctl.devKeys.handle(ev)) ev.accepted = true
                    }
                    Keys.onEscapePressed: { scene.ctl.passText = ""; text = "" }
                }

                Row {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -14
                    spacing: 10
                    visible: !scene.ctl.showPassword && scene.passStyle !== "text"
                    Repeater {
                        model: scene.passStyle === "dots" ? passField.text.length : 0
                        delegate: Rectangle {
                            required property int index
                            width: index === passField.text.length - 1 ? 14 : 12; height: width; radius: width / 2
                            color: index === passField.text.length - 1 ? M3.primary : M3.m3OnSurfaceVariant
                            scale: 0
                            NumberAnimation on scale { from: 0; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                        }
                    }
                    Repeater {
                        model: scene.passStyle === "shapes" ? passField.text.length : 0
                        delegate: ExpressiveDot {
                            required property int index
                            readonly property bool newest: index === passField.text.length - 1
                            readonly property int seed: {
                                var h = (index + 1) * 2654435761
                                h = (h ^ (h >>> 13)) >>> 0
                                h = (h * 2246822519) >>> 0
                                h = (h ^ (h >>> 11)) >>> 0
                                return h
                            }
                            shape: scene.ctl.dotCatalog[seed % scene.ctl.dotCatalog.length]
                            dotSize: newest ? 17 : 14
                            roundness: 0.75
                            spin: -Math.PI / 2
                            dotColor: newest ? M3.primary : M3.m3OnSurfaceVariant
                            Behavior on dotColor { ColorAnimation { duration: M3.durFast } }
                            Behavior on dotSize { NumberAnimation { duration: M3.durMed; easing.type: Easing.OutCubic } }
                            morph: 0.0
                            NumberAnimation on morph { from: 0.0; to: 1.0; duration: 340; easing.type: Easing.OutCubic }
                            scale: 0.0
                            NumberAnimation on scale { from: 0.0; to: 1.0; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: -14
                    visible: scene.ctl.passText.length === 0
                    text: Lang.t("lock.enter")
                    color: M3.m3OnSurfaceVariant
                    font { family: M3.fontFamily; pixelSize: 15; weight: Font.Medium }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44; height: 44; radius: 22
                    color: eyeMa.containsMouse ? M3.hoverOf(M3.tertiary)
                         : (scene.ctl.showPassword ? M3.tertiaryContainer : "transparent")
                    Behavior on color { ColorAnimation { duration: M3.durFast } }
                    Text {
                        anchors.centerIn: parent
                        text: scene.ctl.showPassword ? "visibility_off" : "visibility"
                        color: M3.m3OnSurfaceVariant
                        font { family: "Material Symbols Rounded"; pixelSize: 20 }
                    }
                    MouseArea {
                        id: eyeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { scene.ctl.showPassword = !scene.ctl.showPassword; passField.forceActiveFocus() }
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: M3.s8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: scene.ctl.statusWorking ? "progress_activity" : scene.ctl.statusError ? "error" : "lock"
                    color: scene.ctl.statusWorking ? M3.primary : scene.ctl.statusError ? M3.error : M3.m3OnSurfaceVariant
                    font { family: "Material Symbols Rounded"; pixelSize: 16 }
                    SequentialAnimation on rotation {
                        running: scene.ctl.statusWorking
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: 360; duration: 1400 }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: scene.ctl.statusWorking ? Lang.t("lock.auth")
                        : scene.ctl.statusError ? Lang.t("lock.wrong").replace("{n}", scene.ctl.errorCount)
                        : Lang.t("lock.locked")
                    color: scene.ctl.statusWorking ? M3.primary : scene.ctl.statusError ? M3.error : M3.m3OnSurfaceVariant
                    font: M3.labelMedium
                }
            }
        }
    }

    // ── живлення ──
    LockWidget {
        id: wPower
        host: scene
        wid: "power"
        shapeable: false
        shown: scene.powerButtons
        opacity: scene.stage(0.7, 0.3)

        Row {
            spacing: M3.s8
            Repeater {
                model: [
                    { glyph: "bedtime",            cmd: ["systemctl", "suspend"],  tint: "secondary" },
                    { glyph: "restart_alt",        cmd: ["systemctl", "reboot"],   tint: "tertiary"  },
                    { glyph: "power_settings_new", cmd: ["systemctl", "poweroff"], tint: "error"     }
                ]
                delegate: Rectangle {
                    id: pb
                    required property var modelData
                    readonly property color base: modelData.tint === "error" ? M3.errorContainer
                                                : modelData.tint === "tertiary" ? M3.tertiaryContainer : M3.secondaryContainer
                    width: 44 * scene.k; height: width
                    radius: pMa.pressed ? 14 : width / 2
                    color: pMa.pressed ? M3.pressedOf(base) : pMa.containsMouse ? M3.hoverOf(base) : base
                    Behavior on radius { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: M3.durFast } }
                    Text {
                        anchors.centerIn: parent
                        text: pb.modelData.glyph
                        color: pb.modelData.tint === "error" ? M3.error : M3.m3OnSecondaryContainer
                        font { family: "Material Symbols Rounded"; pixelSize: 20 }
                    }
                    MouseArea {
                        id: pMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !scene.preview
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scene.ctl.powerExec = pb.modelData.cmd
                    }
                }
            }
        }
    }
}
