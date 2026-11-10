import "root:/theme"
import QtQuick

// BarModule — спільна основа КОЖНОГО модуля бару: розмір, показ/ховання, анімація, вмикання з конфіга.
// Раніше кожен модуль (Media/Record/GameMode/Battery/Window…) сам писав implicitWidth/implicitHeight,
// Behavior, opacity і `visible` — трохи по-різному. А зовнішній `visible: Config…` у BarWindow
// перезаписував внутрішній `visible`, тож порожній модуль лишався «видимим» і його вміст налазив на сусідів.
//
//   BarModule { shown: <є що показувати>; contentW: <природна ширина>; contentH: <висота у вертикальному барі> }
//   Ззовні вмикати/вимикати лише через `enabledByConfig` — НІКОЛИ через `visible`.
Item {
    id: root

    property bool vertical: false
    property int cross: Theme.components.islandCompact

    property bool shown: true                 // чи є що показувати (немає медіа / запису / батареї → false)
    property bool enabledByConfig: true       // перемикач з налаштувань (modules.*)
    property bool animate: false              // плавно змінювати розмір при зміні вмісту
    // "move" — швидший spring для зміни вмісту, "collapse" — м'яке згортання
    property string widthRole: shown ? "move" : "collapse"

    property real contentW: cross             // природна ширина (горизонтальний бар), разом з відступами
    property real contentH: cross             // природна висота (вертикальний бар), разом з відступами

    implicitWidth: shown ? (vertical ? cross : contentW) : 0
    implicitHeight: shown ? (vertical ? contentH : cross) : 0
    opacity: shown ? 1 : 0
    scale: shown ? 1.0 : 0.84
    transformOrigin: Item.Center
    clip: true                                // вміст ніколи не виступає за межі модуля (в т.ч. під час анімації)
    visible: enabledByConfig && (shown || implicitWidth > 0.5 || implicitHeight > 0.5)

    Behavior on implicitWidth  { enabled: root.animate; MotionAnimation { role: root.widthRole } }
    Behavior on implicitHeight { enabled: root.animate; MotionAnimation { role: "morph" } }
    Behavior on opacity { MotionAnimation { role: "fade" } }
    // поява/зникнення модуля: легкий pop, не впливає на layout (лише візуально)
    Behavior on scale { MotionAnimation { role: root.shown ? "enter" : "exit" } }
}
