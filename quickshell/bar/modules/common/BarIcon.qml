import "root:/theme"
import QtQuick

// BarIcon — іконка-гліф (Material Symbols) стандартного розміру для бару.
// Раніше `font { family: Theme.type.icons; pixelSize: Theme.type.iconS }` + колір копіювались у кожному модулі.
// Зміна гліфа (гучність, батарея, мережа) м'яко проявляється замість миттєвого стрибка.
Text {
    id: root

    property int size: Theme.type.iconS
    property bool animate: true
    color: Theme.color.fgSurface
    font { family: Theme.type.icons; pixelSize: size }

    property bool _ready: false
    Component.onCompleted: _ready = true

    onTextChanged: if (_ready && animate && ThemeMotion.enabled) glyphSwap.restart()

    SequentialAnimation {
        id: glyphSwap
        NumberAnimation {
            target: root
            property: "opacity"
            from: 0.25
            to: 1
            duration: ThemeMotion.duration("stateChange")
            easing.type: Easing.BezierSpline
            easing.bezierCurve: ThemeMotion.curveFor("stateChange")
        }
    }
}
