#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
# copyright 2023 <github.attic@typedef.net>, CC BY 4.0

currentnpmversion() {
  local VERSION; read -r VERSION < <(
    npm show --json "${1:?}" |jq -r '._id')
  VERSION="${VERSION##*@}"
  [ -n "${VERSION}" ] && echo "${VERSION}"
}

VERSION="$(currentnpmversion opencode-ai)"
ARGV+=( '--build-arg' "PAYLOADVERSION=${VERSION}" )

IMAGE='opencode'
TAGS=( "0.3-oc${VERSION:?}" 'latest' )

[ -n "${IMAGE}" ] && {
  for TAG in "${TAGS[@]:-latest}"; do
    ARGV+=( '-t' "${IMAGE}:${TAG}" )
  done
}

# non OCI compliant image format stuff
#ARGV+=( '--format' 'docker' )

#docker build "${ARGV:+${ARGV[@]}}" "${@}" "${0%/*}"
podman build "${ARGV:+${ARGV[@]}}" "${@}" "${0%/*}"

