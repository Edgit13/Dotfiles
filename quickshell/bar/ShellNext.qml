//@ pragma UseQApplication
pragma ComponentBehavior: Bound

import "root:/shell"
import "root:/theme"
import "root:/services"
import "root:/states"
import "root:/osd"
import "root:/notifications"
import "root:/dock"
import "root:/settings"
import "root:/windows"
import "root:/gameoverlay"
import "root:/screentool"
import "root:/lockscreen"
import "root:/widgets/desktop"
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    Component.onCompleted: {
        LayoutService.ensure()
        GameModeState.ensure()
        RecordService.ensure()
        MonitorService.ensure()        // легкий процес-монітор (procwatch.py)
        TimerService.ensure()          // перечитати таймери utimer і заново запустити очікування після входу
        SessionService.ensure()        // застосувати таймери простою до swayidle
        PluginService.ensure()         // знайти ~/.config/edots/plugins + вбудовані плагіни
    }

    id: root

    TaskManagerWindow { id: taskManagerWindow }
    SettingsWindow    { id: settingsWindow }
    ScreenTool        { id: screenTool }
    LockScreen        { id: lockScreen }

    Connections {
        target: ShellState

        function onOpenSettingsRequested()   { settingsWindow.open() }
        function onToggleSettingsRequested() { settingsWindow.toggle() }
        function onCloseSettingsRequested()  { settingsWindow.close() }

        function onOpenTasksRequested()   { taskManagerWindow.open() }
        function onToggleTasksRequested() { taskManagerWindow.toggle() }
        function onCloseTasksRequested()  { taskManagerWindow.close() }
    }

    // Settings → Plugins asks the service to open a panel; close Settings first
    // so the surface is not hidden behind the settings window.
    Connections {
        target: PluginService
        function onOpenSurfaceRequested(id) {
            ShellState.closeSettings()
            if (PluginService.hasSurface(id))
                ShellState.openSurface("plugin:" + id)
        }
    }

    IpcHandler {
        target: "pill"
        function showLauncher(): void   { ShellState.openSurface("launcher") }
        function toggleLauncher(): void { ShellState.toggleSurface("launcher") }
        function showWallpaper(): void   { ShellState.openSurface("wallpaper") }
        function toggleWallpaper(): void { ShellState.toggleSurface("wallpaper") }
        function showClipboard(): void   { ShellState.openSurface("clipboard") }
        function toggleClipboard(): void { ShellState.toggleSurface("clipboard") }
        function showMixer(): void   { ShellState.openSurface("mixer") }
        function toggleMixer(): void { ShellState.toggleSurface("mixer") }
        function showAudio(): void   { ShellState.openSurface("audio") }
        function toggleAudio(): void { ShellState.toggleSurface("audio") }
        function showDisplay(): void   { ShellState.openSurface("display") }
        function toggleDisplay(): void { ShellState.toggleSurface("display") }
        function showWifi(): void   { ShellState.openSurface("wifi") }
        function toggleWifi(): void { ShellState.toggleSurface("wifi") }
        function showBluetooth(): void   { ShellState.openSurface("bluetooth") }
        function toggleBluetooth(): void { ShellState.toggleSurface("bluetooth") }
        function showMedia(): void   { ShellState.openSurface("media") }
        function toggleMedia(): void { ShellState.toggleSurface("media") }
        function showPower(): void   { ShellState.openSurface("power") }
        function togglePower(): void { ShellState.toggleSurface("power") }
        function showBinds(): void   { ShellState.openSurface("binds") }
        function toggleBinds(): void { ShellState.toggleSurface("binds") }
        function showResources(): void   { ShellState.openSurface("resources") }
        function toggleResources(): void { ShellState.toggleSurface("resources") }
        function showSettings(): void   { ShellState.toggleSettings() }
        function toggleSettings(): void { ShellState.toggleSettings() }
        function close(): void { ShellState.closeSurfaces() }
    }

    IpcHandler {
        target: "audio"
        function open(): void   { ShellState.openSurface("audio") }
        function toggle(): void { ShellState.toggleSurface("audio") }
        function close(): void  { if (ShellState.activeSurface === "audio") ShellState.closeSurfaces() }
    }

    IpcHandler {
        target: "display"
        function open(): void   { ShellState.openSurface("display") }
        function toggle(): void { ShellState.toggleSurface("display") }
        function close(): void  { if (ShellState.activeSurface === "display") ShellState.closeSurfaces() }
        function revert(): void { DisplayService.revertNow() }
        function keep(): void   { DisplayService.keepChanges() }
        function apply(): void  { DisplayService.applyAll() }
        function refresh(): void { DisplayService.refresh() }
    }

    // per-app audio: open the mixer on its Apps tab
    IpcHandler {
        target: "appaudio"
        function open(): void {
            if (ShellState.activeSurface === "mixer")
                ShellState.openMixerTabRequested(3)
            else {
                ShellState.mixerTab = 3
                ShellState.openSurface("mixer")
            }
        }
        function refresh(): void { AudioService.refresh() }
    }

    // плагіни: qs ipc call plugins open world-clock | setEnabled world-clock true
    IpcHandler {
        target: "plugins"
        function open(id: string): void {
            if (PluginService.hasSurface(id)) ShellState.openSurface("plugin:" + id)
        }
        function toggle(id: string): void {
            if (PluginService.hasSurface(id)) ShellState.toggleSurface("plugin:" + id)
        }
        function close(): void {
            if (ShellState.activeSurface.indexOf("plugin:") === 0) ShellState.closeSurfaces()
        }
        function reload(): void { PluginService.refresh() }
        function setEnabled(id: string, enabled: bool): void { PluginService.setEnabled(id, enabled) }
        function openFolder(): void { PluginService.openFolder() }
    }

    IpcHandler {
        target: "launcher"
        function open(): void { ShellState.openSurface("launcher") }
    }

    IpcHandler {
        target: "bluetooth"
        function open(): void   { ShellState.openSurface("bluetooth") }
        function toggle(): void { ShellState.toggleSurface("bluetooth") }
        function close(): void  { if (ShellState.activeSurface === "bluetooth") ShellState.closeSurfaces() }
        function togglePower(): void { BluetoothService.togglePower() }
        function scan(): void   { BluetoothService.startScan() }
    }

    IpcHandler {
        target: "dashboard"
        function open(): void   { ShellState.openDashboard() }
        function toggle(): void { ShellState.toggleDashboard() }
        function close(): void  { ShellState.closeDashboard() }
    }

    IpcHandler {
        target: "tasks"
        function open(): void   { taskManagerWindow.open() }
        function toggle(): void { taskManagerWindow.toggle() }
        function close(): void  { taskManagerWindow.close() }
    }

    IpcHandler {
        target: "settingsapp"
        function open(): void   { settingsWindow.open() }
        function toggle(): void { settingsWindow.toggle() }
        function close(): void  { settingsWindow.close() }
    }

    IpcHandler {
        target: "screentool"
        function open(): void   { screenTool.start() }
        function close(): void  { screenTool.dismiss() }
        // під час запису toggle зупиняє його (той самий SUPER+U / Print)
        function toggle(): void { if (RecordService.recording) RecordService.stop(); else screenTool.toggle() }
        function stop(): void   { RecordService.stop() }
    }

    Variants {
        model: Quickshell.screens
        SurfaceOverlay {}
    }

    // власний демон сповіщень: спливаючі вікна + центр (swaync більше не потрібен)
    Variants {
        model: Quickshell.screens
        NotificationPopups {}
    }
    Variants {
        model: Quickshell.screens
        NotificationCenter {}
    }
    IpcHandler {
        target: "notifications"
        function toggle(): void { NotificationService.toggleCenter() }
        function open(): void   { NotificationService.openCenter() }
        function close(): void  { NotificationService.closeCenter() }
        function clear(): void  { NotificationService.clearAll() }
        function dnd(): void    { NotificationService.setDnd(!NotificationService.dnd) }
    }

    // M3 OSD (гучність / яскравість)
    Variants {
        model: Quickshell.screens
        OsdWindow {}
    }

    // клавіші: qs -c <cfg> ipc call osd volumeUp  (не обов'язково — OSD і так реагує на зміни)
    IpcHandler {
        target: "osd"
        function volumeUp(): void         { OsdService.volumeStep(0.05) }
        function volumeDown(): void       { OsdService.volumeStep(-0.05) }
        function volumeMute(): void       { OsdService.volumeMute() }
        function brightnessUp(): void     { OsdService.brightnessStep(5) }
        function brightnessDown(): void   { OsdService.brightnessStep(-5) }
    }

    // анімація перемикання теми (повноекранний click-through шар)
    Variants {
        model: Quickshell.screens
        ThemeTransitionOverlay {}
    }

    // qs ipc call theme toggleDesign | setDesign nothing | toggleMode | setMode dark | setTransition dots
    IpcHandler {
        target: "theme"
        function setDesign(name: string): void {
            if (name !== "material" && name !== "nothing") return
            Theme.set("design", name)
        }
        function toggleDesign(): void {
            Theme.set("design", ThemeSettings.wantedDesign === "nothing" ? "material" : "nothing")
        }
        function setMode(mode: string): void { Theme.set("mode", mode) }
        function toggleMode(): void { Theme.set("mode", ThemeSettings.wantedMode === "light" ? "dark" : "light") }
        function setTransition(style: string): void { Theme.set("transition", style) }
    }

    // qs ipc call session apply|lock|suspend|logout|reboot|poweroff
    IpcHandler {
        target: "session"
        function apply(): void { SessionService.apply() }
        function lock(): void { Quickshell.execDetached(["python3", SessionService.helper, "lock"]) }
        function suspend(): void { Quickshell.execDetached(["python3", SessionService.helper, "suspend"]) }
        function logout(): void { Quickshell.execDetached(["python3", SessionService.helper, "logout"]) }
        function reboot(): void { Quickshell.execDetached(["python3", SessionService.helper, "reboot"]) }
        function poweroff(): void { Quickshell.execDetached(["python3", SessionService.helper, "poweroff"]) }
    }

    IpcHandler {
        target: "monitor"
        function relief(minutes: int): void { MonitorService.startRelief(minutes > 0 ? minutes : 0) }
        function reliefStop(): void { ReliefState.stop() }
        function scan(): void { MonitorService.startScan() }
        function thawAll(): void { MonitorService.thawAll() }
    }

    // віджети робочого столу (Settings → Віджети); qs ipc call widgets toggle
    Variants {
        model: Quickshell.screens
        DesktopWidgetsWindow {}
    }
    IpcHandler {
        target: "widgets"
        function toggle(): void { Settings.set("widgets", "enabled", !WidgetsConfig.enabled) }
        function show(): void   { Settings.set("widgets", "enabled", true) }
        function hide(): void   { Settings.set("widgets", "enabled", false) }
        function edit(): void   { if (WidgetsConfig.editing) WidgetsConfig.setEditing(false); else WidgetsConfig.startEdit() }
        function preset(name: string): void { WidgetsConfig.applyPreset(name) }
        function reset(): void  { WidgetsConfig.resetPlacement() }
    }

    // ігровий оверлей (FPS/CPU/GPU) — на шарі Overlay, видно навіть над повноекранними іграми
    Variants {
        model: Quickshell.screens
        GameOverlay {}
    }

    Bar {}
    DockLoader {}
}
