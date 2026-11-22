# share

Private static sites at secret URLs: `https://<host>/<token>/`.

## Setup

On the host, with Docker installed:

1. Clone and configure:

   ```sh
   git clone https://github.com/eferm/share.git && cd share
   cp .env.example .env   # set SHARE_HOST and PORT
   ```

2. Start the server and check it locally:

   ```sh
   make server
   curl -s http://127.0.0.1:<PORT>/healthz   # ok
   ```

3. In Cloudflare, point a Tunnel for `SHARE_HOST` at `http://127.0.0.1:<PORT>`,
   and turn off Always Online and Crawler Hints for the zone. Optional
   Cloudflare settings are in `AGENTS.md`.

4. Check it publicly:

   ```sh
   curl -s https://<SHARE_HOST>/healthz   # ok
   curl -s -o /dev/null -w '%{http_code}\n' https://<SHARE_HOST>/   # 404
   ```

## Publish a site

```sh
make publish SITE=$HOME/projects/trip-photos/build
```

This copies the folder and prints its URL. The first publish creates the URL;
republishing the same folder keeps it. Run it anytime source files change.

The folder needs an `index.html` at the top and relative links only
(`files/plan.pdf`, never `/files/plan.pdf`).

Pages can't use browser storage (`localStorage`, cookies, service workers).
Bundle scripts instead of loading them from other hosts. Anyone with the URL can
download any file in the folder, so keep secrets out of it; dotfiles are never
copied.

## Take a site offline

```sh
make unpublish SITE=$HOME/projects/trip-photos/build
```

The URL answers 404 until the same folder is published again, which restores it
at the same URL.

To change a site's URL delete its folder in `sites/` and publish it again: the
old URL stops working and the site gets a new one. Deleting the folder retires
the URL for good.

A site is tied to its folder's path. If `trip-photos/build` was published and
you then move it to `trip-photos-2/build`, publishing the new path creates a
second site with a new URL, and the old one stays up. Unpublish before moving,
or delete the old folder in `sites/` afterwards.

## List sites

```sh
make list
```

Each line is `<token> -> <source folder>`.

## Update the host

`git pull`, then `make server` to apply Caddyfile and Compose changes without
downtime.
