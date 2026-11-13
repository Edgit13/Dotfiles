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

The site is deployed with rsync to a small Ubuntu box:

```sh
make deploy                     # rsync docs/ to the server
```

nginx is the public front end and serves `/home/eduard/edots-site` directly, so a
deploy needs no restart. The site config is
`tools/nginx/edots-site.conf`; install it once:

```sh
sudo cp tools/nginx/edots-site.conf /etc/nginx/sites-available/edots
sudo ln -s /etc/nginx/sites-available/edots /etc/nginx/sites-enabled/edots
sudo rm -f /etc/nginx/sites-enabled/default
sudo setfacl -m u:www-data:x /home/eduard   # nginx must traverse the home dir
sudo nginx -t && sudo systemctl reload nginx
```

It disables directory listing, hides dotfiles and the repo README, adds
`nosniff`/frame/referrer headers and caches assets for a week.

Public access goes through a **Cloudflare Tunnel**, so the box opens no inbound
ports and the home IP stays hidden; TLS terminates at Cloudflare. The tunnel
config is `tools/cloudflared/config.yml`:

```sh
sudo mkdir -p /etc/cloudflared
sudo install -m 644 tools/cloudflared/config.yml /etc/cloudflared/
sudo cloudflared service install
```

Tunnel credentials (`~/.cloudflared/*.json`) live outside the repository. Each
hostname is a proxied CNAME to `<tunnel-id>.cfargotunnel.com`, created with
`cloudflared tunnel route dns edots <host>`:

| Hostname | Origin |
|---|---|
| `ekhub.pp.ua` | nginx, static `docs/` on `127.0.0.1:80` |
| `student.ekhub.pp.ua` | nginx on `127.0.0.1:8082` → StudentP on `127.0.0.1:3131` |
| `cloud.ekhub.pp.ua` | NextCloud on `https://192.168.1.109:443` |

`tools/nginx/studentp.conf` keeps the app off the public interfaces and limits
`/auth/login` attempts; the zone lives in `studentp-ratelimit.conf` (both go to
the server's `/etc/nginx`).

`tools/systemd/edots-site.service` is a local-only fallback: it runs
`python3 -m http.server` on `127.0.0.1:8091` for previews. It is not exposed.

Override the deploy target with `EDOTS_DOCS_HOST=user@host` and
`EDOTS_DOCS_DIR=/path`. No credentials are stored in the repository — use SSH
keys.
