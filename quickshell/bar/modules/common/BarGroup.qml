import "root:/theme"
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    property bool vertical: false
    property real pad: Theme.space.xxs
    default property alias content: grid.data

    readonly property bool hasContent: grid.visibleChildren.length > 0

    color: Theme.color.surfaceContainerHigh
    border.width: Theme.settings.nothing ? ThemeNothing.hairline : 0
    border.color: Theme.color.outlineVariant
    radius: Theme.shape.radius("full", Math.min(width, height))
    // тримаємо групу «живою», поки її opacity доанімовується до нуля
    visible: hasContent || opacity > 0.01
    clip: true

    implicitWidth: hasContent ? grid.implicitWidth + pad * 2 : 0
    implicitHeight: hasContent ? grid.implicitHeight + pad * 2 : 0
    opacity: hasContent ? 1 : 0

    // Розмір групи навмисно НЕ анімується окремо: діти (BarModule) вже плавно
    // змінюють власну ширину, а GridLayout веде за ними. Подвійна анімація
    // (Behavior на implicitWidth) лише відставала б від вмісту й обрізала його.
    Behavior on opacity { MotionAnimation { role: "fade" } }

    GridLayout {
        id: grid
        x: root.pad
        y: root.pad
        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columns: root.vertical ? 1 : 999
        rows: root.vertical ? 999 : 1
        rowSpacing: Theme.space.xxs
        columnSpacing: Theme.space.xxs
    }
}
