pragma ComponentBehavior: Bound
import "root:/theme"
import "root:/services"
import Quickshell
import QtQuick
import QtQuick.Effects

// NotifIcon — іконка застосунку у squircle-бейджі; фото сповіщення, якщо воно справді фото.
// Без іконки — літера застосунку (ніколи не показуємо магентовий «image-missing»).
//
// image-path у D-Bus часто містить не файл, а ім'я іконки ("telegram"), тому значення
// розрізняємо: шлях/URL → фото, голе ім'я → іконка теми. Для імені спершу шукаємо
// desktop-entry (за id, назвою або частиною іконки), потім appIcon, потім саме ім'я.
Item {
    id: root
    required property var notif
    property bool critical: false
    // група/бар/локскрін: беремо іконку застосунку навіть якщо сповіщення несе фото
    property bool appOnly: false

    readonly property string photo: {
        if (root.appOnly || !root.notif) return ""
        const v = root.notif.image ? String(root.notif.image) : ""
        return NotificationService.isImageSource(v) ? v : ""
    }
    property bool photoBroken: false
    onNotifChanged: root.photoBroken = false
    onPhotoChanged: root.photoBroken = false

    readonly property bool isPhoto: root.photo.length > 0 && !root.photoBroken
    // порядок: app-icon → desktop-entry → назва застосунку → image як ім'я іконки
    readonly property string iconSource: {
        const n = root.notif || {}
        // залежність від індексу desktop-entry: він наповнюється асинхронно
        const apps = DesktopEntries.applications.values
        const names = []
        if (n.appIcon) names.push(n.appIcon)
        const byEntry = root._entry(n.desktopEntry)
        if (byEntry && byEntry.icon) names.push(byEntry.icon)
        const byName = root._entry(n.appName)
        if (byName && byName.icon) names.push(byName.icon)
        if (n.image && !NotificationService.isImageSource(n.image)) names.push(n.image)
        for (let i = 0; i < names.length; i++) {
            const resolved = root._resolve(names[i])
            if (resolved.length > 0) return resolved
        }
        return ""
    }
    readonly property string src: root.isPhoto ? root.photo : root.iconSource
    readonly property bool hasImg: root.src.length > 0 && img.status === Image.Ready

    // squircle: фото — більш квадратне, іконка — майже коло
    readonly property real shapeRadius: root.isPhoto ? Theme.shape.radius("md", height) : Theme.shape.radius("lg", height)

    function _resolve(value) {
        let s = String(value || "").trim()
        if (s === "") return ""
        if (s.indexOf("image://icon/") === 0) s = s.substring("image://icon/".length)
        s = s.split("?")[0].trim()
        if (s === "") return ""
        if (s.charAt(0) === "/") return "file://" + s
        if (/^(file|data|qrc|https?):/i.test(s)) return s
        if (s.indexOf("image:") === 0) return s
        // checked lookup: "" замість магентового плейсхолдера, коли іконки немає
        return Quickshell.iconPath(s, "")
    }

    function _entry(name) {
        if (!name) return null
        const s = String(name).trim()
        if (s === "" || s.charAt(0) === "/") return null
        const direct = DesktopEntries.heuristicLookup(s)
        if (direct) return direct
        const wanted = s.toLowerCase()
        const apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            if (String(e.name || "").toLowerCase() === wanted) return e
            const icon = String(e.icon || "").toLowerCase()
            if (icon === wanted) return e
            // "telegram" знаходить org.telegram.desktop
            if (icon.split(".").indexOf(wanted) >= 0) return e
        }
        return null
    }

    Rectangle {
        anchors.fill: parent
        radius: root.shapeRadius
        color: root.critical ? (Theme.settings.nothing ? "transparent" : Theme.color.error)
             : (Theme.settings.nothing ? "transparent" : Theme.color.primaryContainer)
        // Nothing: контурна «плитка» іконки; критичне — червоний контур
        border.width: Theme.settings.nothing ? 1 : 0
        border.color: root.critical ? ThemeNothing.red : Qt.rgba(Theme.color.fgSurface.r, Theme.color.fgSurface.g, Theme.color.fgSurface.b, 0.28)
        visible: !root.isPhoto
        Behavior on color { MotionColorAnimation { role: "stateChange" } }
        ThemedText {
            anchors.centerIn: parent
            visible: !root.hasImg
            text: (root.notif && root.notif.appName ? String(root.notif.appName) : "?").charAt(0).toUpperCase()
            style: Theme.type.titleMedium
            emphasized: true
            color: root.critical ? (Theme.settings.nothing ? ThemeNothing.red : Theme.color.fgError)
                 : (Theme.settings.nothing ? Theme.color.fgSurface : Theme.color.fgPrimaryContainer)
        }
    }

    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: root.shapeRadius }
    }
    Image {
        id: img
        anchors.fill: parent
        anchors.margins: root.isPhoto ? 0 : root.width * 0.18
        source: root.src
        fillMode: root.isPhoto ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        asynchronous: true
        sourceSize.width: 128
        sourceSize.height: 128
        opacity: root.hasImg ? 1 : 0
        Behavior on opacity { MotionAnimation { role: "enter" } }
        layer.enabled: root.isPhoto
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        onStatusChanged: {
            if (status === Image.Error && root.isPhoto) root.photoBroken = true
        }
    }
}
