import "root:/theme"
import QtQuick

// MotionStagger — MotionAnimation із затримкою запуску (staggered вхід списків).
// У Qt 6 Animation не має властивості delay, тому затримка — це PauseAnimation
// перед анімацією в SequentialAnimation. Роль лишається тією самою, тому
// Reduce Motion та Animation Speed продовжують працювати.
SequentialAnimation {
    id: root

    property string role: "stateChange"
    property int delay: 0

    // без анімацій / у Reduce Motion затримка не потрібна
    PauseAnimation { duration: ThemeMotion.enabled && !ThemeMotion.reduced ? Math.max(0, root.delay) : 0 }
    MotionAnimation { role: root.role }
}
