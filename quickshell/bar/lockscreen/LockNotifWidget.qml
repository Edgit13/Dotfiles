import QtQuick
import "root:/theme"
import "root:/settings"
import "root:/services"
import "root:/notifications"

// LockNotifWidget — сповіщення просто на екрані блокування.
// Режими (Settings → Локскрін → Сповіщення):
//   off   — не показувати
//   count — лише лічильник
//   list  — лічильник + компактні картки (не більше lockscreen.notifMax)
// Текст сповіщень показується тільки якщо lockscreen.notifContent = true;
// інакше видно лише застосунок і кількість. Взаємодії немає — це не спосіб
// обійти блокування.
Item {
    id: root

    required property var host                 // LockM3 / LockNothing
    property bool shaped: false                // увімкнена M3/Nothing-форма фону
    property color shapeFg: "#ffffff"          // колір тексту на формі

    readonly property real k: host && host.k ? host.k : 1
    readonly property bool nothing: Theme.settings.nothing
    readonly property bool editable: !!(host && host.editable)
    readonly property string mode: String(Settings.get("lockscreen", "notifMode") || "count")
    readonly property bool showContent: Settings.get("lockscreen", "notifContent") === true
    readonly property int maxItems: Math.max(1, Math.round(Number(Settings.get("lockscreen", "notifMax") ?? 3)))
    readonly property var items: (NotificationService.items || []).slice(0, maxItems)
    readonly property int total: NotificationService.count
    readonly property int unread: NotificationService.unreadCount
    readonly property real cardW: Math.max(190 * k, Math.min(330 * k, (host ? host.width : 1280) * 0.44))

    readonly property color ink: shaped ? shapeFg
                               : (nothing ? "#F2F2F2" : Theme.color.fgSurface)
    readonly property color dim: shaped ? Qt.rgba(shapeFg.r, shapeFg.g, shapeFg.b, 0.64)
                               : (nothing ? Qt.rgba(1, 1, 1, 0.55) : Theme.color.fgSurfaceVariant)
    readonly property color accent: nothing ? ThemeNothing.red : Theme.color.primary
    readonly property color face: shaped ? Qt.rgba(shapeFg.r, shapeFg.g, shapeFg.b, 0.10)
                               : (nothing ? Qt.rgba(0, 0, 0, 0.58)
                                          : Qt.rgba(Theme.color.surfaceContainerHigh.r,
                                                    Theme.color.surfaceContainerHigh.g,
                                                    Theme.color.surfaceContainerHigh.b, 0.88))
    readonly property color edge: shaped ? Qt.rgba(shapeFg.r, shapeFg.g, shapeFg.b, 0.30)
                               : (nothing ? Qt.rgba(1, 1, 1, 0.20) : "transparent")

    implicitWidth: body.implicitWidth
    implicitHeight: body.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Column {
        id: body
        width: implicitWidth
        spacing: 8 * root.k

        // ── лічильник ──
        Rectangle {
            implicitWidth: headRow.implicitWidth + 26 * root.k
            implicitHeight: 34 * root.k
            width: implicitWidth
            height: implicitHeight
            radius: root.nothing ? 10 : height / 2
            color: root.face
            border.width: (root.nothing || root.shaped) ? 1 : 0
            border.color: root.edge

            Row {
                id: headRow
                anchors.centerIn: parent
                spacing: 7 * root.k

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "off" ? "notifications_off" : "notifications"
                    color: root.mode === "off" ? root.dim : root.ink
                    font { family: Theme.type.icons; pixelSize: Math.round(18 * root.k) }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mode === "off"
                          ? Lang.t("lock.notif.off")
                          : Lang.t("lock.notif.count").replace("{n}", root.total)
                    color: root.mode === "off" ? root.dim : root.ink
                    font {
                        family: root.nothing ? Theme.type.mono : Theme.type.sans
                        pixelSize: Math.round(12 * root.k)
                        weight: Font.Medium
                        letterSpacing: root.nothing ? 1.5 : 0
                    }
                }
                Rectangle {
                    visible: root.mode !== "off" && root.unread > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6 * root.k; height: width; radius: width / 2
                    color: root.accent
                }
            }
        }

        // ── картки ──
        Repeater {
            model: root.mode === "list" ? root.items : []

            Rectangle {
                id: card
                required property var modelData
                readonly property var it: modelData

                implicitWidth: root.cardW
                implicitHeight: Math.max(30 * root.k, msg.implicitHeight) + 18 * root.k
                width: implicitWidth
                height: implicitHeight
                radius: root.nothing ? 10 : 16
                color: root.face
                border.width: (root.nothing || root.shaped) ? 1 : 0
                border.color: root.edge
                clip: true

                // непрочитане — акцентна смужка
                Rectangle {
                    visible: !card.it.read
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 3 * root.k
                    color: root.accent
                }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: (card.it.read ? 9 : 12) * root.k
                    anchors.rightMargin: 9 * root.k
                    anchors.topMargin: 8 * root.k
                    anchors.bottomMargin: 8 * root.k
                    spacing: 9 * root.k

                    NotifIcon {
                        width: 28 * root.k
                        height: width
                        notif: card.it
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        id: msg
                        width: card.width - (card.it.read ? 9 : 12) * root.k
                               - 9 * root.k - 28 * root.k - 9 * root.k - 9 * root.k
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1 * root.k

                        Text {
                            width: parent.width
                            text: root.nothing ? String(card.it.appName || "").toUpperCase()
                                               : (card.it.appName || "")
                            color: root.dim
                            elide: Text.ElideRight
                            font {
                                family: root.nothing ? Theme.type.mono : Theme.type.sans
                                pixelSize: Math.round(11 * root.k)
                                weight: Font.Medium
                                letterSpacing: root.nothing ? 1.2 : 0
                            }
                        }
                        Text {
                            width: parent.width
                            visible: root.showContent && text.length > 0
                            text: card.it.summary || ""
                            color: root.ink
                            elide: Text.ElideRight
                            font { family: Theme.type.sans; pixelSize: Math.round(13 * root.k); weight: Font.DemiBold }
                        }
                        Text {
                            width: parent.width
                            visible: root.showContent && text.length > 0
                            text: card.it.body || ""
                            color: root.dim
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font { family: Theme.type.sans; pixelSize: Math.round(12 * root.k) }
                        }
                    }
                }
            }
        }

        // ── порожній стан (видно в редакторі прев'ю) ──
        Rectangle {
            visible: root.mode === "list" && root.items.length === 0
            implicitWidth: root.cardW
            implicitHeight: 42 * root.k
            width: implicitWidth
            height: implicitHeight
            radius: root.nothing ? 10 : 16
            color: root.face
            border.width: (root.nothing || root.shaped) ? 1 : 0
            border.color: root.edge

            Text {
                anchors.centerIn: parent
                text: Lang.t("lock.notif.empty")
                color: root.dim
                font {
                    family: root.nothing ? Theme.type.mono : Theme.type.sans
                    pixelSize: Math.round(12 * root.k)
                    letterSpacing: root.nothing ? 1.2 : 0
                }
            }
        }
    }
}
