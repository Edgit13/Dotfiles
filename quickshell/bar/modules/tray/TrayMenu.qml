pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/shell"
import "root:/settings"
import "root:/modules/common"
import Quickshell
import Quickshell.Wayland
import QtQuick

// TrayMenu — M3-меню StatusNotifier-айтема (DBusMenu).
//
// Раніше це був PopupWindow (xdg_popup) із розміром від вмісту. DBusMenu вантажиться ліниво:
// при першому відкритті пунктів ще нема → popup мапиться «порожнім» і потім змінює розмір →
// меню розтягнуте / через раз порожнє, а grabFocus-popup на dwl-композиторах (MangoWM) ще й
// непередбачувано закривається. Тому, як у nova-shell / caelestia, меню — це оверлей-вікно на
// весь екран (layer Overlay) без жодних popup-grab'ів: розмір вікна фіксований, а картка
// просто малюється всередині й сама росте, коли підвантажаться пункти. Клік поза карткою /
// Esc закривають меню; підменю — drill-down із рядком «назад».
PanelWindow {
    id: root

    property Item anchorItem: null
    property string placement: "top"        // сторона бару: top | bottom | left | right

    property var initialMenu: null          // QsMenuHandle (SystemTrayItem.menu)
    property string initialTitle: ""
    property var _stack: []                 // [{ handle: QsMenuEntry, title: string }]
    property bool shown: false              // логічний стан; вікно живе ще на час анімації закриття
    property bool _settled: false           // після короткої паузи вважаємо, що пункти вже підвантажились

    // геометрія іконки в координатах екрана
    property real _ax: 0
    property real _ay: 0
    property real _aw: 0
    property real _ah: 0
    property real _sw: 1920
    property real _sh: 1080

    readonly property real edge: 8
    readonly property real gap: 6

    readonly property var currentMenu: _stack.length > 0
        ? _stack[_stack.length - 1].handle : initialMenu
    readonly property string headerTitle: _stack.length > 0
        ? _stack[_stack.length - 1].title : initialTitle

    signal menuDismissed()

    // необов'язковий нижній пункт «Сховати з бару / Показувати в барі»
    property string pinLabel: ""
    property string pinIcon: "\ue8f5"      // visibility_off
    signal pinClicked()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "edots-traymenu"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown || card.opacity > 0.01

    function openAt(handle, title) {
        if (!handle || !anchorItem) return
        const w = anchorItem.QsWindow.window
        if (!w || !w.screen) return

        const scr = w.screen
        const a = w.anchors
        const m = w.margins
        const p = anchorItem.mapToItem(null, 0, 0)
        const ox = a.left ? m.left : (a.right ? scr.width - w.width - m.right : (scr.width - w.width) / 2)
        const oy = a.top ? m.top : (a.bottom ? scr.height - w.height - m.bottom : (scr.height - w.height) / 2)

        _sw = scr.width
        _sh = scr.height
        _ax = ox + p.x
        _ay = oy + p.y
        _aw = anchorItem.width
        _ah = anchorItem.height

        screen = scr
        initialMenu = handle
        initialTitle = title || ""
        _stack = []
        _settled = false
        shown = true
        settle.restart()
    }
    function close() { shown = false }
    function drill(entry) {
        _stack = _stack.concat([{ handle: entry, title: entry.text }])
    }
    function back() {
        if (_stack.length > 0) _stack = _stack.slice(0, -1)
    }

    // поки меню відкрите, пілл бару не згортається (див. ShellState.setHold)
    readonly property string _holdKey: "traymenu-" + Math.random().toString(36).slice(2)
    onShownChanged: {
        if (shown) scope.forceActiveFocus()
        ShellState.setHold(_holdKey, shown, root.screen ? root.screen.name : "")
    }
    Component.onDestruction: ShellState.setHold(_holdKey, false, "")

    onVisibleChanged: {
        if (visible) {
            scope.forceActiveFocus()
        } else {
            settle.stop()
            _stack = []
            root.menuDismissed()
        }
    }

    Timer {
        id: settle
        interval: 350
        onTriggered: root._settled = true
    }

    QsMenuOpener {
        id: opener
        menu: root.currentMenu
    }

    Item {
        id: scope
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: {
            if (root._stack.length > 0) root.back()
            else root.close()
        }

        // клік будь-де поза карткою закриває меню
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.close()
        }

        ElevationShadow {
            id: card
            width: Theme.components.dp(236)
            height: Math.min(column.implicitHeight + Theme.space.sm * 2, root._sh - root.edge * 2)
            radius: Theme.shape.menu
            level: 3

            // вхід/вихід: fade + «виростання» від боку, з якого відкрито меню
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.9
            transformOrigin: root.placement === "bottom" ? Item.Bottom
                           : root.placement === "left"   ? Item.Left
                           : root.placement === "right"  ? Item.Right
                           : Item.Top
            Behavior on opacity { MotionAnimation { role: root.shown ? "fade" : "exit" } }
            Behavior on scale   { MotionAnimation { role: root.shown ? "enter" : "exit" } }
            // висота плавно підлаштовується, коли підвантажуються пункти / відкривається підменю
            Behavior on height  { enabled: root.shown; MotionAnimation { role: "morph" } }

            x: {
                let v
                if (root.placement === "left") v = root._ax + root._aw + root.gap
                else if (root.placement === "right") v = root._ax - width - root.gap
                else v = root._ax + root._aw / 2 - width / 2
                return Math.max(root.edge, Math.min(v, root._sw - width - root.edge))
            }
            y: {
                let v
                if (root.placement === "bottom") v = root._ay - height - root.gap
                else if (root.placement === "top") v = root._ay + root._ah + root.gap
                else v = root._ay + root._ah / 2 - height / 2
                return Math.max(root.edge, Math.min(v, root._sh - height - root.edge))
            }

            // клік по порожньому місцю картки не має закривати меню
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: Theme.space.sm
                contentWidth: width
                contentHeight: column.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                clip: true

                Column {
                    id: column
                    width: flick.width
                    spacing: 2

                    // ── «назад» у підменю ────────────────────────────────
                    Rectangle {
                        width: column.width
                        height: root._stack.length > 0 ? Theme.components.dp(36) : 0
                        visible: height > 0.5
                        opacity: root._stack.length > 0 ? 1 : 0
                        radius: Theme.shape.listItem
                        color: "transparent"
                        Behavior on height  { MotionAnimation { role: "move" } }
                        Behavior on opacity { MotionAnimation { role: "fade" } }

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Theme.stateLayer(Theme.color.surfaceContainerHigh, Theme.color.fgSurface,
                                                    Theme.components.stateHover)
                            opacity: backMa.containsMouse ? 1 : 0
                            Behavior on opacity { MotionAnimation { role: "hover" } }
                        }

                        BarIcon {
                            id: backIcon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space.sm
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\ue5c4"          // arrow_back
                            size: Theme.components.dp(18)
                            color: Theme.color.fgSurfaceVariant
                        }
                        ThemedText {
                            anchors.left: backIcon.right
                            anchors.leftMargin: Theme.space.sm
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space.sm
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.headerTitle
                            style: Theme.type.bodyMedium
                            color: Theme.color.fgSurface
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.back()
                        }
                    }

                    // ── пункти меню ──────────────────────────────────────
                    Repeater {
                        model: opener.children

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            property bool revealed: false
                            Component.onCompleted: revealed = true
                            readonly property var entry: modelData
                            readonly property bool separator: entry.isSeparator
                            readonly property bool hasIcon: !separator && entry.icon !== ""
                            readonly property bool hasCheck: !separator
                                && entry.buttonType !== QsMenuButtonType.None

                            width: column.width
                            height: separator ? Theme.components.dp(9) : Theme.components.dp(36)
                            radius: separator ? 0 : Theme.shape.listItem
                            color: "transparent"
                            readonly property bool show: revealed && root.shown
                            readonly property int stagger: root.shown ? Math.min(index, 10) * 22 : 0
                            opacity: (show ? 1 : 0) * (separator || entry.enabled ? 1 : 0.4)
                            Behavior on opacity { MotionStagger { role: "enter"; delay: row.stagger } }
                            transform: Translate {
                                y: row.show ? 0 : 6
                                Behavior on y { MotionStagger { role: "enter"; delay: row.stagger } }
                            }

                            // hover-шар: плавний fade замість миттєвої заливки
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.radius
                                visible: !row.separator && row.entry.enabled
                                color: Theme.stateLayer(Theme.color.surfaceContainerHigh, Theme.color.fgSurface,
                                                        Theme.components.stateHover)
                                opacity: rowMa.containsMouse ? 1 : 0
                                Behavior on opacity { MotionAnimation { role: "hover" } }
                            }

                            // розділювач
                            Rectangle {
                                visible: row.separator
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.space.xs
                                anchors.rightMargin: Theme.space.xs
                                height: 1
                                color: Theme.color.outlineVariant
                            }

                            // іконка пункту
                            Image {
                                id: entryIcon
                                visible: row.hasIcon
                                source: row.hasIcon ? row.entry.icon : ""
                                sourceSize.width: Theme.components.dp(18)
                                sourceSize.height: Theme.components.dp(18)
                                width: Theme.components.dp(18)
                                height: Theme.components.dp(18)
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.space.sm
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                            }

                            // чекбокс / радіо
                            BarIcon {
                                id: checkIcon
                                visible: row.hasCheck
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.space.sm
                                anchors.verticalCenter: parent.verticalCenter
                                size: Theme.components.dp(18)
                                color: row.entry.checkState === Qt.Checked
                                    ? Theme.color.primary : Theme.color.fgSurfaceVariant
                                text: {
                                    const checked = row.entry.checkState === Qt.Checked
                                    if (row.entry.buttonType === QsMenuButtonType.RadioButton)
                                        return checked ? "\ue837" : "\ue836"   // radio_button_checked/unchecked
                                    return checked ? "\ue834" : "\ue835"       // check_box/check_box_outline_blank
                                }
                            }

                            ThemedText {
                                anchors.left: row.hasCheck ? checkIcon.right
                                            : row.hasIcon ? entryIcon.right
                                            : parent.left
                                anchors.leftMargin: Theme.space.sm
                                anchors.right: chevron.visible ? chevron.left : parent.right
                                anchors.rightMargin: Theme.space.sm
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.separator ? "" : row.entry.text
                                style: Theme.type.bodyMedium
                                color: Theme.color.fgSurface
                                elide: Text.ElideRight
                            }

                            BarIcon {
                                id: chevron
                                visible: !row.separator && row.entry.hasChildren
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.space.sm
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\ue5cc"          // chevron_right
                                size: Theme.components.dp(18)
                                color: Theme.color.fgSurfaceVariant
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                enabled: !row.separator && row.entry.enabled
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (row.entry.hasChildren) root.drill(row.entry)
                                    else {
                                        row.entry.triggered()
                                        root.close()
                                    }
                                }
                            }
                        }
                    }

                    // ── «Сховати з бару» / «Показувати в барі» ───────────
                    Item {
                        width: column.width
                        height: root.pinLabel !== "" ? Theme.components.dp(9) : 0
                        visible: height > 0
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.space.xs
                            anchors.rightMargin: Theme.space.xs
                            height: 1
                            color: Theme.color.outlineVariant
                        }
                    }
                    Rectangle {
                        width: column.width
                        height: root.pinLabel !== "" ? Theme.components.dp(36) : 0
                        visible: height > 0
                        radius: Theme.shape.listItem
                        color: "transparent"

                        Rectangle {
                            anchors.fill: parent
                            radius: parent.radius
                            color: Theme.stateLayer(Theme.color.surfaceContainerHigh, Theme.color.fgSurface,
                                                    Theme.components.stateHover)
                            opacity: pinMa.containsMouse ? 1 : 0
                            Behavior on opacity { MotionAnimation { role: "hover" } }
                        }
                        BarIcon {
                            id: pinGlyph
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.space.sm
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pinIcon
                            size: Theme.components.dp(18)
                            color: Theme.color.fgSurfaceVariant
                        }
                        ThemedText {
                            anchors.left: pinGlyph.right
                            anchors.leftMargin: Theme.space.sm
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.space.sm
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.pinLabel
                            style: Theme.type.bodyMedium
                            color: Theme.color.fgSurface
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            id: pinMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.pinClicked(); root.close() }
                        }
                    }

                    // порожнє меню (буває в деяких апів) — показуємо лише коли пункти точно не прийшли
                    ThemedText {
                        width: column.width
                        height: (opener.children.values.length === 0 && root._settled) ? Theme.components.dp(36) : 0
                        visible: height > 0
                        text: Lang.t("tray.menu.empty")
                        style: Theme.type.bodyMedium
                        color: Theme.color.fgSurfaceVariant
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }
}
