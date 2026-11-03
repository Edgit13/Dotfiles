import "root:/services"
import QtQuick

// PluginBarSlot — loads one plugin bar module from its own folder.
// The module receives `vertical` and `cross`; it should define both with
// defaults so it still works when previewed outside the bar.
Loader {
    id: root

    required property var plugin
    property bool vertical: false
    property real cross: 0

    active: !!plugin
    source: active ? PluginService.barQml(plugin) : ""

    visible: active && status === Loader.Ready && item && item.visible !== false
    implicitWidth: item ? item.implicitWidth : 0
    implicitHeight: item ? item.implicitHeight : 0

    function applyHostProperties() {
        if (!item) return
        if (item.vertical !== undefined) item.vertical = root.vertical
        if (item.cross !== undefined) item.cross = root.cross
    }

    onLoaded: applyHostProperties()
    onVerticalChanged: applyHostProperties()
    onCrossChanged: applyHostProperties()
    onStatusChanged: {
        if (status === Loader.Ready) applyHostProperties()
        else if (status === Loader.Error)
            console.warn("[plugins] failed to load bar module:", plugin ? plugin.id : "?")
    }
}
