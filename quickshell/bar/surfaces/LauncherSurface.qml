pragma ComponentBehavior: Bound

import "root:/theme"
import "root:/settings"
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// LauncherSurface.qml — розширений лаунчер.
//   • застосунки (як раніше)
//   • калькулятор: 2+2 або =2+2 → Enter копіює результат
//   • емодзі: :smile → Enter копіює
//   • файли: /report або f:report → Enter відкриває
//   • команди: >htop → Enter запускає, Ctrl+Enter — у терміналі
// Дані: LauncherService (apps + launcher-kit.py для файлів та емодзі).
// ==========================================================================
Item {
    id: root

    signal appLaunched

    readonly property bool nothing: Theme.settings.nothing
    readonly property string mode: LauncherService.mode
    readonly property bool hasQuery: LauncherService.query.trim().length > 0

    readonly property string placeholder: {
        switch (mode) {
        case "calc":    return Lang.t("launcher.search.calc")
        case "files":   return Lang.t("launcher.search.files")
        case "emoji":   return Lang.t("launcher.search.emoji")
        case "command": return Lang.t("launcher.search.command")
        default:        return Lang.t("ui.launcher.search")
        }
    }

    readonly property string modeBadge: {
        switch (mode) {
        case "calc":    return Lang.t("launcher.mode.calc")
        case "files":   return Lang.t("launcher.mode.files")
        case "emoji":   return Lang.t("launcher.mode.emoji")
        case "command": return Lang.t("launcher.mode.command")
        default:        return ""
        }
    }

    readonly property string emptyText: {
        if (mode === "emoji") return LauncherService.emojiReady
            ? Lang.t("launcher.empty.emoji") : Lang.t("launcher.loading")
        if (mode === "files") return LauncherService.filesBusy
            ? Lang.t("launcher.searching") : Lang.t("launcher.empty.files")
        if (mode === "command") return Lang.t("launcher.empty.command")
        if (mode === "calc") return ""
        return Lang.t("launcher.empty.apps")
    }

    readonly property var hintChips: [
        { prefix: ">", label: Lang.t("launcher.chip.run") },
        { prefix: "/", label: Lang.t("launcher.chip.files") },
        { prefix: ":", label: Lang.t("launcher.chip.emoji") },
        { prefix: "=", label: Lang.t("launcher.chip.math") }
    ]

    onVisibleChanged: {
        if (visible) {
            LauncherService.reset()
            Qt.callLater(() => searchInput.forceActiveFocus())
        }
    }
    Component.onCompleted: {
        Qt.callLater(() => searchInput.forceActiveFocus())
    }

    Item {
        anchors.fill: parent

        // ---- поле пошуку ----
        Rectangle {
            id: searchBox
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: root.nothing ? 44 : 40
            radius: root.nothing ? ThemeNothing.corners.md - 2 : 20
            color: root.nothing ? "transparent" : Colors.bg1
            border.width: root.nothing ? 1 : (searchInput.activeFocus ? 2 : 1)
            border.color: root.nothing
                ? (searchInput.activeFocus ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.75) : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.22))
                : (searchInput.activeFocus ? Colors.accent : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.25))
            Behavior on border.color { ColorAnimation { duration: 160 } }

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: root.modeBadge.length > 0 ? 84 : 16
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.fg
                font { family: Colors.uiFont; pixelSize: 12 }
                selectionColor: root.nothing ? ThemeNothing.red : Colors.accent
                selectedTextColor: root.nothing ? "#FFFFFF" : Colors.onAccent
                cursorDelegate: root.nothing ? nothingCaret : null
                focus: true
                selectByMouse: true
                clip: true
                text: LauncherService.query
                onTextChanged: if (LauncherService.query !== text) LauncherService.query = text

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 2
                    verticalAlignment: Text.AlignVCenter
                    text: root.nothing ? root.placeholder.toUpperCase() : root.placeholder
                    color: Colors.grey2
                    visible: searchInput.text.length === 0
                    elide: Text.ElideRight
                    font {
                        family: root.nothing ? Theme.type.mono : searchInput.font.family
                        pixelSize: root.nothing ? 10 : searchInput.font.pixelSize
                        letterSpacing: root.nothing ? 2 : 0
                    }
                }

                Keys.onDownPressed: {
                    LauncherService.moveSelection(1)
                    event.accepted = true
                }
                Keys.onUpPressed: {
                    LauncherService.moveSelection(-1)
                    event.accepted = true
                }
                Keys.onReturnPressed: {
                    const terminal = (event.modifiers & Qt.ControlModifier) !== 0
                    if (LauncherService.activateSelected(terminal))
                        root.appLaunched()
                    event.accepted = true
                }
            }

            // індикатор режиму праворуч у полі
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: root.modeBadge.length > 0
                text: root.modeBadge
                color: Colors.accent
                opacity: 0.85
                font {
                    family: root.nothing ? Theme.type.mono : Colors.uiFont
                    pixelSize: root.nothing ? 9 : 9
                    letterSpacing: root.nothing ? 1.6 : 0.8
                    weight: 600
                }
            }
        }

        Component {
            id: nothingCaret
            Rectangle { width: 2; color: ThemeNothing.red }
        }

        // ---- підказки форматів (порожній запит) ----
        RowLayout {
            id: hintRow
            anchors.top: searchBox.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 6
            visible: !root.hasQuery

            Repeater {
                model: root.hintChips
                delegate: Rectangle {
                    required property var modelData
                    implicitWidth: chipLabel.implicitWidth + 16
                    implicitHeight: 22
                    radius: root.nothing ? 6 : 11
                    color: chipMouse.containsMouse
                        ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.08) : "transparent"
                    border.width: 1
                    border.color: root.nothing
                        ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.18)
                        : Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.12)

                    Text {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: {
                            const label = root.nothing ? modelData.label.toUpperCase() : modelData.label
                            return modelData.prefix + " " + label
                        }
                        color: Colors.grey2
                        font {
                            family: root.nothing ? Theme.type.mono : Colors.uiFont
                            pixelSize: root.nothing ? 8 : 9
                            letterSpacing: root.nothing ? 1.2 : 0
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            LauncherService.query = modelData.prefix + " "
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ---- результати ----
        ListView {
            id: appList
            anchors.top: hintRow.visible ? hintRow.bottom : searchBox.bottom
            anchors.topMargin: 8
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            clip: true
            spacing: 4
            highlightMoveDuration: 0
            focus: false

            model: LauncherService.results
            currentIndex: LauncherService.selectedIndex
            onCurrentIndexChanged: if (LauncherService.selectedIndex !== currentIndex)
                LauncherService.selectedIndex = currentIndex

            delegate: Rectangle {
                id: appRow
                required property int index
                required property var modelData

                readonly property string kind: modelData.kind || "app"
                readonly property bool current: LauncherService.selectedIndex === index
                readonly property bool solid: current && !root.nothing
                // Material: суцільний акцент і «on»-текст. Nothing: легка заливка + контур, текст лишається звичайним.
                readonly property color titleColor: solid ? Colors.onAccent
                    : kind === "calc" ? Colors.accent
                    : kind === "info" ? Colors.grey2
                    : Colors.fg
                readonly property color subColor: solid ? Colors.onAccent : Colors.grey2
                readonly property string iconSource: kind === "file"
                    ? Quickshell.iconPath(modelData.icon || "text-x-generic")
                    : kind === "app"
                        ? Quickshell.iconPath(modelData.icon || "application-x-executable")
                        : ""
                readonly property string subtitle: kind === "app"
                    ? (modelData.genericName || "")
                    : kind === "file" ? (modelData.dir || "")
                    : kind === "emoji" ? ""
                    : kind === "calc" ? (modelData.expression || "")
                    : kind === "command" ? Lang.t(modelData.terminal
                        ? "launcher.command.term" : "launcher.command.bg")
                    : (modelData.subtitle || "")
                readonly property string actionHint: kind === "file"
                    ? Lang.t("launcher.hint.open")
                    : kind === "emoji" ? Lang.t("launcher.hint.copy")
                    : kind === "calc" ? Lang.t("launcher.hint.copy")
                    : kind === "command" ? Lang.t(modelData.terminal
                        ? "launcher.hint.terminal" : "launcher.hint.run")
                    : ""

                width: appList.width
                height: root.nothing ? 52 : 48
                radius: root.nothing ? ThemeNothing.corners.md - 2 : 8
                color: solid ? Colors.accent
                    : current ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.07)
                    : (rowMouse.containsMouse ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.05) : "transparent")
                border.width: current ? 1 : 0
                border.color: root.nothing ? Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.30) : Colors.accent
                Behavior on color { ColorAnimation { duration: 140 } }

                // індикатор вибору (Nothing): червона крапка, що «вискакує»
                Rectangle {
                    visible: root.nothing
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: ThemeNothing.red
                    opacity: appRow.current ? 1 : 0
                    scale: appRow.current ? 1 : 0.2
                    Behavior on opacity { NumberAnimation { duration: 140 } }
                    Behavior on scale   { NumberAnimation { duration: 220; easing.type: Easing.OutBack; easing.overshoot: 2.5 } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: root.nothing ? 24 : 12
                    anchors.rightMargin: 12
                    spacing: 12
                    Behavior on anchors.leftMargin { NumberAnimation { duration: 160 } }

                    Rectangle {
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: root.nothing ? 9 : 6
                        color: appRow.solid ? Colors.onAccent : Colors.bg2
                        border.width: root.nothing ? 1 : 0
                        border.color: Qt.rgba(Colors.fg.r, Colors.fg.g, Colors.fg.b, 0.14)

                        Image {
                            anchors.fill: parent
                            anchors.margins: 4
                            visible: appRow.kind === "app" || appRow.kind === "file"
                            source: appRow.iconSource
                            smooth: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appRow.kind === "emoji"
                            text: modelData.char || ""
                            font.pixelSize: 20
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appRow.kind === "calc"
                            text: "="
                            color: appRow.solid ? Colors.onAccent : Colors.accent
                            font {
                                family: Theme.type.mono
                                pixelSize: 17
                                weight: 700
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appRow.kind === "command"
                            text: ">_"
                            color: appRow.solid ? Colors.onAccent : Colors.accent
                            font {
                                family: Theme.type.mono
                                pixelSize: 12
                                weight: 600
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appRow.kind === "info"
                            text: "i"
                            color: Colors.grey2
                            font {
                                family: Theme.type.mono
                                pixelSize: 14
                                weight: 600
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        Text {
                            text: appRow.kind === "app" ? modelData.name
                                : appRow.kind === "file" ? modelData.name
                                : appRow.kind === "emoji" ? modelData.name
                                : (modelData.title || "")
                            color: appRow.titleColor
                            font {
                                family: Colors.uiFont
                                pixelSize: appRow.kind === "calc" ? 15 : 12
                                weight: appRow.kind === "calc" ? 600 : 500
                            }
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Text {
                            visible: appRow.subtitle.length > 0
                            text: root.nothing
                                ? appRow.subtitle.toUpperCase()
                                : appRow.subtitle
                            color: appRow.subColor
                            opacity: appRow.solid ? 0.85 : 1.0
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            font {
                                family: root.nothing ? Theme.type.mono : Colors.uiFont
                                pixelSize: root.nothing ? 8 : 10
                                letterSpacing: root.nothing ? 1.2 : 0
                            }
                        }
                    }

                    Text {
                        visible: appRow.actionHint.length > 0 && !appRow.solid
                        text: appRow.actionHint
                        color: Colors.grey2
                        opacity: 0.8
                        font {
                            family: root.nothing ? Theme.type.mono : Colors.uiFont
                            pixelSize: root.nothing ? 8 : 9
                            letterSpacing: root.nothing ? 1.2 : 0.6
                        }
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: appRow.kind === "info" ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onEntered: LauncherService.selectedIndex = index
                    onClicked: {
                        if (LauncherService.activate(modelData))
                            root.appLaunched()
                    }
                }
            }
        }

        // ---- порожній стан ----
        Text {
            anchors.centerIn: appList
            width: appList.width - 32
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: LauncherService.results.length === 0 && root.hasQuery
                && root.emptyText.length > 0
            text: root.nothing ? root.emptyText.toUpperCase() : root.emptyText
            color: Colors.grey2
            font {
                family: root.nothing ? Theme.type.mono : Colors.uiFont
                pixelSize: root.nothing ? 9 : 11
                letterSpacing: root.nothing ? 1.4 : 0
            }
        }
    }
}
