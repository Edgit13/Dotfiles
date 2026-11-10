import "root:/theme"
import "root:/services"
import "root:/settings"
import Quickshell
import QtQuick
import QtQuick.Layouts

// CalendarCard — місяць із заокругленими клітинками, днями сусідніх місяців і крапками справ/таймерів.
DashCard {
    id: root

    SystemClock { id: clk; precision: SystemClock.Minutes }

    readonly property date today: clk.date
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth()

    function shiftMonth(d) {
        let m = viewMonth + d, y = viewYear
        if (m < 0) { m = 11; y -= 1 }
        if (m > 11) { m = 0; y += 1 }
        viewMonth = m; viewYear = y
    }
    function goToday() { viewYear = today.getFullYear(); viewMonth = today.getMonth() }
    function _pad(n) { return (n < 10 ? "0" : "") + n }

    readonly property var dayNames: [0, 1, 2, 3, 4, 5, 6].map(i => Lang.t("ui.dow." + i))

    // 6 тижнів × 7 днів, понеділок — перший
    readonly property var cells: {
        const startOffset = (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7
        const t = today
        const arr = []
        for (let i = 0; i < 42; i++) {
            const d = new Date(viewYear, viewMonth, 1 - startOffset + i)
            const y = d.getFullYear(), m = d.getMonth(), n = d.getDate()
            arr.push({
                day: n,
                inMonth: m === viewMonth,
                isToday: n === t.getDate() && m === t.getMonth() && y === t.getFullYear(),
                key: y + "-" + _pad(m + 1) + "-" + _pad(n)
            })
        }
        return arr
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.sm

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.xs

            ThemedText {
                Layout.fillWidth: true
                text: Lang.t("ui.month." + root.viewMonth) + " " + root.viewYear
                style: Theme.type.titleMedium
                emphasized: true
                font.family: Theme.settings.nothing ? Theme.type.dot : style.family
                font.capitalization: Theme.settings.nothing ? Font.AllUppercase : Font.MixedCase
            }
            DashButton { variant: "subtle"; size: Theme.components.dp(32); icon: "\ue935"; onClicked: root.goToday() }
            DashButton { variant: "subtle"; size: Theme.components.dp(32); icon: "\ue5cb"; onClicked: root.shiftMonth(-1) }
            DashButton { variant: "subtle"; size: Theme.components.dp(32); icon: "\ue5cc"; onClicked: root.shiftMonth(1) }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            columnSpacing: Theme.space.xs
            rowSpacing: 0
            uniformCellWidths: true
            Repeater {
                model: root.dayNames
                ThemedText {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            columnSpacing: Theme.space.xs
            rowSpacing: Theme.space.xs
            uniformCellWidths: true
            uniformCellHeights: true

            Repeater {
                model: root.cells
                Rectangle {
                    id: cell
                    required property var modelData
                    readonly property int marks: (TodoService.dueMap[modelData.key] || 0) + (TimerService.dayMap[modelData.key] || 0)

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Theme.components.dp(26)
                    radius: modelData.isToday ? height / 2 : Theme.shape.radius("md", height)
                    color: modelData.isToday ? (Theme.settings.nothing ? Theme.color.tertiary : Theme.color.primaryContainer)
                         : (modelData.inMonth && !Theme.settings.nothing) ? Theme.color.surfaceContainerHighest
                         : "transparent"
                    Behavior on color { MotionColorAnimation { role: "hover" } }

                    ThemedText {
                        anchors.centerIn: parent
                        text: cell.modelData.day
                        style: Theme.type.labelMedium
                        emphasized: cell.modelData.isToday
                        color: cell.modelData.isToday ? (Theme.settings.nothing ? Theme.color.fgTertiary : Theme.color.fgPrimaryContainer)
                             : cell.modelData.inMonth ? Theme.color.fgSurface
                             : Theme.color.outline
                        opacity: cell.modelData.inMonth || cell.modelData.isToday ? 1 : 0.55
                    }
                    Rectangle {
                        visible: cell.marks > 0
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 3
                        width: 4; height: 4; radius: 2
                        color: cell.modelData.isToday ? (Theme.settings.nothing ? Theme.color.fgTertiary : Theme.color.fgPrimaryContainer)
                             : (Theme.settings.nothing ? Theme.color.tertiary : Theme.color.primary)
                    }
                }
            }
        }
    }
}
