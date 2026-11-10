import "root:/theme"
import "root:/services"
import "root:/modules/common"
import QtQuick

// NightLightModule — sun / moon toggle for the night light.
BarModule {
    id: root

    readonly property bool active: NightLightService.enabled

    animate: true
    contentW: Theme.components.islandCompact
    contentH: Theme.components.islandCompact

    BarButton {
        anchors.fill: parent
        onClicked: NightLightService.toggle()

        BarIcon {
            anchors.centerIn: parent
            text: root.active ? "\ue518" : "\ue51c"   // light_mode / dark_mode
            color: root.active ? Theme.color.tertiary : Theme.color.fgSurfaceVariant
            rotation: root.active ? 0 : -90
            Behavior on color { MotionColorAnimation { role: "stateChange" } }
            Behavior on rotation { MotionAnimation { role: "morph" } }
        }
    }
}
