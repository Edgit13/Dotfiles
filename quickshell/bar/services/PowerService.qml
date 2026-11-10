pragma Singleton
import "root:/settings"
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

// PowerService — стан живлення для меню Power.
//  • батарея та профіль живлення — через Quickshell.Services.UPower (реактивно, без процесів);
//  • споживачі CPU/RAM — через scripts/powerwatch.py, який працює ЛИШЕ поки
//    меню відкрите (subscribe/unsubscribe), тому у фоні нічого не опитується.
Singleton {
    id: root

    property int subscribers: 0
    readonly property bool active: subscribers > 0
    function subscribe() { subscribers += 1 }
    function unsubscribe() { subscribers = Math.max(0, subscribers - 1) }

    // ───────── батарея ─────────
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.isPresent
        && (battery.type === UPowerDeviceType.Battery || battery.percentage > 0)
    readonly property real level: hasBattery ? Math.max(0, Math.min(100, (battery.percentage || 0) * 100)) : 0
    readonly property int state: battery ? battery.state : UPowerDeviceState.Unknown
    readonly property bool charging: state === UPowerDeviceState.Charging
        || state === UPowerDeviceState.PendingCharge
    readonly property bool discharging: state === UPowerDeviceState.Discharging
        || state === UPowerDeviceState.PendingDischarge
    readonly property bool full: state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: UPower.onBattery && !charging && !full
    readonly property real drawWatts: {
        if (!hasBattery)
            return 0
        const w = Math.abs(battery.changeRate || 0)
        return isFinite(w) ? w : 0
    }
    readonly property real energyWh: hasBattery ? (battery.energy || 0) : 0
    readonly property real capacityWh: hasBattery ? (battery.energyCapacity || 0) : 0
    readonly property real _upHealth: {
        if (!hasBattery || !battery.healthSupported)
            return -1
        const h = Number(battery.healthPercentage)
        if (!isFinite(h) || h <= 0)
            return -1
        return h <= 1.5 ? h * 100 : h     // деякі версії віддають частку, не відсотки
    }
    readonly property real health: _upHealth > 0 ? _upHealth
        : (sysDesignWh > 0 && capacityWh > 0 ? Math.min(100, capacityWh * 100 / sysDesignWh) : -1)
    // повна ємність / health = проєктна ємність (UPower не завжди віддає її окремо)
    readonly property real designWh: sysDesignWh > 0 ? sysDesignWh
        : (health > 0 && capacityWh > 0 ? capacityWh * 100 / health : 0)
    readonly property int secondsLeft: !hasBattery ? 0 : Math.max(0, Math.round(
        charging ? (battery.timeToFull || 0) : (battery.timeToEmpty || 0)))

    // додаткові дані з sysfs через powerwatch.py
    property int sysCycles: -1
    property real sysDesignWh: 0
    property real sysFullWh: 0
    readonly property int cycles: sysCycles > 0 ? sysCycles : -1

    // ───────── профіль живлення ─────────
    readonly property bool hasPerformance: PowerProfiles.hasPerformanceProfile
    readonly property int profileIndex: PowerProfiles.profile === PowerProfile.PowerSaver ? 0
        : PowerProfiles.profile === PowerProfile.Balanced ? 1 : 2
    function setProfileIndex(i) {
        if (i === 0)
            PowerProfiles.profile = PowerProfile.PowerSaver
        else if (i === 1)
            PowerProfiles.profile = PowerProfile.Balanced
        else if (PowerProfiles.hasPerformanceProfile)
            PowerProfiles.profile = PowerProfile.Performance
    }

    // ───────── семплер процесів ─────────
    readonly property string launcher:
        'for d in "$HOME/.config/quickshell/bar/scripts" "$HOME/.config/quickshell/scripts"; do ' +
        '[ -f "$d/powerwatch.py" ] && exec python3 "$d/powerwatch.py"; done; ' +
        'echo "powerwatch.py not found in ~/.config/quickshell/{bar/,}scripts" >&2; exit 127'

    property bool ready: false
    property int ticks: 0
    property int ncpu: 1
    property real cpu: 0
    property real ramPercent: 0
    property real ramUsed: 0
    property real ramTotal: 0
    property real temp: 0
    property real load: 0
    property real busyCpu: 0        // сума CPU усіх процесів; 100 = одне ядро
    property var top: []

    // вати чесно розподіляємо лише під час розряду; інакше — лише CPU/пам'ять
    readonly property bool estimating: onBattery && drawWatts > 0.1 && busyCpu > 0.1
    function wattsFor(p) {
        if (!estimating || !p || !p.cpu)
            return -1
        return drawWatts * (Number(p.cpu) / busyCpu)
    }

    property bool _alive: true
    onActiveChanged: {
        if (!active) {
            ready = false
            ticks = 0
        }
    }

    function _line(text) {
        let o
        try { o = JSON.parse(text) } catch (e) { return }
        if (o.t !== "snap")
            return
        ncpu = o.ncpu || 1
        cpu = Number(o.cpu) || 0
        ramPercent = Number(o.ram) || 0
        ramUsed = Number(o.ramUsed) || 0
        ramTotal = Number(o.ramTotal) || 0
        temp = Number(o.temp) || 0
        load = Number(o.load) || 0
        busyCpu = Number(o.busyCpu) || 0
        top = o.top || []
        const b = o.battery || {}
        if (b.cycles !== undefined)
            sysCycles = Number(b.cycles) || -1
        sysDesignWh = Number(b.designWh) || 0
        sysFullWh = Number(b.fullWh) || 0
        ticks += 1
        ready = true
    }

    Process {
        id: proc
        command: ["sh", "-c", root.launcher]
        running: root.active && root._alive
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root._line(data) }
        stderr: SplitParser { onRead: data => console.warn("[Power] " + data) }
        onExited: (code, status) => {
            if (code !== 0)
                console.warn("[Power] powerwatch exited, code " + code)
            root.ready = false
            root.ticks = 0
            if (root.active) {
                root._alive = false
                restart.start()
            }
        }
    }
    Timer {
        id: restart
        interval: 4000
        onTriggered: root._alive = true
    }
}
