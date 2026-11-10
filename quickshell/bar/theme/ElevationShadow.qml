import "root:/states"
import "root:/settings"
import "root:/theme"
import QtQuick
import QtQuick.Effects

// Тінь для рівня elevation (0..5) + tonal-заливка. Клади ПІД контент або використовуй як фон:
//   ElevationShadow { level: 2; radius: Theme.shape.card; anchors.fill: parent }
// Caster непрозорий (tonal-колір), тож для напівпрозорих поверхонь ставь color: "transparent"
// і level: 0 (без тіні) або вимикай shadowVisible.
//
// Тінь малюється SDF-шейдером RectangularShadow в один прохід — без layer.enabled +
// MultiEffect. Це той самий підхід, що в dux-shell (elevation_rect.frag), але штатними
// засобами Qt. На слабких GPU (Intel UHD 620) немає offscreen-текстури та повторного
// блюру на кожному кадрі морфу, тож немає «смуги блюру» й просідань під час анімації.
Item {
    id: root
    property real level: 1
    property real radius: ThemeShapes.card
    property color color: ThemeElevation.surfaceFor(level)
    readonly property real shadowOpacity: ThemeElevation.opacity(level)
    property bool shadowVisible: level > 0.05 && shadowOpacity > 0.001
                                  && !ReliefState.effects && Settings.get("theme", "shadows")
    property alias content: caster   // фон-прямокутник (для border тощо)

    // SDF-тінь позаду caster. Один шейдерний прохід, без layer/MultiEffect.
    RectangularShadow {
        anchors.fill: parent
        visible: root.shadowVisible
        radius: root.radius
        blur: ThemeElevation.blur(root.level)
        spread: 0
        offset: Qt.vector2d(0, ThemeElevation.offsetY(root.level))
        color: Qt.rgba(ThemeColors.shadow.r, ThemeColors.shadow.g, ThemeColors.shadow.b,
                       ThemeColors.shadow.a * root.shadowOpacity)
        cached: false
    }

    Rectangle {
        id: caster
        anchors.fill: parent
        radius: root.radius
        color: root.color
        border.width: ThemeSettings.nothing ? ThemeNothing.hairline : 0
        border.color: ThemeColors.outlineVariant
    }
}
