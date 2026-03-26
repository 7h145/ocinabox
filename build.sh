#!/bin/bash
# vim:et:ai:sw=2:tw=0:ft=bash
# copyright 2023 <github.attic@typedef.net>, CC BY 4.0

declare -A C=(
  # Container runtime: some "docker lookalike" OCI runtime
  [crt]='podman'
  #[crt]='docker'

  # Version of the Containerfile and build.sh script
  [containerversion]='0.4'
)

command -v npm >&- || npm() {
  "${C[crt]}" run --rm node:current-alpine npm "${@}"
}

currentnpmversion() {
  local VERSION; read -r VERSION < <(
    npm show --json "${1:?}" 2>&- |jq -r '._id')
  VERSION="${VERSION##*@}"
  [ -n "${VERSION}" ] && echo "${VERSION}"
}

PAYLOADVERSION="$(currentnpmversion opencode-ai)"
ARGV+=( '--build-arg' "PAYLOADVERSION=${PAYLOADVERSION}" )

IMAGE='opencode'
TAGS=( "${C[containerversion]}-oc${PAYLOADVERSION:?}" 'latest' )

[ -n "${IMAGE}" ] && {
  for TAG in "${TAGS[@]:-latest}"; do
    ARGV+=( '-t' "${IMAGE}:${TAG}" )
  done
}

# non OCI compliant image format stuff
#ARGV+=( '--format' 'docker' )

"${C[crt]}" build ${ARGV:+"${ARGV[@]}"} "${@}" "${0%/*}"

