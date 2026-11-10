# Lock screen (MangoWC / Quickshell)

The lock screen lives inside the bar shell at `quickshell/bar/lockscreen/`.
It uses `ext-session-lock-v1`, reads `~/.config/quickshell/colors.json`
(reloading when the palette changes) and is owned by the running bar process —
there is no separate lock-screen instance to install.

## What you get
- Big monospace clock + date
- User avatar + name, PAM password field (Enter to unlock, Esc to clear)
- Show/hide password toggle, attempt counter, per-attempt error state
- Suspend / reboot / poweroff with confirmation overlay
- Optional **Face ID** (webcam, local embeddings via YuNet + SFace) — see the
  main README; enroll with `edots faceid enroll`, then enable it in
  Settings → Lock screen. The password path is unchanged.
- IPC target `ilock` on the bar shell: `relock` / `quit`

## Designs
The scene follows the active theme design (`Theme.settings.nothing`):

- **Material 3** (`LockM3.qml`) — expressive clock, floating shapes, shape-based
  password dots.
- **Nothing** (`LockNothing.qml`) — dot-matrix clock (Doto), seconds strip,
  thin-outline chips, dot-grid wallpaper veil and the red `#D71921` accent.
  Its password field honours Settings → Password style (`shapes` / `dots` /
  `text`).

Both scenes share `LockWidget` / `LockWidgetPanel`. In **Settings → Lock screen**
you can drag widgets directly in the preview; shape, colour and size are edited
in the panel below it. Positions are stored per design in `lockscreen.json`
(`widgets` for M3, `widgetsNothing` for Nothing), so the two layouts never
interfere.

All motion uses `ThemeMotion`, so Reduce Motion, Animation Speed and
animations-off are respected in both designs. Preview is available in Settings
or full screen (the button under the preview).

## Install
`./install.sh` (or `./sync.sh install`) compiles the helper and links the
config. To compile it manually:

    gcc -O2 -o ~/.config/quickshell/bar/lockscreen/pam-auth \
        ~/.config/quickshell/bar/lockscreen/pam-auth.c -lpam

It also installs the PAM service to `/etc/pam.d/quickshell-lock` (via sudo).
Requires `base-devel` and `pam` headers.

## Use

Lock through the bar shell:

    qs -p ~/.config/quickshell/bar/shell.qml ipc call ilock relock

or simply:

    edots lock

MangoWC keybind (`~/.config/mango/binds.conf`):

    bind=SUPER,L,exec,edots lock

Auto-lock on idle / before sleep is handled by `edots` session timers, which
drive `swayidle` and the same `ilock` IPC target.

## Notes
- Requires MangoWC built with `ext-session-lock-v1` support (standard in recent builds).
- Auth runs as your own user against PAM `system-auth` — no sudo needed.
- Colors are read from `~/.config/quickshell/colors.json`; delete that file
  and it falls back to the embedded palette.
