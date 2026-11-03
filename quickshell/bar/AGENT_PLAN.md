# Edots Quickshell — Feature Completion Plan

## Project Overview
- **Directory:** `~/Dotfiles/quickshell/bar` (symlinked as `~/.config/quickshell/bar`)
- **Main Entrypoint:** `ShellNext.qml` (loaded via `shell.qml`)
- **Environment:** Arch Linux, MangoWC (v0.18.1), Quickshell (0.3.2-git), PipeWire (1.6.10), WirePlumber, NetworkManager, BlueZ (bluetoothd), UPower / power-profiles-daemon.
- **Design System:** Material 3 Expressive & Nothing OS (dual-theme engine).

---

## Stage 0: Existing Feature Inventory & Gap Analysis

### Existing Systems (Preserve & Extend)
| System | Status | Core Files | Notes / Gaps |
|---|---|---|---|
| **Morphing Shell & Bar** | Fully Functional | `shell/Bar.qml`, `shell/BarWindow.qml`, `shell/MorphShell.qml`, `shell/SurfaceOverlay.qml`, `shell/ShellState.qml` | Handles pill/full bar, popups, morph transitions, multi-monitor. Needs registration for new surfaces. |
| **Theme Engine** | Fully Functional | `theme/Theme.qml`, `theme/ThemeColors.qml`, `theme/ThemeNothing.qml`, `theme/ThemeTypography.qml` | M3 Expressive & Nothing OS. All new UI must use Theme.* tokens without hardcoding. |
| **Settings & Localization** | Fully Functional | `settings/Schema.qml`, `settings/SettingsState.qml`, `settings/SettingsApp.qml`, `settings/Lang.qml` | Schema-driven settings + Ukrainian/English localization. |
| **Wi-Fi Manager** | Partially Implemented | `services/WifiService.qml`, `surfaces/WifiSurface.qml`, `modules/network/NetworkModule.qml` | Only basic Wi-Fi scan and connect. Missing: Ethernet info, VPN, saved connections, IP/Gateway/DNS, diagnostics. |
| **Mixer & Audio** | Partially Implemented | `surfaces/MixerSurface.qml`, `modules/volume/VolumeModule.qml` | Only default sink volume slider and brightness slider. Missing: output/input device selector, mic mute/volume, per-app volume, profiles. |
| **Power & Battery** | Partially Implemented | `surfaces/PowerSurface.qml`, `modules/battery/BatteryModule.qml`, `modules/power/PowerModule.qml` | Only 4 action buttons (lock/logout/reboot/shutdown). Missing: battery health %, cycle count, temp, charge stats, power-profiles-daemon profiles, charging thresholds. |
| **Bluetooth Manager** | **MISSING** | None (`BluetoothService.qml`, `BluetoothSurface.qml` do not exist) | No Bluetooth management surface or service. Native `Quickshell.Bluetooth` is available in Quickshell 0.3.2. |
| **Update Center** | **MISSING** | None | No system update checker or update UI in shell or settings. `checkupdates` and `yay` are available. |
| **Diagnostics Center** | Partially Implemented | `services/PerformanceService.qml`, `services/MonitorService.qml`, `surfaces/ResourcesSurface.qml`, `surfaces/ProcessMonitorTab.qml` | Great resource monitor, but no system diagnostic status (systemd services, Edots service health, audio/net/bt diagnostic checks, sanitized export). |
| **Launcher, Clipboard, Wallpapers, Media, Binds** | Fully Functional | `surfaces/LauncherSurface.qml`, `ClipboardSurface.qml`, `WallpaperSurface.qml`, `MediaSurface.qml`, `BindsSurface.qml` | Keep intact. |
| **OSD, Notifications, Desktop Widgets, Dock, LockScreen, ScreenTool** | Fully Functional | `osd/`, `notifications/`, `widgets/`, `dock/`, `lockscreen/`, `screentool/` | Keep intact. |

---

## Detailed Roadmap

### Stage 1: Bluetooth Manager
1. Implement `services/BluetoothService.qml` using `Quickshell.Bluetooth` (BlueZ D-Bus integration) with `bluetoothctl` commands/fallbacks.
   - Adapter state (enabled/disabled, discoverable, discovering/scanning).
   - Device discovery and list (paired, connected, available nearby).
   - Actions: connect, disconnect, pair, unpair/remove, trust/untrust.
   - Device attributes: name, address, battery percentage, RSSI/type/icon, connection state.
   - Proper async handling, error feedback, loading states, empty states.
2. Implement `surfaces/BluetoothSurface.qml`:
   - Dual theme: Material 3 Expressive and Nothing OS.
   - Header with adapter toggle, scan button, status.
   - Device list grouped by Connected / Paired / Discovered.
   - Device item details (icon, battery pill, trust badge, connect/disconnect button, overflow menu for unpair/trust).
3. Implement `modules/bluetooth/BluetoothModule.qml`:
   - Bar reveal button showing Bluetooth glyph, connected device name or battery when hovered, click to toggle/open surface.
4. Integrate with `shell/SurfaceOverlay.qml`, `shell/BarWindow.qml`, `shell/ShellNext.qml` (IPC targets: `pill.showBluetooth`, `pill.toggleBluetooth`), and `settings/Schema.qml` + `settings/Lang.qml`.
5. Test: Bluetooth adapter toggle, scan, pairing/connection with available devices, UI responsiveness, theme switching.

### Stage 2: Network Manager+
1. Extend `services/WifiService.qml`:
   - Ethernet detection & status (connection name, speed, state via `nmcli device`).
   - VPN management (active & available VPN connections, toggle connect/disconnect).
   - Saved connections list with forget option.
   - Network IP details: IPv4/IPv6 address, Gateway, DNS servers, interface names.
   - Connection diagnostics (ping gateway/DNS/internet latency test).
   - Robust parsing handling SSIDs with spaces, colons, or UTF-8.
2. Extend `surfaces/WifiSurface.qml`:
   - Add segmented tabs / sections: Wi-Fi, Ethernet, VPN, Details & Diagnostics.
   - Display active network configuration (IP, subnet, gateway, DNS).
   - Support VPN connect/disconnect with status indicators.
   - Support both Material 3 and Nothing OS.
3. Update `settings/Lang.qml` with all new localized strings.
4. Test: Wi-Fi scan, Ethernet detection, VPN listing, details display, diagnostic ping.

### Stage 3: Audio Device Manager
1. Create `services/AudioService.qml` (or integrate PipeWire/WirePlumber manager):
   - Track all audio sinks (output devices) and sources (input devices/microphones).
   - Default output & input selection (switching via `Pipewire.preferredDefaultAudioSink` or `wpctl set-default`).
   - Microphone mute toggle and volume control.
   - Per-application playback streams tracking (app name, icon, volume, mute).
   - Audio profiles and port detection where supported.
2. Extend `surfaces/MixerSurface.qml`:
   - Retain existing volume hero and brightness sliders.
   - Add Output Devices selector (choose default speaker/headphone).
   - Add Input Devices selector & Microphone volume/mute slider.
   - Add Application Volume list (per-stream volume sliders).
   - Both Material 3 Expressive and Nothing OS styles.
3. Update `modules/volume/VolumeModule.qml` if needed.
4. Update `settings/Lang.qml`.
5. Test: Device switching, volume adjustments, mic mute, per-app volume adjustments, theme compatibility.

### Stage 4: Power Manager
1. Create `services/PowerManagerService.qml`:
   - Integrate with `Quickshell.Services.UPower` (battery devices, energy, rate, time to full/empty).
   - Read sysfs `/sys/class/power_supply/BAT*` for:
     - Battery health calculation (`charge_full / charge_full_design * 100`).
     - Cycle count (`cycle_count`).
     - Battery temperature (from hwmon/sysfs when available).
   - Integrate with `power-profiles-daemon` (`PowerProfiles` or `powerprofilesctl`) for profiles (Performance, Balanced, Power Saver).
   - Check hardware support for charging thresholds (`charge_control_limit_max`, `charge_control_end_threshold`). Never show fake thresholds if unsupported.
2. Extend `surfaces/PowerSurface.qml`:
   - Keep existing Lock, Logout, Reboot, Shutdown actions.
   - Add battery health, cycles, and charging rate card when battery is present.
   - Add Power Profile switcher (Performance / Balanced / Power Saver).
   - Support both Material 3 and Nothing OS styling.
3. Update `settings/Lang.qml`.
4. Test: Profile switching, battery statistics display, accuracy of sysfs readings.

### Stage 5: Update Center
1. Create `services/UpdateService.qml`:
   - Check official updates safely via `checkupdates` (no pacman lock interference).
   - Check AUR updates optionally via `yay -Qum`.
   - Parse package names, old versions, new versions, repo/AUR tag.
   - Provide refresh capability.
   - Safe update trigger: NEVER auto-update, NEVER run in background without user interaction.
   - Launch update command in user's configured terminal (`ghostty -e pacman -Syu` or `yay -Syu`) with confirmation dialog.
2. Create `surfaces/UpdateSurface.qml`:
   - Update list with package name, old -> new version, repo badge.
   - Refresh button with loading animation.
   - "Update All in Terminal" button with explicit confirmation dialog.
   - Both Material 3 Expressive and Nothing OS styling.
3. Integrate into `shell/SurfaceOverlay.qml`, `shell/BarWindow.qml`, `shell/ShellNext.qml` (IPC `pill.showUpdates`), and settings.
4. Update `settings/Lang.qml`.
5. Test: Package checking, version parsing, terminal launch on confirm, cancellation.

### Stage 6: Diagnostics Center
1. Create `services/DiagnosticsService.qml`:
   - Check systemd unit statuses (`bluetooth`, `NetworkManager`, `pipewire`, `wireplumber`, `power-profiles-daemon`).
   - Check Edots components health and Quickshell error logs.
   - Check system tools availability (`quickshell`, `mmsg`, `nmcli`, `bluetoothctl`, `wpctl`, `pactl`, `brightnessctl`).
   - Collect network, audio, bluetooth diagnostic summary.
   - Collect MangoWC information (`mmsg get version`, active monitors, tags).
   - Hardware summary (CPU model, GPU driver/model, RAM total/available, battery status).
   - Sanitized report generator (stripping any credentials/tokens/personal paths, showing preview before exporting to file).
2. Create `surfaces/DiagnosticsSurface.qml` (or integrate into `ResourcesSurface.qml` / `SettingsApp.qml`):
   - Health status overview cards (green/yellow/red indicators).
   - Service status list with restart/check options.
   - Export sanitized diagnostic report button with save path dialog.
   - Both Material 3 Expressive and Nothing OS styling.
3. Update `settings/Lang.qml`.
4. Test: Service checks, diagnostic reporting, report sanitization, export to disk.

### Stage 7: Integration and Consistency Pass
1. Shell integration:
   - Verify `shell/SurfaceOverlay.qml` handles all surfaces (`bluetooth`, `wifi`, `mixer`, `power`, `updates`, `diagnostics`).
   - Verify `shell/BarWindow.qml` pill panels and sizing.
   - Verify `shell/ShellNext.qml` IPC handlers for all surfaces.
   - Verify multi-monitor behavior (proper screen assignment and focus).
   - Verify keyboard navigation and Escape key behavior.
2. Design & Theme consistency:
   - Verify all new UI components in Material 3 Expressive mode.
   - Verify all new UI components in Nothing OS mode (dot typography, monochrome, red accent, wireframe borders).
   - Verify light and dark mode switching.
3. Settings persistence and schema verification.
4. Comprehensive testing and error checking.
