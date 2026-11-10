import QtQuick

// NothingFaceId — Face ID у стилі Nothing: dot-matrix 13×13.
//   idle      — обличчя з крапок у кутових дужках
//   scanning  — червона лінія-сканер проходить сіткою, крапки під нею спалахують
//   ok        — обличчя «розчиняється» в галочку з крапок
//   fail      — усе червоне + струс
Canvas {
    id: root

    property string mode: "idle"          // idle | scanning | ok | fail | busy | unavailable
    property real size: 104
    property color ink: "white"
    property color red: "#D71921"
    property color dim: "#999999"
    signal clicked()

    readonly property bool scanning: mode === "scanning"
    readonly property bool ok: mode === "ok"
    readonly property bool fail: mode === "fail"
    readonly property bool muted: mode === "unavailable" || mode === "busy"

    width: size
    height: size
    antialiasing: true

    property real phase: -2
    property real morph: ok ? 1 : 0
    Behavior on morph { NumberAnimation { duration: 520; easing.type: Easing.InOutCubic } }
    NumberAnimation on phase {
        running: root.scanning
        from: -2; to: 15
        duration: 1500
        loops: Animation.Infinite
    }
    onPhaseChanged: requestPaint()
    onMorphChanged: requestPaint()
    onModeChanged: requestPaint()
    onInkChanged: requestPaint()
    onRedChanged: requestPaint()
    onSizeChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onFailChanged: if (fail) shake.restart()
    transform: Translate { id: shiftX; x: 0 }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: shiftX; property: "x"; to: -9; duration: 50 }
        NumberAnimation { target: shiftX; property: "x"; to: 9; duration: 70 }
        NumberAnimation { target: shiftX; property: "x"; to: -5; duration: 60 }
        NumberAnimation { target: shiftX; property: "x"; to: 0; duration: 60 }
    }

    // ── візерунки (колонка, рядок) на сітці 13×13 ──
    readonly property var facePts: {
        const p = []
        // кутові дужки
        const arm = [[0,0],[1,0],[2,0],[3,0],[0,1],[0,2],[0,3]]
        for (let i = 0; i < arm.length; i++) {
            const a = arm[i][0], b = arm[i][1]
            p.push([a, b], [12 - a, b], [a, 12 - b], [12 - a, 12 - b])
        }
        // очі
        p.push([4,4],[4,5],[8,4],[8,5])
        // ніс
        p.push([6,5],[6,6],[6,7],[5,7])
        // усмішка
        p.push([4,9],[5,10],[6,10],[7,10],[8,9])
        return p
    }
    readonly property var checkPts: [[3,7],[4,8],[5,9],[6,8],[7,7],[8,6],[9,5],[10,4]]

    function toSet(list) {
        const o = {}
        for (let i = 0; i < list.length; i++) o[list[i][0] + "," + list[i][1]] = true
        return o
    }
    readonly property var faceSet: toSet(facePts)
    readonly property var checkSet: toSet(checkPts)

    onPaint: {
        const ctx = getContext("2d")
        const N = 13
        const cell = width / N
        ctx.reset()

        const base = fail ? red : (muted ? dim : ink)
        for (let y = 0; y < N; y++) {
            for (let x = 0; x < N; x++) {
                const key = x + "," + y
                const wFace = faceSet[key] ? (1 - morph) : 0
                const wCheck = checkSet[key] ? morph : 0
                const on = Math.max(wFace, wCheck)

                // сканер: смуга навколо рядка phase
                const d = Math.abs(y + 0.5 - phase)
                const scan = scanning ? Math.max(0, 1 - d / 1.7) : 0

                const baseAlpha = 0.14 + (muted ? 0.45 : 0.86) * on
                const rad = cell * (0.13 + 0.19 * on + 0.10 * scan * (on > 0 ? 1.0 : 0.6))
                const cx = (x + 0.5) * cell
                const cy = (y + 0.5) * cell

                ctx.beginPath()
                ctx.arc(cx, cy, rad, 0, Math.PI * 2)
                if (scan > 0.05) {
                    // червоний «промінь»: крапки під ним світяться
                    ctx.fillStyle = Qt.rgba(red.r, red.g, red.b, Math.min(1, baseAlpha * 0.4 + scan * 0.9))
                } else {
                    ctx.fillStyle = Qt.rgba(base.r, base.g, base.b, baseAlpha)
                }
                ctx.fill()
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.mode !== "scanning" && root.mode !== "ok"
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
