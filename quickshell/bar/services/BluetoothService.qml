pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// ==========================================================================
// BluetoothService.qml — бекенд Bluetooth-менеджера для Edots Quickshell.
// Поєднує пряму реактивність Quickshell.Bluetooth (BlueZ D-Bus) для стану
// адаптера та асинхронні команди bluetoothctl/btquery.py для повної
// інформації про пристрої (рівень батареї, підключення, сполучення, довіра).
// ==========================================================================

Singleton {
    id: root

    property bool available: true
    property bool enabled: Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
    property string adapterName: Bluetooth.defaultAdapter ? (Bluetooth.defaultAdapter.name || "Bluetooth") : ""
    property bool scanning: false

    property string connectionState: "idle" // "idle" | "connecting" | "disconnecting" | "pairing" | "error"
    property string statusMessage: ""
    property string pendingMac: ""

    property var devices: [] // [{ mac, name, connected, paired, trusted, blocked, icon, battery }]

    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property var pairedDevices: devices.filter(d => d.paired && !d.connected)
    readonly property var discoveredDevices: devices.filter(d => !d.paired && !d.connected)
    readonly property int connectedCount: connectedDevices.length

    property int subscribers: 0
    readonly property bool active: subscribers > 0

    function subscribe() {
        subscribers += 1
        if (subscribers === 1) refresh()
    }
    function unsubscribe() {
        subscribers = Math.max(0, subscribers - 1)
    }

    // Реактивне оновлення з BlueZ D-Bus
    Connections {
        target: Bluetooth.defaultAdapter || null
        function onEnabledChanged() {
            root.enabled = Bluetooth.defaultAdapter ? Bluetooth.defaultAdapter.enabled : false
            root.refresh()
        }
        function onDiscoveringChanged() {
            if (Bluetooth.defaultAdapter) root.scanning = Bluetooth.defaultAdapter.discovering
        }
    }

    Timer {
        id: pollTimer
        interval: root.scanning ? 2000 : 4000
        repeat: true
        running: root.active && root.enabled
        onTriggered: root.refresh()
    }

    // Запит статусу через швидкий допоміжний скрипт
    Process {
        id: queryProc
        command: ["python3", Quickshell.env("HOME") + "/Dotfiles/quickshell/bar/scripts/btquery.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text || !text.trim()) return
                try {
                    const data = JSON.parse(text)
                    root.available = data.available !== false
                    if (data.adapter && data.adapter.length > 0) root.adapterName = data.adapter
                    if (!Bluetooth.defaultAdapter) root.enabled = data.powered === true
                    if (Array.isArray(data.devices)) {
                        root.devices = data.devices
                    }
                    if (data.discovering !== undefined && !scanProc.running) {
                        root.scanning = data.discovering
                    }
                } catch (e) {
                    console.warn("BluetoothService parse error:", e)
                }
            }
        }
    }

    function refresh() {
        if (!queryProc.running) queryProc.running = true
    }

    function togglePower() {
        if (Bluetooth.defaultAdapter) {
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
        }
        powerProc.command = ["bluetoothctl", "power", root.enabled ? "off" : "on"]
        powerProc.running = true
    }

    Process {
        id: powerProc
        onExited: root.refresh()
    }

    function startScan() {
        if (root.scanning) return
        root.scanning = true
        root.statusMessage = ""
        if (Bluetooth.defaultAdapter) {
            try { Bluetooth.defaultAdapter.discovering = true } catch (e) {}
        }
        scanProc.command = ["bluetoothctl", "--timeout", "15", "scan", "on"]
        scanProc.running = true
    }

    function stopScan() {
        root.scanning = false
        if (Bluetooth.defaultAdapter) {
            try { Bluetooth.defaultAdapter.discovering = false } catch (e) {}
        }
        if (scanProc.running) {
            scanProc.terminate()
        }
        stopScanProc.command = ["bluetoothctl", "scan", "off"]
        stopScanProc.running = true
    }

    Process {
        id: scanProc
        onExited: {
            root.scanning = false
            root.refresh()
        }
    }
    Process {
        id: stopScanProc
        onExited: root.refresh()
    }

    function connectDevice(mac) {
        root.pendingMac = mac
        root.connectionState = "connecting"
        root.statusMessage = ""
        connectProc.command = ["bluetoothctl", "connect", mac]
        connectProc.running = true
    }

    Process {
        id: connectProc
        stderr: StdioCollector { id: connectErr }
        onExited: (code) => {
            root.pendingMac = ""
            if (code === 0) {
                root.connectionState = "idle"
                root.statusMessage = ""
            } else {
                root.connectionState = "error"
                root.statusMessage = connectErr.text.trim() || "Помилка підключення"
            }
            root.refresh()
        }
    }

    function disconnectDevice(mac) {
        root.pendingMac = mac
        root.connectionState = "disconnecting"
        disconnectProc.command = ["bluetoothctl", "disconnect", mac]
        disconnectProc.running = true
    }

    Process {
        id: disconnectProc
        onExited: {
            root.pendingMac = ""
            root.connectionState = "idle"
            root.refresh()
        }
    }

    function pairDevice(mac) {
        root.pendingMac = mac
        root.connectionState = "pairing"
        root.statusMessage = ""
        pairProc.command = ["bluetoothctl", "pair", mac]
        pairProc.running = true
    }

    Process {
        id: pairProc
        stderr: StdioCollector { id: pairErr }
        onExited: (code) => {
            root.pendingMac = ""
            if (code === 0) {
                root.connectionState = "idle"
            } else {
                root.connectionState = "error"
                root.statusMessage = pairErr.text.trim() || "Помилка сполучення"
            }
            root.refresh()
        }
    }

    function unpairDevice(mac) {
        removeProc.command = ["bluetoothctl", "remove", mac]
        removeProc.running = true
    }

    Process {
        id: removeProc
        onExited: root.refresh()
    }

    function toggleTrust(mac, currentTrusted) {
        trustProc.command = ["bluetoothctl", currentTrusted ? "untrust" : "trust", mac]
        trustProc.running = true
    }

    Process {
        id: trustProc
        onExited: root.refresh()
    }

    Component.onCompleted: refresh()
}
