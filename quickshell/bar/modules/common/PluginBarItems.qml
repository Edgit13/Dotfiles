import "root:/services"
import QtQuick
import QtQuick.Layouts

// PluginBarItems — the Repeater that turns enabled bar plugins into items.
//
// It lives in its own component on purpose: BarWindow is instantiated once per
// screen from Quickshell.Variants, which gives it a `modelData` property (the
// monitor). A Repeater declared inside BarWindow would see that property
// instead of its own delegate `modelData`, so the plugin delegate received the
// monitor object. Keeping the Repeater here gives it a clean delegate context.
Repeater {
    id: root

    // leading | center | trailing | sorted (every plugin with a bar entry)
    property string position: "trailing"
    property bool vertical: false
    property real cross: 0
    // Layout.alignment for hosts that are a RowLayout/GridLayout (0 = none).
    property int layoutAlignment: 0

    readonly property var entries: position === "leading" ? PluginService.leadingBarPlugins
        : position === "center" ? PluginService.centerBarPlugins
        : position === "trailing" ? PluginService.trailingBarPlugins
        : PluginService.barPluginsSorted

    model: entries

    delegate: PluginBarSlot {
        vertical: root.vertical
        cross: root.cross
        Layout.alignment: root.layoutAlignment
    }

    // Repeater's `modelData`/`index` context properties are not visible from a
    // file-based delegate component, so hand each item its plugin explicitly.
    onItemAdded: (index, item) => { item.plugin = root.entries[index] }
}
