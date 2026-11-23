#!/usr/bin/env bash
# A site is sites/<token>/: a copy of SITE plus .source, SITE's realpath, which maps SITE to its token.

set -euo pipefail
shopt -s nullglob

USAGE="usage: sites list | sites publish|unpublish SITE"
COMMAND="${1:?${USAGE}}"
SITES="$(dirname "${BASH_SOURCE[0]}")/sites"
readonly USAGE COMMAND SITES

# About 95 bits as 16 alphanumeric characters
new_token() {
  openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | cut -c 1-16
}

# grep exits 1 on no match (a first publish); other failures return explicitly, since set -e is off
# inside the caller's $(...). /dev/null keeps grep off stdin when the glob is empty.
find_site() {
  local source
  source="$(grep -lxF -- "${SITE}" /dev/null "${SITES}"/*/.source)" || [[ $? == 1 ]] || return
  printf '%s' "${source%/.source}"
}

publish() {
  local host="${SHARE_HOST:?SHARE_HOST is unset; run through make}"
  if [[ ! -f "${SITE}/index.html" ]]; then
    printf '%s/index.html is missing; the site URL would be a 404\n' "${SITE}" >&2
    exit 1
  fi

  mkdir -p "${SITES}"
  local site
  site="$(find_site)"
  if [[ -z "${site}" ]]; then
    site="${SITES}/$(new_token)"
    mkdir "${site}"
    printf '%s\n' "${SITE}" >"${site}/.source"
  fi

  # --delete spares excluded files, so .source survives. A served FIFO blocks a Caddy thread forever.
  rsync -a --delete --safe-links --no-specials --no-devices --exclude='.*' -- "${SITE}/" "${site}/"

  local url
  url="https://${host}/$(basename "${site}")/"
  local status
  status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${url}")"
  printf '%s  %s\n' "${status}" "${url}"
  # 302: Cloudflare Access login
  [[ "${status}" == 200 || "${status}" == 302 ]]
}

unpublish() {
  local site
  site="$(find_site)"
  if [[ -z "${site}" ]]; then
    printf '%s is not published\n' "${SITE}" >&2
    exit 1
  fi
  # .source stays, so the next publish reuses the token
  find "${site}" -mindepth 1 -maxdepth 1 ! -name .source -exec rm -rf -- {} +
  printf '%s is offline\n' "${SITE}"
}

has_source() { [[ -f "$1/.source" ]]; }
source_exists() { [[ -d "$(<"$1/.source")" ]]; }
has_content() { [[ -n "$(find "$1" -mindepth 1 -maxdepth 1 ! -name .source -print -quit)" ]]; }

# Each check assumes the ones before it hold
site_status() {
  if ! has_source "$1"; then
    printf 'invalid'
  elif ! source_exists "$1"; then
    printf 'orphaned'
  elif ! has_content "$1"; then
    printf 'unpublished'
  else
    printf 'valid'
  fi
}

list() {
  local site
  for site in "${SITES}"/*/; do
    site="${site%/}"
    local source
    source="$(cat "${site}/.source" 2>/dev/null || printf -)"
    printf '%s -> %s  (%s)\n' "$(basename "${site}")" "${source}" "$(site_status "${site}")"
  done
}

case "${COMMAND}" in
  list) list ;;
  publish | unpublish)
    SITE="$(realpath "${2:?${USAGE}}")"
    readonly SITE
    "${COMMAND}"
    ;;
  *)
    printf '%s\n' "${USAGE}" >&2
    exit 1
    ;;
esac
