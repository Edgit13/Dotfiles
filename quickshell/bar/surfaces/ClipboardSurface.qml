pragma ComponentBehavior: Bound

import "root:/theme"
import "root:/settings"
import "root:/settings/material"
import "root:/shell"
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ==========================================================================
// ClipboardSurface.qml — історія буфера обміну (cliphist).
//
// Розбір історії живе в scripts/clipboard.py: він читає `cliphist list`,
// декодує картинки в ~/.cache/edots/clipvis (щоб показати справжнє прев'ю)
// і визначає тип запису — текст, картинка, файли, посилання, колір.
//
// Тут — пошук, фільтри за типом, список карток із прев'ю, клавіатура:
// ↑/↓ вибір, Enter копіювати й закрити, Ctrl+Delete прибрати запис,
// Ctrl+Shift+Delete очистити всю історію.
// ==========================================================================

Item {
    id: root

    readonly property bool nothing: Theme.settings.nothing
    readonly property string helper: Quickshell.shellPath("scripts/clipboard.py")

    property var entries: []
    property string query: ""
    property string filter: "all"
    property int current: 0
    property bool confirmingWipe: false
    property bool loading: true
    property string failure: ""
    property bool copyThenClose: false

    function dp(v) { return Theme.components.dp(v) }

    function bytes(n) {
        if (!n || n <= 0) return ""
        if (n < 1000) return n + " B"
        if (n < 1000000) return (n / 1000).toFixed(0) + " KB"
        if (n < 1000000000) return (n / 1000000).toFixed(n < 10000000 ? 1 : 0) + " MB"
        return (n / 1000000000).toFixed(1) + " GB"
    }

    // ── фільтри ──
    readonly property var groups: [
        { id: "all",   label: Lang.t("clip.all") },
        { id: "text",  label: Lang.t("clip.text") },
        { id: "image", label: Lang.t("clip.images") },
        { id: "files", label: Lang.t("clip.files") },
        { id: "url",   label: Lang.t("clip.links") },
        { id: "color", label: Lang.t("clip.colors") }
    ]

    function countOf(id) {
        if (id === "all") return root.entries.length
        return root.entries.filter(e => e.kind === id).length
    }

    // «all» + лише ті типи, що реально є в історії
    readonly property var chips: root.groups
        .filter(g => g.id === "all" || root.countOf(g.id) > 0)
        .map(g => ({ id: g.id, label: g.label, count: root.countOf(g.id) }))

    readonly property var filtered: {
        const needle = root.query.trim().toLowerCase()
        return root.entries.filter(e => {
            if (root.filter !== "all" && e.kind !== root.filter) return false
            if (needle.length === 0) return true
            const hay = [e.title, e.body, e.color, (e.files || []).join(" ")]
                .join(" ").toLowerCase()
            return hay.indexOf(needle) >= 0
        })
    }

    onFilteredChanged: {
        if (root.current >= root.filtered.length)
            root.current = Math.max(0, root.filtered.length - 1)
    }

    function iconOf(kind) {
        switch (kind) {
        case "image": return "image"
        case "files": return "folder"
        case "url":   return "link"
        case "color": return "palette"
        case "binary": return "data_object"
        default:      return "subject"
        }
    }

    function selectBy(delta) {
        if (root.filtered.length === 0) return
        root.current = Math.min(root.filtered.length - 1, Math.max(0, root.current + delta))
    }

    function copy(item) {
        if (!item) return
        root.copyThenClose = true
        copyProc.copy(item)
    }

    function remove(item) {
        if (!item) return
        root.entries = root.entries.filter(e => e.id !== item.id)
        deleteProc.del(item)
    }

    // ── історія з cliphist ──
    function refresh() {
        if (listProc.running) return
        root.loading = true
        listProc.running = true
    }

    Process {
        id: listProc
        command: ["python3", root.helper, "entries", "--limit", "200"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                try {
                    const j = JSON.parse(text.trim())
                    root.entries = j.items || []
                    root.current = 0
                    root.failure = ""
                } catch (e) {
                    root.entries = []
                    root.failure = text.trim().slice(0, 200)
                }
            }
        }
    }

    Process {
        id: copyProc
        function copy(item) {
            command = ["sh", "-c",
                "printf '%s\\t%s' \"$1\" \"$2\" | cliphist decode | wl-copy",
                "--", item.id, item.preview
            ]
            running = true
        }
        onExited: {
            if (root.copyThenClose) {
                root.copyThenClose = false
                ShellState.closeSurfaces()
            }
        }
    }

    Process {
        id: deleteProc
        function del(item) {
            command = ["sh", "-c",
                "printf '%s\\t%s' \"$1\" \"$2\" | cliphist delete",
                "--", item.id, item.preview
            ]
            running = true
        }
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: {
            root.confirmingWipe = false
            root.refresh()
        }
    }

    Component.onCompleted: {
        root.refresh()
        Qt.callLater(() => search.forceActiveFocus())
    }
    onVisibleChanged: {
        if (visible) {
            root.refresh()
            Qt.callLater(() => search.forceActiveFocus())
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.dp(10)

        // ── пошук + очищення історії ──
        RowLayout {
            Layout.fillWidth: true
            spacing: root.dp(8)

            Rectangle {
                id: field
                Layout.fillWidth: true
                Layout.preferredHeight: root.dp(42)
                radius: Theme.shape.field
                color: root.nothing ? "transparent" : Theme.color.surfaceContainerHighest
                border.width: root.nothing ? 1 : (search.activeFocus ? 2 : 0)
                border.color: root.nothing
                    ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b,
                               search.activeFocus ? 0.75 : 0.22)
                    : Theme.color.primary

                ThemedText {
                    anchors.left: parent.left
                    anchors.leftMargin: root.dp(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: Theme.color.fgSurfaceVariant
                    font.family: Theme.type.icons
                    font.pixelSize: root.dp(18)
                }

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: root.dp(40)
                    anchors.rightMargin: root.dp(12)
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.color.fgSurface
                    font.family: root.nothing ? Theme.type.mono : Theme.type.bodyMedium.family
                    font.pixelSize: Theme.type.bodyMedium.size
                    selectByMouse: true
                    clip: true
                    focus: true
                    selectionColor: root.nothing ? ThemeNothing.red : Theme.color.primary
                    selectedTextColor: root.nothing ? "#FFFFFF" : Theme.color.fgPrimary

                    onTextChanged: if (root.query !== text) root.query = text

                    ThemedText {
                        anchors.fill: parent
                        visible: search.text.length === 0
                        text: Lang.t("clip.search")
                        color: Theme.color.fgSurfaceVariant
                        style: Theme.type.bodyMedium
                        font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
                        elide: Text.ElideRight
                    }

                    Keys.onDownPressed: { root.selectBy(1); event.accepted = true }
                    Keys.onUpPressed: { root.selectBy(-1); event.accepted = true }
                    Keys.onReturnPressed: root.copy(root.filtered[root.current])
                    Keys.onEnterPressed: root.copy(root.filtered[root.current])
                    Keys.onDeletePressed: {
                        if (event.modifiers & Qt.ControlModifier) {
                            if (event.modifiers & Qt.ShiftModifier) root.confirmingWipe = true
                            else root.remove(root.filtered[root.current])
                            event.accepted = true
                        }
                    }
                }
            }

            MaterialIconButton {
                icon: "delete_sweep"
                style: "tonal"
                visible: root.entries.length > 0 && !root.confirmingWipe
                tooltip: Lang.t("clip.wipe")
                onClicked: root.confirmingWipe = true
            }
        }

        // ── смуга фільтрів (або підтвердження очищення) ──
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: root.dp(30)

            RowLayout {
                anchors.fill: parent
                spacing: root.dp(8)
                visible: root.confirmingWipe

                ThemedText {
                    Layout.fillWidth: true
                    text: Lang.t("clip.wipeAsk")
                    style: Theme.type.labelMedium
                    color: Theme.color.error
                    elide: Text.ElideRight
                }
                Rectangle {
                    implicitWidth: yesText.implicitWidth + root.dp(20)
                    implicitHeight: root.dp(28)
                    radius: Theme.shape.chip
                    color: Theme.color.errorContainer
                    ThemedText {
                        id: yesText
                        anchors.centerIn: parent
                        text: Lang.t("clip.yes")
                        style: Theme.type.labelMedium
                        color: Theme.color.fgErrorContainer
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: wipeProc.running = true
                    }
                }
                Rectangle {
                    implicitWidth: noText.implicitWidth + root.dp(20)
                    implicitHeight: root.dp(28)
                    radius: Theme.shape.chip
                    color: root.nothing ? "transparent" : Theme.color.surfaceContainerHighest
                    border.width: root.nothing ? 1 : 0
                    border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                                          Theme.color.fgSurface.b, 0.22)
                    ThemedText {
                        id: noText
                        anchors.centerIn: parent
                        text: Lang.t("clip.cancel")
                        style: Theme.type.labelMedium
                        color: Theme.color.fgSurface
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.confirmingWipe = false
                    }
                }
            }

            Flickable {
                id: chipStrip
                anchors.fill: parent
                visible: !root.confirmingWipe
                contentWidth: chipRow.implicitWidth
                contentHeight: height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick

                Row {
                    id: chipRow
                    spacing: root.dp(8)
                    height: chipStrip.height

                    Repeater {
                        model: root.chips
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool active: root.filter === modelData.id

                            width: chipLabel.implicitWidth + chipCount.implicitWidth + root.dp(22)
                            height: root.dp(28)
                            anchors.verticalCenter: parent.verticalCenter
                            radius: Theme.shape.chip
                            color: chip.active
                                ? (root.nothing ? Qt.rgba(1, 1, 1, 0.12) : Theme.color.secondaryContainer)
                                : (root.nothing ? "transparent" : Theme.color.surfaceContainerHighest)
                            border.width: root.nothing ? 1 : 0
                            border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g,
                                                  Theme.color.fgSurface.b, chip.active ? 0.45 : 0.16)
                            Behavior on color { MotionColorAnimation { role: "hover" } }

                            Row {
                                anchors.centerIn: parent
                                spacing: root.dp(6)

                                ThemedText {
                                    id: chipLabel
                                    text: chip.modelData.label
                                    style: Theme.type.labelMedium
                                    color: chip.active && !root.nothing
                                        ? Theme.color.fgSecondaryContainer : Theme.color.fgSurface
                                    font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
                                }
                                ThemedText {
                                    id: chipCount
                                    text: String(chip.modelData.count)
                                    style: Theme.type.labelSmall
                                    color: Theme.color.fgSurfaceVariant
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.filter = chip.modelData.id
                                    root.current = 0
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── список ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: root.dp(6)
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds
                reuseItems: true

                Connections {
                    target: root
                    function onCurrentChanged() {
                        if (root.current >= 0 && root.current < list.count)
                            list.positionViewAtIndex(root.current, ListView.Contain)
                    }
                    function onFilteredChanged() {
                        Qt.callLater(() => list.positionViewAtBeginning())
                    }
                }

                delegate: Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    readonly property bool sel: root.current === index
                    readonly property bool img: modelData.kind === "image"
                    readonly property bool hovered: cardHover.hovered || cardMouse.containsMouse

                    width: ListView.view ? ListView.view.width : 0
                    height: root.dp(card.img ? 72 : 58)
                    radius: Theme.shape.card
                    color: card.sel
                        ? (root.nothing ? Qt.rgba(1, 1, 1, 0.09) : Theme.color.primaryContainer)
                        : (root.nothing ? "transparent"
                                        : (card.hovered ? Theme.color.surfaceContainer
                                                        : Theme.color.surfaceContainerLow))
                    border.width: root.nothing ? 1 : (card.sel ? 0 : 1)
                    border.color: root.nothing
                        ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b,
                                  card.sel ? 0.55 : (card.hovered ? 0.30 : 0.12))
                        : Theme.color.outlineVariant
                    Behavior on color { MotionColorAnimation { role: "hover" } }
                    Behavior on border.color { MotionColorAnimation { role: "hover" } }

                    readonly property color ink: card.sel && !root.nothing
                        ? Theme.color.fgPrimaryContainer : Theme.color.fgSurface
                    readonly property color inkSoft: card.sel && !root.nothing
                        ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant

                    // прев'ю картинки
                    Rectangle {
                        id: preview
                        visible: card.img
                        x: root.dp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.dp(58)
                        height: root.dp(46)
                        radius: Theme.shape.radius("sm", height)
                        color: Theme.color.surfaceContainerHighest
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: card.modelData.thumb ? "file://" + card.modelData.thumb : ""
                            sourceSize.width: Math.round(preview.width * 2)
                            sourceSize.height: Math.round(preview.height * 2)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                        }
                        ThemedText {
                            anchors.centerIn: parent
                            visible: !card.modelData.thumb
                            text: "image"
                            color: Theme.color.fgSurfaceVariant
                            font.family: Theme.type.icons
                            font.pixelSize: root.dp(20)
                        }
                    }

                    // іконка або кольоровий зразок для решти типів
                    Rectangle {
                        id: glyph
                        visible: !card.img
                        x: root.dp(12)
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.dp(32)
                        height: width
                        radius: card.modelData.kind === "color"
                            ? Theme.shape.radius("sm", height) : width / 2
                        color: card.modelData.kind === "color"
                            ? card.modelData.color : (root.nothing
                                ? Qt.rgba(1, 1, 1, 0.06) : Theme.color.surfaceContainerHighest)
                        border.width: card.modelData.kind === "color" ? 1 : 0
                        border.color: Theme.color.outline

                        ThemedText {
                            anchors.centerIn: parent
                            visible: card.modelData.kind !== "color"
                            text: root.iconOf(card.modelData.kind)
                            color: card.inkSoft
                            font.family: Theme.type.icons
                            font.pixelSize: root.dp(18)
                        }
                    }

                    Column {
                        anchors.left: card.img ? preview.right : glyph.right
                        anchors.leftMargin: root.dp(10)
                        anchors.right: trailing.left
                        anchors.rightMargin: root.dp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: root.dp(1)

                        ThemedText {
                            width: parent.width
                            text: card.modelData.title
                            style: Theme.type.bodyMedium
                            color: card.ink
                            emphasized: card.sel
                            elide: Text.ElideRight
                            font.capitalization: root.nothing ? Font.MixedCase : Font.MixedCase
                        }
                        ThemedText {
                            width: parent.width
                            visible: text.length > 0
                            text: root.metaOf(card.modelData)
                            style: Theme.type.labelSmall
                            color: card.inkSoft
                            elide: Text.ElideRight
                            font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
                        }
                    }

                    // праворуч: тип / кількість, а на наведенні — видалити
                    Item {
                        id: trailing
                        anchors.right: parent.right
                        anchors.rightMargin: root.dp(8)
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.dp(64)
                        height: parent.height

                        ThemedText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !card.hovered
                            text: root.badgeOf(card.modelData)
                            style: Theme.type.labelSmall
                            color: card.inkSoft
                            font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
                        }

                        Rectangle {
                            visible: card.hovered
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: root.dp(30)
                            height: width
                            radius: width / 2
                            color: delMouse.containsMouse
                                ? Qt.rgba(Theme.color.error.r, Theme.color.error.g, Theme.color.error.b, 0.16)
                                : "transparent"

                            ThemedText {
                                anchors.centerIn: parent
                                text: "delete"
                                color: delMouse.containsMouse ? Theme.color.error : card.inkSoft
                                font.family: Theme.type.icons
                                font.pixelSize: root.dp(18)
                            }

                            MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.remove(card.modelData)
                            }
                        }
                    }

                    HoverHandler { id: cardHover }
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.current = card.index
                            root.copy(card.modelData)
                        }
                    }
                }
            }

            ThemedText {
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: !root.loading && root.filtered.length === 0
                text: root.entries.length === 0
                    ? Lang.t("clip.empty") : Lang.t("clip.noMatch")
                style: Theme.type.bodyMedium
                color: Theme.color.fgSurfaceVariant
                font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
                wrapMode: Text.WordWrap
            }

            ThemedText {
                anchors.centerIn: parent
                visible: root.loading && root.entries.length === 0
                text: Lang.t("clip.loading")
                style: Theme.type.bodyMedium
                color: Theme.color.fgSurfaceVariant
            }

            Keys.onPressed: e => {
                if (e.key === Qt.Key_Down) { root.selectBy(1); e.accepted = true }
                else if (e.key === Qt.Key_Up) { root.selectBy(-1); e.accepted = true }
            }
        }

        // ── підказка ──
        ThemedText {
            Layout.fillWidth: true
            visible: root.filtered.length > 0
            text: root.nothing ? Lang.t("clip.hint").toUpperCase() : Lang.t("clip.hint")
            style: Theme.type.labelSmall
            color: Theme.color.fgSurfaceVariant
            elide: Text.ElideRight
            font.capitalization: root.nothing ? Font.AllUppercase : Font.MixedCase
        }
    }

    // ── дрібні похідні для карток ──
    function metaOf(e) {
        if (e.kind === "image") {
            const size = root.bytes(e.bytes)
            return (e.fmt ? e.fmt.toUpperCase() : "") + (size.length > 0 ? " · " + size : "")
        }
        if (e.kind === "text") {
            if (e.body && e.body.length > 0) return e.body
            if (e.lines > 1) return e.lines + " " + Lang.t("clip.lines")
            if (e.chars > 0) return e.chars + " " + Lang.t("clip.chars")
            return ""
        }
        if (e.kind === "files") {
            const rest = (e.files || []).length - 1
            if (rest > 0) return Lang.t("clip.moreFiles").replace("{n}", rest)
            return ""
        }
        if (e.kind === "url") return e.body
        if (e.kind === "color") return Lang.t("clip.color")
        return ""
    }

    function badgeOf(e) {
        switch (e.kind) {
        case "image": return e.w && e.h ? e.w + "×" + e.h : "IMG"
        case "files": return String(e.count || (e.files || []).length)
        case "url":   return "URL"
        case "color": return "HEX"
        default:      return ""
        }
    }

    // ── зовнішнє керування (IPC/тести) ──
    function setQuery(text) {
        root.query = text
        search.text = text
        search.forceActiveFocus()
    }
    function moveSelection(delta) { root.selectBy(delta) }
    function activate() { root.copy(root.filtered[root.current]) }
}
