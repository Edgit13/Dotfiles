# Agent Handoff Guide

## Project Status
- Working directory: `~/Dotfiles/quickshell/bar` (symlinked at `~/.config/quickshell/bar`).
- Entrypoint: `ShellNext.qml` (wrapped by `shell.qml`).
- Current stage: **Stage 4 — Power Manager**.
- Completed: Stage 0 (Audit), Stage 1 (Bluetooth Manager), Stage 2 (Network Manager+), Stage 3 (Audio Device Manager).

## Context & Architecture
1. **Power & Battery Stack**:
   - `Quickshell.Services.UPower`: `UPower.displayDevice` has `percentage`, `state`, `timeToEmpty`, `timeToFull`, `changeRate`.
   - `PowerProfiles`: `profile`, `hasPerformanceProfile` ("power-saver", "balanced", "performance").
   - Sysfs `/sys/class/power_supply/BAT*`: `cycle_count`, `charge_full`, `charge_full_design`, `charge_now`, `current_now`, `voltage_now`.
   - Charging threshold: check `/sys/class/power_supply/BAT*/charge_control_end_threshold` or similar. Only expose if hardware supports it.
2. **Surfaces**: `surfaces/PowerSurface.qml` has lock/logout/reboot/shutdown. Extend it with battery health, cycle count, temperature, charging stats, power profile switcher (Performance/Balanced/Power Saver).
3. **Execution rules**: Test after each stage, update `AGENT_PROGRESS.md` and `AGENT_HANDOFF.md`, proceed sequentially.

## Immediate Action: Stage 4 — Power Manager
- Create `services/PowerManagerService.qml`:
  - Query battery metrics from UPower & sysfs (`cycle_count`, health %, rate, time to full/empty).
  - Power profiles (read and switch via `powerprofilesctl` / `PowerProfiles`).
  - Charging threshold check (never expose unsupported fake options).
- Extend `surfaces/PowerSurface.qml`:
  - Add Battery Stats Card (health %, cycle count, charge rate, time remaining).
  - Add Power Profile selector (Performance, Balanced, Power Saver).
  - Keep Lock, Logout, Reboot, Shutdown intact.
  - Support Material 3 and Nothing OS styles.
- Add strings to `settings/Lang.qml`.
- Test with `reload.sh` and IPC.
