import "root:/theme"
import "root:/shell"
import "root:/modules/common"
import "root:/modules/workspace"
import "root:/modules/resources"
import "root:/modules/gamemode"
import "root:/modules/nightlight"
import "root:/modules/record"
import "root:/modules/privacy"
import "root:/modules/launcher"
import "root:/modules/window"
import "root:/modules/clock"
import "root:/modules/language"
import "root:/modules/volume"
import "root:/modules/network"
import "root:/modules/battery"
import "root:/modules/bluetooth"
import "root:/modules/tray"
import "root:/modules/media"
import "root:/modules/notifications"
import "root:/modules/power"
import "root:/surfaces"
import "root:/states"
import "root:/services"
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: win

    required property var modelData
    screen: modelData

    readonly property string monitorName: modelData.name
    readonly property string configuredPosition: BarConfig.positionFor(monitorName)
    // pill / islands — горизонтальні: для left/right (де їх обрізало б по ширині вікна) падаємо на top
    readonly property bool pill: BarConfig.style === "pill"
    readonly property bool islands: BarConfig.style === "islands"
    readonly property bool fullMorph: BarConfig.fullMorph
    readonly property bool islandsMorph: BarConfig.islandsMorph
    readonly property string position: ((pill || islands) && (configuredPosition === "left" || configuredPosition === "right")) ? "top" : configuredPosition
    readonly property bool vertical: position === "left" || position === "right"
    readonly property int thickness: BarConfig.thicknessFor(monitorName)
    readonly property bool pillMorph: BarConfig.pillMorph
    readonly property bool islandMorphOpen: islandsMorph &&
        (islandMorphLeft.surfaceState === "expanded" || islandMorphCenter.surfaceState === "expanded" || islandMorphRight.surfaceState === "expanded")
    readonly property bool barMorphOpen: fullMorph && barMorph.surfaceState === "expanded"
    readonly property bool anyMorphOpen: islandMorphOpen || barMorphOpen || (pill && pillSurface.surfaceState === "expanded")

    // морф-панель, відкрита в одній із капсул / у смузі
    function _morphTargetFor(name) {
        if (pillMorph) return pillSurface
        if (fullMorph) return barMorph
        const side = _islandFor(name)
        return side === "leading" ? islandMorphLeft : side === "center" ? islandMorphCenter : islandMorphRight
    }
    function _islandFor(name) {
        switch (name) {
        case "launcher": case "media": case "wallpaper": case "clipboard": case "binds": return "leading"
        case "resources": case "dashboard": return "center"
        case "wifi": case "bluetooth": case "mixer": case "audio": case "power": case "updates": case "diagnostics": return "trailing"
        default: return String(name || "").indexOf("plugin:") === 0 ? "trailing" : "leading"
        }
    }
    function _collapseMorphs(except) {
        if (pillMorph && pillSurface !== except) pillSurface.collapse()
        if (islandsMorph) {
            if (islandMorphLeft !== except) islandMorphLeft.collapse()
            if (islandMorphCenter !== except) islandMorphCenter.collapse()
            if (islandMorphRight !== except) islandMorphRight.collapse()
        }
        if (fullMorph && barMorph !== except) barMorph.collapse()
    }
    // єдиний вхід для модулів бару: у morph-режимі панель росте з відповідної капсули/модуля
    function openPanel(name, anchor) {
        if (pillMorph) {
            pillSurface.activePanel = name
            pillSurface.surfaceState = "expanded"
            return
        }
        if (islandsMorph || fullMorph) {
            const target = _morphTargetFor(name)
            if (target.surfaceState === "expanded" && target.activePanel === name) {
                target.collapse()
                return
            }
            _collapseMorphs(target)
            if (fullMorph) barMorph.anchorItem = anchor || _anchorFor(name)
            target.activePanel = name
            target.surfaceState = "expanded"
            return
        }
        if (name === "dashboard") {
            ShellState.toggleDashboard(win.monitorName)
        } else {
            ShellState.toggleSurface(name, win.monitorName)
        }
    }
    // точка росту для повного бару — реальний модуль, а не весь екран
    function _anchorFor(name) {
        switch (name) {
        case "launcher": return launcherItem
        case "media": return mediaItem
        case "resources": return resourcesItem
        case "dashboard": return clockItem
        case "wifi": return networkItem
        case "bluetooth": return bluetoothItem
        case "mixer": case "audio": return volumeItem
        case "power": return powerItem
        default: return powerItem
        }
    }
    function _morphAnchorEnd(name) {
        switch (name) {
        case "launcher": case "wallpaper": case "clipboard": case "binds": case "resources": case "dashboard": return false
        default: return true
        }
    }

    // ігровий режим + «плоский бар»: без заокруглень, зовнішніх відступів і тіні (лише повний бар)
    readonly property bool flat: !pill && !islands && GameModeState.active && GameModeState.optFlatBar
    readonly property int gap: (pill || islands) ? BarConfig.pillEdgeGap : (flat ? 0 : Theme.space.screenMargin)
    readonly property int reserve: (pill || islands) ? thickness + gap : thickness + gap * 2
    readonly property int cross: thickness - Theme.space.xs * 2
    readonly property int inner: cross - Theme.space.xxs * 2

    readonly property var morphModules: [dashboardSurface, pillSurface]
        .concat(fullMorph ? [barMorph] : [])
        .concat(islandsMorph ? [islandMorphLeft, islandMorphCenter, islandMorphRight] : [])

    // панелі, що морфяться з бару: [ширина, висота] (dashboard рахується окремо)
    readonly property var pillPanelSize: {
        const sizes = {
            wifi: [460, 440], bluetooth: [460, 480], mixer: [480, 420], audio: [600, 660],
            media: [460, 320], power: [480, 700], launcher: [560, 520],
            wallpaper: [620, 480], clipboard: [640, 600], binds: [700, 620], resources: [560, 620]
        }
        for (const plugin of (PluginService.surfaces || []))
            sizes["plugin:" + plugin.id] = [plugin.surface.w, plugin.surface.h]
        return sizes
    }
    readonly property var pillPanelIds: BarConfig.morphPanels
        .concat((PluginService.surfaces || []).map(function (plugin) { return "plugin:" + plugin.id }))
    readonly property var pillComponents: ({
        dashboard: pDashboard, wifi: pWifi, bluetooth: pBluetooth, mixer: pMixer, audio: pAudio, media: pMedia, power: pPower, launcher: pLauncher,
        wallpaper: pWallpaper, clipboard: pClipboard, updates: pUpdates, diagnostics: pDiagnostics, binds: pBinds, resources: pResources
    })
    readonly property bool dashOpen: dashboardSurface.occupies

    // Поки курсор на пігулці, не перецентровуємо її при зміні ширини (напр. прийшло
    // сповіщення й жива капсула стала ширшою) — інакше модуль під курсором «уїжджає».
    property bool _pillAnchor: false
    property real _pillAnchorX: 0

    // Наскільки compact-«коробка» морф-модуля виступає за reserve. barMorph/island-морфи стартують
    // біля внутрішнього краю смуги (reserve - gap) і мають власну compact-висоту, тож їхнє
    // тіло закінчується нижче, ніж reserve + overflow — без цієї поправки панель обрізається знизу.
    function _overhang(mod) {
        if (position === "top") return Math.max(0, (mod.y || 0) + (mod.height || 0) - reserve)
        if (position === "left") return Math.max(0, (mod.x || 0) + (mod.width || 0) - reserve)
        return Math.max(0, (vertical ? (mod.width || 0) : (mod.height || 0)) - gap)
    }
    function _maxOverflow(dir) {
        let m = 0
        for (const mod of morphModules) {
            const ov = mod[dir] || 0
            // поправка — лише для MorphSurface (має _th); dashboardSurface рахує overflow як всю висоту
            if (ov > 0) m = Math.max(m, ov + (mod._th !== undefined ? _overhang(mod) : 0))
        }
        return m
    }
    readonly property real _overflowNow: {
        if (position === "top") return _maxOverflow("overflowBottom")
        if (position === "bottom") return _maxOverflow("overflowTop")
        if (position === "left") return _maxOverflow("overflowRight")
        return _maxOverflow("overflowLeft")
    }
    readonly property bool _anyMorphBusy: morphModules.some(function (m) { return m.busy === true })

    // Вікно росте одразу, а стискається лише коли анімація згортання закінчилась. Інакше layer-shell
    // вікно зменшувалось у момент зміни стану, і панель, що ще «їде» назад, зникала миттєво.
    property real _overflowHeld: 0
    function _syncOverflow() {
        if (_overflowNow >= _overflowHeld || !_anyMorphBusy) _overflowHeld = _overflowNow
    }
    on_OverflowNowChanged: _syncOverflow()
    on_AnyMorphBusyChanged: _syncOverflow()
    readonly property real freeOverflow: _overflowHeld

    WlrLayershell.namespace: "edots-bar"
    WlrLayershell.keyboardFocus: (dashOpen || anyMorphOpen) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    anchors {
        top: position === "top" || vertical
        bottom: position === "bottom" || vertical
        left: position === "left" || !vertical
        right: position === "right" || !vertical
    }

    implicitWidth: vertical ? reserve + freeOverflow : 0
    implicitHeight: vertical ? 0 : reserve + freeOverflow

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: reserve

    mask: Region {
        Region {
            x: 0; y: 0
            width: (win.pill && pillSurface.surfaceState === "expanded") ? win.width : 0
            height: (win.pill && pillSurface.surfaceState === "expanded") ? win.height : 0
        }
        Region { item: win.pill ? pillSurface.bodyItem : (win.islands ? null : surface) }
        Region { item: win.islands ? islandLeft : null }
        Region { item: win.islands ? islandCenter : null }
        Region { item: win.islands ? islandRight : null }
        Region { item: win.barMorphOpen ? barMorph.bodyItem : null }
        Region { item: islandMorphLeft.surfaceState === "expanded" ? islandMorphLeft.bodyItem : null }
        Region { item: islandMorphCenter.surfaceState === "expanded" ? islandMorphCenter.bodyItem : null }
        Region { item: islandMorphRight.surfaceState === "expanded" ? islandMorphRight.bodyItem : null }
        Region { item: win.dashOpen ? dashboardSurface : null }
    }

    // зміна режиму відкриття — закрити все відкрите
    Connections {
        target: BarConfig
        function onOpenModeChanged() { win._collapseMorphs(null); ShellState.closeSurfaces() }
    }

    function _forThisMonitor(monitor) { return !monitor || monitor === "" || monitor === win.monitorName }

    Connections {
        target: ShellState

        // morph-режим: IPC/кнопки дашборду керують морф-панеллю, а не окремою поверхнею
        function onOpenDashboardRequested(monitor) {
            if (!win._forThisMonitor(monitor) || !(win.pillMorph || win.islandsMorph || win.fullMorph)) return
            const t = win._morphTargetFor("dashboard")
            win._collapseMorphs(t)
            if (win.fullMorph) barMorph.anchorItem = clockItem
            t.activePanel = "dashboard"
            t.surfaceState = "expanded"
        }
        function onToggleDashboardRequested(monitor) {
            if (!win._forThisMonitor(monitor) || !(win.pillMorph || win.islandsMorph || win.fullMorph)) return
            const t = win._morphTargetFor("dashboard")
            if (t.surfaceState === "expanded" && t.activePanel === "dashboard") {
                t.collapse()
            } else {
                win._collapseMorphs(t)
                if (win.fullMorph) barMorph.anchorItem = clockItem
                t.activePanel = "dashboard"
                t.surfaceState = "expanded"
            }
        }
        function onCloseDashboardRequested() {
            const t = win._morphTargetFor("dashboard")
            if (t && t.activePanel === "dashboard") t.collapse()
        }

        function onActiveSurfaceChanged() {
            if (!(win.pillMorph || win.islandsMorph || win.fullMorph)) return
            const s = ShellState.activeSurface
            if (s === "idle" || s === "") {
                win._collapseMorphs(null)
            } else if (win.pillPanelIds.includes(s) && BarConfig.canMorph(s)) {
                if (ShellState.activeMonitor === win.monitorName || !ShellState.activeMonitor || ShellState.activeMonitor === "") {
                    const t = win._morphTargetFor(s)
                    win._collapseMorphs(t)
                    if (win.fullMorph) barMorph.anchorItem = win._anchorFor(s)
                    t.activePanel = s
                    t.surfaceState = "expanded"
                }
            } else {
                win._collapseMorphs(null)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        visible: win.anyMorphOpen
        z: 1   // під пігулкою/морф-поверхнями (z: 2), щоб клік усередині панелі її не закривав
        onClicked: {
            win._collapseMorphs(null)
            ShellState.closeSurfaces()
        }
    }

    DashboardSurface {
        id: dashboardSurface
        z: 1
        listenShell: !win.pill && !win.fullMorph && !win.islandsMorph   // морф-режими тримають дашборд усередині бару
        hostMonitor: win.monitorName
        revealDirection: win.position

        readonly property real stripEnd: win.gap + win.thickness + Theme.space.sm
        readonly property real targetWidth: win.vertical ? Math.min(800, win.width - stripEnd - win.gap * 2)
                                                         : Math.min(920, win.width - win.gap * 4)

        maxHeight: {
            const sh = win.screen ? win.screen.height : 1080
            const se = win.gap + win.thickness + Theme.space.sm
            return win.vertical ? sh - win.gap * 2 : sh - se - win.gap
        }

        width: targetWidth
        // Вікно росте від краю бару, тож для right/bottom відступ рахуємо від протилежного краю вікна
        x: win.position === "right" ? win.width - stripEnd - width
           : win.position === "left" ? stripEnd
           : Math.round((win.width - width) / 2)
        y: win.position === "bottom" ? win.height - stripEnd - height
           : win.position === "top" ? stripEnd
           : Math.round((win.height - height) / 2)
    }

    // ---- ПОВНИЙ БАР (Full Mode) ----
    Item {
        id: surface
        z: 2

        // ВИПРАВЛЕНО: використовуємо ТІЛЬКИ opacity та enabled, без visible: false
        opacity: win.pill ? 0 : ((win.islandMorphOpen || win.barMorphOpen) ? 0.45 : 1)
        enabled: !win.pill
        scale: win.pill ? 0.88 : 1.0
        transformOrigin: Item.Center

        Behavior on opacity { MotionAnimation { role: "fade" } }
        Behavior on scale { MotionAnimation { role: "morph" } }

        x: win.position === "right" ? win.width - win.gap - win.thickness : win.gap
        y: win.position === "bottom" ? win.height - win.gap - win.thickness : win.gap
        width: win.vertical ? win.thickness : Math.max(0, win.width - win.gap * 2)
        height: win.vertical ? Math.max(0, win.height - win.gap * 2) : win.thickness

        ElevationShadow {
            anchors.fill: parent
            visible: !win.islands
            level: win.flat ? 0 : 0.5
            radius: win.flat ? 0 : Theme.shape.radius("full", win.thickness)
            color: Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer
        }

        // ---- floating capsules (style: islands) ----
        // Три окремі капсули за групами BarLayout: leading / center / trailing.
        readonly property real islandPadX: Theme.space.xs
        readonly property color islandFill: Theme.settings.nothing
            ? Theme.color.surface : Theme.color.surfaceContainer
        // капсула живе, поки її група має вміст або ще доанімовується прозорість
        readonly property bool leadingIsland: win.islands && layout.leadingWidth > 1
        readonly property bool centerIsland: win.islands && layout.centerWidth > 1
        readonly property bool trailingIsland: win.islands && layout.trailingWidth > 1

        ElevationShadow {
            id: islandLeft
            visible: surface.leadingIsland || opacity > 0.01
            opacity: surface.leadingIsland ? 1 : 0
            Behavior on opacity { MotionAnimation { role: "fade" } }
            x: layout.x + layout.leadingX - surface.islandPadX
            y: 0
            width: layout.leadingWidth + surface.islandPadX * 2
            height: surface.height
            level: 0.6
            radius: Theme.shape.radius("full", height)
            color: surface.islandFill
        }
        ElevationShadow {
            id: islandCenter
            visible: surface.centerIsland || opacity > 0.01
            opacity: surface.centerIsland ? 1 : 0
            Behavior on opacity { MotionAnimation { role: "fade" } }
            x: layout.x + layout.centerX - surface.islandPadX
            y: 0
            width: layout.centerWidth + surface.islandPadX * 2
            height: surface.height
            level: 0.6
            radius: Theme.shape.radius("full", height)
            color: surface.islandFill
        }
        ElevationShadow {
            id: islandRight
            visible: surface.trailingIsland || opacity > 0.01
            opacity: surface.trailingIsland ? 1 : 0
            Behavior on opacity { MotionAnimation { role: "fade" } }
            x: layout.x + layout.trailingX - surface.islandPadX
            y: 0
            width: layout.trailingWidth + surface.islandPadX * 2
            height: surface.height
            level: 0.6
            radius: Theme.shape.radius("full", height)
            color: surface.islandFill
        }

        BarLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: Theme.space.xs
            vertical: win.vertical

            leading: [
                LauncherModule {
                    id: launcherItem
                    vertical: win.vertical; cross: win.cross
                    enabledByConfig: BarConfig.moduleEnabled("launcher")
                    onActivated: win.openPanel("launcher", launcherItem)
                },
                WindowModule {
                    monitor: win.monitorName; vertical: win.vertical; cross: win.cross
                    enabledByConfig: BarConfig.moduleEnabled("window") && !ReliefState.hidden("barmodules")
                },
                BarGroup {
                    vertical: win.vertical
                    MediaModule {
                        id: mediaItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("media") && !ReliefState.hidden("barmodules")
                        onMediaRequested: win.openPanel("media", mediaItem)
                    }
                },
                PluginBarItems {
                    position: "leading"
                    vertical: win.vertical
                    cross: win.inner
                }
            ]

            center: [
                BarGroup {
                    vertical: win.vertical
                    ResourcesModule {
                        id: resourcesItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("resources") && !ReliefState.hidden("barmodules")
                        onResourcesRequested: win.openPanel("resources", resourcesItem)
                    }
                },
                BarGroup {
                    vertical: win.vertical
                    WorkspaceStrip {
                        monitor: win.monitorName; vertical: win.vertical; itemSize: win.inner
                        visible: BarConfig.moduleEnabled("workspaces")
                    }
                },
                BarGroup {
                    vertical: win.vertical
                    ClockModule {
                        id: clockItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("clock")
                        onClicked: win.openPanel("dashboard", clockItem)
                    }
                },
                PluginBarItems {
                    position: "center"
                    vertical: win.vertical
                    cross: win.inner
                }
            ]

            trailing: [
                BarGroup {
                    vertical: win.vertical
                    RecordModule { vertical: win.vertical; cross: win.inner }
                    PrivacyModule {
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("privacy")
                    }
                    GameModeModule { vertical: win.vertical; cross: win.inner }
                    NightLightModule {
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("nightlight")
                    }
                    VolumeModule {
                        id: volumeItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("mixer")
                        onMixerRequested: win.openPanel("mixer", volumeItem)
                        onStudioRequested: win.openPanel("audio", volumeItem)
                    }
                    NetworkModule {
                        id: networkItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("wifi")
                        onWifiRequested: win.openPanel("wifi", networkItem)
                    }
                    BluetoothModule {
                        id: bluetoothItem
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("bluetooth")
                        onBluetoothRequested: win.openPanel("bluetooth", bluetoothItem)
                    }
                    BatteryModule {
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("battery")
                    }
                    TrayModule {
                        vertical: win.vertical; cross: win.inner
                        placement: win.position
                        enabledByConfig: BarConfig.moduleEnabled("tray")
                    }
                    NotificationModule {
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("notifications")
                    }
                    LanguageModule {
                        vertical: win.vertical; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("language")
                    }
                    PluginBarItems {
                        position: "trailing"
                        vertical: win.vertical
                        cross: win.inner
                    }
                },
                PowerModule {
                    id: powerItem
                    vertical: win.vertical; cross: win.cross
                    enabledByConfig: BarConfig.moduleEnabled("power")
                    onPowerRequested: win.openPanel("power", powerItem)
                    onSettingsRequested: ShellState.toggleSettings()
                }
            ]
        }
    }

    // ---- МОРФ У ПОВНІЙ СМУЗІ (style: full, openMode: morph) ----
    // Панель росте з реального модуля, по якому клікнули (launcher / wifi / power...),
    // а не з окремого вікна. Для вертикального бару — росте всередину екрана.
    MorphSurface {
        id: barMorph
        visible: win.fullMorph
        z: 4
        interactive: surfaceState !== "compact"
        closeOnEscape: BarConfig.pillCloseOnEscape

        property Item anchorItem: null
        property string activePanel: ""
        readonly property bool panelEnd: win._morphAnchorEnd(activePanel)
        readonly property var anchorRect: {
            const it = anchorItem
            if (!it) return ({ x: 0, y: 0, width: 0, height: 0 })
            const p = it.mapToItem(win.contentItem, 0, 0)
            return ({ x: p.x, y: p.y, width: it.width, height: it.height })
        }

        readonly property real panelW: expandedWidth
        readonly property real panelH: expandedHeight
        readonly property real anchorX: anchorRect.x + anchorRect.width / 2
        readonly property real anchorY: anchorRect.y + anchorRect.height / 2
        // Якщо панель біля краю екрана не вміщається — рости вбік від краю, а не за екран.
        readonly property bool growRight: !win.vertical && (anchorX - panelW / 2 < win.gap)
        readonly property bool growLeft:  !win.vertical && (anchorX + panelW / 2 > win.width - win.gap)
        readonly property bool growDown:  win.vertical && (anchorY - panelH / 2 < win.gap)
        readonly property bool growUp:    win.vertical && (anchorY + panelH / 2 > win.height - win.gap)

        originX: win.vertical ? (win.position === "right" ? 1 : 0)
                : (growRight && !growLeft ? 0
                   : growLeft && !growRight ? 1
                   : (panelEnd ? 1 : 0.5))
        originY: win.vertical ? (growDown && !growUp ? 0
                                 : growUp && !growDown ? 1 : 0.5)
                : (win.position === "bottom" ? 1 : 0)
        // повна смуга: панель росте від внутрішнього краю бару, а не поверх самої смуги
        readonly property real rawX: win.vertical
            ? (win.position === "right" ? surface.x : surface.x + surface.width)
            : (growRight && !growLeft ? anchorRect.x
               : growLeft && !growRight ? anchorRect.x + anchorRect.width
               : anchorX)
        readonly property real rawY: win.vertical
            ? (growDown && !growUp ? anchorRect.y
               : growUp && !growDown ? anchorRect.y + anchorRect.height
               : anchorY)
            : (win.position === "bottom" ? surface.y : surface.y + surface.height)
        // страховка: навіть після вибору напрямку не даємо тілу вийти за межі екрана
        readonly property real bodyLeft: rawX + (width - _tw) * originX
        readonly property real bodyTop:  rawY + (height - _th) * originY
        readonly property real shiftX: bodyLeft < win.gap ? win.gap - bodyLeft
            : bodyLeft + _tw > win.width - win.gap ? win.width - win.gap - bodyLeft - _tw : 0
        readonly property real shiftY: bodyTop < win.gap ? win.gap - bodyTop
            : bodyTop + _th > win.height - win.gap ? win.height - win.gap - bodyTop - _th : 0
        x: rawX + shiftX
        y: rawY + shiftY

        baseColor: activePanel === "" ? "transparent"
                 : (Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer)

        expandedWidth: {
            if (activePanel === "dashboard") return Math.min(920, screen.width - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            if (s) return Math.min(s[0], screen.width - win.gap * 4)
            return Math.max(280, layout.width)
        }
        expandedHeight: {
            if (activePanel === "dashboard") return Math.min(760, screen.height - win.thickness - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            if (s) return Math.min(s[1], screen.height - win.thickness - win.gap * 4)
            return win.thickness
        }

        onSurfaceStateChanged: {
            if (surfaceState === "compact") {
                activePanel = ""
                ShellState.closeSurfaces()
            }
        }

        expanded: [
            Item {
                anchors.fill: parent
                Loader {
                    anchors.fill: parent
                    active: barMorph.activePanel !== "" && barMorph.activePanel.indexOf("plugin:") !== 0
                    sourceComponent: win.pillComponents[barMorph.activePanel] || null
                }
                Loader {
                    anchors.fill: parent
                    active: barMorph.activePanel.indexOf("plugin:") === 0
                    source: barMorph.activePanel.indexOf("plugin:") === 0
                        ? PluginService.surfaceQml(barMorph.activePanel.substring(7)) : ""
                }
            }
        ]
    }

    // ---- МОРФ В ОСТРІВЦЯХ (style: islands, openMode: morph) ----
    // Кожна з трьох капсул морфиться самостійно: панель росте з тієї капсули, де клікнули.
    // compact-стан прозорий і не перехоплює мишу — статичні капсули лишаються клікабельними.
    MorphSurface {
        id: islandMorphLeft
        visible: win.islandsMorph
        z: 4
        interactive: surfaceState !== "compact"
        closeOnEscape: BarConfig.pillCloseOnEscape
        property string activePanel: ""

        readonly property real padX: Theme.space.xs
        x: surface.x + layout.x + layout.leadingX - padX
        y: win.position === "bottom" ? surface.y + surface.height : surface.y
        originX: 0
        originY: win.position === "bottom" ? 1 : 0
        baseColor: activePanel === "" ? "transparent"
                 : (Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer)

        expandedWidth: {
            if (activePanel === "dashboard") return Math.min(920, screen.width - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[0], screen.width - win.gap * 4) : Math.max(280, layout.leadingWidth + padX * 2)
        }
        expandedHeight: {
            if (activePanel === "dashboard") return Math.min(760, screen.height - win.thickness - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[1], screen.height - win.thickness - win.gap * 4) : win.thickness
        }

        onSurfaceStateChanged: {
            if (surfaceState === "compact") { activePanel = ""; ShellState.closeSurfaces() }
        }

        expanded: [
            Item {
                anchors.fill: parent
                Loader {
                    anchors.fill: parent
                    active: islandMorphLeft.activePanel !== "" && islandMorphLeft.activePanel.indexOf("plugin:") !== 0
                    sourceComponent: win.pillComponents[islandMorphLeft.activePanel] || null
                }
                Loader {
                    anchors.fill: parent
                    active: islandMorphLeft.activePanel.indexOf("plugin:") === 0
                    source: islandMorphLeft.activePanel.indexOf("plugin:") === 0
                        ? PluginService.surfaceQml(islandMorphLeft.activePanel.substring(7)) : ""
                }
            }
        ]
    }

    MorphSurface {
        id: islandMorphCenter
        visible: win.islandsMorph
        z: 4
        interactive: surfaceState !== "compact"
        closeOnEscape: BarConfig.pillCloseOnEscape
        property string activePanel: ""

        x: surface.x + layout.x + layout.centerX + layout.centerWidth / 2
        y: win.position === "bottom" ? surface.y + surface.height : surface.y
        originX: 0.5
        originY: win.position === "bottom" ? 1 : 0
        baseColor: activePanel === "" ? "transparent"
                 : (Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer)

        expandedWidth: {
            if (activePanel === "dashboard") return Math.min(920, screen.width - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[0], screen.width - win.gap * 4) : Math.max(280, layout.centerWidth)
        }
        expandedHeight: {
            if (activePanel === "dashboard") return Math.min(760, screen.height - win.thickness - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[1], screen.height - win.thickness - win.gap * 4) : win.thickness
        }

        onSurfaceStateChanged: {
            if (surfaceState === "compact") { activePanel = ""; ShellState.closeSurfaces() }
        }

        expanded: [
            Item {
                anchors.fill: parent
                Loader {
                    anchors.fill: parent
                    active: islandMorphCenter.activePanel !== "" && islandMorphCenter.activePanel.indexOf("plugin:") !== 0
                    sourceComponent: win.pillComponents[islandMorphCenter.activePanel] || null
                }
                Loader {
                    anchors.fill: parent
                    active: islandMorphCenter.activePanel.indexOf("plugin:") === 0
                    source: islandMorphCenter.activePanel.indexOf("plugin:") === 0
                        ? PluginService.surfaceQml(islandMorphCenter.activePanel.substring(7)) : ""
                }
            }
        ]
    }

    MorphSurface {
        id: islandMorphRight
        visible: win.islandsMorph
        z: 4
        interactive: surfaceState !== "compact"
        closeOnEscape: BarConfig.pillCloseOnEscape
        property string activePanel: ""

        readonly property real padX: Theme.space.xs
        x: surface.x + layout.x + layout.trailingX + layout.trailingWidth + padX
        y: win.position === "bottom" ? surface.y + surface.height : surface.y
        originX: 1
        originY: win.position === "bottom" ? 1 : 0
        baseColor: activePanel === "" ? "transparent"
                 : (Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer)

        expandedWidth: {
            if (activePanel === "dashboard") return Math.min(920, screen.width - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[0], screen.width - win.gap * 4) : Math.max(280, layout.trailingWidth + padX * 2)
        }
        expandedHeight: {
            if (activePanel === "dashboard") return Math.min(760, screen.height - win.thickness - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            return s ? Math.min(s[1], screen.height - win.thickness - win.gap * 4) : win.thickness
        }

        onSurfaceStateChanged: {
            if (surfaceState === "compact") { activePanel = ""; ShellState.closeSurfaces() }
        }

        expanded: [
            Item {
                anchors.fill: parent
                Loader {
                    anchors.fill: parent
                    active: islandMorphRight.activePanel !== "" && islandMorphRight.activePanel.indexOf("plugin:") !== 0
                    sourceComponent: win.pillComponents[islandMorphRight.activePanel] || null
                }
                Loader {
                    anchors.fill: parent
                    active: islandMorphRight.activePanel.indexOf("plugin:") === 0
                    source: islandMorphRight.activePanel.indexOf("plugin:") === 0
                        ? PluginService.surfaceQml(islandMorphRight.activePanel.substring(7)) : ""
                }
            }
        ]
    }

    // ---- ПІГУЛКА (Pill Mode) ----
    MorphSurface {
        id: pillSurface
        z: 2

        opacity: win.pill ? 1 : 0
        enabled: win.pill
        scale: win.pill ? 1.0 : 0.88
        transformOrigin: Item.Center

        Behavior on opacity { MotionAnimation { role: "fade" } }
        Behavior on scale { MotionAnimation { role: "morph" } }

        x: win.vertical ? (win.position === "right" ? win.width - win.gap - win.thickness : win.gap)
                        : (win._pillAnchor ? win._pillAnchorX : Math.round((win.width - width) / 2))
        y: win.vertical ? Math.round((win.height - height) / 2)
                        : (win.position === "bottom" ? win.height - win.gap - win.thickness : win.gap)
        Behavior on x { MotionAnimation { role: "move" } }

        property string activePanel: ""

        onSurfaceStateChanged: {
            if (surfaceState === "compact") {
                activePanel = ""
                ShellState.closeSurfaces()
            }
        }
        onVisibleChanged: if (!visible) { surfaceState = "compact"; activePanel = "" }

        originX: 0.5
        originY: win.position === "bottom" ? 1.0 : 0.0

        closeOnEscape: BarConfig.pillCloseOnEscape
        baseColor: Theme.settings.nothing ? Theme.color.surface : Theme.color.surfaceContainer

        compactWidth: compactRow.implicitWidth + Theme.space.lg * 2
        compactHeight: win.thickness

        // на вузькому екрані hover-рядок не вміщається — лишаємо компактну пігулку,
        // інакше капсулу обрізало б по краях екрана
        readonly property real _hoverW: hoverRow.implicitWidth + Theme.space.lg * 2
        readonly property real _rawInset: hoverExtraLeft.implicitWidth + hoverRow.spacing
        // де буде пілл у compact (ядро стоїть на місці) — перевіряємо, що розгорнутий не вилізе за екран
        readonly property real _pillX: win._pillAnchor ? win._pillAnchorX : Math.round((win.width - compactWidth) / 2)
        readonly property bool _hoverFits: {
            if (!screen) return false
            const left = _pillX - _rawInset
            return left >= win.gap && left + _hoverW <= win.width - win.gap
        }
        hoverWidth: BarConfig.pillHover && _hoverFits ? _hoverW : 0
        hoverHeight: win.thickness
        hoverPersistent: true
        holdHover: ShellState.heldOn(win.monitorName)
        // тримаємо ядро (workspaces/clock/live…) на місці: додаткові модулі з'являються обабіч
        hoverCoreInset: _rawInset

        // поки курсор на пігулці — жива капсула не зникає і пігулка не перецентровується
        onHoveredChanged: {
            NotificationService.setLivePaused(hovered)
            if (win.vertical) return
            if (hovered) { win._pillAnchorX = pillSurface.x; win._pillAnchor = true }
            else if (!holdHover) win._pillAnchor = false
        }
        // меню закрилось, а курсор не на пілі — відпускаємо якір і даємо пілу згорнутись
        onHoldHoverChanged: if (!holdHover && !hovered) win._pillAnchor = false

        expandedWidth: {
            if (activePanel === "dashboard") return Math.min(920, screen.width - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            if (s) return Math.min(s[0], screen.width - win.gap * 4)
            return hoverRow.implicitWidth + Theme.space.lg * 2
        }
        expandedHeight: {
            if (activePanel === "dashboard") return Math.min(760, screen.height - win.thickness - win.gap * 4)
            const s = win.pillPanelSize[activePanel]
            if (s) return Math.min(s[1], screen.height - win.thickness - win.gap * 4)
            return win.thickness
        }

        // тап по порожньому місцю відкритої панелі її більше не закриває:
        // закриття — Esc, клік поза панеллю (MouseArea вище) або кнопки самої панелі

        compact: [
            RowLayout {
                id: compactRow
                anchors.centerIn: parent
                spacing: Theme.space.md

                WorkspaceStrip {
                    Layout.alignment: Qt.AlignVCenter
                    monitor: win.monitorName; itemSize: win.inner; compact: true
                    visible: BarConfig.moduleEnabled("workspaces")
                }
                ClockModule {
                    Layout.alignment: Qt.AlignVCenter
                    cross: win.inner
                    enabledByConfig: BarConfig.moduleEnabled("clock")
                    onClicked: win.openPanel("dashboard")
                }
                LiveSpot {
                    Layout.alignment: Qt.AlignVCenter
                    cross: win.inner
                    onMediaRequested: win.openPanel("media")
                    onTimerRequested: win.openPanel("dashboard")
                }
                // з'являються лише під час запису / ігрового режиму; клік зупиняє
                RecordModule   { Layout.alignment: Qt.AlignVCenter; cross: win.inner }
                PrivacyModule {
                    Layout.alignment: Qt.AlignVCenter
                    cross: win.inner
                    enabledByConfig: BarConfig.moduleEnabled("privacy")
                }
                GameModeModule { Layout.alignment: Qt.AlignVCenter; cross: win.inner }
                NightLightModule {
                    Layout.alignment: Qt.AlignVCenter
                    cross: win.inner
                    enabledByConfig: BarConfig.moduleEnabled("nightlight")
                }
                LanguageModule {
                    Layout.alignment: Qt.AlignVCenter
                    cross: win.inner
                    enabledByConfig: BarConfig.moduleEnabled("language")
                }
            }
        ]

        hover: [
            RowLayout {
                id: hoverRow
                anchors.centerIn: parent
                spacing: Theme.space.sm

                // ── додаткові модулі ліворуч ──
                RowLayout {
                    id: hoverExtraLeft
                    opacity: pillSurface.hoverActive ? 1 : 0
                    Behavior on opacity { MotionAnimation { role: pillSurface.hoverActive ? "contentIn" : "contentOut" } }
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.space.sm

                    LauncherModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("launcher")
                        onActivated: win.openPanel("launcher")
                    }
                    WindowModule {
                        Layout.alignment: Qt.AlignVCenter
                        monitor: win.monitorName; cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("window") && !ReliefState.hidden("barmodules")
                    }
                    ResourcesModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("resources") && !ReliefState.hidden("barmodules")
                        onResourcesRequested: win.openPanel("resources")
                    }
                    MediaModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("media") && !ReliefState.hidden("barmodules")
                        onMediaRequested: win.openPanel("media")
                    }
                }

                // ── ядро: той самий набір і порядок, що й у compact,
                //    щоб при hover-розгортанні модулі не зсувалися з-під курсора ──
                RowLayout {
                    id: hoverCore
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.space.md

                    WorkspaceStrip {
                        Layout.alignment: Qt.AlignVCenter
                        monitor: win.monitorName; itemSize: win.inner; compact: true
                        visible: BarConfig.moduleEnabled("workspaces")
                    }
                    ClockModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("clock")
                        onClicked: win.openPanel("dashboard")
                    }
                    LiveSpot {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        onMediaRequested: win.openPanel("media")
                        onTimerRequested: win.openPanel("dashboard")
                    }
                    RecordModule   { Layout.alignment: Qt.AlignVCenter; cross: win.inner }
                    PrivacyModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("privacy")
                    }
                    GameModeModule { Layout.alignment: Qt.AlignVCenter; cross: win.inner }
                    NightLightModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("nightlight")
                    }
                    LanguageModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("language")
                    }
                }

                // ── додаткові модулі праворуч ──
                RowLayout {
                    id: hoverExtraRight
                    opacity: pillSurface.hoverActive ? 1 : 0
                    Behavior on opacity { MotionAnimation { role: pillSurface.hoverActive ? "contentIn" : "contentOut" } }
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.space.sm

                    VolumeModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("mixer")
                        onMixerRequested: win.openPanel("mixer")
                        onStudioRequested: win.openPanel("audio")
                    }
                    NetworkModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("wifi")
                        onWifiRequested: win.openPanel("wifi")
                    }
                    BluetoothModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("bluetooth")
                        onBluetoothRequested: win.openPanel("bluetooth")
                    }
                    BatteryModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("battery")
                    }
                    TrayModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        placement: win.position
                        enabledByConfig: BarConfig.moduleEnabled("tray")
                    }
                    NotificationModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("notifications")
                    }
                    PluginBarItems {
                        position: "sorted"
                        vertical: false
                        cross: win.inner
                        layoutAlignment: Qt.AlignVCenter
                    }
                    PowerModule {
                        Layout.alignment: Qt.AlignVCenter
                        cross: win.inner
                        enabledByConfig: BarConfig.moduleEnabled("power")
                        onPowerRequested: win.openPanel("power")
                    }
                }
            }
        ]

        expanded: [
            Item {
                anchors.fill: parent
                Loader {
                    anchors.fill: parent
                    active: pillSurface.activePanel !== ""
                    opacity: active ? 1 : 0
                    Behavior on opacity { MotionAnimation { role: "fade" } }
                    sourceComponent: win.pillComponents[pillSurface.activePanel]
                        || (pillSurface.activePanel.indexOf("plugin:") === 0 ? pPlugin : null)
                }
            }
        ]
    }

    Component { id: pDashboard; DashboardSurface { anchors.fill: parent; occupies: true; listenShell: false; hostMonitor: win.monitorName; revealDirection: win.position } }
    Component { id: pWifi; WifiSurface { anchors.fill: parent } }
    Component { id: pBluetooth; BluetoothSurface { anchors.fill: parent } }
    Component { id: pMixer; MixerSurface { anchors.fill: parent } }
    Component { id: pAudio; AudioStudioSurface { anchors.fill: parent } }
    Component { id: pMedia; MediaSurface { anchors.fill: parent } }
    Component { id: pPower; PowerSurface { anchors.fill: parent; onRequestClose: win._collapseMorphs(null) } }
    Component { id: pUpdates; UpdateSurface { anchors.fill: parent } }
    Component { id: pDiagnostics; DiagnosticsSurface { anchors.fill: parent } }
    Component { id: pWallpaper; WallpaperSurface { anchors.fill: parent } }
    Component { id: pClipboard; ClipboardSurface { anchors.fill: parent } }
    Component { id: pBinds; BindsSurface { anchors.fill: parent } }
    Component { id: pResources; ResourcesSurface { anchors.fill: parent; onRequestClose: win._collapseMorphs(null) } }
    Component { id: pLauncher; LauncherSurface { anchors.fill: parent; onAppLaunched: win._collapseMorphs(null) } }
    Component { id: pPlugin
        Loader {
            anchors.fill: parent
            active: true
            source: pillSurface.activePanel.indexOf("plugin:") === 0
                ? PluginService.surfaceQml(pillSurface.activePanel.substring(7)) : ""
        }
    }
}
