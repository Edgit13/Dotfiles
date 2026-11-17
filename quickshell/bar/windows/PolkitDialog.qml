import "root:/theme"
import "root:/settings"
import "root:/services"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// PolkitDialog — «Потрібен пароль» у стилі Edots.
//
// Полікіт-агент живе в PolkitService; це вікно лише показує запит:
// іконка дії, текст від polkitd, (за потреби) вибір користувача/групи,
// поле пароля, помилка невдалої спроби. Enter — підтвердити, Esc — скасувати.
//
// Вікно одне на сеанс і переїжджає на сфокусований монітор: polkitd
// реєструє рівно одного агента, тож окремі вікна на кожен екран тут не
// потрібні (і зайві — кожне тягнуло б свою реєстрацію).
// ==========================================================================
PanelWindow {
    id: win

    readonly property bool nothing: Theme.settings.nothing
    readonly property bool motion: Theme.motion.enabled && !Theme.motion.reduced

    // ── на якому екрані питати ──
    readonly property var targetScreen: {
        const list = Quickshell.screens
        const name = MangoService.focusedMonitor
        for (let i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        return list.length > 0 ? list[0] : null
    }

    screen: win.targetScreen
    visible: PolkitService.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    anchors { top: true; bottom: true; left: true; right: true }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "edots-polkit"
    WlrLayershell.keyboardFocus: win.visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function d(v) { return Theme.components.dp(v) }

    function submitValue() {
        if (!PolkitService.needInput) return
        const v = input.text
        if (v.length === 0) return
        input.text = ""
        PolkitService.submit(v)
    }
    function focusField() {
        if (!PolkitService.needInput) return
        Qt.callLater(() => input.forceActiveFocus())
    }

    onVisibleChanged: if (visible) focusField()
    Connections {
        target: PolkitService
        function onFlowChanged() {
            input.text = ""
            win.focusField()
        }
        function onNeedInputChanged() {
            if (PolkitService.needInput) { input.text = ""; win.focusField() }
        }
        function onFailedChanged() {
            if (PolkitService.failed) input.text = ""
        }
    }

    // ── затемнення: кліки не проходять у застосунки під діалогом ──
    Rectangle {
        anchors.fill: parent
        color: Theme.color.scrim
        opacity: win.visible ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
    MouseArea { anchors.fill: parent }

    // ── картка ──
    ElevationShadow {
        id: card
        level: 5
        radius: Theme.shape.dialog
        width: Math.min(win.width - win.d(48), win.d(420))
        height: body.implicitHeight + win.d(48)
        anchors.centerIn: parent

        scale: win.visible ? 1 : 0.96
        opacity: win.visible ? 1 : 0
        focus: win.visible
        Behavior on opacity { NumberAnimation { duration: win.motion ? 140 : 0 } }
        Behavior on scale { NumberAnimation { duration: win.motion ? 180 : 0; easing.type: Easing.OutCubic } }

        Keys.onEscapePressed: PolkitService.cancel()

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: win.d(24)
            spacing: win.d(16)

            // заголовок
            RowLayout {
                Layout.fillWidth: true
                spacing: win.d(14)

                Item {
                    Layout.alignment: Qt.AlignTop
                    implicitWidth: win.d(40)
                    implicitHeight: win.d(40)

                    readonly property string iconPath: PolkitService.iconName.length > 0
                        ? Quickshell.iconPath(PolkitService.iconName, true) : ""

                    Image {
                        anchors.centerIn: parent
                        visible: parent.iconPath !== ""
                        source: parent.iconPath
                        sourceSize.width: win.d(40) * (win.screen ? win.screen.devicePixelRatio : 1)
                        sourceSize.height: win.d(40) * (win.screen ? win.screen.devicePixelRatio : 1)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    ThemedText {
                        anchors.centerIn: parent
                        visible: parent.iconPath === ""
                        text: "lock"
                        color: win.nothing ? ThemeNothing.red : Theme.color.primary
                        font.family: Theme.type.icons
                        font.pixelSize: win.d(28)
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: win.d(2)

                    ThemedText {
                        Layout.fillWidth: true
                        text: PolkitService.message.length > 0
                            ? PolkitService.message : Lang.t("ui.polkit.title")
                        style: Theme.type.titleMedium
                        color: Theme.color.fgSurface
                        wrapMode: Text.WordWrap
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        visible: PolkitService.actionId.length > 0
                        text: PolkitService.actionId
                        style: Theme.type.monoSmall
                        color: Theme.color.fgSurfaceVariant
                        elide: Text.ElideMiddle
                    }
                }
            }

            // від імені кого (лише коли polkit пропонує вибір)
            Flow {
                Layout.fillWidth: true
                spacing: win.d(8)
                visible: PolkitService.identities.length > 1
                Repeater {
                    model: PolkitService.identities
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool current: PolkitService.active && PolkitService.flow
                            ? modelData === PolkitService.flow.selectedIdentity : false
                        width: idLabel.implicitWidth + win.d(24)
                        height: win.d(32)
                        radius: Theme.shape.chip
                        color: current
                            ? (win.nothing ? Qt.rgba(1, 1, 1, 0.12) : Theme.color.secondaryContainer)
                            : "transparent"
                        border.width: 1
                        border.color: current
                            ? (win.nothing ? Qt.rgba(1, 1, 1, 0.4) : "transparent")
                            : Theme.color.outlineVariant

                        ThemedText {
                            id: idLabel
                            anchors.centerIn: parent
                            text: PolkitService.identityLabel(modelData)
                            style: Theme.type.labelMedium
                            color: current
                                ? (win.nothing ? Theme.color.fgSurface : Theme.color.fgSecondaryContainer)
                                : Theme.color.fgSurfaceVariant
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                input.text = ""
                                PolkitService.selectIdentity(modelData)
                            }
                        }
                    }
                }
            }

            // повідомлення / помилка від polkit чи PAM
            ThemedText {
                Layout.fillWidth: true
                visible: text.length > 0 || PolkitService.failed
                text: PolkitService.note.length > 0
                    ? PolkitService.note
                    : (PolkitService.failed ? Lang.t("ui.polkit.wrong") : "")
                style: Theme.type.bodySmall
                color: (PolkitService.noteError || PolkitService.failed)
                    ? Theme.color.error : Theme.color.fgSurfaceVariant
                wrapMode: Text.WordWrap
            }

            // поле пароля
            ColumnLayout {
                Layout.fillWidth: true
                spacing: win.d(6)
                visible: PolkitService.needInput

                ThemedText {
                    text: PolkitService.prompt.length > 0
                        ? PolkitService.prompt : Lang.t("ui.polkit.prompt")
                    style: Theme.type.labelMedium
                    color: input.activeFocus
                        ? (win.nothing ? Theme.color.fgSurface : Theme.color.primary)
                        : Theme.color.fgSurfaceVariant
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: win.d(48)
                    radius: Theme.shape.field
                    color: "transparent"
                    border.width: win.nothing ? 1 : (input.activeFocus ? win.d(2) : 1)
                    border.color: win.nothing
                        ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b,
                                  input.activeFocus ? 0.75 : 0.25)
                        : (input.activeFocus ? Theme.color.primary : Theme.color.outline)
                    Behavior on border.color { MotionColorAnimation { role: "hover" } }

                    TextInput {
                        id: input
                        anchors.fill: parent
                        anchors.leftMargin: win.d(16)
                        anchors.rightMargin: win.d(16)
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.color.fgSurface
                        font.family: Theme.type.bodyLarge.family
                        font.pixelSize: Theme.type.bodyLarge.size
                        selectByMouse: true
                        clip: true
                        echoMode: PolkitService.responseVisible ? TextInput.Normal : TextInput.Password
                        selectionColor: win.nothing ? ThemeNothing.red : Theme.color.primary
                        selectedTextColor: win.nothing ? "#FFFFFF" : Theme.color.fgPrimary

                        onAccepted: win.submitValue()
                        Keys.onReturnPressed: win.submitValue()
                        Keys.onEnterPressed: win.submitValue()
                        Keys.onEscapePressed: PolkitService.cancel()
                    }
                }
            }

            // кнопки
            RowLayout {
                Layout.fillWidth: true
                spacing: win.d(8)
                Item { Layout.fillWidth: true }

                DialogButton {
                    label: Lang.t("ui.polkit.cancel")
                    onClicked: PolkitService.cancel()
                }
                DialogButton {
                    label: Lang.t("ui.polkit.submit")
                    primary: true
                    enabled: !PolkitService.needInput || input.text.length > 0
                    onClicked: win.submitValue()
                }
            }
        }
    }

    // ── кнопка діалогу ──
    component DialogButton: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        signal clicked()

        readonly property bool nothing: Theme.settings.nothing

        implicitWidth: btnText.implicitWidth + Theme.components.dp(40)
        implicitHeight: Theme.components.dp(40)
        radius: Theme.shape.button
        opacity: btn.enabled ? 1 : Theme.components.disabledContent

        color: btn.primary
            ? (btn.nothing ? ThemeNothing.red : Theme.color.primary)
            : (hover.hovered
                ? (btn.nothing ? Qt.rgba(1, 1, 1, 0.08)
                               : Theme.stateLayer(Theme.color.surface, Theme.color.fgSurface, 0.08))
                : "transparent")
        border.width: btn.primary ? 0 : 1
        border.color: btn.nothing
            ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.3)
            : Theme.color.outline

        HoverHandler { id: hover }
        MouseArea {
            anchors.fill: parent
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }

        ThemedText {
            id: btnText
            anchors.centerIn: parent
            text: btn.label
            style: Theme.type.labelLarge
            emphasized: true
            color: btn.primary
                ? (btn.nothing ? "#FFFFFF" : Theme.color.fgPrimary)
                : Theme.color.fgSurface
        }
    }
}
