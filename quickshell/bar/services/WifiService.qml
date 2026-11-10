pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// ==========================================================================
// WifiService.qml — бекенд Network Manager+ для Edots Quickshell.
// Повне керування мережами: Wi-Fi сканування та підключення, Ethernet стан
// та швидкість, VPN з'єднання, збережені профілі, IP/Шлюз/DNS та діагностика.
// ==========================================================================

Singleton {
    id: root

    // "idle" | "scanning" | "connecting" | "connected" | "failed" | "passwordRequired"
    property string connectionState: "idle"
    property string connectionError: ""
    property string pendingSsid: ""

    property bool scanning: false
    property var networks: [] // [{ ssid, signal, security, secured, inUse }]

    readonly property var currentNetwork: networks.find(n => n.inUse) || null

    // ---- Network Manager+ розширення ----
    property var ethernetDevices: [] // [{ device, state, connection, connected, speed }]
    property var vpnConnections: []  // [{ name, type, uuid, device, active }]
    property var savedConnections: []// [{ name, type, uuid, device, active }]
    property var ipDetails: ({ ip: "", gateway: "", dns: [], interface: "" })
    property var diagnostics: ({ tested: false, gateway_ok: false, internet_ok: false, latency: -1.0 })
    property bool diagRunning: false

    readonly property bool hasEthernet: ethernetDevices.some(d => d.connected)
    readonly property bool hasVpn: vpnConnections.some(v => v.active)

    // Розбиває рядок `nmcli -t` по неекранованих ':' і знімає екранування.
    function _splitTerse(line) {
        const out = []
        let cur = ""
        for (let i = 0; i < line.length; i++) {
            const c = line[i]
            if (c === "\\" && i + 1 < line.length) { cur += line[++i]; continue }
            if (c === ":") { out.push(cur); cur = ""; continue }
            cur += c
        }
        out.push(cur)
        return out
    }

    function scan() {
        if (scanning) return
        scanning = true
        rescanProc.running = true
        refreshInfo(false)
    }

    Process {
        id: rescanProc
        command: ["nmcli", "device", "wifi", "rescan"]
        onExited: listProc.running = true
    }

    Process {
        id: listProc
        command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = []
                const lines = text.split("\n")
                for (const line of lines) {
                    if (!line.trim()) continue
                    // Розбивка nmcli -t з урахуванням екранованих \: та \\ (без lookbehind —
                    // QML JS-рушій його не підтримує, через що весь рядок лишався одним полем)
                    const parts = root._splitTerse(line)
                    const ssid = parts[0]
                    if (!ssid) continue // приховані/порожні SSID пропускаємо
                    const signal = parseInt(parts[1], 10) || 0
                    const security = (parts[2] || "").trim()
                    const inUse = (parts[3] || "").trim() === "*"

                    // Уникаємо дублікатів (та сама мережа з кількох BSSID)
                    if (parsed.some(n => n.ssid === ssid)) continue

                    parsed.push({
                        ssid: ssid,
                        signal: signal,
                        security: security,
                        secured: security !== "" && security !== "--",
                        inUse: inUse
                    })
                }
                parsed.sort((a, b) => b.signal - a.signal)
                root.networks = parsed
                root.scanning = false
            }
        }
    }

    function toggleWifi() {
        wifiToggleProc.command = ["nmcli", "radio", "wifi", Networking.wifiEnabled ? "off" : "on"]
        wifiToggleProc.running = true
    }
    Process { id: wifiToggleProc }

    function connectTo(ssid, password) {
        root.pendingSsid = ssid
        root.connectionState = "connecting"
        root.connectionError = ""

        connectProc.command = password
            ? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
            : ["nmcli", "device", "wifi", "connect", ssid]
        connectProc.running = true
    }

    Process {
        id: connectProc
        stdout: StdioCollector {}
        stderr: StdioCollector { id: connectErr }
        onExited: (exitCode) => {
            if (exitCode === 0) {
                root.connectionState = "connected"
                root.scan()
            } else {
                root.connectionState = "failed"
                root.connectionError = "Не вдалося підключитись"
            }
        }
    }

    function requestConnect(ssid) {
        const net = root.networks.find(n => n.ssid === ssid)
        if (net && net.secured) {
            root.pendingSsid = ssid
            root.connectionState = "passwordRequired"
        } else {
            root.connectTo(ssid, "")
        }
    }

    function disconnectCurrent() {
        if (!root.currentNetwork) return
        disconnectProc.command = ["nmcli", "connection", "down", "id", root.currentNetwork.ssid]
        disconnectProc.running = true
    }

    Process {
        id: disconnectProc
        onExited: root.scan()
    }

    function cancelPassword() {
        root.connectionState = "idle"
        root.pendingSsid = ""
    }

    // ---- Network Manager+: опитування Ethernet / VPN / IP / Діагностики ----
    function refreshInfo(runPing) {
        if (netInfoProc.running) return
        if (runPing) root.diagRunning = true
        netInfoProc.command = runPing
            ? ["python3", Quickshell.env("HOME") + "/Dotfiles/quickshell/bar/scripts/netinfo.py", "--ping"]
            : ["python3", Quickshell.env("HOME") + "/Dotfiles/quickshell/bar/scripts/netinfo.py"]
        netInfoProc.running = true
    }

    Process {
        id: netInfoProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.diagRunning = false
                if (!text || !text.trim()) return
                try {
                    const data = JSON.parse(text)
                    if (Array.isArray(data.ethernet)) root.ethernetDevices = data.ethernet
                    if (Array.isArray(data.vpn)) root.vpnConnections = data.vpn
                    if (Array.isArray(data.saved)) root.savedConnections = data.saved
                    if (data.details) root.ipDetails = data.details
                    if (data.diag && data.diag.tested) root.diagnostics = data.diag
                } catch (e) {
                    console.warn("WifiService netinfo parse error:", e)
                }
            }
        }
    }

    function connectVpn(uuid) {
        vpnUpProc.command = ["nmcli", "connection", "up", "uuid", uuid]
        vpnUpProc.running = true
    }
    Process {
        id: vpnUpProc
        onExited: root.refreshInfo(false)
    }

    function disconnectVpn(uuid) {
        vpnDownProc.command = ["nmcli", "connection", "down", "uuid", uuid]
        vpnDownProc.running = true
    }
    Process {
        id: vpnDownProc
        onExited: root.refreshInfo(false)
    }

    function deleteSaved(uuid) {
        delConnProc.command = ["nmcli", "connection", "delete", "uuid", uuid]
        delConnProc.running = true
    }
    Process {
        id: delConnProc
        onExited: {
            root.refreshInfo(false)
            root.scan()
        }
    }

    function runDiagnostics() {
        refreshInfo(true)
    }

    Component.onCompleted: {
        scan()
        refreshInfo(false)
    }
}
