//@ pragma UseQApplication
import "root:/states"
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// Shared Material 3 foundation (colors.json is watched inside M3.qml).
import "material"
import "root:/theme"
import "root:/settings"

Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    // дизайн "Nothing" → окрема сцена (LockNothing.qml); інакше — M3 Expressive сцена нижче
    readonly property bool nothing: Theme.settings.nothing
    property bool authenticating: false
    property bool showPassword: false
    property int errorCount: 0

    // ---- animation / event tickers (visible to every surface) ----
    property real parallaxX: 0
    property real parallaxY: 0
    property int  shakeTick: 0
    property int  successTick: 0

    function clamp01(v) { return v < 0 ? 0 : (v > 1 ? 1 : v) }

    // Full M3 Expressive shape catalog (from the reference PNG).
    readonly property var dotCatalog: [
        "cookie", "sunny", "burst", "star",
        "clover", "flower", "pentagon", "hexagon",
        "square", "oval", "pill", "pill_diag",
        "blob", "circle"
    ]

    // Ambient floating shapes: shape / size / initial pos / drift
    readonly property var floaters: [
        { shape: "blob",    size: 260, x: 0.08, y: 0.18, ax: 0.05, ay: 0.02, dur: 32000 },
        { shape: "cookie",  size: 200, x: 0.82, y: 0.28, ax: 0.05, ay: 0.03, dur: 38000 },
        { shape: "flower",  size: 180, x: 0.72, y: 0.78, ax: 0.04, ay: 0.04, dur: 42000 }
    ]

    FileView {
        id: wallpaperFile
        path: Quickshell.shellPath("../current-wallpaper.txt")
        watchChanges: true
        printErrors: false
        // watchChanges only emits fileChanged — without reload() the text stays stale
        onFileChanged: reload()
        onLoaded: root.wallpaperPath = text().trim()
        onTextChanged: {
            root.wallpaperPath = text().trim()
            // the wallpaper picker writes this file after awww changed the image
            root.refreshWallpaper()
        }
    }

    // ---- wallpaper source ----
    // awww is the source of truth for what is actually on screen. The text file
    // can be stale (a restored daemon cache, an install script, another tool),
    // so ask the compositor on startup and every time the lock opens.
    property var wallpaperByScreen: ({})
    property string wallpaperFromCompositor: ""

    property string wallpaperPath: ""
    readonly property string effectiveWallpaper: wallpaperFromCompositor.length > 0
        ? wallpaperFromCompositor : wallpaperPath
    readonly property string wallpaperUrl: effectiveWallpaper.length > 0
        ? "file://" + effectiveWallpaper : ""

    function refreshWallpaper() {
        if (!wallpaperQuery.running) wallpaperQuery.running = true
    }

    function parseWallpaperQuery(out) {
        const map = {}
        let first = ""
        const lines = String(out || "").split("\n")
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i]
            const at = line.indexOf("currently displaying:")
            if (at < 0) continue
            // "currently displaying: image: /path" or "animated: /path"
            let p = line.substring(at + "currently displaying:".length).trim()
            p = p.replace(/^(image|animated|video):\s*/, "").trim()
            if (!p.length) continue
            if (!first.length) first = p
            const m = line.match(/^\s*:?\s*([^:]+):/)
            if (m && m[1].trim().length > 0) map[m[1].trim()] = p
        }
        wallpaperByScreen = map
        wallpaperFromCompositor = first
    }

    // per-output wallpaper, falling back to the text file
    function wallpaperFor(surface) {
        const name = surface && surface.screen ? surface.screen.name : ""
        let p = (name.length > 0 && wallpaperByScreen[name]) ? wallpaperByScreen[name] : wallpaperFromCompositor
        if (!p || !p.length) p = wallpaperPath
        return p && p.length > 0 ? "file://" + p : ""
    }

    Process {
        id: wallpaperQuery
        command: ["sh", "-c", "awww query 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.parseWallpaperQuery(text) }
    }

    Component.onCompleted: {
        root.refreshWallpaper()
        root.refreshFaceStatus()
    }

    readonly property string greeting: {
        var h = new Date().getHours()
        if (h < 5)  return Lang.t("lock.greet.night")
        if (h < 12) return Lang.t("lock.greet.morning")
        if (h < 18) return Lang.t("lock.greet.afternoon")
        return Lang.t("lock.greet.evening")
    }
    readonly property string greetingIcon: {
        var h = new Date().getHours()
        if (h < 5)  return "bedtime"
        if (h < 12) return "wb_sunny"
        if (h < 18) return "wb_twilight"
        return "dark_mode"
    }

    // ---------------------------------------------------------------- auth
    Process {
        id: authProc
        stdinEnabled: true
        property string pendingPassword: ""
        onStarted: write(pendingPassword + "\n")
        onExited: (exitCode, exitStatus) => {
            root.authenticating = false
            root.statusWorking = false
            if (exitCode === 0) {
                root.successTick += 1
                lock.locked = false
            } else {
                root.errorCount += 1
                root.statusError = true
                root.shakeTick += 1
            }
        }
    }

    // ------------------------------------------------------------- face id
    // Local, opt-in Face ID: YuNet finds the face, SFace compares embeddings.
    // The helper runs in a private venv (see scripts/faceid.py).  A correct
    // password always unlocks; Face ID only ever *adds* a way in.
    readonly property string faceHelper: Quickshell.shellPath("scripts/faceid.sh")
    // режим розробника: безпечні гарячі клавіші на локскріні (Settings → Локскрін)
    LockDev { id: devKeysImpl }
    readonly property var devKeys: devKeysImpl

    readonly property bool faceEnabled: Settings.get("lockscreen", "faceUnlock") === true
    property bool faceEnrolled: false
    property string faceState: "idle"   // idle | scanning | ok | fail | busy | unavailable
    property int faceAttempts: 0
    property string faceReason: ""
    property string faceStatusRaw: ""
    property string faceRaw: ""

    readonly property string faceLabel: {
        switch (root.faceState) {
        case "scanning":    return Lang.t("lock.face.scan")
        case "ok":          return Lang.t("lock.face.ok")
        case "fail":        return Lang.t("lock.face.fail")
        case "busy":        return Lang.t("lock.face.busy")
        case "unavailable": return Lang.t("lock.face.unavailable")
        }
        return Lang.t("lock.face.idle")
    }

    function refreshFaceStatus() {
        if (faceStatusProc.running) return
        root.faceStatusRaw = ""
        faceStatusProc.running = true
    }

    function applyFaceStatus(raw) {
        try {
            const info = JSON.parse(String(raw || "{}"))
            root.faceEnrolled = info.enrolled === true
        } catch (e) {
            root.faceEnrolled = false
        }
        // First lock after startup: the status arrives a moment later.
        if (lock.locked && root.faceEnabled && root.faceEnrolled
                && root.faceState === "idle")
            faceStartTimer.restart()
    }

    function tryFaceUnlock() {
        if (!lock.locked || !root.faceEnabled || !root.faceEnrolled) return
        if (faceProc.running || root.authenticating) return
        root.faceState = "scanning"
        root.faceReason = ""
        root.faceRaw = ""
        faceProc.running = true
    }

    function retryFace() {
        if (!root.faceEnabled) return
        if (!root.faceEnrolled) { root.refreshFaceStatus(); return }
        if (faceProc.running) return
        root.faceAttempts = 0
        root.tryFaceUnlock()
    }

    function applyFaceResult(code, raw) {
        let info = {}
        try { info = JSON.parse(String(raw || "{}")) } catch (e) {}
        root.faceReason = String(info.reason || "")

        if (code === 0) {
            if (!lock.locked) return
            root.faceState = "ok"
            root.successTick += 1
            faceUnlockTimer.restart()
            return
        }

        root.faceState = "idle"
        if (code === 2) {
            root.faceEnrolled = false
        } else if (code === 3) {
            root.faceState = "busy"
        } else if (code === 4) {
            root.faceState = "unavailable"
        } else if (root.faceReason === "no face" || root.faceReason === "hold still") {
            // Give the user a second chance if they were still sitting down.
            if (root.faceAttempts < 2) {
                root.faceAttempts += 1
                faceRetryTimer.restart()
            } else {
                root.faceState = "fail"
            }
        } else {
            root.faceState = "fail"
        }
    }

    Process {
        id: faceStatusProc
        command: ["bash", root.faceHelper, "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.faceStatusRaw = text
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) root.applyFaceStatus(root.faceStatusRaw)
        }
    }

    Process {
        id: faceProc
        command: ["bash", root.faceHelper, "verify", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.faceRaw = text
        }
        onExited: (exitCode, exitStatus) => root.applyFaceResult(exitCode, root.faceRaw)
        onRunningChanged: if (running) root.faceState = "scanning"
    }

    Timer { id: faceStartTimer; interval: 700;  repeat: false; onTriggered: root.tryFaceUnlock() }
    Timer { id: faceRetryTimer; interval: 2600; repeat: false; onTriggered: root.tryFaceUnlock() }
    Timer {
        id: faceUnlockTimer
        interval: 380
        repeat: false
        onTriggered: if (lock.locked) lock.locked = false
    }

    Connections {
        target: Settings
        function onChanged(cat, key, value) {
            if (cat !== "lockscreen" || key !== "faceUnlock") return
            if (value === true) {
                root.refreshFaceStatus()
                if (lock.locked) faceStartTimer.restart()
            } else {
                root.faceState = "idle"
            }
        }
    }

    Process { id: powerProc }

    property string passText: ""
    property bool statusWorking: false
    property bool statusError: false
    property var powerExec: []

    function tryUnlock() {
        if (root.authenticating || passText.length === 0) return
        root.authenticating = true
        root.statusError = false
        root.statusWorking = true
        authProc.pendingPassword = root.passText
        root.passText = ""
        authProc.exec([root.home + "/.config/quickshell/bar/lockscreen/pam-auth"])
    }

    function runPower(cmd) { powerProc.exec(cmd) }

    // ------------------------------------------------------------- session
    WlSessionLock {
        id: lock
        locked: false
        // re-read the live wallpaper every time the lock opens
        onLockedChanged: if (locked) {
            root.refreshWallpaper()
            root.faceState = "idle"
            root.faceAttempts = 0
            root.refreshFaceStatus()
            faceStartTimer.restart()
        } else {
            root.faceState = "idle"
        }
        onSecureChanged: if (!secure) console.log("Lockscreen: unlocked")

        WlSessionLockSurface {
            id: surf
            color: M3.surface

            // ============ M3 EXPRESSIVE SCENE (лише коли дизайн ≠ Nothing) ============
            Loader {
                id: m3Loader
                anchors.fill: parent
                active: !root.nothing
                sourceComponent: Component { LockM3 { ctl: root } }
            }

            // ============ NOTHING SCENE (дизайн Nothing) ============
            Loader {
                id: nothingLoader
                anchors.fill: parent
                active: root.nothing
                sourceComponent: Component { LockNothing { ctl: root } }
            }

            Connections {
                target: root
                function onSuccessTickChanged() {
                    if (!root.nothing && Settings.get("lockscreen", "successFlash") !== false)
                        successFlashAnim.restart()
                }
            }

            // ============ SUCCESS FLASH ============
            Rectangle {
                id: successFlash
                anchors.fill: parent
                color: root.nothing ? M3.m3OnSurface : M3.primary
                opacity: 0
                z: 100
                SequentialAnimation {
                    id: successFlashAnim
                    NumberAnimation { target: successFlash; property: "opacity"; to: 0.35; duration: 120 }
                    NumberAnimation { target: successFlash; property: "opacity"; to: 0.0; duration: 480; easing.type: Easing.OutCubic }
                }
            }

            // ============ POWER CONFIRM DIALOG ============
            Rectangle {
                id: confirmPower
                anchors.fill: parent
                color: M3.scrim
                opacity: visible ? 0.7 : 0
                visible: root.powerExec.length > 0
                Behavior on opacity { NumberAnimation { duration: M3.durMed } }
                MouseArea { anchors.fill: parent }

                Rectangle {
                    anchors.centerIn: parent
                    width: 400
                    height: col2.implicitHeight + M3.s24 * 2
                    radius: root.nothing ? ThemeNothing.corners.lg : 32
                    color: M3.surfaceContainerHigh
                    border.width: 1
                    border.color: root.nothing ? M3.outline : M3.outlineVariant
                    scale: confirmPower.visible ? 1.0 : 0.9
                    Behavior on scale {
                        NumberAnimation {
                            duration: M3.durMed
                            easing.type: Easing.OutBack
                            easing.overshoot: 1.1
                        }
                    }

                    Column {
                        id: col2
                        anchors {
                            left: parent.left; right: parent.right; top: parent.top
                            margins: M3.s24
                        }
                        spacing: M3.s24

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 56; height: 56
                            radius: M3.rFull
                            color: root.nothing ? "transparent" : M3.errorContainer
                            border.width: root.nothing ? 1 : 0
                            border.color: ThemeNothing.red

                            SequentialAnimation on scale {
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 1.06; duration: 1800; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1.06; to: 1.0; duration: 1800; easing.type: Easing.InOutSine }
                            }

                            Text {
                                anchors.centerIn: parent
                                text: "power_settings_new"
                                color: M3.error
                                font { family: "Material Symbols Rounded"; pixelSize: 26 }
                            }
                        }

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                if (root.powerExec.length === 0) return ""
                                const t = Lang.t("lock.confirm").replace("{cmd}", root.powerExec[root.powerExec.length - 1])
                                return root.nothing ? t.toUpperCase() : t
                            }
                            color: M3.m3OnSurface
                            font: root.nothing
                                  ? ({ family: M3.fontMono, pixelSize: 16, weight: Font.Medium, letterSpacing: 3 })
                                  : M3.titleLarge

                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: M3.s12

                            Rectangle {
                                width: 140; height: 44; radius: M3.rFull
                                color: root.nothing
                                     ? (yesMa.pressed ? Qt.darker(ThemeNothing.red, 1.2)
                                        : yesMa.containsMouse ? Qt.lighter(ThemeNothing.red, 1.15) : ThemeNothing.red)
                                     : yesMa.pressed      ? M3.pressedOf(M3.errorContainer)
                                     : yesMa.containsMouse ? M3.hoverOf(M3.errorContainer)
                                     : M3.errorContainer
                                Behavior on color { ColorAnimation { duration: M3.durFast } }
                                scale: yesMa.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: M3.s8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "check"
                                        color: root.nothing ? "#FFFFFF" : M3.error
                                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Lang.t("lock.yes")
                                        color: root.nothing ? "#FFFFFF" : M3.error
                                        font: M3.labelLarge
                                    }
                                }
                                MouseArea {
                                    id: yesMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.runPower(root.powerExec)
                                        root.powerExec = []
                                    }
                                }
                            }

                            Rectangle {
                                width: 140; height: 44; radius: M3.rFull
                                border.width: root.nothing ? 1 : 0
                                border.color: M3.outline
                                color: root.nothing
                                     ? (noMa.pressed ? Qt.rgba(M3.fg.r, M3.fg.g, M3.fg.b, 0.16)
                                        : noMa.containsMouse ? Qt.rgba(M3.fg.r, M3.fg.g, M3.fg.b, 0.08) : "transparent")
                                     : noMa.pressed      ? M3.pressedOf(M3.primary)
                                     : noMa.containsMouse ? M3.hoverOf(M3.primary)
                                     : M3.primary
                                Behavior on color { ColorAnimation { duration: M3.durFast } }
                                scale: noMa.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Row {
                                    anchors.centerIn: parent
                                    spacing: M3.s8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "close"
                                        color: root.nothing ? M3.m3OnSurface : M3.m3OnPrimary
                                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Lang.t("lock.cancel")
                                        color: root.nothing ? M3.m3OnSurface : M3.m3OnPrimary
                                        font: M3.labelLarge
                                    }
                                }
                                MouseArea {
                                    id: noMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.powerExec = []
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Timer {
        id: quitTimer
        interval: 200
        onTriggered: console.log("Lockscreen: quit suppressed")
    }

    Timer {
        interval: 2500
        running: lock.locked && !lock.secure
        repeat: false
        onTriggered: {
            if (!lock.secure) {
                console.error("ilock: compositor did not confirm session lock " +
                              "(ext-session-lock-v1 unsupported?) — quitting")
                console.log("Lockscreen: quit suppressed")
            }
        }
    }

    IpcHandler {
        target: "ilock"
        function relock(): void { lock.locked = true }
        function quit(): void { console.log("Lockscreen: quit suppressed") }
    }
}
