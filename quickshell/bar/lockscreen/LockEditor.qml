import QtQuick
import QtQuick.Layouts
import "root:/theme"
import "root:/settings"
import "root:/shell"
import "material"

// LockEditor — прев'ю локскріну в Settings + кнопка «на весь екран» + панель властивостей віджета.
Item {
    id: root
    implicitHeight: col.implicitHeight

    readonly property bool uk: Lang.current.indexOf("uk") === 0
    ColumnLayout {
        id: col
        width: parent.width
        spacing: Theme.space.md

        // ── заголовок секції: прев'ю + віджети ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space.md
            Layout.topMargin: Theme.space.md
            spacing: Theme.space.xxs

            ThemedText {
                Layout.fillWidth: true
                text: Lang.t("section.lock.preview").toUpperCase()
                style: Theme.type.labelMedium
                emphasized: true
                color: Theme.color.primary
                font.letterSpacing: 1.2 * Theme.space.k
            }
            ThemedText {
                Layout.fillWidth: true
                text: root.uk
                      ? "Тягни елементи прямо на прев'ю. Вибери віджет нижче, щоб змінити форму, колір і розмір."
                      : "Drag elements right on the preview. Pick a widget below to change its shape, colour and size."
                style: Theme.type.bodySmall
                color: Theme.color.fgSurfaceVariant
                wrapMode: Text.WordWrap
            }
        }

        // ── прев'ю ──
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(root.width, Theme.components.dp(640))
            Layout.preferredHeight: Layout.preferredWidth * 9 / 16
            LockPreview { id: prev; anchors.fill: parent }
        }

        // ── на весь екран ──
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitHeight: Theme.components.dp(48)
            implicitWidth: fsRow.implicitWidth + Theme.space.xl * 2
            radius: fsMa.pressed ? Theme.shape.radius("md", height) : height / 2
            color: Theme.stateLayer(Theme.color.primary, Theme.color.fgPrimary, fsMa.containsMouse ? Theme.components.stateHover : 0)
            Behavior on radius { MotionAnimation { role: "morph" } }
            Row {
                id: fsRow
                anchors.centerIn: parent
                spacing: Theme.space.sm
                Text { anchors.verticalCenter: parent.verticalCenter; text: "open_in_full"; font.family: "Material Symbols Rounded"; font.pixelSize: 20; color: Theme.color.fgPrimary }
                ThemedText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.uk ? "Редагувати на весь екран" : "Edit on full screen"
                    style: Theme.type.labelLarge
                    color: Theme.color.fgPrimary
                }
            }
            MouseArea {
                id: fsMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: { LockEditorState.open = true; ShellState.closeSettings() }
            }
        }

        LockWidgetPanel { Layout.fillWidth: true; pv: prev }
    }
}
