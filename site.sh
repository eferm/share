#!/usr/bin/env bash
# Publish or take down a copy of SITE at https://SHARE_HOST/<token>/.
#
# A site is sites/<token>/: a copy of SITE plus a hidden .source file holding SITE's absolute
# path. publish finds the site whose .source names SITE, or creates one under a new random token,
# then refreshes the copy. unpublish deletes everything but .source, so the token is kept for a later
# publish. Caddy serves only sites/, so SITE can live anywhere on the host.

set -euo pipefail
# An empty sites/ expands sites/*/.source to nothing
shopt -s nullglob

COMMAND="${1:?usage: site publish|unpublish SITE}"
SITE="$(realpath "${2:?usage: site publish|unpublish SITE}")"
SITES="$(dirname "${BASH_SOURCE[0]}")/sites"
# The Makefile exports SHARE_HOST from .env
HOST="${SHARE_HOST:?SHARE_HOST is unset; run through make}"
readonly COMMAND SITE SITES HOST

# 12 random bytes are 16 URL-safe base64 characters (96 bits) with no padding
new_token() {
  openssl rand -base64 12 | tr '+/' '-_'
}

# Print the sites/<token> folder whose .source names SITE, or nothing when none does. grep exits 1
# for no match, which is every first publish; any other failure is returned, and stops the caller.
# set -e is off inside the caller's $(...), so the return is explicit. /dev/null keeps grep off
# stdin when sites/ is empty.
find_site() {
  local source
  source="$(grep -lxF -- "${SITE}" /dev/null "${SITES}"/*/.source)" || [[ $? == 1 ]] || return
  printf '%s' "${source%/.source}"
}

publish() {
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

  # --delete makes the copy exact, and excluded dotfiles (.source among them) are kept out of it and
  # left in place. --safe-links drops symlinks that point outside SITE, so a link cannot reach
  # the rest of the host's files from inside the container. --no-specials and --no-devices keep
  # FIFOs and device files out: opening a FIFO blocks a Caddy thread for good.
  rsync -a --delete --safe-links --no-specials --no-devices --exclude='.*' -- "${SITE}/" "${site}/"

  local url
  url="https://${HOST}/$(basename "${site}")/"
  local status
  status="$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' "${url}")"
  printf '%s  %s\n' "${status}" "${url}"
  # 302 is Cloudflare Access sending an unauthenticated request to its login page
  [[ "${status}" == 200 || "${status}" == 302 ]]
}

unpublish() {
  local site
  site="$(find_site)"
  if [[ -z "${site}" ]]; then
    printf '%s is not published\n' "${SITE}" >&2
    exit 1
  fi
  # site is sites/<token>, taken from an existing .source file, never sites/ itself. Keeping .source
  # leaves an empty folder, which Caddy answers with 404, as the record of the token; a later publish
  # of SITE brings the site back at the same URL.
  find "${site}" -mindepth 1 -maxdepth 1 ! -name .source -exec rm -rf -- {} +
  printf '%s is offline\n' "${SITE}"
}

case "${COMMAND}" in
  publish) publish ;;
  unpublish) unpublish ;;
esac
