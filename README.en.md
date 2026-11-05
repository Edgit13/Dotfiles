<div align="center">

<img src="screenshots/banner.png" alt="Nook — a MangoWM + Quickshell rice" width="100%">

<br>

<img src="screenshots/icon.png" alt="Edots" width="88">

# Edots

**Nook's MangoWM + Quickshell rice.**
Material 3 Expressive and Nothing — two designs, one wallpaper palette.

[![Wayland](https://img.shields.io/badge/Wayland-MangoWM-6B4EBA?style=flat-square&logo=wayland&logoColor=F4F1EA)](https://github.com/DreamMaoMao/mangowc)
[![Quickshell](https://img.shields.io/badge/Shell-Quickshell-E01B24?style=flat-square)](https://quickshell.org)
[![License](https://img.shields.io/badge/License-MIT-000000?style=flat-square)](LICENSE)

[**Full documentation →**](README.md) · [Features](README.md#-features) · [Gallery](README.md#-gallery) · [Install](README.md#-installation) · [Keybinds](README.md#-keybinds)

<br>

<img src="screenshots/Bar-Material.png" alt="Edots bar — Material 3" width="100%">
<sub><b>Material 3 Expressive</b> — tonal pills, dynamic colours</sub>

<br><br>

<img src="screenshots/Bar-Nothing.png" alt="Edots bar — Nothing" width="100%">
<sub><b>Nothing</b> — monochrome, dot-matrix rings, one red accent</sub>

</div>

<br>

## What is Edots?

A full Wayland desktop built around a morphing Quickshell bar: a launcher,
dashboard, wallpaper picker, mixer, audio studio, display centre, notification
daemon, lock screen and settings window. One palette generated from the current
wallpaper repaints the bar, GTK, terminals, Firefox, rofi and KDE.

## Highlights

| | |
|---|---|
| 🎨 **Two designs** | Material 3 Expressive and Nothing, light and dark, switchable live. |
| 🧩 **Modular bar** | Any edge, per monitor, with modules you can toggle and reorder. |
| 🪄 **Surfaces** | Launcher, wallpapers, clipboard, mixer, audio, display, Wi-Fi, media, power, keybinds. |
| 🔎 **Advanced launcher** | Apps, files, calculator, emoji and shell commands in one field. |
| 📊 **Dashboard** | Weather, resources, media, workspaces and a planner. |
| 🎚 **Audio studio** | 10-band EQ, presets, bypass and RNNoise mic cleanup via EasyEffects. |
| 🔀 **Per-app audio** | Per-app volume, mute and pinned output devices. |
| 🖥 **Display centre** | Resolution, refresh, scale, rotation and layout with an 18-second safety rollback. |
| 🔒 **Lock screen** | Quickshell + PAM, ken burns, parallax, power menu, lock-before-suspend. |
| 🌙 **Idle & session** | Lock, display-off and suspend timers written live to `swayidle`. |
| 🧱 **Plugins** | Drop in a folder with `plugin.json` for a panel, a bar module, or both. |
| 🩺 **`edots` CLI** | Every surface plus `edots doctor` for a full health check. |

## Quick start

```sh
git clone https://github.com/Edgit13/Dotfiles ~/Dotfiles
cd ~/Dotfiles && ./install.sh
```

Then log out and back in, and check the install:

```sh
edots doctor
```

See the [main README](README.md) for requirements, all keybinds, IPC, the colour
system, plugin authoring and the repository layout.

<br>

<div align="center">

**Made by [Nook](https://github.com/Edgit13) · MIT**

</div>
