import "root:/theme"
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// SystemCard — аватар, user @ host, ОС, чіпи WM + uptime.
DashCard {
    id: root

    property string osName: "Linux"
    property string wmName: "MangoWC"
    property string uptimeText: "—"
    property string hostName: ""
    readonly property string userName: Quickshell.env("USER") || "user"

    function _fmtUptime(sec) {
        const d = Math.floor(sec / 86400)
        const h = Math.floor((sec % 86400) / 3600)
        const m = Math.floor((sec % 3600) / 60)
        if (d > 0) return d + " д " + h + " год"
        if (h > 0) return h + " год " + m + " хв"
        return m + " хв"
    }

    Process {
        id: osProc
        command: ["sh", "-c", "grep '^PRETTY_NAME=' /etc/os-release | cut -d'\"' -f2"]
        stdout: StdioCollector { onStreamFinished: if (text.trim().length > 0) root.osName = text.trim() }
    }
    Process {
        id: hostProc
        command: ["hostname"]
        stdout: StdioCollector { onStreamFinished: root.hostName = text.trim() }
    }
    Process {
        id: upProc
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector { onStreamFinished: root.uptimeText = root._fmtUptime(parseFloat(text.split(" ")[0])) }
    }
    Timer {
        interval: 60000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { osProc.running = true; upProc.running = true; if (!root.hostName) hostProc.running = true }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Theme.space.lg

        DashAvatar { size: Theme.components.dp(72); Layout.alignment: Qt.AlignVCenter }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Theme.space.xs

            ThemedText {
                Layout.fillWidth: true
                text: root.userName + (root.hostName ? " @ " + root.hostName : "")
                style: Theme.type.titleLarge
                emphasized: true
                font.family: Theme.settings.nothing ? Theme.type.dot : style.family
                elide: Text.ElideRight
            }
            ThemedText {
                Layout.fillWidth: true
                text: root.osName
                style: Theme.type.bodySmall
                color: Theme.color.fgSurfaceVariant
                elide: Text.ElideRight
            }
            Row {
                spacing: Theme.space.xs
                InfoChip { icon: "\ue30d"; label: root.wmName }
                InfoChip { icon: "\ue425"; label: root.uptimeText }
            }
        }
    }
}
