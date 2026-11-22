# share

Private static sites at `https://<SHARE_HOST>/<token>/`. The repo is cloned on
the host and run there: a Caddy container serves `sites/`, and a Cloudflare
Tunnel publishes it. The Caddyfile holds every rule the host enforces;
Cloudflare is configured in its dashboard, see
[Cloudflare settings](#cloudflare-settings). Human workflows: `README.md`.

## Model

- A site is `sites/<token>/`: a copy of a source folder from anywhere on the
  host, plus a hidden `.source` file holding that folder's resolved absolute
  path. These folders are the only state, and git ignores them.
- `make publish SITE=<folder>` is idempotent. It starts or reloads the
  container, finds the site whose `.source` names the folder or creates one
  under a new random token, and replaces the copy. A rebuilt folder goes live on
  its next publish.
- `make unpublish SITE=<folder>` empties `sites/<token>` down to `.source`. The
  empty folder answers 404 and keeps the token, so the folder's next publish
  restores the same URL. The source folder stays as it is.
- Deleting `sites/<token>` by hand retires its token; the folder's next publish
  gets a new one.

## Request path

```
browser → Cloudflare edge (HTTPS) → Cloudflare Tunnel → cloudflared on the host
        → 127.0.0.1:<PORT> → Caddy container → /share/sites/<token>/...
```

The container listens on loopback only, so the Tunnel is its one public path. It
mounts this repo read-only at `/share` and serves `/share/sites`.

## Ownership

- This repo: `Caddyfile`, `compose.yaml`, `Makefile`, `site.sh`.
- Site projects: their content and build. Sites are data on the host.
- `.env`: the host-specific values, untracked, read by Make and Compose.
- Cloudflare dashboard: the Tunnel route, DNS, and zone settings.

## Invariants

- The token is the only access control. Tokens appear only as folder names in
  `sites/`, in the URLs handed to visitors, and in the access log.
- Only published sites answer; every other path, `/` included, is a 404.
  Directory browsing is off, and dotfiles are hidden at every level, `.source`
  included.
- Every response, errors included, carries
  `X-Robots-Tag: noindex, nofollow, noarchive`, `Referrer-Policy: no-referrer`,
  `Cache-Control: private, no-cache`, `X-Content-Type-Options: nosniff`, and
  `Access-Control-Allow-Origin: *`.
- Every response except PDFs carries `Content-Security-Policy: sandbox ...`
  without `allow-same-origin`, so every document a browser can run script in is
  sandboxed.
- Shared caches, Cloudflare's included, store nothing (`private`), so a publish
  or unpublish is live on the next request.
- Major search engine indexers and AI providers' clients (training crawlers,
  AI search, and assistants fetching a page for a user), matched by user agent
  in `@bots` in the Caddyfile, get 403. Every other client is served,
  link-preview fetchers included: a URL reaches them only when someone holding
  it shares it. `/healthz` answers `ok` for uptime monitoring.
- The host serves static files only and has no per-site configuration. Caddy
  writes an access log to stdout, `/healthz` excluded, which Docker keeps until
  the container is recreated.
- A site's copy holds only regular files and symlinks inside its source folder:
  dotfiles, symlinks that point outside, FIFOs, and device files stay out
  (`rsync --exclude='.*' --safe-links --no-specials --no-devices`).
- Deletions in `sites/` (`publish`'s `rsync --delete`, `unpublish`'s emptying)
  target a `sites/<token>` folder that `publish` created or that `find_site`
  found through its `.source`. An empty target would be `sites/` itself,
  deleting every site.

## Files

- `Caddyfile` — the `(headers)` snippet, imported by the site and by
  `handle_errors`; the access log; the sandbox on `@documents`; the `@bots`
  user-agent block; `/healthz`; compression; static files from `/share/sites`
  with dotfiles hidden.
- `compose.yaml` — the pinned Caddy image, `127.0.0.1:${PORT}`, the read-only
  repo mount at `/share`, and a healthcheck on `/healthz` that `make server`
  waits for before reloading.
- `.env.example` — the host-specific settings, documented.
- `Makefile` — `publish`, `unpublish`, and `server`, which `publish` runs.
- `site.sh` — `publish` and `unpublish` for one source folder.

## Access log

Page views, one line each (time, visitor IP, status, path, user agent):

```sh
docker compose logs -f --no-log-prefix web \
  | jq -r 'select(.logger | startswith("http.log.access")) | select(.request.uri | test("/$|/[^./]+$")) | [(.ts|floor|todate), .request.headers["Cf-Connecting-Ip"][0], .status, .request.uri, .request.headers["User-Agent"][0][:40]] | @tsv'
```

- Caddy names the logger `http.log.access.log0`, so the filter matches the
  prefix.
- Caddy sees cloudflared as the client; `Cf-Connecting-Ip` holds the visitor.
- The path filter keeps pages and drops their assets. A returning browser's
  assets answer 304 under `no-cache`.

## Cloudflare settings

Set in the dashboard for the zone holding `SHARE_HOST`:

- **Tunnel route:** `SHARE_HOST` → `http://127.0.0.1:<PORT>` on the host.
- **Always Online: off** (Caching → Configuration). On, it sends popular URLs to
  the Internet Archive.
- **Crawler Hints: off** (Caching → Configuration). On, it reports changed URLs
  to IndexNow search engines.
- **Email Obfuscation: off** for `SHARE_HOST` (a Configuration Rule, or
  zone-wide under Scrape Shield). On, it rewrites email addresses in pages and
  injects a decoding script.

Further hardening, each a rule matching `http.host eq "<SHARE_HOST>"`:

- **Block verified search and AI bots:** a Custom rule with action Block on
  `cf.verified_bot_category in {"Search Engine Crawler" "AI Crawler"
  "AI Assistant" "AI Search"}`. It adds Cloudflare's verified-bot signal to the
  Caddyfile's user-agent list for the same two groups.
- **Cloudflare Access** with a One-Time PIN allow-list: visitors also prove an
  email address, so a leaked URL alone opens nothing.

Check from outside with `curl -sI https://<SHARE_HOST>/<token>/<file>`:
`cf-cache-status` is `DYNAMIC` or `BYPASS`, and `Cache-Control` reads
`private, no-cache`. A zone-wide Browser Cache TTL set to anything but "Respect
Existing Headers" can rewrite it.

## Security model

- A token is 12 random bytes as 16 URL-safe characters (96 bits). On a
  case-insensitive filesystem, the macOS default, lookups ignore case, which
  leaves about 84 bits.
- URLs leak through the people and apps that handle them: forwarding, link
  scanners in corporate email and Gmail, Chrome Enhanced Safe Browsing and Edge
  SmartScreen (cloud fetchers with browser user agents), and the source-URL
  metadata macOS attaches to downloads. A URL lasts until its token is retired;
  retire it and publish again when one spreads. End-to-end encrypted messengers
  that build link previews on the sender's device are the safest channel.
- The access log holds every requested URL, tokens included, so it reveals every
  visited site to anyone who can read Docker logs on the host.
- The origin answers nothing that names a site. The remaining path to a token is
  a visitor's browser, covered below.

### Shared origin

All sites share the origin `https://<SHARE_HOST>`, and browsers scope
`localStorage`, IndexedDB, cookies, and the Cache API by origin. Those stores
can hold tokens: cache keys are full URLs, and apps store their own URLs. The
`sandbox` CSP without `allow-same-origin` gives each page a unique opaque
origin, so those APIs are unavailable and a script on one site reads nothing
another site stored. Sites therefore keep no browser state; they run scripts and
fetch their own files.

A page's script still sees its own URL and files, so sites follow these rules:

- Scripts are bundled into the site. Pages load no third-party scripts
  (analytics, widgets, CDN libraries, tag managers).
- Pages insert only trusted content as HTML.
- Each site has its own token and links to no other share site.
- Published folders hold no secrets: anyone with the URL can download every
  file.
- Code and sites owned by others go on a separate host.

## Extending

- Block a major search engine or AI provider's client: add its user-agent token
  to `@bots` in the Caddyfile, then `make server`. Other clients stay
  unblocked; the user-agent list only catches clients that identify themselves.
- Change headers or origin behavior: edit the Caddyfile, then `make server` (a
  graceful reload).
- Upgrade Caddy: bump the tag in `compose.yaml` (releases:
  <https://github.com/caddyserver/caddy/releases>), then `make server`.
- `site.sh` targets macOS's bash 3.2 and is ShellCheck-clean
  (`shellcheck site.sh`).

## Gotchas

- Compose mounts the whole repo: git writes changed files under new inodes, and
  a single-file bind mount keeps reading the old one.
- `SITE` goes through `realpath` before matching `.source`: two spellings of one
  folder share a token, and a moved folder is a new site whose old copy stays up
  until its `sites/<token>` is deleted.
- `rsync --delete` keeps excluded files, which is how `.source` survives each
  publish.
- `find_site` matches `.source` against an existing folder's resolved path. A
  folder in `sites/` without `.source`, or whose source folder is gone, is
  outside `publish` and `unpublish` and stays served until deleted by hand;
  `grep . sites/*/.source` beside `ls sites` shows them.
- Caddy's `header` directive skips error responses; `handle_errors` imports the
  same snippet.
- Chromium's PDF viewer refuses to render a PDF served with a CSP sandbox, so
  `@documents` is every path except `*.pdf`.
- `find_site` expects one `.source` per source folder. Two (from a hand-copied
  `sites/<token>`, or two publishes of a new folder started at the same moment)
  break `publish` and `unpublish` for that folder until the extra one is
  deleted.
- A content folder made by someone else (an archive, an export) can carry
  symlinks to `.source` inside its own site; check such folders before
  publishing.
- `make server` reloads Caddy through its admin API, which listens only once the
  container is up; `docker compose up -d --wait` holds until the healthcheck
  passes.
- `publish` checks the live URL and accepts 200, or 302 from Cloudflare Access
  sending the request to its login page. `site.sh` reads `SHARE_HOST` from the
  environment, which the Makefile exports.
- A hostname resolved before its DNS record exists stays cached as nonexistent
  for the zone's negative TTL, home routers included. Check new routes over
  DNS-over-HTTPS.
