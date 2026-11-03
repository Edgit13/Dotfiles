import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import "root:/widgets"
import Quickshell
import Quickshell.Networking
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// WifiSurface.qml — Material 3 Expressive & Nothing OS Network Manager+.
// Вкладки: Wi-Fi, Ethernet, VPN, Деталі та Діагностика з'єднання.
// Збережено 100% функціоналу підключення/паролів до Wi-Fi.
// ==========================================================================

Item {
    id: root

    property string passwordInput: ""
    property int currentTab: 0 // 0: Wi-Fi, 1: Ethernet, 2: VPN, 3: Деталі

    readonly property bool nothing: Theme.settings.nothing

    Component.onCompleted: {
        WifiService.scan()
        WifiService.refreshInfo(false)
    }

    function signalIcon(signalPct) {
        const s = signalPct / 100
        if (s >= 0.75) return "\ue1ba"
        if (s >= 0.50) return "\uebe1"
        if (s >= 0.25) return "\uebd6"
        return "\uebe4"
    }

    // ---- M3 мережевий рядок ----
    component NetworkRow: Rectangle {
        id: row
        property string ssid: ""
        property int signalPct: 0
        property bool secured: false
        property bool inUse: false
        signal clicked()

        readonly property bool nothing: Theme.settings.nothing
        readonly property color inkColor: Colors.fg

        Layout.fillWidth: true
        Layout.preferredHeight: nothing ? 44 : 40
        radius: nothing ? ThemeNothing.corners.md - 2 : Md.rM
        color: nothing
            ? (row.inUse ? Qt.rgba(inkColor.r, inkColor.g, inkColor.b, 0.07)
               : rowMa.containsMouse ? Qt.rgba(inkColor.r, inkColor.g, inkColor.b, 0.05) : "transparent")
            : (row.inUse ? Md.primaryContainer
               : (rowMa.containsMouse ? Md.hoverOf(Md.surfaceContainerHigh) : Md.surfaceContainerHigh))
        border.width: nothing && row.inUse ? 1 : 0
        border.color: Qt.rgba(inkColor.r, inkColor.g, inkColor.b, 0.30)
        Behavior on color { ColorAnimation { duration: Md.durFast } }

        Rectangle {
            visible: row.nothing
            x: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 6; height: 6; radius: 3
            color: ThemeNothing.red
            opacity: row.inUse ? 1 : 0
            scale: row.inUse ? 1 : 0.2
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: row.nothing ? 24 : 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                visible: !row.nothing
                text: root.signalIcon(row.signalPct)
                color: row.inUse ? Md.primary : Md.m3OnSurfaceVariant
                font { family: "Material Symbols Rounded"; pixelSize: 16 }
            }
            Row {
                visible: row.nothing
                spacing: 2
                height: 13
                Layout.alignment: Qt.AlignVCenter
                Repeater {
                    model: 4
                    delegate: Rectangle {
                        required property int index
                        width: 3; height: 4 + index * 3; radius: 1.5
                        y: 13 - height
                        color: row.inkColor
                        opacity: row.signalPct >= (index + 1) * 25 - 12 ? 1.0 : ThemeNothing.dotOpacityOff
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                text: row.ssid
                color: row.nothing ? row.inkColor : (row.inUse ? Md.m3OnPrimaryContainer : Md.m3OnSurface)
                font { family: Colors.uiFont; pixelSize: 12; weight: row.inUse ? 600 : 400 }
                elide: Text.ElideRight
            }
            Text {
                visible: row.secured
                text: "\ue899"
                color: Md.m3OnSurfaceVariant
                font { family: "Material Symbols Rounded"; pixelSize: 13 }
            }
            Text {
                text: row.signalPct + "%"
                color: Md.m3OnSurfaceVariant
                font { family: Colors.monoFont; pixelSize: 11; letterSpacing: row.nothing ? 1 : 0 }
                Layout.preferredWidth: 36
            }
        }

        MouseArea {
            id: rowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.clicked()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.sm

        // ---- ПЕРЕМИКАЧ ВКЛАДОК (M3 Segmented / Nothing style) ----
        MaterialSegmented {
            options: [
                { label: Lang.t("net.tab.wifi") },
                { label: Lang.t("net.tab.ethernet") },
                { label: Lang.t("net.tab.vpn") },
                { label: Lang.t("net.tab.details") }
            ]
            selectedIndex: root.currentTab
            onSelected: index => root.currentTab = index
        }

        // ==================================================================
        // ВКЛАДКА 0: WI-FI МЕРЕЖІ
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 0

            // Головний список
            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                visible: WifiService.connectionState !== "passwordRequired" && WifiService.connectionState !== "connecting"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "\ue63e"
                        color: Md.primary
                        font { family: "Material Symbols Rounded"; pixelSize: 18 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "Wi-Fi"
                        color: Md.m3OnSurface
                        font { family: Colors.uiFont; pixelSize: 13; weight: 600 }
                    }

                    // Лоадер при скануванні
                    LoadingIndicator {
                        visible: WifiService.scanning
                        size: 22
                    }
                    Text {
                        visible: !WifiService.scanning
                        text: "\ue5d5"
                        color: refreshHover.hovered ? Md.primary : Md.m3OnSurfaceVariant
                        font { family: "Material Symbols Rounded"; pixelSize: 17 }
                        HoverHandler { id: refreshHover }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WifiService.scan()
                        }
                    }

                    // M3 switch Wi-Fi on/off
                    Rectangle {
                        width: 52
                        height: 32
                        radius: 16
                        color: Networking.wifiEnabled ? Md.primary : "transparent"
                        border.width: Networking.wifiEnabled ? 0 : 2
                        border.color: Md.outline
                        Rectangle {
                            width: Networking.wifiEnabled ? 24 : 16
                            height: width
                            radius: width / 2
                            x: Networking.wifiEnabled ? parent.width - width - 4 : 6
                            anchors.verticalCenter: parent.verticalCenter
                            color: Networking.wifiEnabled ? Md.m3OnPrimary : Md.outline
                            Behavior on x { NumberAnimation { duration: Md.durMed; easing.type: Easing.OutCubic } }
                            Behavior on width { NumberAnimation { duration: Md.durFast } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WifiService.toggleWifi()
                        }
                    }
                }

                // Поточне підключення
                RowLayout {
                    Layout.fillWidth: true
                    visible: WifiService.currentNetwork !== null
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        text: WifiService.currentNetwork ? ("Підключено: " + WifiService.currentNetwork.ssid) : ""
                        color: Md.primary
                        font { family: Colors.uiFont; pixelSize: 11 }
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "\ue16f"
                        color: disconnectHover.hovered ? Md.error : Md.m3OnSurfaceVariant
                        font { family: "Material Symbols Rounded"; pixelSize: 15 }
                        HoverHandler { id: disconnectHover }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WifiService.disconnectCurrent()
                        }
                    }
                }

                // Помилка
                RowLayout {
                    Layout.fillWidth: true
                    visible: WifiService.connectionState === "failed"
                    spacing: 6
                    Text {
                        text: "\uf8b6"
                        color: Md.error
                        font { family: "Material Symbols Rounded"; pixelSize: 14 }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: WifiService.connectionError + " (" + WifiService.pendingSsid + ")"
                        color: Md.error
                        font { family: Colors.uiFont; pixelSize: 10 }
                        elide: Text.ElideRight
                    }
                    Text {
                        text: "Повторити"
                        color: Md.primary
                        font { family: Colors.uiFont; pixelSize: 10; underline: true }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: WifiService.requestConnect(WifiService.pendingSsid)
                        }
                    }
                }

                // Список мереж
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: networksCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: networksCol
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: !Networking.wifiEnabled
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 20
                            text: "Увімкни Wi-Fi, щоб побачити мережі"
                            color: Md.m3OnSurfaceVariant
                            font { family: Colors.uiFont; pixelSize: 11 }
                        }

                        Text {
                            visible: Networking.wifiEnabled && !WifiService.scanning && WifiService.networks.length === 0
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 20
                            text: "Мереж не знайдено"
                            color: Md.m3OnSurfaceVariant
                            font { family: Colors.uiFont; pixelSize: 11 }
                        }

                        Repeater {
                            model: Networking.wifiEnabled ? WifiService.networks : []
                            delegate: NetworkRow {
                                required property var modelData
                                ssid: modelData.ssid
                                signalPct: modelData.signal
                                secured: modelData.secured
                                inUse: modelData.inUse
                                onClicked: WifiService.requestConnect(modelData.ssid)
                            }
                        }
                    }
                }
            }

            // Ввід пароля / підключення
            ColumnLayout {
                anchors.fill: parent
                spacing: 12
                visible: WifiService.connectionState === "passwordRequired" || WifiService.connectionState === "connecting"

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: "\ue5c4"
                        color: backHover.hovered ? Md.primary : Md.m3OnSurfaceVariant
                        font { family: "Material Symbols Rounded"; pixelSize: 16 }
                        HoverHandler { id: backHover }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            enabled: WifiService.connectionState === "passwordRequired"
                            onClicked: WifiService.cancelPassword()
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: WifiService.pendingSsid
                        color: Md.m3OnSurface
                        font { family: Colors.uiFont; pixelSize: 13; weight: 600 }
                        elide: Text.ElideRight
                    }
                }

                // Лоадер при підключенні
                RowLayout {
                    visible: WifiService.connectionState === "connecting"
                    spacing: 10
                    LoadingIndicator { size: 26 }
                    Text {
                        text: "Підключення..."
                        color: Md.m3OnSurfaceVariant
                        font { family: Colors.uiFont; pixelSize: 12 }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    visible: WifiService.connectionState === "passwordRequired"
                    radius: Md.rS
                    color: Md.surfaceContainerLow
                    border.width: pwInput.activeFocus ? 2 : 1
                    border.color: pwInput.activeFocus ? Md.primary : Md.outlineVariant

                    TextInput {
                        id: pwInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        color: Md.m3OnSurface
                        font { family: Colors.uiFont; pixelSize: 12 }
                        echoMode: TextInput.Password
                        focus: WifiService.connectionState === "passwordRequired"
                        text: root.passwordInput
                        onTextChanged: root.passwordInput = text

                        Keys.onReturnPressed: root.submitPw()
                        Keys.onEnterPressed: root.submitPw()
                    }
                }

                Text {
                    visible: WifiService.connectionState === "passwordRequired"
                    text: "Enter \u2014 підключитись"
                    color: Md.m3OnSurfaceVariant
                    font { family: Colors.uiFont; pixelSize: 9; italic: true }
                }
            }
        }

        // ==================================================================
        // ВКЛАДКА 1: ETHERNET
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 1

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.space.md

                ThemedText {
                    text: Lang.t("net.eth.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                Repeater {
                    model: WifiService.ethernetDevices
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(56)
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: modelData.connected
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07) : Theme.color.primaryContainer)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainer)
                        border.width: 1
                        border.color: modelData.connected
                                      ? (root.nothing ? ThemeNothing.red : Theme.color.primary)
                                      : Theme.color.outlineVariant

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.md

                            Text {
                                text: "\ue0be" // router / settings_ethernet
                                color: modelData.connected ? (root.nothing ? ThemeNothing.red : Theme.color.fgPrimaryContainer) : Theme.color.outline
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                ThemedText {
                                    text: (modelData.connection || modelData.device)
                                    style: Theme.type.titleSmall
                                    emphasized: true
                                    color: modelData.connected ? (root.nothing ? Colors.fg : Theme.color.fgPrimaryContainer) : Theme.color.fgSurface
                                }
                                ThemedText {
                                    text: modelData.device + (modelData.speed > 0 ? (" • " + modelData.speed + " Mb/s") : "")
                                    style: Theme.type.bodySmall
                                    color: modelData.connected ? (root.nothing ? Colors.grey2 : Theme.color.fgPrimaryContainer) : Theme.color.outline
                                }
                            }

                            Rectangle {
                                implicitWidth: statusLbl.implicitWidth + Theme.space.md * 2
                                implicitHeight: Theme.components.dp(24)
                                radius: height / 2
                                color: modelData.connected ? Theme.color.primary : Theme.color.surfaceContainerHighest
                                ThemedText {
                                    id: statusLbl
                                    anchors.centerIn: parent
                                    text: modelData.connected ? Lang.t("net.eth.connected") : Lang.t("net.eth.disconnected")
                                    style: Theme.type.labelSmall
                                    color: modelData.connected ? Theme.color.fgPrimary : Theme.color.outline
                                }
                            }
                        }
                    }
                }

                // Якщо немає Ethernet
                Item {
                    visible: WifiService.ethernetDevices.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    ThemedText {
                        anchors.centerIn: parent
                        text: "Мережевих адаптерів Ethernet не знайдено"
                        style: Theme.type.bodySmall
                        color: Theme.color.outline
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ==================================================================
        // ВКЛАДКА 2: VPN З'ЄДНАННЯ
        // ==================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 2

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.space.md

                ThemedText {
                    text: Lang.t("net.vpn.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                // Якщо VPN немає
                Item {
                    visible: WifiService.vpnConnections.length === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space.sm
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\ue899"
                            color: Theme.color.outline
                            font { family: Theme.type.icons; pixelSize: Theme.components.dp(36) }
                        }
                        ThemedText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Lang.t("net.vpn.empty")
                            style: Theme.type.bodyMedium
                            color: Theme.color.outline
                        }
                    }
                }

                Repeater {
                    model: WifiService.vpnConnections
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(52)
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: modelData.active
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.08) : Theme.color.secondaryContainer)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainer)
                        border.width: 1
                        border.color: modelData.active
                                      ? (root.nothing ? ThemeNothing.red : Theme.color.secondary)
                                      : Theme.color.outlineVariant

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.space.md
                            spacing: Theme.space.md

                            Text {
                                text: "\ue8e8" // vpn_key / shield
                                color: modelData.active ? (root.nothing ? ThemeNothing.red : Theme.color.fgSecondaryContainer) : Theme.color.outline
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                ThemedText {
                                    text: modelData.name
                                    style: Theme.type.titleSmall
                                    emphasized: true
                                }
                                ThemedText {
                                    text: modelData.type
                                    style: Theme.type.labelSmall
                                    color: Theme.color.outline
                                }
                            }

                            MaterialButton {
                                text: modelData.active ? Lang.t("net.vpn.disconnect") : Lang.t("net.vpn.connect")
                                style: modelData.active ? "outlined" : "filled"
                                onClicked: {
                                    if (modelData.active) WifiService.disconnectVpn(modelData.uuid)
                                    else WifiService.connectVpn(modelData.uuid)
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ==================================================================
        // ВКЛАДКА 3: ДЕТАЛІ ТА ДІАГНОСТИКА
        // ==================================================================
        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.currentTab === 3
            clip: true
            contentWidth: width
            contentHeight: detailsCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: detailsCol
                width: parent.width
                spacing: Theme.space.md

                // 1. IP & Інтерфейс Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: ipCol.implicitHeight + Theme.space.md * 2
                    radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                    color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                    border.width: 1
                    border.color: Theme.color.outlineVariant

                    ColumnLayout {
                        id: ipCol
                        anchors.fill: parent
                        anchors.margins: Theme.space.md
                        spacing: Theme.space.sm

                        ThemedText {
                            text: Lang.t("net.tab.details")
                            style: Theme.type.labelMedium
                            emphasized: true
                            color: Theme.color.primary
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            ThemedText { text: Lang.t("net.details.interface") + ":"; style: Theme.type.bodySmall; color: Theme.color.outline }
                            Item { Layout.fillWidth: true }
                            ThemedText { text: WifiService.ipDetails.interface || "—"; style: Theme.type.bodySmall; emphasized: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedText { text: Lang.t("net.details.ip") + ":"; style: Theme.type.bodySmall; color: Theme.color.outline }
                            Item { Layout.fillWidth: true }
                            ThemedText { text: WifiService.ipDetails.ip || "—"; style: Theme.type.bodySmall; emphasized: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedText { text: Lang.t("net.diag.gateway") + ":"; style: Theme.type.bodySmall; color: Theme.color.outline }
                            Item { Layout.fillWidth: true }
                            ThemedText { text: WifiService.ipDetails.gateway || "—"; style: Theme.type.bodySmall; emphasized: true }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedText { text: Lang.t("net.diag.dns") + ":"; style: Theme.type.bodySmall; color: Theme.color.outline }
                            Item { Layout.fillWidth: true }
                            ThemedText { text: WifiService.ipDetails.dns.join(", ") || "—"; style: Theme.type.bodySmall; emphasized: true }
                        }
                    }
                }

                // 2. Діагностика з'єднання Card
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: diagCol.implicitHeight + Theme.space.md * 2
                    radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                    color: root.nothing ? "transparent" : Theme.color.surfaceContainer
                    border.width: 1
                    border.color: Theme.color.outlineVariant

                    ColumnLayout {
                        id: diagCol
                        anchors.fill: parent
                        anchors.margins: Theme.space.md
                        spacing: Theme.space.sm

                        RowLayout {
                            Layout.fillWidth: true
                            ThemedText {
                                Layout.fillWidth: true
                                text: Lang.t("net.diag.title")
                                style: Theme.type.labelMedium
                                emphasized: true
                                color: Theme.color.primary
                            }
                            MaterialButton {
                                text: Lang.t("net.diag.run")
                                style: "tonal"
                                enabled_: !WifiService.diagRunning
                                onClicked: WifiService.runDiagnostics()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: WifiService.diagnostics.gateway_ok ? "\ue86c" : "\ue5c9"
                                color: WifiService.diagnostics.gateway_ok ? Theme.color.success : Theme.color.error
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            }
                            ThemedText { text: Lang.t("net.diag.gateway"); style: Theme.type.bodySmall }
                            Item { Layout.fillWidth: true }
                            ThemedText {
                                text: WifiService.diagnostics.tested ? (WifiService.diagnostics.gateway_ok ? "Досяжний" : "Недоступний") : "—"
                                style: Theme.type.labelSmall
                                color: WifiService.diagnostics.gateway_ok ? Theme.color.success : Theme.color.outline
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: WifiService.diagnostics.internet_ok ? "\ue86c" : "\ue5c9"
                                color: WifiService.diagnostics.internet_ok ? Theme.color.success : Theme.color.error
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            }
                            ThemedText { text: Lang.t("net.diag.internet"); style: Theme.type.bodySmall }
                            Item { Layout.fillWidth: true }
                            ThemedText {
                                text: WifiService.diagnostics.tested ? (WifiService.diagnostics.internet_ok ? "З'єднано" : "Офлайн") : "—"
                                style: Theme.type.labelSmall
                                color: WifiService.diagnostics.internet_ok ? Theme.color.success : Theme.color.outline
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: "\ue8b5" // timer / speed
                                color: Theme.color.outline
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            }
                            ThemedText { text: Lang.t("net.diag.latency"); style: Theme.type.bodySmall }
                            Item { Layout.fillWidth: true }
                            ThemedText {
                                text: WifiService.diagnostics.latency > 0 ? (WifiService.diagnostics.latency + " ms") : "—"
                                style: Theme.type.monoMedium
                                color: Theme.color.fgSurface
                            }
                        }
                    }
                }

                // 3. Збережені мережі (з можливістю видалення)
                ThemedText {
                    text: Lang.t("net.saved.title")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.outline
                }

                Repeater {
                    model: WifiService.savedConnections
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(44)
                        radius: root.nothing ? ThemeNothing.corners.sm : Theme.shape.sm
                        color: root.nothing ? "transparent" : Theme.color.surfaceContainerLow
                        border.width: 1
                        border.color: Theme.color.outlineVariant

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space.md
                            anchors.rightMargin: Theme.space.sm
                            spacing: Theme.space.sm

                            Text {
                                text: modelData.type.indexOf("wireless") >= 0 ? "\ue63e" : (modelData.type.indexOf("ethernet") >= 0 ? "\ue0be" : "\ue8e8")
                                color: Theme.color.fgSurfaceVariant
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                ThemedText {
                                    text: modelData.name
                                    style: Theme.type.bodySmall
                                    emphasized: true
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    text: modelData.type + (modelData.active ? " • Активне" : "")
                                    style: Theme.type.labelSmall
                                    color: modelData.active ? Theme.color.primary : Theme.color.outline
                                }
                            }

                            MaterialIconButton {
                                icon: "delete"
                                color: Theme.color.outline
                                tooltip: Lang.t("net.saved.forget")
                                onClicked: WifiService.deleteSaved(modelData.uuid)
                            }
                        }
                    }
                }
            }
        }
    }

    function submitPw() {
        if (pwInput.text.length > 0) {
            WifiService.connectTo(WifiService.pendingSsid, pwInput.text)
            root.passwordInput = ""
        }
    }
}
