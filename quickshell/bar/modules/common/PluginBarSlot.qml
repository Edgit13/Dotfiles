import "root:/theme"
import "root:/services"
import QtQuick

// PluginBarSlot — loads one plugin bar module from its own folder.
// The module receives `vertical` and `cross`; it should define both with
// defaults so it still works when previewed outside the bar.
Loader {
    id: root

    property var plugin: null
    property bool vertical: false
    property real cross: 0

    active: !!plugin
    source: active ? PluginService.barQml(plugin) : ""

    // плагіни з'являються/зникають так само м'яко, як вбудовані модулі
    opacity: active && status === Loader.Ready ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { MotionAnimation { role: "fade" } }

    function applyHostProperties() {
        if (!item) return
        if (item.vertical !== undefined) item.vertical = root.vertical
        if (item.cross !== undefined) item.cross = root.cross
    }

    onLoaded: {
        // Loader copies its own visible state onto the item when it is created,
        // and the delegate may be created before the slot becomes active.
        if (item && !item.visible) item.visible = true
        applyHostProperties()
    }
    onVerticalChanged: applyHostProperties()
    onCrossChanged: applyHostProperties()
    onStatusChanged: {
        if (status === Loader.Ready) applyHostProperties()
        else if (status === Loader.Error)
            console.warn("[plugins] failed to load bar module:", plugin ? plugin.id : "?")
    }
}
