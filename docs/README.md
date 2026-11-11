# Docs site

Static HTML, no build step. The site is served by GitHub Pages directly from this
folder — `Settings → Pages → Deploy from a branch → master /docs`.

```
docs/
├─ index.html      overview
├─ install.html    requirements, installer, updates, NixOS
├─ keybinds.html   every bind, launcher prefixes, CLI/IPC
├─ themes.html     Material vs Nothing, palettes, night light
├─ plugins.html    manifest, folders, CLI
└─ assets/
   ├─ style.css
   ├─ app.js       scroll reveal, progress bar, copy buttons, ticker
   └─ img/         copies of the screenshots used on the pages
```

## Preview locally

```sh
python3 -m http.server -d docs 8080
# http://localhost:8080
```

`make docs` prints the same commands.

## Editing

- Shared header and footer are duplicated in each page on purpose: no templating,
  no JavaScript, no dependencies.
- Keep links relative (`install.html`, `assets/img/...`) so the site works under
  the `/Dotfiles/` project path.
- Screenshots live in `screenshots/` at the repo root; copy only the ones a page
  needs into `assets/img/` (Pages publishes `docs/` only).
- Palette: black `#0b0a09`, ink `#f4f1ea`, red `#e01b24`, purple `#6b4eba`,
  lavender `#cdbff0`.

## Motion

`assets/app.js` is progressive enhancement: scroll reveal, the top progress bar,
copy buttons on code blocks, the hero ticker and the pointer spotlight. Without
JavaScript the page is fully readable, and everything is disabled for
`prefers-reduced-motion: reduce`. Keep new animations in the same spirit —
short, transform/opacity only, no layout shift.

## Hosting

The site is deployed with rsync to a small Ubuntu box and served by a systemd
unit on **:8091**:

```sh
make deploy                     # rsync docs/ to the server
```

The unit lives in `tools/systemd/edots-site.service` and runs
`python3 -m http.server` as the `eduard` user, with `ProtectSystem=strict`,
`ProtectHome=read-only` and no capabilities. Install it once on the server:

```sh
sudo install -m 644 tools/systemd/edots-site.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now edots-site
```

Point a reverse proxy or tunnel at `http://127.0.0.1:8091`. Override the target
with `EDOTS_DOCS_HOST=user@host` and `EDOTS_DOCS_DIR=/path`. No credentials are
stored in the repository — use SSH keys.
