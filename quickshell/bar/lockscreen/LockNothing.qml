import "root:/states"
import QtQuick
import QtQuick.Effects
import Quickshell
import "root:/theme"
import "root:/settings"
import "root:/services"
import "material"

// LockNothing — сцена локскріну в дизайні "Nothing".
//   • розмите, трохи знебарвлене шпалерне тло (Ken Burns + паралакс) під темною вуаллю
//   • великий dot-matrix годинник (Doto): цифри плавно «перегортаються», під ними — 60 точок-секунд
//   • дата / привітання, погода та «зараз грає» — окремі віджети
//   • пароль — капсула з точками: літера запалює точку з «пульсом»; перевірка — хвиля; помилка — червоний спалах + стрясання
//   • Face ID — обличчя з крапок, червоний сканер, галочка при успіху
//   • віджети можна тягнути в редакторі (Settings → Локскрін), позиції зберігаються в lockscreen.widgets
// Стан і дії беруться з LockScreen.qml (ctl): passText, tryUnlock(), statusWorking/Error, powerExec …
Item {
    id: scene

    required property var ctl
    property bool preview: false                  // живий прев'ю в Settings (без фокусу й анімації входу)
    property bool editable: false                 // редактор: віджети тягаються мишею
    readonly property string selectedId: (ctl && ctl.selected !== undefined) ? ctl.selected : ""

    // ---------------------------------------------------------------- палітра
    readonly property color ink:  M3.m3OnSurface
    readonly property color dim:  M3.m3OnSurfaceVariant
    readonly property color line: M3.outline
    readonly property color red:  ThemeNothing.red

    readonly property int slots: Math.max(16, scene.ctl.passText.length)
    readonly property real k: Math.max(0.75, height / 1080)
    readonly property string mono: Theme.type.mono
    readonly property string dot:  Theme.type.dot
    readonly property real clockScale: (Settings.get("lockscreen", "clockSize") || 160) / 160

    // ---------------------------------------------------------------- налаштування
    function cfg(key) { return Settings.get("lockscreen", key) }
    readonly property string layoutMode: cfg("layout") || "center"
    readonly property bool clock24h: cfg("clock24h") !== false
    readonly property bool showSeconds: cfg("showSeconds") === true
    readonly property bool showDate: cfg("showDate") !== false
    readonly property bool showGreeting: cfg("greeting") !== false
    readonly property bool showUser: cfg("showUser") !== false
    readonly property bool weatherWidget: cfg("weatherWidget") === true
    readonly property bool mediaWidget: cfg("mediaWidget") === true
    // для розкладки: якщо лишився один чип — тримаємо його по центру
    readonly property bool weatherShown: scene.weatherWidget
    readonly property bool mediaShown: scene.mediaWidget && (MediaService.has || scene.preview || scene.editable)
    readonly property string passStyle: cfg("passwordStyle") || "shapes"
    readonly property bool powerButtons: cfg("powerButtons") !== false
    readonly property bool kenBurns: cfg("kenBurns") !== false && !preview && !editable
    readonly property bool parallax: cfg("parallax") !== false && !preview && !editable
    readonly property string fillMode: cfg("fillMode") || "fill"
    readonly property real blurStrength: cfg("blurStrength") !== undefined ? cfg("blurStrength") : 0.4
    readonly property real blurRadius: cfg("blurRadius") !== undefined ? cfg("blurRadius") : 40
    readonly property real scrimOpacity: cfg("scrimOpacity") !== undefined ? cfg("scrimOpacity") : 0.5

    // ---------------------------------------------------------------- віджети (редактор)
    readonly property string widgetsKey: "widgetsNothing"   // власна розкладка, не змішується з M3
    readonly property var wmap: { const m = cfg(widgetsKey); return (m && typeof m === "object") ? m : ({}) }
    readonly property var shapeList: ["default", "circle", "square", "pill", "oval"]

    function basePos(id) {
        const c = {
            clock:    [0.50, 0.305],
            date:     [0.50, 0.445],
            weather:  [scene.mediaShown ? 0.405 : 0.500, 0.535],
            media:    [scene.weatherShown ? 0.595 : 0.500, 0.535],
            notif:    [0.800, 0.460],
            user:     [0.50, 0.655],
            password: [0.50, 0.845],
            power:    [0.947, 0.947]
        }[id] || [0.5, 0.5]
        let x = c[0], y = c[1]
        if (id === "power") return { x: x, y: y }
        const shift = {
            top:    { clock: 0.175, date: 0.315, weather: 0.405, media: 0.405, notif: 0.405, user: 0.525, password: 0.735 },
            bottom: { clock: 0.425, date: 0.565, weather: 0.645, media: 0.645, notif: 0.645, user: 0.745, password: 0.905 }
        }[layoutMode]
        if (shift && shift[id] !== undefined) y = shift[id]
        else if (layoutMode === "left" && id !== "notif") x = 0.30 + (x - 0.5) * 0.75
        return { x: x, y: y }
    }
    function defColor(id) {
        return { clock: "primary", date: "tertiary", weather: "secondary", media: "secondary", notif: "secondary", user: "primary" }[id] || "surface"
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
    // Nothing: форми або білі (чорний текст), або графітові, або червоні
    function tintBg(n) {
        switch (n) {
        case "primary":   return "#FFFFFF"
        case "secondary": return "#242424"
        case "tertiary":  return ThemeNothing.red
        default:          return "#101010"
        }
    }
    function tintFg(n) {
        switch (n) {
        case "primary":   return "#000000"
        case "secondary": return "#EDEDED"
        case "tertiary":  return "#FFFFFF"
        default:          return "#FFFFFF"
        }
    }
    function select(id) { if (ctl && ctl.select) ctl.select(id) }
    function saveWidget(id, props) { if (ctl && ctl.saveWidget) ctl.saveWidget(id, props) }

    // ---------------------------------------------------------------- стан сцени
    property bool errFlash: false
    property real sweep: -2          // хвиля перевірки
    property real succ: -1           // хвиля успіху
    property real intro: 0           // 0 → 1: хореографія появи
    property real parX: 0
    property real parY: 0
    property var now: new Date()

    // Face ID (керується з LockScreen.qml)
    readonly property bool faceShown: scene.ctl.faceEnabled === true
                                      && scene.ctl.faceEnrolled === true
    readonly property color faceTint: scene.ctl.faceState === "fail" ? scene.red
                                     : scene.ctl.faceState === "ok"   ? scene.ink
                                     : scene.dim
    readonly property string faceLabel: {
        switch (scene.ctl.faceState) {
        case "scanning":    return Lang.t("lock.face.scan")
        case "ok":          return Lang.t("lock.face.ok")
        case "fail":        return Lang.t("lock.face.fail")
        case "busy":        return Lang.t("lock.face.busy")
        case "unavailable": return Lang.t("lock.face.unavailable")
        }
        return Lang.t("lock.face.idle")
    }

    function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }
    // прибираємо емодзі з назв треків — у Nothing все має бути монохромним
    function cleanMeta(t) {
        const s = String(t || "")
        let o = ""
        for (let i = 0; i < s.length; i++) {
            const cp = s.codePointAt(i)
            if (cp > 0xFFFF) i++
            if ((cp >= 0x2190 && cp <= 0x2BFF) || cp >= 0x1F000) continue
            o += String.fromCodePoint(cp)
        }
        return o.replace(/\s+/g, " ").trim()
    }
    function stage(from, span) { return clamp01((intro - from) / span) }
    function focusInput() { if (!scene.preview && !scene.editable) passField.forceActiveFocus() }
    function st(from, span) { return scene.preview ? 1 : scene.stage(from, span) }

    Keys.onPressed: ev => {
        if (!scene.preview && scene.ctl.devKeys !== undefined && scene.ctl.devKeys.handle(ev))
            ev.accepted = true
    }

    LockDevBadge {
        ctl: scene.ctl
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24 * scene.k
        opacity: scene.editable ? 0 : 1
    }

    Component.onCompleted: {
        if (preview) { intro = 1; return }
        focusInput(); introAnim.start()
    }

    NumberAnimation { id: introAnim; target: scene; property: "intro"; from: 0; to: 1
                      duration: ThemeMotion.duration("enter")
                      easing.type: Easing.BezierSpline; easing.bezierCurve: ThemeMotion.curveFor("enter") }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: scene.now = new Date()
    }

    // ---------------------------------------------------------------- тло
    Rectangle { anchors.fill: parent; color: M3.surface }

    Item {
        id: wpLayer
        readonly property int overscan: 48
        width: scene.width + overscan * 2
        height: scene.height + overscan * 2
        x: -overscan - (scene.parallax ? scene.parX : 0) * 14
        y: -overscan - (scene.parallax ? scene.parY : 0) * 14
        transformOrigin: Item.Center
        opacity: wpFx.visible ? scene.st(0.0, 0.6) : 0

        property real kb: 1.0
        SequentialAnimation on kb {
            running: scene.kenBurns && ThemeMotion.enabled && !ThemeMotion.reduced
            alwaysRunToEnd: true
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 1.06; duration: Math.round(26000 / ThemeMotion.speed); easing.type: Easing.InOutSine }
            NumberAnimation { from: 1.06; to: 1.0; duration: Math.round(26000 / ThemeMotion.speed); easing.type: Easing.InOutSine }
        }
        scale: kb

        Image {
            id: wpImg
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
            source: wpImg
            visible: wpImg.status === Image.Ready
            blurEnabled: !ReliefState.effects && scene.blurStrength > 0
            blur: scene.blurStrength
            blurMax: scene.blurRadius
            saturation: -0.55            // у дусі Nothing — майже монохромне
            brightness: -0.04
        }
    }

    // вуаль + м'яке затемнення зверху/знизу для читабельності
    Rectangle {
        anchors.fill: parent
        color: M3.surface
        opacity: wpFx.visible ? scene.scrimOpacity : 1.0
        Behavior on opacity { MotionAnimation { role: "fade" } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, 0.55) }
            GradientStop { position: 0.45; color: "transparent" }
            GradientStop { position: 1.0;  color: Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, 0.70) }
        }
    }

    Canvas {
        anchors.fill: parent
        opacity: 0.06 * scene.st(0.1, 0.5)
        readonly property color c: scene.ink
        onCChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = c
            const pitch = 28
            for (let y = pitch / 2; y < height; y += pitch)
                for (let x = pitch / 2; x < width; x += pitch)
                    ctx.fillRect(x, y, 2, 2)
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !scene.editable
        hoverEnabled: true
        onClicked: scene.focusInput()
        onPositionChanged: mouse => {
            if (!scene.parallax) return
            scene.parX = (mouse.x / width  - 0.5) * 2
            scene.parY = (mouse.y / height - 0.5) * 2
        }
        onExited: { scene.parX = 0; scene.parY = 0 }
    }
    Behavior on parX { MotionAnimation { role: "move" } }
    Behavior on parY { MotionAnimation { role: "move" } }

    // ---------------------------------------------------------------- шапка
    Row {
        anchors { left: parent.left; top: parent.top; leftMargin: 40 * scene.k; topMargin: 36 * scene.k }
        spacing: 10
        opacity: scene.st(0.15, 0.4)
        Rectangle {
            width: 7; height: 7; radius: 3.5
            anchors.verticalCenter: parent.verticalCenter
            color: scene.ctl.statusError || scene.errFlash ? scene.red : scene.ink
            Behavior on color { MotionColorAnimation { role: "stateChange" } }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Lang.t("lock.locked").toUpperCase()
            color: scene.dim
            font { family: scene.mono; pixelSize: 12; letterSpacing: 3 }
        }
    }

    Text {
        anchors { right: parent.right; top: parent.top; rightMargin: 40 * scene.k; topMargin: 36 * scene.k }
        visible: scene.showUser
        opacity: scene.st(0.15, 0.4)
        text: (Quickshell.env("USER") || "").toUpperCase()
        color: scene.dim
        font { family: scene.mono; pixelSize: 12; letterSpacing: 3 }
    }

    // ---------------------------------------------------------------- годинник
    LockWidget {
        id: wClock
        host: scene
        wid: "clock"
        opacity: scene.st(0.05, 0.5)

        Column {
            spacing: Math.round(16 * scene.k)

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 0
                readonly property int px: Math.round(scene.height * 0.20 * scene.clockScale)
                readonly property string hh: Qt.formatDateTime(scene.now, scene.clock24h ? "HH" : "hh")
                readonly property string mm: Qt.formatDateTime(scene.now, "mm")

                RollDigit { value: parent.hh.charAt(0); px: parent.px; tint: wClock.shaped ? wClock.fg : scene.ink; fam: scene.dot }
                RollDigit { value: parent.hh.charAt(1); px: parent.px; tint: wClock.shaped ? wClock.fg : scene.ink; fam: scene.dot }
                Text {
                    text: ":"
                    color: wClock.shaped ? wClock.fg : scene.dim
                    font { family: scene.dot; pixelSize: parent.px }
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -parent.px * 0.02
                }
                RollDigit { value: parent.mm.charAt(0); px: parent.px; tint: wClock.shaped ? wClock.fg : scene.ink; fam: scene.dot }
                RollDigit { value: parent.mm.charAt(1); px: parent.px; tint: wClock.shaped ? wClock.fg : scene.ink; fam: scene.dot }
                Text {
                    visible: scene.showSeconds
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: parent.px * 0.30
                    text: Qt.formatDateTime(scene.now, "ss")
                    color: wClock.shaped ? wClock.fg : scene.red
                    leftPadding: Math.round(10 * scene.k)
                    font { family: scene.dot; pixelSize: Math.round(parent.px * 0.24) }
                }
            }

            // 60 точок-секунд: пройдені — напівяскраві, поточна — червона й трохи більша
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Math.round(6 * scene.k)
                Repeater {
                    model: 60
                    delegate: Rectangle {
                        id: tick
                        required property int index
                        readonly property int sec: scene.now.getSeconds()
                        readonly property bool cur: index === sec
                        width: Math.round(4 * scene.k); height: width; radius: width / 2
                        color: cur ? scene.red : (wClock.shaped ? wClock.fg : scene.ink)
                        opacity: cur ? 1.0 : (index < sec ? 0.5 : ThemeNothing.dotOpacityOff)
                        scale: cur ? 1.7 : 1.0
                        Behavior on opacity { MotionAnimation { role: "hover" } }
                        Behavior on scale   { MotionAnimation { role: "morph" } }
                        Behavior on color   { MotionColorAnimation { role: "stateChange" } }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- дата / привітання
    LockWidget {
        id: wDate
        host: scene
        wid: "date"
        shown: scene.showDate || scene.showGreeting
        opacity: scene.st(0.12, 0.45)

        Row {
            spacing: 10
            Rectangle {
                width: 5; height: 5; radius: 2.5
                anchors.verticalCenter: parent.verticalCenter
                color: scene.red
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const greet = scene.showGreeting && scene.ctl.greeting ? scene.ctl.greeting.toUpperCase() : ""
                    const date = scene.showDate ? Qt.formatDateTime(scene.now, "dddd · d MMMM").toUpperCase() : ""
                    return greet && date ? greet + "  ·  " + date : (greet || date)
                }
                color: wDate.shaped ? wDate.fg : scene.dim
                font { family: scene.mono; pixelSize: Math.round(15 * Math.max(1, scene.k)); letterSpacing: 3 }
            }
        }
    }

    // ---------------------------------------------------------------- погода
    LockWidget {
        id: wWeather
        host: scene
        wid: "weather"
        shown: scene.weatherWidget
        opacity: scene.st(0.2, 0.45)

        Item {
            width: chipRow.implicitWidth + 30
            height: 34 * Math.max(1, scene.k)

            // без форми — тонкий контур; з формою фон малює сам LockWidget
            Rectangle {
                anchors.fill: parent
                visible: !wWeather.shaped
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: scene.line
            }

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: WeatherService.iconGlyph
                    color: wWeather.fg
                    font { family: Theme.type.icons; pixelSize: Math.round(18 * Math.max(1, scene.k)) }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: isNaN(WeatherService.temperatureC) ? "—" : Math.round(WeatherService.temperatureC) + "°"
                    color: wWeather.fg
                    font { family: scene.mono; pixelSize: Math.round(14 * Math.max(1, scene.k)); letterSpacing: 1.5 }
                }
            }
        }
    }

    // ---------------------------------------------------------------- «зараз грає»
    LockWidget {
        id: wMedia
        host: scene
        wid: "media"
        shown: scene.mediaWidget && (MediaService.has || scene.editable)
        opacity: scene.st(0.2, 0.45)

        Item {
            width: mediaRow.implicitWidth + 30
            height: 34 * Math.max(1, scene.k)

            Rectangle {
                anchors.fill: parent
                visible: !wMedia.shaped
                radius: height / 2
                color: "transparent"
                border.width: 1
                border.color: scene.line
            }

            Row {
                id: mediaRow
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: MediaService.playing ? "graphic_eq" : "music_note"
                    color: wMedia.fg
                    font { family: Theme.type.icons; pixelSize: Math.round(18 * Math.max(1, scene.k)) }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, (wMedia.shaped ? 150 : 200) * scene.k)
                    elide: Text.ElideRight
                    text: MediaService.has ? scene.cleanMeta(MediaService.title) : "—"
                    color: wMedia.fg
                    font { family: scene.mono; pixelSize: Math.round(13 * Math.max(1, scene.k)); letterSpacing: 1.2 }
                }
            }
            MouseArea {
                anchors.fill: parent
                enabled: !scene.preview && !scene.editable
                cursorShape: Qt.PointingHandCursor
                onClicked: MediaService.togglePlay()
            }
        }
    }

    // ---------------------------------------------------------------- сповіщення
    LockWidget {
        id: wNotif
        host: scene
        wid: "notif"
        shown: scene.editable || (String(scene.cfg("notifMode") || "count") !== "off"
                                  && NotificationService.count > 0)
        opacity: scene.st(0.3, 0.4)

        LockNotifWidget {
            host: scene
            shaped: wNotif.shaped
            shapeFg: wNotif.fg
        }
    }

    // ---------------------------------------------------------------- Face ID
    LockWidget {
        id: wUser
        host: scene
        wid: "user"
        shown: scene.faceShown || scene.editable
        opacity: scene.faceShown ? scene.st(0.28, 0.4) : 0.35

        Column {
            spacing: 10

            NothingFaceId {
                anchors.horizontalCenter: parent.horizontalCenter
                size: Math.round(104 * Math.max(1, scene.k))
                mode: scene.faceShown ? scene.ctl.faceState : "idle"
                ink: wUser.shaped ? wUser.fg : scene.ink
                red: scene.red
                dim: wUser.shaped ? wUser.fg : scene.dim
                onClicked: if (scene.faceShown) scene.ctl.retryFace()
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5; height: 5; radius: 2.5
                    color: scene.ctl.faceState === "fail" ? scene.red : scene.ink
                    visible: scene.faceShown && (scene.ctl.faceState === "scanning" || scene.ctl.faceState === "fail")
                    SequentialAnimation on opacity {
                        running: ThemeMotion.enabled && !ThemeMotion.reduced
                                 && scene.faceShown && scene.ctl.faceState === "scanning"
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: ThemeMotion.duration("fade") }
                        NumberAnimation { to: 1.0; duration: ThemeMotion.duration("fade") }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: scene.faceShown ? scene.faceLabel.toUpperCase() : "FACE ID"
                    color: wUser.shaped ? wUser.fg : scene.faceTint
                    font { family: scene.mono; pixelSize: 12; letterSpacing: 3 }
                }
            }
        }
    }

    // ---------------------------------------------------------------- пароль
    LockWidget {
        id: wPass
        host: scene
        wid: "password"
        shapeable: false
        opacity: scene.st(0.38, 0.42)

        Column {
            spacing: 14

            // підказка / статус
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (scene.ctl.statusWorking ? Lang.t("lock.auth")
                     : scene.ctl.statusError   ? Lang.t("lock.wrong").replace("{n}", scene.ctl.errorCount)
                     : Lang.t("lock.enter")).toUpperCase()
                color: scene.ctl.statusError ? scene.red : scene.dim
                font { family: scene.mono; pixelSize: 13; letterSpacing: 4 }
                Behavior on color { MotionColorAnimation { role: "stateChange" } }
            }

            // відкритий пароль (режим «показати»)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                height: (scene.ctl.showPassword && scene.passStyle !== "text") ? 26 : 0
                visible: height > 1
                clip: true
                text: scene.ctl.passText
                color: scene.ink
                verticalAlignment: Text.AlignVCenter
                font { family: scene.mono; pixelSize: 20; letterSpacing: 4 }
                Behavior on height { MotionAnimation { role: "expand" } }
            }

            // капсула з точками-слотами (стиль shapes — 16 слотів; dots — по символу; text — сам пароль)
            Rectangle {
                id: capsule
                anchors.horizontalCenter: parent.horizontalCenter
                width: Math.max(scene.passStyle === "text" ? 0 : slotRow.implicitWidth, textPass.implicitWidth) + 56
                height: 60
                radius: 30
                color: Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, 0.40)
                border.width: 1
                border.color: scene.errFlash ? scene.red
                            : passField.activeFocus ? Qt.rgba(scene.ink.r, scene.ink.g, scene.ink.b, 0.55)
                            : scene.line
                Behavior on border.color { MotionColorAnimation { role: "stateChange" } }
                Behavior on width { MotionAnimation { role: "morph" } }

                scale: 0.92 + 0.08 * scene.st(0.4, 0.5)
                transform: Translate { id: shakeShift; x: 0 }

                MouseArea {
                    anchors.fill: parent
                    onClicked: scene.focusInput()
                }

                Text {
                    id: textPass
                    anchors.centerIn: parent
                    visible: scene.passStyle === "text"
                    text: scene.ctl.passText
                    color: scene.ink
                    font { family: scene.mono; pixelSize: 20; letterSpacing: 4 }
                }

                Row {
                    id: slotRow
                    anchors.centerIn: parent
                    visible: scene.passStyle !== "text"
                    spacing: 15

                    Repeater {
                        model: scene.passStyle === "dots" ? scene.ctl.passText.length : scene.slots
                        delegate: Item {
                            id: slot
                            required property int index
                            readonly property bool lit: index < scene.ctl.passText.length
                            readonly property bool newest: index === scene.ctl.passText.length - 1
                            readonly property bool wave: scene.ctl.statusWorking && Math.abs(index - scene.sweep) < 1.6
                            readonly property bool ok: index <= scene.succ
                            readonly property real appear: scene.clamp01((scene.intro - 0.5 - index * 0.012) * 7)

                            width: 13; height: 13

                            Rectangle {
                                anchors.fill: parent
                                radius: 6.5
                                color: scene.errFlash ? scene.red : scene.ink
                                opacity: (scene.errFlash || slot.lit || slot.wave || slot.ok)
                                         ? 1.0 : ThemeNothing.dotOpacityOff
                                scale: (slot.newest ? 1.35 : (slot.lit || slot.ok ? 1.0 : 0.78)) * slot.appear
                                Behavior on scale   { MotionAnimation { role: "morph" } }
                                Behavior on opacity { MotionAnimation { role: "hover" } }
                                Behavior on color   { MotionColorAnimation { role: "stateChange" } }
                            }

                            // кільце-«пульс» при введенні символу
                            Rectangle {
                                id: ripple
                                anchors.centerIn: parent
                                width: 13; height: 13; radius: 6.5
                                color: "transparent"
                                border.width: 1
                                border.color: scene.ink
                                opacity: 0
                            }
                            ParallelAnimation {
                                id: rippleAnim
                                NumberAnimation { target: ripple; property: "scale"; from: 1.0; to: 2.6
                                                  duration: ThemeMotion.duration("expand")
                                                  easing.type: Easing.BezierSpline; easing.bezierCurve: ThemeMotion.curveFor("expand") }
                                NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0.0
                                                  duration: ThemeMotion.duration("expand")
                                                  easing.type: Easing.BezierSpline; easing.bezierCurve: ThemeMotion.curveFor("expand") }
                            }
                            onLitChanged: if (lit) rippleAnim.restart()
                        }
                    }
                }
            }

            // перемикач «показати / сховати»
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: showLabel.implicitWidth + 28
                height: 28
                radius: 14
                color: showMa.containsMouse ? Qt.rgba(scene.ink.r, scene.ink.g, scene.ink.b, 0.10) : "transparent"
                border.width: 1
                border.color: scene.line
                Behavior on color { MotionColorAnimation { role: "hover" } }
                Text {
                    id: showLabel
                    anchors.centerIn: parent
                    text: (scene.ctl.showPassword ? Lang.t("lock.hide") : Lang.t("lock.show")).toUpperCase()
                    color: scene.dim
                    font { family: scene.mono; pixelSize: 11; letterSpacing: 3 }
                }
                MouseArea {
                    id: showMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { scene.ctl.showPassword = !scene.ctl.showPassword; scene.focusInput() }
                }
            }
        }
    }

    // ---------------------------------------------------------------- живлення
    LockWidget {
        id: wPower
        host: scene
        wid: "power"
        shapeable: false
        shown: scene.powerButtons
        opacity: scene.st(0.55, 0.4)

        Row {
            spacing: 12
            Repeater {
                model: [
                    { glyph: "bedtime",            cmd: ["systemctl", "suspend"],  danger: false },
                    { glyph: "restart_alt",        cmd: ["systemctl", "reboot"],   danger: false },
                    { glyph: "power_settings_new", cmd: ["systemctl", "poweroff"], danger: true  }
                ]
                delegate: Rectangle {
                    id: pb
                    required property var modelData
                    width: 44 * Math.max(1, scene.k); height: width; radius: width / 2
                    color: pMa.pressed ? Qt.rgba(scene.ink.r, scene.ink.g, scene.ink.b, 0.18)
                         : pMa.containsMouse ? Qt.rgba(scene.ink.r, scene.ink.g, scene.ink.b, 0.10)
                         : Qt.rgba(M3.surface.r, M3.surface.g, M3.surface.b, 0.40)
                    border.width: 1
                    border.color: pMa.containsMouse && modelData.danger ? scene.red : scene.line
                    scale: pMa.pressed ? 0.92 : (pMa.containsMouse ? 1.07 : 1.0)
                    Behavior on color        { MotionColorAnimation { role: "hover" } }
                    Behavior on border.color { MotionColorAnimation { role: "stateChange" } }
                    Behavior on scale        { MotionAnimation { role: "press" } }
                    Text {
                        anchors.centerIn: parent
                        text: pb.modelData.glyph
                        color: pMa.containsMouse && pb.modelData.danger ? scene.red : scene.ink
                        font { family: "Material Symbols Rounded"; pixelSize: Math.round(20 * Math.max(1, scene.k)) }
                    }
                    MouseArea {
                        id: pMa
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !scene.preview && !scene.editable
                        cursorShape: Qt.PointingHandCursor
                        onClicked: scene.ctl.powerExec = pb.modelData.cmd
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- вхід (невидимий, лише фокус/ввід)
    TextInput {
        id: passField
        width: 1; height: 1
        opacity: 0
        focus: true
        echoMode: TextInput.Normal
        text: scene.ctl.passText
        onTextChanged: if (text !== scene.ctl.passText) scene.ctl.passText = text
        onAccepted: {
            if (scene.preview || scene.editable) return
            if (scene.ctl.authenticating || text.length === 0) return
            scene.ctl.tryUnlock()
            text = ""
        }
        Keys.onPressed: ev => {
            if (!scene.preview && scene.ctl.devKeys !== undefined && scene.ctl.devKeys.handle(ev))
                ev.accepted = true
        }
        Keys.onEscapePressed: { scene.ctl.passText = ""; text = "" }
    }

    // ---------------------------------------------------------------- анімації подій
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: shakeShift; property: "x"; to: -12; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to:  10; duration: 70; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to:  -6; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to:   3; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: shakeShift; property: "x"; to:   0; duration: 70; easing.type: Easing.OutQuad }
    }
    Timer { id: errTimer; interval: 700; onTriggered: scene.errFlash = false }

    NumberAnimation { id: succAnim; target: scene; property: "succ"; from: -1; to: scene.slots + 3
                      duration: ThemeMotion.duration("morph")
                      easing.type: Easing.BezierSpline; easing.bezierCurve: ThemeMotion.curveFor("morph") }

    Connections {
        target: scene.ctl
        function onShakeTickChanged() {
            scene.errFlash = true
            errTimer.restart()
            if (ThemeMotion.enabled && !ThemeMotion.reduced) shakeAnim.restart()
        }
        function onSuccessTickChanged() { succAnim.restart() }
    }

    // «хвиля» під час перевірки паролю
    NumberAnimation {
        target: scene
        property: "sweep"
        from: -2; to: scene.slots + 1
        duration: Math.round(1000 / ThemeMotion.speed)
        loops: Animation.Infinite
        running: scene.ctl.statusWorking && ThemeMotion.enabled && !ThemeMotion.reduced
    }
}
