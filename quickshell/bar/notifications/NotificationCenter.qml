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
    property var selected: null        // вибір з клавіатури (NotifItem)
    property bool menuOpen: false
    readonly property var shownGroups: NotificationService.appGroups(win.filter, win.query)
    // плоский список у тому ж порядку, що й на екрані (група → її картки)
    readonly property var flatItems: {
        const out = []
        const gs = win.shownGroups
        for (let i = 0; i < gs.length; i++) {
            const its = gs[i].items || []
            for (let j = 0; j < its.length; j++) out.push(its[j])
        }
        return out
    }
    readonly property int readCount: NotificationService.items.filter(i => i.read).length
    readonly property string emptyMsg: win.query !== "" ? Lang.t("ui.notif.noResults")
        : win.filter === "unread" ? Lang.t("ui.notif.noUnread")
        : win.filter === "pinned" ? Lang.t("ui.notif.noPinned")
        : Lang.t("ui.notif.empty")

    readonly property var headerActions: {
        const list = []
        if (NotificationService.unreadCount > 0)
            list.push({ icon: "done_all", label: Lang.t("ui.notif.markAllRead"),
                        run: function () { NotificationService.markAllRead() } })
        if (win.readCount > 0)
            list.push({ icon: "delete_sweep", label: Lang.t("ui.notif.clearRead"),
                        run: function () { NotificationService.clearRead() } })
        if (NotificationService.count > 0)
            list.push({ icon: "close", label: Lang.t("ui.notif.clear"), danger: true,
                        run: function () { NotificationService.clearAll() } })
        return list
    }

    function openMenu(anchor, actions) {
        if (!anchor || !actions || actions.length === 0) return
        win.menuOpen = true
        menu.show(anchor, actions)
    }
    function closeMenu() {
        menu.close()
    }
    function resetSelection() {
        win.selected = win.flatItems.length > 0 ? win.flatItems[0] : null
    }
    function syncSelection() {
        if (!win.open) return
        if (!win.selected || win.flatItems.indexOf(win.selected) < 0) resetSelection()
    }
    function moveSelection(delta) {
        const list = win.flatItems
        if (list.length === 0) { win.selected = null; return }
        let i = list.indexOf(win.selected)
        if (i < 0) i = delta > 0 ? 0 : list.length - 1
        else i = Math.max(0, Math.min(list.length - 1, i + delta))
        win.selected = list[i]
    }
    function activateSelected() {
        if (!win.selected) return
        NotificationService.activateItem(win.selected)
    }
    function snoozeSelected() {
        if (win.selected) NotificationService.snooze(win.selected)
    }
    function togglePinSelected() {
        if (win.selected) NotificationService.togglePin(win.selected)
    }
    function copySelected() {
        if (win.selected) NotificationService.copy(win.selected)
    }
    function dismissSelected() {
        if (win.selected) NotificationService.dismiss(win.selected)
    }

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
        if (!win.open) {
            win.closeMenu()
            win.selected = null
            return
        }
        win.filter = "all"
        win.query = ""
        searchInput.text = ""
        win.resetSelection()
        panel.forceActiveFocus()
    }
    onShownGroupsChanged: Qt.callLater(win.syncSelection)
    onFilterChanged: Qt.callLater(win.resetSelection)
    onQueryChanged: Qt.callLater(win.syncSelection)

    Connections {
        target: NotificationService
        function onItemsChanged() { Qt.callLater(win.syncSelection) }
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
        Keys.onEscapePressed: {
            if (win.menuOpen) { win.closeMenu(); return }
            if (win.query !== "") {
                searchInput.text = ""
                win.query = ""
                searchInput.forceActiveFocus()
                return
            }
            NotificationService.closeCenter()
        }
        Keys.onPressed: function (e) {
            if (e.key === Qt.Key_Escape) return
            if (win.menuOpen) return
            if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
            switch (e.key) {
            case Qt.Key_Slash:
                searchInput.forceActiveFocus()
                e.accepted = true
                break
            case Qt.Key_Up:
                win.moveSelection(-1)
                e.accepted = true
                break
            case Qt.Key_Down:
                win.moveSelection(1)
                e.accepted = true
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                win.activateSelected()
                e.accepted = true
                break
            case Qt.Key_Delete:
                win.dismissSelected()
                e.accepted = true
                break
            case Qt.Key_P:
                win.togglePinSelected()
                e.accepted = true
                break
            case Qt.Key_S:
                win.snoozeSelected()
                e.accepted = true
                break
            case Qt.Key_C:
                win.copySelected()
                e.accepted = true
                break
            }
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
                    implicitWidth: Theme.components.dp(40)
                    implicitHeight: implicitWidth
                    radius: Theme.shape.radius("lg", height)
                    color: Theme.settings.nothing ? "transparent" : Theme.color.primaryContainer
                    border.width: Theme.settings.nothing ? 1 : 0
                    border.color: Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.25)
                    Text {
                        anchors.centerIn: parent
                        text: NotificationService.dnd ? "\ue7f6" : "\ue7f4"
                        font { family: Theme.type.icons; pixelSize: Theme.type.iconM }
                        color: Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgPrimaryContainer
                    }
                    Behavior on color { MotionColorAnimation { role: "stateChange" } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredWidth: 0
                    spacing: 0

                    ThemedText {
                        Layout.fillWidth: true
                        text: Lang.t("ui.notif.title")
                        style: Theme.type.titleMedium
                        emphasized: true
                        elide: Text.ElideRight
                    }
                    ThemedText {
                        Layout.fillWidth: true
                        text: {
                            const shown = win.flatItems.length
                            const total = NotificationService.count
                            if (win.query !== "" || win.filter !== "all")
                                return Lang.t("ui.notif.showing").replace("{n}", shown).replace("{m}", total)
                            if (total === 0) return Lang.t("ui.notif.empty")
                            if (NotificationService.unreadCount > 0)
                                return Lang.tn("ui.notif.unreadCount", NotificationService.unreadCount)
                                     + " · " + Lang.tn("ui.notif.total", total)
                            return Lang.tn("ui.notif.total", total)
                        }
                        style: Theme.type.labelSmall
                        color: NotificationService.unreadCount > 0 ? Theme.color.primary : Theme.color.fgSurfaceVariant
                        elide: Text.ElideRight
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
                MaterialIconButton {
                    id: headerMenuBtn
                    icon: "more_vert"
                    tooltip: Lang.t("ui.notif.moreActions")
                    width: Theme.components.dp(34)
                    height: width
                    onClicked: win.openMenu(headerMenuBtn, win.headerActions)
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
                            NotificationGroup {
                                active: win.open
                                stackIndex: index
                                selectedItem: win.selected
                                onMenuRequested: (anchor, actions) => win.openMenu(anchor, actions)
                            }
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
                ThemedText {
                    visible: win.shownGroups.length > 0
                    text: Lang.t("ui.notif.keys")
                    style: Theme.type.labelSmall
                    color: Theme.color.fgSurfaceVariant
                    opacity: 0.75
                }
            }
        }

        // ---- меню «⋮» ----
        MouseArea {
            anchors.fill: parent
            visible: win.menuOpen
            enabled: win.menuOpen
            z: 900
            onClicked: win.closeMenu()
            onWheel: wheel => { wheel.accepted = true }
        }
        NotifMenu {
            id: menu
            onClosed: win.menuOpen = false
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
