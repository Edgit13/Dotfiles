import "root:/theme"
import "root:/modules/common"
import "root:/services"
import Quickshell
import QtQuick

// BluetoothModule — кнопка Bluetooth на барі. При наведенні виїжджає назва підключеного пристрою.
// ЛКМ: відкрити Bluetooth-поверхню · ПКМ: швидке увімкнення/вимкнення.
BarRevealButton {
    id: root

    signal bluetoothRequested()

    readonly property bool enabled: BluetoothService.enabled
    readonly property var connected: BluetoothService.connectedDevices
    readonly property bool hasConnected: connected.length > 0
    readonly property var firstDevice: hasConnected ? connected[0] : null

    glyph: !enabled ? "\ue1a8" : "\ue1a7"
    glyphColor: hasConnected ? Theme.color.primary : (enabled ? Theme.color.fgSurface : Theme.color.outline)

    label: {
        if (!enabled) return "Off"
        if (hasConnected && firstDevice) {
            const devName = firstDevice.name || firstDevice.mac
            const bat = firstDevice.battery >= 0 ? (" " + firstDevice.battery + "%") : ""
            return (connected.length > 1 ? ("(" + connected.length + ") ") : "") + devName + bat
        }
        return "Bluetooth"
    }
    labelColor: hasConnected ? Theme.color.primary : (enabled ? Theme.color.fgSurface : Theme.color.outline)
    verticalLabel: hasConnected ? ((firstDevice && firstDevice.battery >= 0) ? (firstDevice.battery + "%") : "ON") : (enabled ? "ON" : "OFF")

    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            BluetoothService.togglePower()
        } else {
            root.bluetoothRequested()
        }
    }
}
