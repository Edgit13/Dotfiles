# Changelog

All notable changes to Edots are recorded here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are tagged `vX.Y.Z`. Run `./tools/release.sh X.Y.Z` to cut one.

## [Unreleased]

### Changed

- Refreshed the screenshots for the current shell: the bar in all three styles
  (full, pill, islands), the launcher, Settings and the wallpaper picker.
  The docs site uses the same images.

## [1.0.0] — 2026-11-11

First versioned snapshot of the rice. Everything below was already in the tree;
the tag exists so people can pin a known-good state.

### Added

- **Bar**: three styles — `full`, `pill` and `islands` (three floating capsules) —
  on any edge, per monitor. Morph, window, spotlight and drawer open modes.
- **Surfaces**: launcher, wallpapers, clipboard, mixer, audio studio, display
  centre, Wi-Fi, Bluetooth, media, power menu, updates, diagnostics, keybind
  cheat-sheet and resources.
- **Lock screen**: Nothing and Material 3 designs, configurable clock, widgets,
  wallpaper fill modes, an editor, PAM unlock and optional on-device Face ID.
- **Notifications**: center with grouping, snooze, history limit, urgency
  accents, inline actions and configurable density.
- **Dashboard**: overview, media, performance, workspaces and planner tabs, plus
  calendar, weather, timer, todo and brightness cards.
- **Tray**: StatusNotifier host with Material 3 DBusMenu popups and submenus.
- **Audio**: per-app volume and output routing, EQ, presets and mic processing.
- **Night light**: gammastep-backed service with manual and scheduled modes.
- **Updates**: repo + AUR + Flatpak check with a surface and notifications.
- **Capture**: screenshot, region OCR, Google Lens and recording from the bar.
- **Plugins**: bundled examples, a manifest format and CLI management
  (`edots plugin …`).
- **Themes**: Material 3 Expressive and Nothing, light/dark, wallpaper-derived
  palettes, dot/fade/scan transitions, and sync to GTK, terminals, Firefox,
  rofi and KDE.
- **CLI**: `edots` with surfaces, theme, session, Face ID, updates, diagnostics
  and raw IPC passthrough.
- **Tooling**: `tools/lint.sh`, `tools/release.sh`, `Makefile`, pre-commit hook
  and a GitHub Actions lint workflow.
- **Docs**: static site in `docs/` (overview, install, keybinds, themes,
  plugins) with a small progressive-enhancement motion layer — scroll reveal,
  a progress bar, copy buttons and a ticker, all disabled under
  `prefers-reduced-motion`.

### Changed

- Lock screen settings are grouped into General, Clock & date, Widgets,
  Background & effects, Password & security, Power and Advanced, and live under
  **System** in Settings.
- Settings search matches section group titles in both Ukrainian and English.

### Fixed

- Pill and island morph no longer show the previous hover row through the
  expanding panel: an opaque underlay sits between the hover and expanded slots.
- `edots backup` no longer calls a missing `bup.sh`; it writes a timestamped
  archive of the live configuration instead.

[Unreleased]: https://github.com/Edgit13/Dotfiles/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Edgit13/Dotfiles/releases/tag/v1.0.0
