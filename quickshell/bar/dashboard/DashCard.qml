import "root:/theme"
import QtQuick
import QtQuick.Layouts

// DashCard — плоска тональна M3 Expressive картка (без тіні, як у dux-shell).
// DashCard { title: "Погода"; fill: Theme.color.tertiaryContainer; content: [ ... ] }
Item {
    id: root
    default property alias content: body.data
    property string title: ""
    property color fill: Theme.color.surfaceContainerHigh
    property real cornerRadius: Theme.shape.cardLarge
    property real pad: Theme.space.lg
    property int level: 0                       // лишено для сумісності зі старим API

    implicitHeight: Math.max(72, col.implicitHeight + pad * 2)

    Rectangle {
        anchors.fill: parent
        radius: root.cornerRadius
        color: Theme.settings.nothing ? Theme.color.surfaceContainerLow : root.fill
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.22)
        Behavior on color { MotionColorAnimation { role: "hover" } }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Theme.space.sm

        Row {
            visible: root.title.length > 0
            spacing: Theme.space.xs
            Rectangle {
                visible: Theme.settings.nothing
                width: 5; height: 5; radius: 2.5
                anchors.verticalCenter: parent.verticalCenter
                color: ThemeNothing.red
            }
            ThemedText {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.settings.nothing ? root.title.toUpperCase() : root.title
                style: Theme.settings.nothing ? Theme.type.labelMedium : Theme.type.titleSmall
                color: Theme.color.fgSurfaceVariant
                font.letterSpacing: Theme.settings.nothing ? 2 : style.tracking
            }
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
        }
    }
}
