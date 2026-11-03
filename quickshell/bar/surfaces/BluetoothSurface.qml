import "root:/theme"
import "root:/services"
import "root:/settings"
import "root:/settings/material"
import "root:/widgets"
import Quickshell
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// BluetoothSurface.qml — Material 3 Expressive & Nothing OS менеджер Bluetooth.
// Підтримка перегляду адаптера, сканування ефіру, списку підключених,
// збережених та нових пристроїв, відображення заряду батареї, сполучення/
// відключення та довіри.
// ==========================================================================

Item {
    id: root

    Component.onCompleted: BluetoothService.subscribe()
    Component.onDestruction: BluetoothService.unsubscribe()

    readonly property bool nothing: Theme.settings.nothing

    function getDeviceIcon(icon, devName) {
        const i = (icon || "").toLowerCase()
        const n = (devName || "").toLowerCase()
        if (i.indexOf("headset") >= 0 || i.indexOf("headphones") >= 0 || n.indexOf("jbl") >= 0 || n.indexOf("buds") >= 0 || n.indexOf("airpod") >= 0) return "\ue310"
        if (i.indexOf("audio") >= 0 || i.indexOf("speaker") >= 0 || n.indexOf("speaker") >= 0 || n.indexOf("sound") >= 0) return "\ue050"
        if (i.indexOf("phone") >= 0 || n.indexOf("phone") >= 0 || n.indexOf("note") >= 0 || n.indexOf("galaxy") >= 0) return "\ue32c"
        if (i.indexOf("keyboard") >= 0 || n.indexOf("keyboard") >= 0 || n.indexOf("kb") >= 0) return "\ue312"
        if (i.indexOf("mouse") >= 0 || n.indexOf("mouse") >= 0) return "\ue323"
        if (i.indexOf("gamepad") >= 0 || i.indexOf("gaming") >= 0 || n.indexOf("controller") >= 0) return "\ue338"
        if (i.indexOf("computer") >= 0 || i.indexOf("laptop") >= 0) return "\ue30a"
        return "\ue1a7"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.space.md

        // ---- ЗАГОЛОВОК І ТОГЛ АДАПТЕРА ----
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.components.dp(54)
            radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
            color: root.nothing ? "transparent" : Theme.color.surfaceContainer
            border.width: root.nothing ? 1 : 0
            border.color: Theme.color.outlineVariant

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space.md
                anchors.rightMargin: Theme.space.md
                spacing: Theme.space.sm

                Rectangle {
                    implicitWidth: Theme.components.dp(34)
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: BluetoothService.enabled
                           ? (root.nothing ? ThemeNothing.red : Theme.color.primary)
                           : Theme.color.surfaceContainerHighest

                    Text {
                        anchors.centerIn: parent
                        text: "\ue1a7"
                        color: BluetoothService.enabled ? (root.nothing ? Colors.fg : Theme.color.fgPrimary) : Theme.color.outline
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    ThemedText {
                        text: Lang.t("bt.title")
                        style: Theme.type.titleSmall
                        emphasized: true
                    }
                    ThemedText {
                        text: !BluetoothService.enabled
                              ? Lang.t("bt.status.off")
                              : (BluetoothService.scanning
                                 ? Lang.t("bt.status.scanning")
                                 : (BluetoothService.adapterName || Lang.t("bt.status.on")))
                        style: Theme.type.bodySmall
                        color: BluetoothService.scanning ? Theme.color.primary : Theme.color.fgSurfaceVariant
                    }
                }

                // Кнопка сканування
                Item {
                    visible: BluetoothService.enabled
                    implicitWidth: Theme.components.dp(36)
                    implicitHeight: Theme.components.dp(36)

                    LoadingIndicator {
                        anchors.centerIn: parent
                        visible: BluetoothService.scanning
                        size: 22
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: !BluetoothService.scanning
                        radius: width / 2
                        color: scanHover.hovered ? Theme.color.surfaceContainerHighest : "transparent"
                        HoverHandler { id: scanHover }

                        Text {
                            anchors.centerIn: parent
                            text: "\ue5d5" // refresh
                            color: scanHover.hovered ? Theme.color.primary : Theme.color.fgSurfaceVariant
                            font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: BluetoothService.startScan()
                        }
                    }
                }

                // Вимикач живлення
                MaterialSwitch {
                    checked: BluetoothService.enabled
                    onToggled: BluetoothService.togglePower()
                }
            }
        }

        // ---- ПОВІДОМЛЕННЯ ПРО ПОМИЛКУ / СТАН ----
        Rectangle {
            Layout.fillWidth: true
            visible: BluetoothService.statusMessage.length > 0
            implicitHeight: msgText.implicitHeight + Theme.space.sm * 2
            radius: Theme.shape.sm
            color: Theme.color.errorContainer
            RowLayout {
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                spacing: Theme.space.xs
                Text {
                    text: "\ue000"
                    color: Theme.color.fgErrorContainer
                    font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                }
                ThemedText {
                    id: msgText
                    Layout.fillWidth: true
                    text: BluetoothService.statusMessage
                    style: Theme.type.bodySmall
                    color: Theme.color.fgErrorContainer
                }
            }
        }

        // ---- ЕКРАН КОЛИ BLUETOOTH ВИМКНЕНО ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !BluetoothService.enabled

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Theme.space.md
                width: parent.width * 0.8

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: Theme.components.dp(64)
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: Theme.color.surfaceContainerHigh
                    Text {
                        anchors.centerIn: parent
                        text: "\ue1a8" // bluetooth_disabled
                        color: Theme.color.outline
                        font { family: Theme.type.icons; pixelSize: Theme.components.dp(32) }
                    }
                }

                ThemedText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Lang.t("bt.disabled")
                    style: Theme.type.titleMedium
                    emphasized: true
                }

                ThemedText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Lang.t("bt.enableHint")
                    style: Theme.type.bodySmall
                    color: Theme.color.fgSurfaceVariant
                }

                MaterialButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: Lang.t("bt.action.connect")
                    icon: "\ue1a7"
                    onClicked: BluetoothService.togglePower()
                }
            }
        }

        // ---- СПИСОК ПРИСТРОЇВ ----
        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: BluetoothService.enabled
            clip: true
            contentWidth: width
            contentHeight: devCol.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: devCol
                width: flick.width
                spacing: Theme.space.md

                // 1. Підключені пристрої
                ThemedText {
                    visible: BluetoothService.connectedDevices.length > 0
                    text: Lang.t("bt.connected")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.primary
                }

                Repeater {
                    model: BluetoothService.connectedDevices
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(52)
                        radius: root.nothing ? ThemeNothing.corners.md : Theme.shape.md
                        color: root.nothing
                               ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.06)
                               : Theme.color.primaryContainer
                        border.width: root.nothing ? 1 : 0
                        border.color: root.nothing ? ThemeNothing.red : Theme.color.outlineVariant

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space.md
                            anchors.rightMargin: Theme.space.md
                            spacing: Theme.space.sm

                            // Іконка типу пристрою
                            Text {
                                text: root.getDeviceIcon(modelData.icon, modelData.name)
                                color: root.nothing ? ThemeNothing.red : Theme.color.fgPrimaryContainer
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                ThemedText {
                                    text: modelData.name || modelData.mac
                                    style: Theme.type.titleSmall
                                    emphasized: true
                                    color: root.nothing ? Colors.fg : Theme.color.fgPrimaryContainer
                                    elide: Text.ElideRight
                                }
                                RowLayout {
                                    spacing: Theme.space.xs
                                    ThemedText {
                                        text: modelData.mac
                                        style: Theme.type.bodySmall
                                        color: root.nothing ? Colors.grey2 : Theme.color.outline
                                    }
                                    // Рівень заряду батареї пристрою
                                    Rectangle {
                                        visible: modelData.battery >= 0
                                        implicitWidth: batRow.implicitWidth + Theme.space.xs * 2
                                        implicitHeight: Theme.components.dp(16)
                                        radius: Theme.shape.xs
                                        color: root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.15) : Theme.color.surfaceContainer
                                        RowLayout {
                                            id: batRow
                                            anchors.centerIn: parent
                                            spacing: 2
                                            Text {
                                                text: "\ue1a3" // battery
                                                color: root.nothing ? Colors.fg : Theme.color.primary
                                                font { family: Theme.type.icons; pixelSize: 11 }
                                            }
                                            Text {
                                                text: modelData.battery + "%"
                                                color: root.nothing ? Colors.fg : Theme.color.fgSurface
                                                font { family: Theme.type.mono; pixelSize: 10; weight: 600 }
                                            }
                                        }
                                    }
                                }
                            }

                            // Кнопка відключення
                            MaterialButton {
                                text: Lang.t("bt.action.disconnect")
                                style: "outlined"
                                enabled_: !(BluetoothService.pendingMac === modelData.mac && BluetoothService.connectionState === "disconnecting")
                                onClicked: BluetoothService.disconnectDevice(modelData.mac)
                            }
                        }
                    }
                }

                // 2. Збережені (сполучені) пристрої
                ThemedText {
                    visible: BluetoothService.pairedDevices.length > 0
                    text: Lang.t("bt.paired")
                    style: Theme.type.labelMedium
                    emphasized: true
                    color: Theme.color.outline
                }

                Repeater {
                    model: BluetoothService.pairedDevices
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(48)
                        radius: root.nothing ? ThemeNothing.corners.sm : Theme.shape.sm
                        color: pMa.containsMouse
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.05) : Theme.color.surfaceContainerHigh)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainer)
                        border.width: root.nothing ? 1 : 0
                        border.color: Theme.color.outlineVariant

                        MouseArea {
                            id: pMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space.md
                            anchors.rightMargin: Theme.space.sm
                            spacing: Theme.space.sm

                            Text {
                                text: root.getDeviceIcon(modelData.icon, modelData.name)
                                color: Theme.color.fgSurfaceVariant
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                ThemedText {
                                    text: modelData.name || modelData.mac
                                    style: Theme.type.bodyMedium
                                    emphasized: true
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    text: modelData.mac + (modelData.trusted ? " • Довірений" : "")
                                    style: Theme.type.labelSmall
                                    color: Theme.color.outline
                                }
                            }

                            // Довіра
                            MaterialIconButton {
                                icon: modelData.trusted ? "verified" : "shield"
                                color: modelData.trusted ? Theme.color.primary : Theme.color.outline
                                tooltip: modelData.trusted ? Lang.t("bt.action.untrust") : Lang.t("bt.action.trust")
                                onClicked: BluetoothService.toggleTrust(modelData.mac, modelData.trusted)
                            }

                            // Видалення / забути
                            MaterialIconButton {
                                icon: "delete"
                                color: Theme.color.outline
                                tooltip: Lang.t("bt.action.unpair")
                                onClicked: BluetoothService.unpairDevice(modelData.mac)
                            }

                            // Підключити
                            MaterialButton {
                                text: Lang.t("bt.action.connect")
                                style: "filled"
                                enabled_: !(BluetoothService.pendingMac === modelData.mac && BluetoothService.connectionState === "connecting")
                                onClicked: BluetoothService.connectDevice(modelData.mac)
                            }
                        }
                    }
                }

                // 3. Доступні нові пристрої (ефір)
                RowLayout {
                    Layout.fillWidth: true
                    ThemedText {
                        Layout.fillWidth: true
                        text: Lang.t("bt.available")
                        style: Theme.type.labelMedium
                        emphasized: true
                        color: Theme.color.outline
                    }
                    ThemedText {
                        visible: BluetoothService.scanning
                        text: Lang.t("bt.status.scanning")
                        style: Theme.type.labelSmall
                        color: Theme.color.primary
                    }
                }

                // Порожній стан пошуку
                Rectangle {
                    visible: BluetoothService.discoveredDevices.length === 0
                    Layout.fillWidth: true
                    implicitHeight: Theme.components.dp(56)
                    radius: Theme.shape.sm
                    color: Theme.color.surfaceContainerLowest
                    border.width: 1
                    border.color: Theme.color.outlineVariant

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: Theme.space.sm
                        LoadingIndicator {
                            visible: BluetoothService.scanning
                            size: 18
                        }
                        ThemedText {
                            text: BluetoothService.scanning
                                  ? Lang.t("bt.status.scanning")
                                  : Lang.t("bt.empty.available")
                            style: Theme.type.bodySmall
                            color: Theme.color.outline
                        }
                    }
                }

                Repeater {
                    model: BluetoothService.discoveredDevices
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Theme.components.dp(44)
                        radius: root.nothing ? ThemeNothing.corners.sm : Theme.shape.sm
                        color: discMa.containsMouse
                               ? (root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.05) : Theme.color.surfaceContainerHigh)
                               : (root.nothing ? "transparent" : Theme.color.surfaceContainerLow)
                        border.width: root.nothing ? 1 : 0
                        border.color: Theme.color.outlineVariant

                        MouseArea {
                            id: discMa
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.space.md
                            anchors.rightMargin: Theme.space.sm
                            spacing: Theme.space.sm

                            Text {
                                text: root.getDeviceIcon(modelData.icon, modelData.name)
                                color: Theme.color.fgSurfaceVariant
                                font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                ThemedText {
                                    text: modelData.name || modelData.mac
                                    style: Theme.type.bodyMedium
                                    elide: Text.ElideRight
                                }
                                ThemedText {
                                    text: modelData.mac
                                    style: Theme.type.labelSmall
                                    color: Theme.color.outline
                                }
                            }

                            MaterialButton {
                                text: Lang.t("bt.action.pair")
                                style: "tonal"
                                enabled_: !(BluetoothService.pendingMac === modelData.mac && (BluetoothService.connectionState === "pairing" || BluetoothService.connectionState === "connecting"))
                                onClicked: BluetoothService.pairDevice(modelData.mac)
                            }
                        }
                    }
                }
            }
        }
    }
}
