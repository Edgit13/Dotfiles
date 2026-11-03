# Edots plugins

A plugin is a folder with a `plugin.json` manifest. It can add a **surface**
panel (opened from the bar, Settings, a keybind or IPC) and/or a module in the
**bar**. The bundled `world-clock` example shows both.

```
plugins/
└── world-clock/
    ├── plugin.json
    ├── WorldClock.qml       # optional surface
    └── WorldClockBar.qml    # optional bar module
```

## Where plugins live

| Source | Folder |
|---|---|
| Your plugins | `~/.config/edots/plugins/<id>/` |
| Bundled examples | `quickshell/bar/plugins/<id>/` (installed as `~/.config/quickshell/bar/plugins/`) |

A user plugin with the same `id` as a bundled plugin overrides it. Enable state
is stored in `~/.config/quickshell/plugins.json`; it is separate from the
plugin folders, so updating dotfiles never loses your choices.

Open the folder from Settings → **Plugins** → **Plugins folder**, or run
`edots plugin folder`.

## Manifest

```json
{
  "id": "world-clock",
  "name": "World Clock",
  "description": "Local time plus a few cities.",
  "version": "1.0.0",
  "author": "Edots",
  "icon": "public",
  "defaultEnabled": false,
  "surface": {
    "qml": "WorldClock.qml",
    "width": 520,
    "height": 460,
    "end": true,
    "typing": false
  },
  "bar": {
    "qml": "WorldClockBar.qml",
    "position": "trailing",
    "order": 100
  }
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | `[a-z0-9][a-z0-9._-]*`, at most 64 characters, unique |
| `name` | no | Shown in Settings and as the surface title; defaults to `id` |
| `description`, `version`, `author` | no | Shown in Settings |
| `icon` | no | Material Symbols ligature (for example `public`); defaults to `extension` |
| `defaultEnabled` | no | State before the user flips the switch; defaults to `false` |
| `surface.qml` | yes* | QML file inside the plugin folder |
| `surface.width` / `height` | no | Panel size in dp; defaults to 560 × 480 |
| `surface.end` | no | Anchor the panel to the end of the bar instead of its start |
| `surface.typing` | no | Request keyboard focus for text input |
| `bar.qml` | yes* | QML file inside the plugin folder |
| `bar.position` | no | `leading`, `center` or `trailing`; defaults to `trailing` |
| `bar.order` | no | Sort order inside the group; defaults to 100 |

\* A plugin must provide at least one of `surface` or `bar`. Entry paths must
stay inside the plugin folder and be plain `.qml` files (max 1.5 MB).

## Writing QML

Plugin files are loaded from their own folder but can import the shell modules:

```qml
import qs.theme          // Theme singleton and ThemedText
import qs.services       // PluginService, DisplayService, …
import qs.shell          // ShellState
import qs.modules.common // BarButton, BarIcon, …
import Quickshell
import QtQuick
import QtQuick.Layouts
```

A surface fills the panel content area. Give it a normal `Item`/`Layout` root and
optionally a `signal requestClose()` to close the panel from inside.

A bar module can define:

```qml
Item {
    property bool vertical: false
    property real cross: 32

    implicitWidth: …
    implicitHeight: …
}
```

The host sets `vertical` and `cross` when it loads the module. Set both with
defaults so the file also works when previewed alone. `implicitWidth` and
`implicitHeight` decide the module's space in the bar.

Clicking a bar module can open its own surface:

```qml
MouseArea {
    anchors.fill: parent
    onClicked: ShellState.toggleSurface("plugin:world-clock")
}
```

## Commands

```bash
edots plugin                 # list plugins and state
edots plugin open <id>       # open a surface (the shell starts if needed)
edots plugin enable <id>
edots plugin disable <id>
edots plugin toggle <id>
edots plugin reload          # rescan folders
edots plugin folder          # open ~/.config/edots/plugins
edots plugin path            # print the folder
edots plugin json            # raw JSON (used by the shell)

qs ipc call plugins open world-clock
qs ipc call plugins setEnabled world-clock true
qs ipc call plugins reload
```

Settings → **Plugins** has the same controls plus the manifest error list.

## Trust and safety

Plugins are arbitrary QML and run with your user privileges. There is **no
sandbox**. Only install plugins you trust, and remember that loading a plugin
can read files, run processes and change shell state. Manifest validation only
keeps entry paths inside the plugin folder and checks the JSON shape — it is
not a security boundary.

Animations should use the shell's motion roles (`MotionAnimation`,
`MotionColorAnimation`) so Reduce Motion and Animation Speed keep working.
