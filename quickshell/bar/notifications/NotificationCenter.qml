pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/settings"
import "root:/services"
import "root:/settings/material"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

// NotificationCenter — M3 side sheet: пошук, фільтри (усі / непрочитані / закріплені),
// групи за застосунками, DND, масові дії. Сторона — за позицією центру в налаштуваннях.
PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    readonly property bool target: NotificationService.isCenterTarget(win.screen)
    readonly property bool open: NotificationService.centerOpen && target
    // центр має власну позицію (Settings → Notifications); "same" = як вікна
    readonly property string pos: NotificationService.centerPosition
    readonly property bool atLeft: pos === "left" || pos.indexOf("-left") > 0
    readonly property bool atRight: pos === "right" || pos.indexOf("-right") > 0
    readonly property bool atTop: pos.indexOf("top") === 0
    readonly property bool atBottom: pos.indexOf("bottom") === 0
    readonly property bool atMiddle: !win.atTop && !win.atBottom
    readonly property real m: Theme.space.md

    // стан центру
    property string filter: "all"      // all | unread | pinned
    property string query: ""
    readonly property var shownGroups: NotificationService.appGroups(win.filter, win.query)
    readonly property int readCount: NotificationService.items.filter(i => i.read).length
    readonly property string emptyMsg: win.query !== "" ? Lang.t("ui.notif.noResults")
        : win.filter === "unread" ? Lang.t("ui.notif.noUnread")
        : win.filter === "pinned" ? Lang.t("ui.notif.noPinned")
        : Lang.t("ui.notif.empty")

    // компактна картка, як інші модулі: висота за вмістом, не на весь екран
    readonly property real maxPanelH: win.screen.height - win.m * 2
    readonly property real maxListH: Math.max(Theme.components.dp(96),
        win.maxPanelH - Theme.space.lg * 2 - headerRow.implicitHeight - searchRow.implicitHeight
        - filterRow.implicitHeight - dndRow.implicitHeight - footerRow.implicitHeight
        - (rulesRow.visible ? rulesRow.implicitHeight + bodyCol.spacing : 0)
        - bodyCol.spacing * 6)

    // Розмір самої панелі (анімується ВСЕРЕДИНІ вікна)
    readonly property real panelW: Math.min(Theme.components.dp(NotificationService.centerWidth), win.screen.width - win.m * 2)
    readonly property real panelH: Math.min(bodyCol.implicitHeight + Theme.space.lg * 2, win.maxPanelH)
    readonly property bool atCenterH: !win.atLeft && !win.atRight

    // Вікно має СТАЛИЙ розмір (на всю висоту екрана вздовж краю) і завжди заміплене: прозоре,
    // з порожньою input-маскою, коли центр закритий. Раніше воно ресайзилось (Behavior на
    // implicitHeight) та мапилось/анмапилось на кожне відкриття — layer-shell configure на
    // кожен кадр + власна анімація композитора давали ривки, обріз і «стрибок» прозорості.
    visible: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: win.atLeft || win.atCenterH
        right: win.atRight || win.atCenterH
    }
    implicitWidth: win.atCenterH ? 0 : win.panelW + win.m
    mask: Region { item: win.open ? panel : null }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "m3-notification-center"
    WlrLayershell.keyboardFocus: win.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onOpenChanged: {
        if (!open) return
        win.filter = "all"
        win.query = ""
        searchInput.text = ""
        panel.forceActiveFocus()
    }

    Rectangle {
        id: panel
        width: win.panelW
        height: win.panelH
        clip: true
        radius: Theme.shape.dialog
        color: Theme.color.surfaceContainerLow
        border.width: Theme.settings.nothing ? ThemeNothing.hairline : 1
        border.color: Theme.settings.nothing ? Theme.color.outlineVariant : Theme.color.outlineVariant

        // виїжджає від краю екрана (для центру — лише поява/масштаб)
        readonly property real openX: win.atLeft ? win.m
                                    : win.atRight ? win.width - width - win.m
                                    : (win.width - width) / 2
        x: win.open ? openX : (win.atLeft ? -width - win.m : win.atRight ? win.width + win.m : openX)
        y: win.atBottom ? win.height - height - win.m
         : win.atTop ? win.m
         : (win.height - height) / 2
        opacity: win.open ? 1 : 0
        scale: win.open ? 1 : 0.97
        transformOrigin: win.atLeft ? Item.Left : win.atRight ? Item.Right : Item.Center
        Behavior on height { MotionAnimation { role: "morph" } }
        Behavior on x { MotionAnimation { role: win.open ? "move" : "exit" } }
        Behavior on opacity { MotionAnimation { role: win.open ? "enter" : "exit" } }
        Behavior on scale { MotionAnimation { role: win.open ? "move" : "exit" } }

        focus: true
        Keys.onEscapePressed: NotificationService.closeCenter()
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Slash) { searchInput.forceActiveFocus(); e.accepted = true }
        }

        ColumnLayout {
            id: bodyCol
            // без fill: колонка не стискається, поки панель анімує висоту (clip у panel)
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.space.lg }
            spacing: Theme.space.md
            opacity: win.open ? 1 : 0

            // контент з'являється трохи пізніше за панель — ефект шару
            transform: Translate {
                x: win.open ? 0 : (win.atLeft ? -Theme.space.lg : Theme.space.lg)
                Behavior on x { MotionAnimation { role: win.open ? "contentIn" : "contentOut" } }
            }
            Behavior on opacity { MotionAnimation { role: win.open ? "contentIn" : "contentOut" } }

            // ---- заголовок ----
            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: Theme.space.sm

                Rectangle {
                    implicitWidth: Theme.components.dp(36)
                    implicitHeight: implicitWidth
                    radius: Theme.shape.radius("lg", height)
                    color: Theme.color.primaryContainer
                    Text {
                        anchors.centerIn: parent
                        text: "\ue7f4"
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                        color: Theme.color.fgPrimaryContainer
                    }
                }
                ThemedText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    text: Lang.t("ui.notif.title")
                    style: Theme.type.titleMedium
                    emphasized: true
                    elide: Text.ElideRight
                }
                Rectangle {
                    visible: NotificationService.unreadCount > 0
                    implicitWidth: unreadHeader.implicitWidth + Theme.space.md
                    implicitHeight: Theme.components.dp(20)
                    radius: height / 2
                    color: Theme.settings.nothing ? "transparent" : Theme.color.errorContainer
                    border.width: Theme.settings.nothing ? 1 : 0
                    border.color: Theme.color.error
                    ThemedText {
                        id: unreadHeader
                        anchors.centerIn: parent
                        text: NotificationService.unreadCount
                        style: Theme.type.labelMedium
                        emphasized: true
                        color: Theme.color.fgErrorContainer
                    }
                }
                MaterialIconButton {
                    visible: NotificationService.unreadCount > 0
                    icon: "done_all"
                    tooltip: Lang.t("ui.notif.markAllRead")
                    width: Theme.components.dp(34)
                    height: width
                    onClicked: NotificationService.markAllRead()
                }
                MaterialButton {
                    visible: NotificationService.count > 0
                    text: Lang.t("ui.notif.clear")
                    icon: "delete_sweep"
                    style: "tonal"
                    implicitHeight: Theme.components.buttonXS
                    onClicked: NotificationService.clearAll()
                }
                MaterialIconButton {
                    icon: "close"
                    width: Theme.components.dp(36)
                    height: width
                    onClicked: NotificationService.closeCenter()
                }
            }

            // ---- пошук ----
            Rectangle {
                id: searchRow
                Layout.fillWidth: true
                implicitHeight: Theme.components.dp(42)
                radius: Theme.shape.radius("full", height)
                color: Theme.settings.nothing ? "transparent" : Theme.color.surfaceContainerHigh
                border.width: searchInput.activeFocus || Theme.settings.nothing ? 1 : 0
                border.color: Theme.settings.nothing
                    ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, searchInput.activeFocus ? 0.7 : 0.22)
                    : Theme.color.primary

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space.md
                    anchors.rightMargin: Theme.space.xs
                    spacing: Theme.space.xs

                    Text {
                        text: "\ue8b6"       // search
                        color: Theme.color.fgSurfaceVariant
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconS }
                    }
                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height
                        verticalAlignment: TextInput.AlignVCenter
                        color: Theme.color.fgSurface
                        font.family: Theme.type.bodyLarge.family
                        font.pixelSize: Theme.type.bodyLarge.size
                        selectByMouse: true
                        clip: true
                        selectionColor: Theme.settings.nothing ? ThemeNothing.red : Theme.color.primary
                        selectedTextColor: Theme.settings.nothing ? "#FFFFFF" : Theme.color.fgPrimary
                        onTextChanged: win.query = text

                        ThemedText {
                            anchors.fill: parent
                            visible: searchInput.text.length === 0
                            text: Lang.t("ui.notif.search")
                            style: Theme.type.bodyLarge
                            color: Theme.color.fgSurfaceVariant
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    MaterialIconButton {
                        visible: searchInput.text.length > 0
                        icon: "close"
                        width: Theme.components.dp(30)
                        height: width
                        onClicked: { searchInput.text = ""; searchInput.forceActiveFocus() }
                    }
                }
            }

            // ---- фільтри ----
            RowLayout {
                id: filterRow
                Layout.fillWidth: true
                spacing: Theme.space.xs

                Chip { key: "all";    label: Lang.t("ui.notif.all");    count: NotificationService.count }
                Chip { key: "unread"; label: Lang.t("ui.notif.unread"); count: NotificationService.unreadCount }
                Chip { key: "pinned"; label: Lang.t("ui.notif.pinned"); count: NotificationService.pinnedItems.length }
                Item { Layout.fillWidth: true }
            }

            // ---- правила: заблоковані застосунки ----
            Item {
                id: rulesRow
                Layout.fillWidth: true
                implicitHeight: rulesFlow.implicitHeight
                visible: (NotificationService.blockedApps || []).length > 0

                Flow {
                    id: rulesFlow
                    width: parent.width
                    spacing: Theme.space.xs

                    ThemedText {
                        text: Lang.t("ui.notif.blocked")
                        height: Theme.components.dp(28)
                        verticalAlignment: Text.AlignVCenter
                        style: Theme.type.labelMedium
                        color: Theme.color.fgSurfaceVariant
                    }
                    Repeater {
                        model: NotificationService.blockedApps || []
                        delegate: Rectangle {
                            id: ruleChip
                            required property var modelData
                            readonly property bool hot: ruleMa.containsMouse
                            width: ruleTxt.implicitWidth + ruleX.implicitWidth + Theme.space.md * 2
                            height: Theme.components.dp(28)
                            radius: height / 2
                            color: hot ? Theme.color.error : Theme.color.errorContainer
                            Behavior on color { MotionColorAnimation { role: "hover" } }

                            Row {
                                anchors.centerIn: parent
                                spacing: Theme.space.xs
                                ThemedText {
                                    id: ruleTxt
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(ruleChip.modelData)
                                    style: Theme.type.labelMedium
                                    color: ruleChip.hot ? Theme.color.fgError : Theme.color.fgErrorContainer
                                }
                                Text {
                                    id: ruleX
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\ue5cd"
                                    font { family: Theme.type.icons; pixelSize: Theme.type.iconXS }
                                    color: ruleChip.hot ? Theme.color.fgError : Theme.color.fgErrorContainer
                                }
                            }
                            MouseArea {
                                id: ruleMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotificationService.setRule("blocked", ruleChip.modelData, false)
                            }
                        }
                    }
                }
            }

            // ---- не турбувати ----
            Rectangle {
                id: dndRow
                Layout.fillWidth: true
                implicitHeight: Theme.components.dp(48)
                radius: Theme.shape.cardLarge
                color: Theme.settings.nothing ? "transparent"
                     : NotificationService.dnd ? Theme.color.primaryContainer : Theme.color.surfaceContainerHigh
                border.width: Theme.settings.nothing ? 1 : 0
                border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, NotificationService.dnd ? 0.75 : 0.18)
                Behavior on color { MotionColorAnimation { role: "stateChange" } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space.md
                    anchors.rightMargin: Theme.space.sm
                    spacing: Theme.space.sm
                    Text {
                        text: NotificationService.dnd ? "\ue7f6" : "\ue7f4"
                        color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        ThemedText {
                            text: Lang.t("ui.notif.dnd")
                            style: Theme.type.bodyMedium
                            color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurface
                        }
                        ThemedText {
                            text: Lang.t("ui.notif.dnd.desc")
                            style: Theme.type.labelSmall
                            color: NotificationService.dnd ? Theme.color.fgPrimaryContainer : Theme.color.fgSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }
                    MaterialSwitch {
                        checked: NotificationService.dnd
                        onToggled: NotificationService.setDnd(!NotificationService.dnd)
                    }
                }
            }

            // ---- список ----
            Item {
                id: listBox
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.maximumHeight: win.maxListH
                implicitHeight: win.shownGroups.length === 0
                    ? Theme.components.dp(176)
                    : Math.min(Math.max(flick.contentHeight, Theme.components.dp(56)), win.maxListH)

                Flickable {
                    id: flick
                    anchors.fill: parent
                    clip: true
                    contentWidth: width
                    contentHeight: groupsCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: groupsCol
                        width: flick.width
                        spacing: Theme.space.md

                        Repeater {
                            model: ScriptModel {
                                values: win.shownGroups
                            }
                            NotificationGroup {}
                        }
                    }
                }

                // порожній стан
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: opacity > 0.01
                    opacity: win.shownGroups.length === 0 ? 1 : 0
                    scale: win.shownGroups.length === 0 ? 1 : 0.96
                    spacing: Theme.space.sm
                    Behavior on opacity { MotionAnimation { role: win.shownGroups.length === 0 ? "enter" : "exit" } }
                    Behavior on scale { MotionAnimation { role: win.shownGroups.length === 0 ? "enter" : "exit" } }
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: Theme.components.dp(56)
                        implicitHeight: implicitWidth
                        radius: Theme.shape.radius("lg", height)
                        color: Theme.settings.nothing ? "transparent" : Theme.color.secondaryContainer
                        border.width: Theme.settings.nothing ? 1 : 0
                        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.22)
                        Text {
                            anchors.centerIn: parent
                            text: win.query !== "" ? "\ue8b6" : "\ue7f4"
                            color: Theme.color.fgSecondaryContainer
                            font { family: Theme.type.icons; pixelSize: Theme.type.iconL }
                        }
                    }
                    ThemedText {
                        Layout.alignment: Qt.AlignHCenter
                        text: win.emptyMsg
                        style: Theme.type.bodyMedium
                        color: Theme.color.fgSurfaceVariant
                    }
                }
            }

            // ---- підсумок ----
            RowLayout {
                id: footerRow
                Layout.fillWidth: true
                spacing: Theme.space.sm

                ThemedText {
                    Layout.fillWidth: true
                    text: {
                        let t = Lang.tn("ui.notif.total", NotificationService.count)
                        if (NotificationService.unreadCount > 0)
                            t += " · " + Lang.tn("ui.notif.unreadCount", NotificationService.unreadCount)
                        return t
                    }
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                }
                MaterialButton {
                    visible: win.readCount > 0
                    text: Lang.t("ui.notif.clearRead")
                    icon: "done_all"
                    style: "text"
                    implicitHeight: Theme.components.buttonXS
                    onClicked: NotificationService.clearRead()
                }
            }
        }
    }

    // ---- фільтр-чип ----
    component Chip: Rectangle {
        id: chip
        property string key: "all"
        property string label: ""
        property int count: 0

        implicitHeight: Theme.components.dp(32)
        implicitWidth: chipRow.implicitWidth + Theme.space.lg
        radius: chipMa.pressed ? Theme.shape.buttonPressed : height / 2
        color: win.filter === chip.key
            ? (Theme.settings.nothing ? Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.10) : Theme.color.secondaryContainer)
            : (chipMa.containsMouse ? Theme.color.surfaceContainerHigh : "transparent")
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, win.filter === chip.key ? 0.7 : 0.2)
        scale: chipMa.pressed ? 0.97 : 1
        Behavior on color { MotionColorAnimation { role: "hover" } }
        Behavior on radius { MotionAnimation { role: "morph" } }
        Behavior on scale { MotionAnimation { role: "press" } }

        RowLayout {
            id: chipRow
            anchors.centerIn: parent
            spacing: Theme.space.xs
            ThemedText {
                text: chip.label
                style: Theme.type.labelLarge
                color: win.filter === chip.key
                    ? (Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgSecondaryContainer)
                    : Theme.color.fgSurfaceVariant
            }
            ThemedText {
                visible: chip.count > 0
                text: chip.count
                style: Theme.type.labelSmall
                color: win.filter === chip.key ? Theme.color.primary : Theme.color.fgSurfaceVariant
            }
        }
        MouseArea {
            id: chipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: win.filter = chip.key
        }
    }
}
