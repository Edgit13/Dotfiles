pragma Singleton
import Quickshell
import QtQuick

// Schema.qml — опис усіх налаштувань. Один рядок = одна опція.
Singleton {
    id: root

    readonly property var schema: ({
        general: {
            file: "general.json",
            label: "section.general",
            fields: {
                language:        { type: "enum", options: ["en","uk"], default: "en", label: "Language" },
                userName:        { type: "str",  default: "", label: "Display name", desc: "Empty = system user" },
                autoStart:       { type: "bool", default: false, label: "Open dashboard on login" },
                notifEnabled:    { type: "bool", default: true,  label: "Desktop notifications" },
                weatherCity:     { type: "str",  default: "", label: "Weather city", desc: "Empty = auto-detect by IP" },
                terminalCommand: { type: "str",  default: "ghostty", label: "Terminal" },
                fileManager:     { type: "str",  default: "nautilus", label: "File manager" },
                browser:         { type: "str",  default: "firefox", label: "Browser" }
            }
        },
        theme: {
            file: "theme.json",
            label: "section.appearance",
            fields: {
                mode:             { type: "enum", options: ["system","light","dark"], default: "dark", label: "Color mode", desc: "Follow system or force dark/light." },
                design:           { type: "enum", options: ["material","nothing"], default: "material", label: "Design style", desc: "Material (default) or Nothing (monochrome, dot-matrix, red accent)." },
                transition:       { type: "enum", options: ["off","fade","dots","scan"], default: "dots", label: "Theme transition", desc: "Animation when switching design or light/dark." },
                dynamicColor:     { type: "bool", default: true, label: "Dynamic colors from wallpaper" },
                accent:           { type: "color", default: "#74e7c8", label: "Custom accent" },
                gtkReload:        { type: "enum", options: ["restart","notify","off"], default: "restart", label: "GTK apps after colour change", desc: "GTK4/libadwaita apps only read user CSS at startup. Restart Files (Nautilus) automatically, show a reminder, or do nothing." },
                cornerStyle:      { type: "enum", options: ["material","expressive","rounded"], default: "expressive", label: "Corner style" },
                uiScale:          { type: "num", min: 0.75, max: 1.5, step: 0.05, default: 1.0, label: "UI scale", suffix: "×" },
                animations:       { type: "bool", default: true, label: "Animations" },
                expressiveMotion: { type: "bool", default: true, label: "Expressive motion" },
                reduceMotion:     { type: "bool", default: false, label: "Reduce motion" },
                shadows:          { type: "bool", default: true,  label: "Shadows", desc: "Disable on weak GPUs (e.g. Intel UHD 620) if shadows flicker." },
                animationSpeed:   { type: "num", min: 0.25, max: 3.0, step: 0.05, default: 1.0, label: "Animation speed", suffix: "×" }
            }
        },
        bar: {
            file: "bar.json",
            label: "section.bar",
            fields: {
                position:    { type: "enum", options: ["top","bottom","left","right"], default: "top", label: "Position" },
                style:       { type: "enum", options: ["full","pill","islands"], default: "full", label: "Style", desc: "full = one strip · pill = compact island · islands = three floating capsules" },
                openMode:    { type: "enum", options: ["morph","window","spotlight","drawer"], default: "morph", label: "Open mode", desc: "How modules open. Morph grows out of the bar — works on every style (full strip grows from the clicked module, pill from itself, each island capsule separately)." },
                mode:        { type: "enum", options: ["compact","expanded","morphing"], default: "compact", label: "Mode" },
                elevation:   { type: "num", min: 0, max: 5, step: 1, default: 1, label: "Elevation" },
                mainMonitor: { type: "str", default: "", label: "Main monitor", desc: "Empty = first screen" },
                pillHover:         { type: "bool", default: true, label: "Pill: expand on hover", desc: "Show extra modules when hovering the pill." },
                pillEdgeGap:       { type: "num", min: 0, max: 32, step: 1, default: 8, label: "Pill: edge gap", suffix: "px" },
                pillCloseOnEscape: { type: "bool", default: true, label: "Pill: close on Esc" },
                live:              { type: "bool", default: true, label: "Live capsule", desc: "In pill style, show the current activity inside the capsule — a new notification, a timer or playing media." },
                perMonitor:  { type: "map", default: {}, hidden: true }
            }
        },
        monitor: {
            file: "monitor.json",
            label: "section.monitor",
            fields: {
                enabled:       { type: "bool", default: true, label: "Process monitor", desc: "Lightweight separate process (procwatch.py)." },
                scope:         { type: "enum", options: ["shell","system"], default: "shell", label: "Scope", desc: "shell = Quickshell and its children; system = all your processes." },
                interval:      { type: "num", min: 1, max: 10, step: 0.5, default: 2, label: "Poll interval", suffix: " s" },
                cpuLimit:      { type: "num", min: 20, max: 800, step: 10, default: 90, label: "CPU limit per process", suffix: "%", desc: "% of ONE core (200 = two cores)." },
                memLimit:      { type: "num", min: 0, max: 32768, step: 128, default: 0, label: "Memory limit per process", suffix: " MB", desc: "0 = off." },
                sustain:       { type: "num", min: 3, max: 120, step: 1, default: 15, label: "Exceeded for at least", suffix: " s" },
                shellCpuLimit: { type: "num", min: 5, max: 400, step: 5, default: 25, label: "Quickshell CPU limit", suffix: "%" },
                shellMemLimit: { type: "num", min: 0, max: 8192, step: 64, default: 0, label: "Quickshell memory limit", suffix: " MB", desc: "0 = off." },
                overrides:     { type: "str", default: "", label: "Per-process limits", desc: "name:cpu:mem, ... e.g. firefox:150:4096, obs:200 (empty/0 = default)." },
                notify:        { type: "bool", default: true, label: "Notify on exceed" },
                cooldown:      { type: "num", min: 30, max: 1800, step: 30, default: 180, label: "Notification cooldown", suffix: " s" },
                action:        { type: "enum", options: ["ask","freeze","none"], default: "ask", label: "On exceed", desc: "ask = notification with a Freeze button; freeze = freeze automatically; none = only report." },
                freezeSeconds: { type: "num", min: 5, max: 600, step: 5, default: 30, label: "Freeze duration", suffix: " s", desc: "SIGSTOP, then automatic resume (SIGCONT)." },
                protectSystem: { type: "bool", default: true, label: "Protect system processes", desc: "systemd, compositor, audio, network, login... are never frozen." },
                whitelist:     { type: "str", default: "", label: "Whitelist", desc: "Comma-separated names (globs ok): never reported or frozen." },
                pauseInGame:   { type: "bool", default: true, label: "Pause while game mode is on" },
                reliefEnabled: { type: "bool", default: true, label: "Relief mode for Quickshell", desc: "If the shell exceeds its limit, offer to cut its load for a while." },
                reliefAsk:     { type: "bool", default: true, label: "Ask before relief", desc: "Off = switch automatically." },
                reliefMinutes: { type: "num", min: 1, max: 60, step: 1, default: 10, label: "Relief duration", suffix: " min" },
                reliefMotion:  { type: "bool", default: true, label: "Relief: disable animations" },
                reliefEffects: { type: "bool", default: true, label: "Relief: disable blur and shadows", desc: "Also applies to important parts (lock screen, bar)." },
                reliefHide:    { type: "bool", default: true, label: "Relief: hide heaviest optional parts", desc: "Desktop widgets, dock, game overlay, heavy bar modules - the most expensive first." }
            }
        },
        widgets: {
            file: "widgets.json",
            label: "section.widgets",
            fields: {
                enabled:      { type: "bool", default: true, label: "Desktop widgets", desc: "Move them: qs ipc call widgets edit" },
                monitor:      { type: "str",  default: "", label: "Monitor", desc: "Empty = all screens" },
                anchor:       { type: "enum", options: ["top-left","top","top-right","left","center","right","bottom-left","bottom","bottom-right"], default: "top-right", label: "Position" },
                arrange:      { type: "enum", options: ["row","column","grid"], default: "row", label: "Layout" },
                margin:       { type: "num", min: 0, max: 300, step: 4, default: 48, label: "Edge margin", suffix: "px" },
                spacing:      { type: "num", min: 0, max: 64, step: 2, default: 16, label: "Spacing", suffix: "px" },
                scale:        { type: "num", min: 0.5, max: 2.0, step: 0.05, default: 1.0, label: "Size", suffix: "×" },
                opacity:      { type: "num", min: 0.2, max: 1.0, step: 0.05, default: 1.0, label: "Opacity" },
                colorStyle:   { type: "enum", options: ["mixed","primary","secondary","tertiary","surface"], default: "mixed", label: "Colors", desc: "mixed = each widget has its own accent" },
                clockEnabled:    { type: "bool", default: true, label: "Clock" },
                clockStyle:      { type: "enum", options: ["digital","analog"], default: "digital", label: "Clock style" },
                clockShape:      { type: "enum", options: ["cookie","flower","sunny","circle","squircle","pill","rounded"], default: "cookie", label: "Clock shape" },
                weatherEnabled:  { type: "bool", default: true, label: "Weather" },
                weatherShape:    { type: "enum", options: ["cookie","flower","sunny","circle","squircle","pill","rounded"], default: "flower", label: "Weather shape" },
                mediaEnabled:    { type: "bool", default: true, label: "Media" },
                mediaShape:      { type: "enum", options: ["cookie","flower","sunny","circle","squircle","pill","rounded"], default: "pill", label: "Media shape" },
                mediaHideIdle:   { type: "bool", default: true, label: "Hide media when nothing plays" },
                resourcesEnabled:{ type: "bool", default: true, label: "System resources" },
                resourcesShape:  { type: "enum", options: ["cookie","flower","sunny","circle","squircle","pill","rounded"], default: "sunny", label: "Resources shape" },
                edit:         { type: "bool", default: false, label: "Edit mode", desc: "Drag widgets on the desktop" },
                bgStyle:      { type: "enum", options: ["filled","glass","outline","none"], default: "filled", label: "Background", desc: "Widget background style" },
                bgOpacity:    { type: "num", min: 0.1, max: 1.0, step: 0.05, default: 1.0, label: "Background opacity" },
                preset:       { type: "enum", options: ["custom","corner","stack","desk","centered","minimal","outline"], default: "custom", label: "Preset", desc: "Applies on select" },
                clockPlacement:     { type: "enum", options: ["auto","free"], default: "auto", label: "Clock placement" },
                weatherPlacement:   { type: "enum", options: ["auto","free"], default: "auto", label: "Weather placement" },
                mediaPlacement:     { type: "enum", options: ["auto","free"], default: "auto", label: "Media placement" },
                resourcesPlacement: { type: "enum", options: ["auto","free"], default: "auto", label: "Resources placement" },
                clockX:     { type: "num", min: 0, max: 1, step: 0.001, default: 0.03, hidden: true },
                clockY:     { type: "num", min: 0, max: 1, step: 0.001, default: 0.06, hidden: true },
                weatherX:   { type: "num", min: 0, max: 1, step: 0.001, default: 0.97, hidden: true },
                weatherY:   { type: "num", min: 0, max: 1, step: 0.001, default: 0.06, hidden: true },
                mediaX:     { type: "num", min: 0, max: 1, step: 0.001, default: 0.5,  hidden: true },
                mediaY:     { type: "num", min: 0, max: 1, step: 0.001, default: 0.95, hidden: true },
                resourcesX: { type: "num", min: 0, max: 1, step: 0.001, default: 0.97, hidden: true },
                resourcesY: { type: "num", min: 0, max: 1, step: 0.001, default: 0.55, hidden: true }
            }
        },
        modules: {
            file: "bar.json",
            label: "section.modules",
            fields: {
                order:         { type: "arr",  default: ["workspaces","clock","launcher","window","media","mixer","wifi","bluetooth","tray","notifications","battery","nightlight","power"], path: "modules.order", hidden: true },
                workspaces:    { type: "bool", default: true, label: "Workspaces", path: "modules.workspaces" },
                clock:         { type: "bool", default: true, label: "Clock", path: "modules.clock" },
                launcher:      { type: "bool", default: true, label: "Launcher", path: "modules.launcher" },
                window:        { type: "bool", default: true, label: "Window title", path: "modules.window" },
                media:         { type: "bool", default: true, label: "Media", path: "modules.media" },
                resources: { type: "bool", default: true, label: "Resources", path: "modules.resources" },
                mixer:         { type: "bool", default: true, label: "Volume", path: "modules.mixer" },
                wifi:          { type: "bool", default: true, label: "Wi-Fi", path: "modules.wifi" },
                bluetooth:     { type: "bool", default: true, label: "Bluetooth", path: "modules.bluetooth" },
                tray:          { type: "bool", default: true, label: "Tray", path: "modules.tray" },
                notifications: { type: "bool", default: true, label: "Notifications", path: "modules.notifications" },
                battery:       { type: "bool", default: true, label: "Battery", path: "modules.battery" },
                nightlight:    { type: "bool", default: true, label: "Night light", path: "modules.nightlight" },
                privacy:       { type: "bool", default: true, label: "Privacy indicators", desc: "Green dot in the bar while an app is using the camera or microphone.", path: "modules.privacy" },
                power:         { type: "bool", default: true, label: "Power", path: "modules.power" }
            }
        },
        osd: {
            file: "bar.json",
            label: "section.osd",
            fields: {
                enabled:    { type: "bool", default: true, label: "Show OSD", desc: "Pill on volume / brightness change.", path: "osd.enabled" },
                volume:     { type: "bool", default: true, label: "Volume", path: "osd.volume" },
                brightness: { type: "bool", default: true, label: "Brightness", path: "osd.brightness" },
                position:   { type: "pos",  default: "bottom", label: "Position", desc: "Where on the screen the OSD appears.", path: "osd.position" },
                margin:     { type: "num", min: 24, max: 400, step: 4, default: 110, label: "Distance from edge", suffix: " px", path: "osd.margin" },
                size:       { type: "num", min: 0.6, max: 1.6, step: 0.05, default: 1.0, label: "Size", suffix: "×", path: "osd.size" },
                duration:   { type: "num", min: 0.5, max: 5, step: 0.1, default: 1.8, label: "Duration", suffix: " s", path: "osd.duration" }
            }
        },
        notif: {
            file: "bar.json",
            label: "section.notif",
            fields: {
                dnd:        { type: "bool", default: false, label: "Do not disturb", desc: "No popups (critical ones still show).", path: "notif.dnd" },
                toasts:     { type: "bool", default: true, label: "Popups", desc: "Cards that slide in at the screen edge.", path: "notif.toasts" },
                bar:        { type: "bool", default: true, label: "Show in bar", desc: "Bell expands into the latest notification.", path: "notif.bar" },
                position:   { type: "pos",  default: "top-right", label: "Popup position", desc: "Where popups appear.", path: "notif.position" },
                centerPosition: { type: "enum", options: ["same","top-left","top","top-right","left","center","right","bottom-left","bottom","bottom-right"], default: "same", label: "Notification center position", desc: "Where the notification center opens. \"Same as popups\" follows the popup position.", path: "notif.centerPosition" },
                margin:     { type: "num", min: 8, max: 200, step: 4, default: 16, label: "Distance from edge", suffix: " px", path: "notif.margin" },
                width:      { type: "num", min: 280, max: 560, step: 10, default: 380, label: "Width", suffix: " px", path: "notif.width" },
                timeout:    { type: "num", min: 1, max: 30, step: 1, default: 6, label: "Timeout (normal)", suffix: " s", path: "notif.timeout" },
                timeoutLow: { type: "num", min: 1, max: 20, step: 1, default: 4, label: "Timeout (low)", suffix: " s", path: "notif.timeoutLow" },
                maxVisible: { type: "num", min: 1, max: 8, step: 1, default: 4, label: "Max popups", path: "notif.maxVisible" },
                history:    { type: "num", min: 10, max: 200, step: 10, default: 60, label: "History limit", desc: "How many notifications are kept in the center.", path: "notif.history" },
                snooze:     { type: "num", min: 1, max: 120, step: 1, default: 15, label: "Snooze duration", suffix: " min", path: "notif.snooze" },
                group:      { type: "bool", default: true, label: "Group by app", desc: "Stack notifications from the same app together.", path: "notif.group" },
                actions:    { type: "bool", default: true, label: "Show action buttons", desc: "Inline buttons provided by the app.", path: "notif.actions" },
                accent:     { type: "bool", default: true, label: "Urgency accent", desc: "Coloured edge for important and critical notifications.", path: "notif.accent" },
                iconSize:   { type: "num", min: 28, max: 56, step: 2, default: 40, label: "Icon size", suffix: " px", path: "notif.iconSize" },
                density:    { type: "enum", options: ["compact","normal","spacious"], default: "normal", label: "Card density", path: "notif.density" },
                centerWidth:{ type: "num", min: 320, max: 560, step: 10, default: 460, label: "Center width", suffix: " px", path: "notif.centerWidth" },
                muted:      { type: "arr", default: [], hidden: true, path: "notif.muted" },
                blocked:    { type: "arr", default: [], hidden: true, path: "notif.blocked" },
                priority:   { type: "arr", default: [], hidden: true, path: "notif.priority" }
            }
        },
        layout: {
            file: "bar.json",
            label: "section.layout",
            fields: {
                active: { type: "layout", default: "dwindle", label: "Window layout", desc: "Applied to all tags. Needs source=~/.config/mango/layout.conf in config.conf.", path: "layout.active",
                          options: ["dwindle", "tile", "scroller", "monocle", "grid", "deck", "center_tile", "right_tile", "vertical_tile", "vertical_scroller", "vertical_grid", "vertical_deck", "fair", "vertical_fair"] },
                cycle:  { type: "str", default: "dwindle,scroller,grid,monocle", label: "Layout cycle", desc: "Comma-separated list for switch_layout (SUPER+Tab).", path: "layout.cycle" }
            }
        },
        gamemode: {
            file: "bar.json",
            label: "section.gamemode",
            fields: {
                effects: { type: "bool", default: true, label: "Disable compositor effects", desc: "Blur, shadows, rounded corners and animations in MangoWM (setoption).", path: "gamemode.effects" },
                tearing: { type: "bool", default: true, label: "Allow tearing", desc: "Fullscreen games may skip vsync for lower latency.", path: "gamemode.tearing" },
                power:   { type: "bool", default: true, label: "Performance power profile", desc: "power-profiles-daemon → performance, restored afterwards.", path: "gamemode.power" },
                idle:    { type: "bool", default: true, label: "Pause idle lock", desc: "swayidle is paused so the screen stays on.", path: "gamemode.idle" },
                dnd:     { type: "bool", default: true, label: "Do not disturb", path: "gamemode.dnd" },
                motion:  { type: "bool", default: true, label: "Disable shell animations", path: "gamemode.motion" },
                notify:  { type: "bool", default: true, label: "Notify on toggle", path: "gamemode.notify" },
                flatBar: { type: "bool", default: true, label: "Flat bar (no corners)", desc: "Full bar loses rounded corners, outer gap and shadow while game mode is on.", path: "gamemode.flatBar" },
                overlay:        { type: "bool", default: true, label: "Performance overlay", desc: "FPS and CPU/GPU load above all windows, even fullscreen games.", path: "gamemode.overlay" },
                overlayFps:     { type: "bool", default: true, label: "Overlay: FPS", path: "gamemode.overlayFps" },
                overlayCpu:     { type: "bool", default: true, label: "Overlay: CPU load", path: "gamemode.overlayCpu" },
                overlayGpu:     { type: "bool", default: true, label: "Overlay: GPU load", desc: "AMD (sysfs) and NVIDIA (nvidia-smi).", path: "gamemode.overlayGpu" },
                overlayTemps:   { type: "bool", default: false, label: "Overlay: temperatures", path: "gamemode.overlayTemps" },
                overlayPos:     { type: "enum", options: ["top-left","top-right","bottom-left","bottom-right"], default: "top-left", label: "Overlay position", path: "gamemode.overlayPos" },
                overlayScale:   { type: "num", min: 0.6, max: 2.5, step: 0.1, default: 1.0, label: "Overlay size", suffix: "×", path: "gamemode.overlayScale" },
                overlayOpacity: { type: "num", min: 0.2, max: 1.0, step: 0.05, default: 0.85, label: "Overlay opacity", path: "gamemode.overlayOpacity" },
                fpsSource:      { type: "enum", options: ["auto","display","mangohud"], default: "auto", label: "FPS source", desc: "auto: MangoHud log when fresh, otherwise display refresh rate.", path: "gamemode.fpsSource" },
                mangohudDir:    { type: "str", default: "/tmp/MangoHud", label: "MangoHud log folder", desc: "output_folder in MangoHud.conf; logging must be on (autostart_log).", path: "gamemode.mangohudDir" }
            }
        },
        capture: {
            file: "capture.json",
            label: "section.capture",
            fields: {
                ocrLang:       { type: "enum", default: "eng", options: ["eng", "ukr", "rus"], label: "OCR language", desc: "Tesseract language data must be installed (tesseract-data-eng/ukr/rus)." },
                ocrSingleLine: { type: "bool", default: false, label: "OCR: single line", desc: "Join the recognised text into one line." },
                ocrRaw:        { type: "bool", default: false, label: "OCR: keep line breaks", desc: "Do not re-flow paragraphs." },
                ocrNotify:     { type: "bool", default: true, label: "Notify after OCR" },
                lensOpen:      { type: "enum", default: "newtab", options: ["newtab", "sidebar"], label: "Lens opens in", desc: "newtab builds a local page and opens your browser; sidebar needs wlrctl + wtype and a browser keybind." },
                screenshotDir: { type: "str", default: "~/Pictures/Screenshots", label: "Screenshot folder" }
            }
        },
        record: {
            file: "bar.json",
            label: "section.record",
            fields: {
                audio:   { type: "enum", default: "system", options: ["system", "mic", "none"], label: "Audio", desc: "System sound, microphone or no audio.", path: "record.audio" },
                fps:     { type: "num", min: 10, max: 120, step: 5, default: 30, label: "Frame rate", suffix: " fps", path: "record.fps" },
                encoder: { type: "enum", default: "software", options: ["software", "vaapi"], label: "Encoder", desc: "vaapi uses the GPU (h264_vaapi) — much lighter on the CPU.", path: "record.encoder" },
                dir:     { type: "str", default: "~/Videos/Recordings", label: "Save folder", path: "record.dir" },
                notify:  { type: "bool", default: true, label: "Notify when saved", desc: "With a thumbnail and Open / Show in folder / Copy path actions.", path: "record.notify" }
            }
        },
        nightlight: {
            file: "nightlight.json",
            label: "section.nightlight",
            fields: {
                enabled:   { type: "bool", default: false, label: "Night light", desc: "Warm the screen with gammastep." },
                mode:      { type: "enum", default: "manual", options: ["manual", "schedule"], label: "Mode", desc: "manual = fixed temperature; schedule = follow sunrise and sunset." },
                temp:      { type: "num", min: 2000, max: 6500, step: 100, default: 4000, label: "Temperature", suffix: " K" },
                dayTemp:   { type: "num", min: 2000, max: 6500, step: 100, default: 6500, label: "Day temperature", suffix: " K" },
                nightTemp: { type: "num", min: 2000, max: 6500, step: 100, default: 4000, label: "Night temperature", suffix: " K" },
                sunset:    { type: "str", default: "19:00", label: "Sunset", desc: "24-hour time, e.g. 19:30." },
                sunrise:   { type: "str", default: "07:00", label: "Sunrise", desc: "24-hour time, e.g. 07:00." }
            }
        },
        updates: {
            file: "updates.json",
            label: "section.updates",
            fields: {
                autoCheck:     { type: "bool", default: false, label: "Check for updates automatically", desc: "Uses checkupdates / yay -Qum / flatpak; never installs anything." },
                intervalHours: { type: "num", min: 1, max: 48, step: 1, default: 6, label: "Check interval", suffix: " h" },
                terminal:      { type: "str", default: "", label: "Terminal for updates", desc: "Empty = General → Terminal (e.g. ghostty)." }
            }
        },
        clock: {
            file: "clock.json",
            label: "section.clock",
            fields: {
                hour12:           { type: "bool", default: false, label: "12-hour" },
                showSeconds:      { type: "bool", default: false, label: "Show seconds" },
                dateFormat:       { type: "str",  default: "d MMMM", label: "Date format" },
                fullDateFormat:   { type: "str",  default: "dddd, d MMMM", label: "Full date format" },
                utcOffsetMinutes: { type: "num", nullable: true, default: null, hidden: true },
                zoneLabel:        { type: "str",  default: "", hidden: true }
            }
        },
        lockscreen: {
            file: "lockscreen.json",
            label: "section.lockscreen",
            fields: {
                // Порядок = порядок у налаштуваннях. Сусідні поля з однаковим
                // group стають однією секцією; group — ключ перекладу в Lang.
                enabled:        { type: "bool", default: true, group: "section.lock.general", label: "Use Edots lock screen" },
                layout:         { type: "enum", options: ["center","top","bottom","left"], default: "center", group: "section.lock.general", label: "Layout", desc: "Where the clock and unlock block sit on the screen." },

                clockStyle:     { type: "enum", options: ["split","solid","stacked"], default: "split", group: "section.lock.clock", label: "Clock style" },
                clockWeight:    { type: "num", min: 100, max: 900, step: 100, default: 300, group: "section.lock.clock", label: "Clock weight" },
                clockSize:      { type: "num", min: 80, max: 320, step: 8, default: 160, group: "section.lock.clock", label: "Clock size", suffix: " px" },
                clock24h:       { type: "bool", default: true, group: "section.lock.clock", label: "24-hour clock" },
                showSeconds:    { type: "bool", default: false, group: "section.lock.clock", label: "Show seconds" },
                showDate:       { type: "bool", default: true, group: "section.lock.clock", label: "Show date" },
                greeting:       { type: "bool", default: true, group: "section.lock.clock", label: "Show greeting" },

                showUser:       { type: "bool", default: true, group: "section.lock.widgets", label: "Show user name" },
                weatherWidget:  { type: "bool", default: false, group: "section.lock.widgets", label: "Weather widget" },
                mediaWidget:    { type: "bool", default: false, group: "section.lock.widgets", label: "Now playing widget" },

                notifMode:      { type: "enum", options: ["off","count","list"], default: "count", group: "section.lock.notifications", label: "Notifications on lock screen", desc: "Off hides them. Counter shows how many are waiting. List adds compact cards." },
                notifContent:   { type: "bool", default: false, group: "section.lock.notifications", label: "Show notification text", desc: "Off keeps only the app and the count, so the lock screen reveals nothing sensitive." },
                notifMax:       { type: "num", min: 1, max: 10, step: 1, default: 3, group: "section.lock.notifications", label: "Cards to show" },

                fillMode:       { type: "enum", options: ["fill","fit","stretch"], default: "fill", group: "section.lock.background", label: "Wallpaper fill mode" },
                blurStrength:   { type: "num", min: 0, max: 1, step: 0.05, default: 0.4, group: "section.lock.background", label: "Blur strength" },
                blurRadius:     { type: "num", min: 8, max: 128, step: 8, default: 40, group: "section.lock.background", label: "Blur radius", suffix: " px" },
                scrimOpacity:   { type: "num", min: 0, max: 1, step: 0.05, default: 0.5, group: "section.lock.background", label: "Dim overlay" },
                kenBurns:       { type: "bool", default: true, group: "section.lock.background", label: "Ken Burns zoom" },
                parallax:       { type: "bool", default: true, group: "section.lock.background", label: "Mouse parallax" },
                floatingShapes: { type: "bool", default: true, group: "section.lock.background", label: "Floating accent shapes" },
                successFlash:   { type: "bool", default: true, group: "section.lock.background", label: "Success flash" },

                passwordStyle:  { type: "enum", options: ["shapes","dots","text"], default: "shapes", group: "section.lock.security", label: "Password style" },
                faceUnlock:     { type: "bool", default: false, group: "section.lock.security", label: "Face ID unlock", desc: "Unlock with the camera after enrolling in a terminal: edots faceid enroll. The password always works." },

                powerButtons:   { type: "bool", default: true, group: "section.lock.power", label: "Power buttons" },

                widgets:        { type: "map", default: {}, hidden: true },
                widgetsNothing: { type: "map", default: {}, hidden: true },

                devMode:        { type: "bool", default: false, group: "section.lock.advanced", label: "Developer mode", desc: "Allow a short whitelist of SAFE hotkeys while locked (screenshot, media, volume, brightness). They never unlock the session. Leave off on shared machines." },
                devScreenshot:  { type: "bool", default: true, group: "section.lock.advanced", label: "Print Screen → screenshot", desc: "Print saves a screenshot; Ctrl+Print also copies it." },
                devImportMango: { type: "bool", default: true, group: "section.lock.advanced", label: "Use my Mango binds", desc: "Reads ~/.config/mango/config.conf and also accepts the combos bound there to screenshot, media, volume and brightness commands." },
                devKeyScreenshot:     { type: "str", default: "Super+U", group: "section.lock.advanced", label: "Screenshot hotkey", desc: "Extra combo for a screenshot while locked, e.g. Super+U. Leave empty to disable." },
                devKeyScreenshotCopy: { type: "str", default: "Super+Shift+U", group: "section.lock.advanced", label: "Screenshot + clipboard hotkey" },
                devMedia:       { type: "bool", default: true, group: "section.lock.advanced", label: "Media keys" },
                devVolume:      { type: "bool", default: true, group: "section.lock.advanced", label: "Volume keys" },
                devBrightness:  { type: "bool", default: true, group: "section.lock.advanced", label: "Brightness keys" },
                devShowKeys:    { type: "bool", default: false, group: "section.lock.advanced", label: "Show pressed hotkeys", desc: "Shows names of function/modified keys (never typed characters) — handy for finding key names." }
            }
        },
        session: {
            file: "session.json",
            label: "section.session",
            fields: {
                idleEnabled:      { type: "bool", default: true, label: "Idle timeouts", desc: "Lock the screen and turn the display off after inactivity. Locking before suspend stays on." },
                lockMinutes:      { type: "num", min: 0, max: 120, step: 1, default: 5, label: "Lock screen after", suffix: " min", desc: "0 = never. The lock screen still appears before suspend." },
                screenOffMinutes: { type: "num", min: 0, max: 120, step: 1, default: 10, label: "Turn display off after", suffix: " min", desc: "Requires wlopm (installed by install.sh). 0 = never." },
                suspendMinutes:   { type: "num", min: 0, max: 240, step: 1, default: 0, label: "Suspend after", suffix: " min", desc: "0 = never. Suspending always locks first when the option below is on." },
                lockOnSuspend:    { type: "bool", default: true, label: "Lock before suspend", desc: "Also used for lid-close and the Suspend action." }
            }
        },
        colors: {
            file: "colors.json",
            label: "section.colors",
            fields: {
                bg0:    { type: "color", default: "#060f0c", label: "Background — deepest" },
                bg1:    { type: "color", default: "#0a1a16", label: "Surface" },
                bg2:    { type: "color", default: "#0f2922", label: "Container" },
                bg3:    { type: "color", default: "#15372e", label: "Container high" },
                bg4:    { type: "color", default: "#1c4a3d", label: "Container highest" },
                fg:     { type: "color", default: "#dae7e3", label: "Foreground" },
                grey1:  { type: "color", default: "#31816c", label: "Outline" },
                grey2:  { type: "color", default: "#90d5c2", label: "Variant" },
                accent: { type: "color", default: "#74e7c8", label: "Accent" },
                red:    { type: "color", default: "#d27c79", label: "Error" },
                blue:   { type: "color", default: "#d27c79", label: "Secondary" },
                purple: { type: "color", default: "#d1df9f", label: "Tertiary" }
            }
        }
    })

    // Сторінки згруповані за змістом. Порядок масиву = порядок у навігації;
    // група змінюється лише між сусідніми сторінками.
    readonly property var pages: [
        { name: "page.appearance", icon: "palette",         group: "group.personal", cats: ["theme"] },
        { name: "page.colors",     icon: "format_paint",    group: "group.personal", cats: ["colors"] },
        { name: "page.wallpapers", icon: "wallpaper",       group: "group.personal", cats: [] },
        { name: "page.bar",        icon: "space_dashboard", group: "group.desktop",  cats: ["bar", "modules"] },
        { name: "page.widgets",    icon: "widgets",         group: "group.desktop",  cats: ["widgets"] },
        { name: "page.layout",     icon: "view_quilt",      group: "group.desktop",  cats: ["layout"] },
        { name: "page.clock",      icon: "schedule",        group: "group.desktop",  cats: ["clock"] },
        { name: "page.nightlight", icon: "bedtime",         group: "group.desktop",  cats: ["nightlight"] },
        { name: "page.general",    icon: "tune",            group: "group.system",   cats: ["general"] },
        { name: "page.session",    icon: "bedtime",         group: "group.system",   cats: ["session"] },
        { name: "page.lockscreen", icon: "lock",            group: "group.system",   cats: ["lockscreen"] },
        { name: "page.osd",        icon: "volume_up",       group: "group.system",   cats: ["osd"] },
        { name: "page.notif",      icon: "notifications",   group: "group.system",   cats: ["notif"] },
        { name: "page.monitor",    icon: "monitor_heart",   group: "group.system",   cats: ["monitor"] },
        { name: "page.updates",    icon: "system_update",   group: "group.system",   cats: ["updates"] },
        { name: "page.gamemode",   icon: "sports_esports",  group: "group.system",   cats: ["gamemode"] },
        { name: "page.record",     icon: "videocam",        group: "group.system",   cats: ["capture", "record"] },
        { name: "page.plugins",    icon: "extension",       group: "group.extras",   cats: [] },
        { name: "page.about",      icon: "info",            group: "group.extras",   cats: [] }
    ]
}
