import QtQuick
import "material"

// FaceIdMark — Face ID в стилі Apple: заокруглені кутові дужки, очі, ніс, усмішка (Canvas).
//   mode: idle | scanning | ok | fail | busy | unavailable
//   scanning → риси обличчя «дихають», дужки пульсують; ok → дужки стають колом з галочкою, що домальовується;
//   fail → струс + червоний колір.
Item {
    id: root

    property string mode: "idle"
    property real size: 96
    signal clicked()

    readonly property bool ok: mode === "ok"
    readonly property bool fail: mode === "fail"
    readonly property bool scanning: mode === "scanning"
    readonly property color tint: fail ? M3.error
                                : (scanning || ok) ? M3.primary
                                : M3.m3OnSurface

    width: size
    height: size

    onTintChanged: { brackets.requestPaint(); features.requestPaint() }
    onSizeChanged: { brackets.requestPaint(); features.requestPaint(); check.requestPaint() }

    onFailChanged: if (fail) shake.restart()
    SequentialAnimation {
        id: shake
        NumberAnimation { target: glyph; property: "x"; to: -9; duration: 50 }
        NumberAnimation { target: glyph; property: "x"; to: 9; duration: 70 }
        NumberAnimation { target: glyph; property: "x"; to: -5; duration: 60 }
        NumberAnimation { target: glyph; property: "x"; to: 0; duration: 60 }
    }

    // ── коло успіху ─────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: root.size * 0.86; height: width; radius: width / 2
        color: M3.primaryContainer
        opacity: root.ok ? 1 : 0
        scale: root.ok ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Behavior on scale { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
    }

    Item {
        id: glyph
        width: root.size; height: root.size

        // дужки
        Canvas {
            id: brackets
            anchors.fill: parent
            opacity: root.ok ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: 200 } }
            transformOrigin: Item.Center
            property real breathe: 1
            scale: breathe
            SequentialAnimation on breathe {
                running: root.scanning
                alwaysRunToEnd: true
                loops: Animation.Infinite
                NumberAnimation { to: 1.06; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.00; duration: 700; easing.type: Easing.InOutSine }
            }
            onPaint: {
                const ctx = getContext("2d")
                const s = width
                ctx.reset()
                ctx.strokeStyle = root.tint
                ctx.lineWidth = s * 0.055
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                const p = s * 0.10, L = p, T = p, R = s - p, B = s - p
                const w = R - L, r = w * 0.26, arm = w * 0.46
                ctx.beginPath()
                ctx.moveTo(L, T + arm); ctx.lineTo(L, T + r); ctx.quadraticCurveTo(L, T, L + r, T); ctx.lineTo(L + arm, T)
                ctx.moveTo(R - arm, T); ctx.lineTo(R - r, T); ctx.quadraticCurveTo(R, T, R, T + r); ctx.lineTo(R, T + arm)
                ctx.moveTo(R, B - arm); ctx.lineTo(R, B - r); ctx.quadraticCurveTo(R, B, R - r, B); ctx.lineTo(R - arm, B)
                ctx.moveTo(L + arm, B); ctx.lineTo(L + r, B); ctx.quadraticCurveTo(L, B, L, B - r); ctx.lineTo(L, B - arm)
                ctx.stroke()
            }
        }

        // очі, ніс, усмішка
        Canvas {
            id: features
            anchors.fill: parent
            property real pulse: 1
            opacity: root.ok ? 0 : pulse
            SequentialAnimation on pulse {
                running: root.scanning
                alwaysRunToEnd: true
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 650; easing.type: Easing.InOutSine }
            }
            onPaint: {
                const ctx = getContext("2d")
                const s = width, cx = s / 2, cy = s / 2
                ctx.reset()
                ctx.strokeStyle = root.tint
                ctx.lineWidth = s * 0.055
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                // очі
                ctx.moveTo(cx - s * 0.15, cy - s * 0.17); ctx.lineTo(cx - s * 0.15, cy - s * 0.08)
                ctx.moveTo(cx + s * 0.15, cy - s * 0.17); ctx.lineTo(cx + s * 0.15, cy - s * 0.08)
                // ніс
                ctx.moveTo(cx + s * 0.02, cy - s * 0.10); ctx.lineTo(cx + s * 0.02, cy + s * 0.05)
                ctx.quadraticCurveTo(cx + s * 0.02, cy + s * 0.09, cx - s * 0.03, cy + s * 0.09)
                // усмішка
                ctx.moveTo(cx - s * 0.16, cy + s * 0.17)
                ctx.quadraticCurveTo(cx, cy + s * 0.30, cx + s * 0.16, cy + s * 0.17)
                ctx.stroke()
            }
        }

        // галочка, що домальовується
        Canvas {
            id: check
            anchors.fill: parent
            property real p: root.ok ? 1 : 0
            Behavior on p { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
            onPChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                const s = width
                ctx.reset()
                if (p <= 0.001) return
                ctx.strokeStyle = M3.m3OnPrimaryContainer
                ctx.lineWidth = s * 0.07
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                const a = { x: s * 0.30, y: s * 0.52 }, b = { x: s * 0.44, y: s * 0.65 }, c = { x: s * 0.71, y: s * 0.36 }
                const l1 = Math.hypot(b.x - a.x, b.y - a.y), l2 = Math.hypot(c.x - b.x, c.y - b.y)
                const d = (l1 + l2) * p
                ctx.beginPath()
                ctx.moveTo(a.x, a.y)
                if (d <= l1) {
                    const t = d / l1
                    ctx.lineTo(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)
                } else {
                    const t = (d - l1) / l2
                    ctx.lineTo(b.x, b.y)
                    ctx.lineTo(b.x + (c.x - b.x) * t, b.y + (c.y - b.y) * t)
                }
                ctx.stroke()
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
