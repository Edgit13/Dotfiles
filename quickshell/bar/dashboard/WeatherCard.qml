import "root:/theme"
import "root:/services"
import "root:/settings"
import QtQuick
import QtQuick.Layouts

// WeatherCard — компактна плитка: значок + температура, опис, min/max.
DashCard {
    id: root
    fill: Theme.color.tertiaryContainer
    cornerRadius: Theme.shape.radius("xl", height)

    function _t(v) { return isNaN(v) ? "—" : Math.round(v) + "°" }
    readonly property color ink: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgTertiaryContainer
    readonly property bool ok: !WeatherService.loading && !WeatherService.error

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space.sm
            Text {
                text: WeatherService.iconGlyph
                font { family: Theme.type.icons; pixelSize: Theme.type.iconXL }
                color: root.ink
                opacity: WeatherService.loading ? 0.4 : 1
                Behavior on opacity { MotionAnimation { role: "fade" } }
            }
            Item { Layout.fillWidth: true }
            ThemedText {
                visible: root.ok
                text: root._t(WeatherService.temperatureC) + "C"
                style: Theme.type.headlineMedium
                emphasized: true
                color: root.ink
                font.family: Theme.settings.nothing ? Theme.type.dot : style.family
            }
        }

        Item { Layout.fillHeight: true }

        ThemedText {
            Layout.fillWidth: true
            text: WeatherService.loading ? Lang.t("ui.weather.loading")
                : WeatherService.error ? Lang.t("ui.weather.error")
                : WeatherService.description
            style: Theme.type.titleSmall
            color: root.ink
            elide: Text.ElideRight
        }
        ThemedText {
            Layout.fillWidth: true
            visible: root.ok
            text: "↑" + root._t(WeatherService.highC) + "  ↓" + root._t(WeatherService.lowC)
            style: Theme.type.labelSmall
            color: root.ink
            opacity: 0.72
        }
    }
}
